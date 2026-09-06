extends Node3D
class_name TerrainBackend

signal ready_changed(ready: bool)
signal changed

const PATCH_SIZE := Vector3i(48, 32, 48)
const CENTER := Vector3(24, 8, 24)
const MAX_HISTORY := 50
const MAX_HISTORY_BYTES := 128 * 1024 * 1024
const VOXEL_BYTES := 2
const SCULPT_FIXED_DT := 1.0 / 60.0
const SCULPT_TOOL_RAISE := "raise"
const SCULPT_TOOL_DIG := "dig"
const SCULPT_TOOL_LEVEL := "level"
const SCULPT_TOOL_SLOPE := "slope"
const SCULPT_TOOL_SMOOTH := "smooth"
const PatchGenerator = preload("res://scripts/patch_generator.gd")
const CheckpointStore = preload("res://scripts/checkpoint_store.gd")

var terrain: Node
var voxels: Object
var initial_generator: Script = PatchGenerator
var generator_id: String = PatchGenerator.GENERATOR_ID
var _backend_ready := false
var _initial_mesh_ready := false
var _revision := 0
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _history_bytes := 0
var _last_edit_ms := 0.0
var _last_edit_submitted_at_ms := -1
var _save_status := "never"
var _error := ""
var _dirty := false
var _checkpoint: RefCounted
@export var checkpoint_root := ""

var _stroke_active := false
var _stroke_tool := ""
var _stroke_settings: Dictionary = {}
var _stroke_reference: Dictionary = {}
var _stroke_normal := Vector3.UP
var _stroke_front_distance := 0.0
var _stroke_before_dirty := false
var _stroke_before: Dictionary = {}
var _stroke_positions: Array[Vector3i] = []
var _stroke_accumulated: Dictionary = {}
var _stroke_fronts: Dictionary = {}
var _stroke_front_axis := 1
var _stroke_front_sign := 1
var _stroke_segments: Array[Dictionary] = []
var _stroke_pending_time := 0.0
var _stroke_input_center := Vector3.ZERO
var _current_region_min := Vector3i.ZERO

func _ready() -> void:
	_checkpoint = CheckpointStore.new(checkpoint_root)
	if not ClassDB.class_exists("VoxelTerrain") or not ClassDB.class_exists("VoxelMesherBlocky"):
		_error = "Native VoxelTerrain/VoxelMesherBlocky unavailable"
		return
	terrain = ClassDB.instantiate("VoxelTerrain")
	terrain.bounds = AABB(Vector3.ZERO, Vector3(PATCH_SIZE))
	var generator_script: Script = initial_generator if initial_generator != null else PatchGenerator
	var mesher: Object = ClassDB.instantiate("VoxelMesherBlocky")
	mesher.library = generator_script.build_library()
	terrain.mesher = mesher
	if generator_script == PatchGenerator and ClassDB.class_exists("VoxelGeneratorFlat"):
		var generator: Object = ClassDB.instantiate("VoxelGeneratorFlat")
		generator.channel = 0
		generator.height = -1.0
		generator.voxel_type = 1
		terrain.generator = generator
	add_child(terrain)
	if ClassDB.class_exists("VoxelViewer"):
		var viewer: Node3D = ClassDB.instantiate("VoxelViewer")
		viewer.position = CENTER
		viewer.view_distance = 64
		add_child(viewer)
	voxels = generator_script.generate()
	var full_area := AABB(Vector3.ZERO, Vector3(PATCH_SIZE))
	var load_deadline := Time.get_ticks_msec() + 15000
	var tool = terrain.get_voxel_tool()
	while not tool.is_area_editable(full_area) and Time.get_ticks_msec() < load_deadline:
		await get_tree().process_frame
	if not tool.is_area_editable(full_area):
		_error = "Native terrain area did not become editable within 15 seconds"
		return
	tool.paste(Vector3i.ZERO, voxels, 1)
	while not terrain.is_area_meshed(full_area) and Time.get_ticks_msec() < load_deadline:
		await get_tree().process_frame
	if not terrain.is_area_meshed(full_area):
		_error = "Native terrain area did not mesh within 15 seconds"
		return
	_initial_mesh_ready = true
	_backend_ready = true
	ready_changed.emit(true)

func is_ready() -> bool:
	return _backend_ready

func apply_sphere(center: Vector3, radius: float, remove: bool) -> bool:
	if _stroke_active:
		_error = "cannot stamp while a sculpt stroke is active"
		return false
	var started := Time.get_ticks_usec()
	var simulation := _simulate_sphere(center, radius, remove)
	if simulation.is_empty():
		return false
	var region: Array[Vector3i] = simulation["region"]
	var region_size: Vector3i = region[1] - region[0]
	var command_bytes := region_size.x * region_size.y * region_size.z * VOXEL_BYTES * 2
	var redo_bytes := _stack_bytes(_redo)
	var projected_bytes := _history_bytes - redo_bytes + command_bytes
	if _undo.size() >= MAX_HISTORY:
		projected_bytes -= _command_bytes(_undo[0])
	if projected_bytes > MAX_HISTORY_BYTES:
		return false
	var before_full: Object = simulation["before"]
	var after_full: Object = simulation["after"]
	var region_min: Vector3i = region[0]
	var region_max: Vector3i = region[1]
	if simulation["changed"].is_empty():
		return false
	var before_region: Object = _extract_region(before_full, region_min, region_max)
	var after_region: Object = _extract_region(after_full, region_min, region_max)
	var terrain_tool = terrain.get_voxel_tool()
	terrain_tool.paste(region_min, after_region, 1)
	_redo.clear()
	_history_bytes -= redo_bytes
	voxels = after_full
	_undo.append({"min": region_min, "size": region_size, "before": before_region, "after": after_region})
	_history_bytes += command_bytes
	if _undo.size() > MAX_HISTORY:
		_history_bytes -= _command_bytes(_undo.pop_front())
	_revision += 1
	_dirty = true
	_last_edit_ms = (Time.get_ticks_usec() - started) / 1000.0
	_last_edit_submitted_at_ms = Time.get_ticks_msec()
	_error = ""
	changed.emit()
	return true

func preview_sphere(center: Vector3, radius: float, remove: bool) -> Array[Vector3i]:
	var simulation := _simulate_sphere(center, radius, remove)
	if simulation.is_empty():
		return []
	return simulation["changed"]

func begin_stroke(tool, center: Vector3, settings: Dictionary, reference_plane: Dictionary = {}) -> bool:
	if _stroke_active or not _backend_ready or voxels == null or not center.is_finite():
		return false
	var normalized_tool := _normalize_sculpt_tool(tool)
	if normalized_tool.is_empty():
		return false
	var radius := clampf(float(settings.get("radius", 2.0)), 0.25, 8.0)
	var strength := float(settings.get("strength", 1.0))
	var falloff := clampf(float(settings.get("falloff", 0.75)), 0.0, 1.0)
	if not is_finite(radius) or not is_finite(strength) or not is_finite(falloff) or strength <= 0.0:
		return false
	if center.x < 0.0 or center.y < 0.0 or center.z < 0.0 or center.x >= PATCH_SIZE.x or center.y >= PATCH_SIZE.y or center.z >= PATCH_SIZE.z:
		return false
	var stroke_reference := reference_plane.duplicate(true)
	if normalized_tool == SCULPT_TOOL_LEVEL or normalized_tool == SCULPT_TOOL_SLOPE:
		if stroke_reference.is_empty():
			stroke_reference = sample_surface_plane(center, _settings_normal(settings), radius + 1.0)
		if not bool(stroke_reference.get("valid", false)):
			return false
		var reference_normal = stroke_reference.get("normal", Vector3.UP)
		if not reference_normal is Vector3 or not reference_normal.is_finite() or reference_normal.length_squared() < 0.000001:
			return false
		stroke_reference["normal"] = reference_normal.normalized()
		if not stroke_reference.has("slope_x") or not stroke_reference.has("slope_z"):
			stroke_reference["slope_x"] = -reference_normal.x / maxf(absf(reference_normal.y), 0.000001)
			stroke_reference["slope_z"] = -reference_normal.z / maxf(absf(reference_normal.y), 0.000001)
	var normal := _settings_normal(settings)
	if normal.length_squared() < 0.000001:
		normal = Vector3.UP
	_stroke_active = true
	_stroke_tool = normalized_tool
	_stroke_settings = {"radius": radius, "strength": strength, "falloff": falloff, "material": clampi(int(settings.get("material", 2)), 1, 65535)}
	_stroke_reference = stroke_reference
	_stroke_normal = normal.normalized()
	_stroke_front_axis = _dominant_axis(_stroke_normal)
	_stroke_front_sign = 1 if _stroke_normal[_stroke_front_axis] >= 0.0 else -1
	_stroke_front_distance = 0.0
	_stroke_before_dirty = _dirty
	_stroke_before.clear()
	_stroke_positions.clear()
	_stroke_accumulated.clear()
	_stroke_fronts.clear()
	_stroke_segments.clear()
	_stroke_pending_time = 0.0
	_stroke_input_center = center
	return true

func update_stroke(center: Vector3, delta_seconds: float) -> bool:
	if not _stroke_active or not center.is_finite() or not is_finite(delta_seconds) or delta_seconds < 0.0:
		return false
	var clamped_center := Vector3(clampf(center.x, 0.0, PATCH_SIZE.x - 0.001), clampf(center.y, 0.0, PATCH_SIZE.y - 0.001), clampf(center.z, 0.0, PATCH_SIZE.z - 0.001))
	_stroke_segments.append({"a": _stroke_input_center, "b": clamped_center, "duration": delta_seconds, "elapsed": 0.0})
	_stroke_input_center = clamped_center
	_stroke_pending_time += delta_seconds
	var changed_before := _stroke_changed_count()
	while _stroke_pending_time + 0.0000001 >= SCULPT_FIXED_DT:
		_consume_stroke_time(SCULPT_FIXED_DT)
		_stroke_pending_time -= SCULPT_FIXED_DT
	return _stroke_changed_count() != changed_before

func end_stroke() -> bool:
	if not _stroke_active:
		return false
	if _stroke_pending_time > 0.0000001:
		_consume_stroke_time(_stroke_pending_time)
		_stroke_pending_time = 0.0
	var changed_cells := _stroke_changed_count()
	if changed_cells == 0:
		_clear_stroke()
		return false
	var region := _stroke_bounds()
	var region_min: Vector3i = region[0]
	var region_max: Vector3i = region[1]
	var region_size := region_max - region_min
	var before_region: Object = _clone_region(voxels, region_min, region_max)
	var after_region: Object = _clone_region(voxels, region_min, region_max)
	for position in _stroke_positions:
		var key := _stroke_key(position)
		if _stroke_before.has(key):
			before_region.set_voxel(int(_stroke_before[key]), position.x - region_min.x, position.y - region_min.y, position.z - region_min.z, PatchGenerator.CHANNEL_TYPE)
	var command_bytes := region_size.x * region_size.y * region_size.z * VOXEL_BYTES * 2
	var redo_bytes := _stack_bytes(_redo)
	var projected_bytes := _history_bytes - redo_bytes + command_bytes
	if _undo.size() >= MAX_HISTORY:
		projected_bytes -= _command_bytes(_undo[0])
	if projected_bytes > MAX_HISTORY_BYTES:
		_restore_stroke()
		_clear_stroke()
		return false
	_redo.clear()
	_history_bytes -= redo_bytes
	_undo.append({"min": region_min, "size": region_size, "before": before_region, "after": after_region})
	_history_bytes += command_bytes
	if _undo.size() > MAX_HISTORY:
		_history_bytes -= _command_bytes(_undo.pop_front())
	_revision += 1
	_dirty = true
	_error = ""
	_clear_stroke()
	changed.emit()
	return true

func cancel_stroke() -> bool:
	if not _stroke_active:
		return false
	var had_changes := _stroke_changed_count() > 0
	_restore_stroke()
	var was_dirty := _stroke_before_dirty
	_clear_stroke()
	_dirty = was_dirty
	if had_changes:
		_error = ""
		changed.emit()
	return true

func sample_surface_plane(center: Vector3, normal: Vector3 = Vector3.UP, radius: float = 3.0) -> Dictionary:
	if not _backend_ready or voxels == null or not center.is_finite() or not normal.is_finite() or not is_finite(radius) or radius <= 0.0:
		return {"valid": false, "error": "invalid surface sample"}
	if normal.length_squared() < 0.000001:
		return {"valid": false, "error": "surface normal is zero"}
	var query_normal := normal.normalized()
	var hit := _find_surface_hit(center, query_normal, clampf(radius, 1.0, 8.0))
	if not bool(hit.get("valid", false)):
		return hit
	var point: Vector3 = hit["point"]
	var slope := _fit_surface_slopes(point, clampf(radius, 1.0, 8.0))
	var fitted_normal := Vector3(-slope.x, 1.0, -slope.y).normalized()
	if query_normal.y < -0.5:
		fitted_normal = -fitted_normal
	return {"valid": true, "point": point, "normal": fitted_normal, "slope_x": slope.x, "slope_z": slope.y}

func get_stroke_state() -> Dictionary:
	return {"active": _stroke_active, "tool": _stroke_tool, "reference": _stroke_reference.duplicate(true), "changed_count": _stroke_changed_count(), "front_distance": _stroke_front_distance}

func undo() -> bool:
	if _stroke_active or not _backend_ready or _undo.is_empty(): return false
	var command: Dictionary = _undo.pop_back()
	_apply_command_region(command, command["before"])
	_redo.append(command)
	_revision += 1
	_dirty = true
	_last_edit_submitted_at_ms = Time.get_ticks_msec()
	changed.emit()
	return true

func redo() -> bool:
	if _stroke_active or not _backend_ready or _redo.is_empty(): return false
	var command: Dictionary = _redo.pop_back()
	_apply_command_region(command, command["after"])
	_undo.append(command)
	_revision += 1
	_dirty = true
	_last_edit_submitted_at_ms = Time.get_ticks_msec()
	changed.emit()
	return true

func save_world() -> bool:
	if _stroke_active:
		_save_status = "error"; _error = "cannot save while a sculpt stroke is active"; return false
	if not _backend_ready:
		_save_status = "error"; _error = "backend not ready"; return false
	var ok: bool = _checkpoint.save(voxels, _revision, generator_id)
	_save_status = "saved" if ok else "error"
	if ok: _dirty = false
	if not ok: _error = _checkpoint.last_error
	return ok

func load_world() -> bool:
	if _stroke_active:
		_save_status = "error"; _error = "cannot load while a sculpt stroke is active"; return false
	if not _backend_ready:
		_save_status = "error"; _error = "backend not ready"; return false
	var loaded = _checkpoint.load()
	if loaded == null:
		_save_status = "error"; _error = _checkpoint.last_error; return false
	var loaded_revision: int = _checkpoint.loaded_revision
	voxels = loaded
	terrain.get_voxel_tool().paste(Vector3i.ZERO, voxels, 1)
	_undo.clear(); _redo.clear(); _history_bytes = 0
	_revision = loaded_revision
	_dirty = false
	_save_status = "loaded"; _error = ""
	_last_edit_submitted_at_ms = Time.get_ticks_msec()
	changed.emit()
	return true

func voxel_at(pos: Vector3i) -> int:
	if not _backend_ready or pos.x < 0 or pos.y < 0 or pos.z < 0 or pos.x >= PATCH_SIZE.x or pos.y >= PATCH_SIZE.y or pos.z >= PATCH_SIZE.z: return 0
	return int(voxels.get_voxel(pos.x, pos.y, pos.z, PatchGenerator.CHANNEL_TYPE))

func stats() -> Dictionary:
	var age := -1
	if _last_edit_submitted_at_ms >= 0: age = Time.get_ticks_msec() - _last_edit_submitted_at_ms
	var native_stats: Dictionary = terrain.get_statistics() if terrain != null and terrain.has_method("get_statistics") else {}
	return {"ready": _backend_ready, "initial_mesh_ready": _initial_mesh_ready, "revision": _revision, "authoritative_revision": _revision, "dirty": _dirty, "undo_count": _undo.size(), "redo_count": _redo.size(), "history_bytes": _history_bytes, "last_edit_ms": _last_edit_ms, "last_edit_age_ms": age, "save_status": _save_status, "pending": "unavailable_per_revision", "settling": "unavailable_per_revision", "native_mesh_ack_revision": -1, "native_mesh_acknowledgement": "unavailable_per_revision", "native_statistics": native_stats, "error": _error}

func _process(_delta: float) -> void:
	# VoxelTerrain.is_area_meshed reports first processing, not an edit revision.
	# Keep derived mesh acknowledgement explicitly unavailable instead of guessing.
	pass

func _normalize_sculpt_tool(tool) -> String:
	if tool is String:
		var name := String(tool).to_lower()
		if name in [SCULPT_TOOL_RAISE, "add"]: return SCULPT_TOOL_RAISE
		if name in [SCULPT_TOOL_DIG, "lower", "remove"]: return SCULPT_TOOL_DIG
		if name in [SCULPT_TOOL_LEVEL, "flatten", "height"]: return SCULPT_TOOL_LEVEL
		if name in [SCULPT_TOOL_SLOPE, "surface", "plane"]: return SCULPT_TOOL_SLOPE
		if name in [SCULPT_TOOL_SMOOTH, "smoothing"]: return SCULPT_TOOL_SMOOTH
	return ""

func _settings_normal(settings: Dictionary) -> Vector3:
	var value = settings.get("surface_normal", Vector3.UP)
	if value is Vector3 and value.is_finite() and value.length_squared() >= 0.000001:
		return value.normalized()
	return Vector3.UP

func _dominant_axis(vector: Vector3) -> int:
	var axis := 0
	if absf(vector.y) > absf(vector.x) and absf(vector.y) >= absf(vector.z): axis = 1
	elif absf(vector.z) > absf(vector.x): axis = 2
	return axis

func _consume_stroke_time(duration: float) -> void:
	var remaining := duration
	while remaining > 0.0000001 and not _stroke_segments.is_empty():
		var segment: Dictionary = _stroke_segments[0]
		var segment_duration: float = segment["duration"]
		var segment_elapsed: float = segment["elapsed"]
		var available := segment_duration - segment_elapsed
		if available <= 0.0000001:
			_stroke_segments.pop_front()
			continue
		var consumed := minf(remaining, available)
		var start: Vector3 = segment["a"]
		var finish: Vector3 = segment["b"]
		var alpha0 := segment_elapsed / segment_duration if segment_duration > 0.0000001 else 1.0
		var alpha1 := (segment_elapsed + consumed) / segment_duration if segment_duration > 0.0000001 else 1.0
		_integrate_stroke_path(start.lerp(finish, alpha0), start.lerp(finish, alpha1), consumed)
		segment["elapsed"] = segment_elapsed + consumed
		_stroke_segments[0] = segment
		remaining -= consumed
		if float(segment["elapsed"]) >= segment_duration - 0.0000001:
			_stroke_segments.pop_front()

func _integrate_stroke_path(start: Vector3, finish: Vector3, duration: float) -> void:
	var distance := start.distance_to(finish)
	var radius: float = _stroke_settings["radius"]
	var spacing := maxf(radius * 0.45, 0.25)
	var steps := maxi(1, ceili(distance / spacing))
	for index in range(1, steps + 1):
		var alpha := float(index) / float(steps)
		_integrate_stroke_sample(start.lerp(finish, alpha), duration / float(steps))

func _integrate_stroke_sample(center: Vector3, duration: float) -> void:
	if _stroke_tool == SCULPT_TOOL_RAISE or _stroke_tool == SCULPT_TOOL_DIG:
		_integrate_front_sample(center, duration)
	elif _stroke_tool == SCULPT_TOOL_LEVEL or _stroke_tool == SCULPT_TOOL_SLOPE:
		_integrate_level_sample(center, duration)
	else:
		_integrate_smooth_sample(center, duration)

func _integrate_front_sample(center: Vector3, duration: float) -> void:
	var radius: float = _stroke_settings["radius"]
	var columns := _stroke_columns(center, radius)
	for column in columns:
		_ensure_front(column, center)
	if columns.is_empty():
		return
	var region := _front_region(columns)
	var region_min: Vector3i = region[0]
	var region_max: Vector3i = region[1]
	_current_region_min = region_min
	var local: Object = _clone_region(voxels, region_min, region_max)
	var changed := false
	var exponent := lerpf(1.0, 4.0, float(_stroke_settings["falloff"]))
	for column in columns:
		var plane_distance := _column_distance(column, center)
		if plane_distance > radius:
			continue
		var influence := pow(maxf(0.0, 1.0 - plane_distance / radius), exponent)
		var key := _column_key(column)
		var amount := float(_stroke_settings["strength"]) * duration * influence
		_stroke_accumulated[key] = float(_stroke_accumulated.get(key, 0.0)) + amount
		# One frontier transition per fixed sample keeps the bounded local
		# buffer valid even at a deliberately high strength setting. Remainder
		# carries into the next tick, preserving time based integration.
		if float(_stroke_accumulated[key]) >= 1.0:
			_stroke_accumulated[key] = float(_stroke_accumulated[key]) - 1.0
			if _advance_front(local, column):
				changed = true
	if changed:
		_write_region(local, region_min)
	_stroke_front_distance += float(_stroke_settings["strength"]) * duration * 0.5

func _integrate_level_sample(center: Vector3, duration: float) -> void:
	var radius: float = _stroke_settings["radius"]
	var columns := _vertical_columns(center, radius)
	var candidates: Array[Dictionary] = []
	var region_min := Vector3i(PATCH_SIZE.x, PATCH_SIZE.y, PATCH_SIZE.z)
	var region_max := Vector3i.ZERO
	var exponent := lerpf(1.0, 4.0, float(_stroke_settings["falloff"]))
	for column in columns:
		var distance := Vector2(float(column.x) - center.x, float(column.z) - center.z).length()
		if distance > radius:
			continue
		var surface_y := _surface_y_near(voxels, column.x, column.z, center.y, radius + 2.0)
		if surface_y < 0.0:
			continue
		var probe := Vector3i(column.x, int(surface_y), column.z)
		var target_y := _stroke_target_height(probe, center)
		var candidate := probe
		var desired := -1
		if target_y > surface_y + 0.5:
			candidate = Vector3i(column.x, int(surface_y), column.z)
			desired = int(_stroke_settings["material"])
		elif target_y < surface_y - 0.5:
			candidate = Vector3i(column.x, int(surface_y) - 1, column.z)
			desired = 0
		else:
			continue
		if candidate.y < 0 or candidate.y >= PATCH_SIZE.y:
			continue
		candidates.append({"column": column, "position": candidate, "desired": desired, "amount": float(_stroke_settings["strength"]) * duration * pow(maxf(0.0, 1.0 - distance / radius), exponent)})
		region_min.x = mini(region_min.x, candidate.x); region_min.y = mini(region_min.y, candidate.y); region_min.z = mini(region_min.z, candidate.z)
		region_max.x = maxi(region_max.x, candidate.x + 1); region_max.y = maxi(region_max.y, candidate.y + 1); region_max.z = maxi(region_max.z, candidate.z + 1)
	if candidates.is_empty():
		return
	_current_region_min = region_min
	var local: Object = _clone_region(voxels, region_min, region_max)
	var changed := false
	for item in candidates:
		var position: Vector3i = item["position"]
		var desired: int = item["desired"]
		var local_pos := position - region_min
		var current := int(local.get_voxel(local_pos.x, local_pos.y, local_pos.z, PatchGenerator.CHANNEL_TYPE))
		if (desired == 0 and current == 0) or (desired != 0 and current != 0):
			continue
		var key := _stroke_key(position)
		_stroke_accumulated[key] = float(_stroke_accumulated.get(key, 0.0)) + float(item["amount"])
		if float(_stroke_accumulated[key]) < 1.0:
			continue
		_stroke_accumulated[key] = float(_stroke_accumulated[key]) - 1.0
		_remember_stroke_original(position)
		local.set_voxel(desired, local_pos.x, local_pos.y, local_pos.z, PatchGenerator.CHANNEL_TYPE)
		changed = true
	if changed:
		_write_region(local, region_min)

func _integrate_smooth_sample(center: Vector3, duration: float) -> void:
	var radius: float = _stroke_settings["radius"]
	var columns := _vertical_columns(center, radius)
	var surfaces := {}
	for column in columns:
		var surface_y := _surface_y_near(voxels, column.x, column.z, center.y, radius + 2.0)
		if surface_y >= 0.0:
			surfaces[_column_key(column)] = surface_y
	var candidates: Array[Dictionary] = []
	var region_min := Vector3i(PATCH_SIZE.x, PATCH_SIZE.y, PATCH_SIZE.z)
	var region_max := Vector3i.ZERO
	for column in columns:
		var key := _column_key(column)
		if not surfaces.has(key):
			continue
		var neighbour_sum := 0.0
		var neighbour_count := 0
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				var neighbour := Vector3i(column.x + dx, 0, column.z + dz)
				var neighbour_key := _column_key(neighbour)
				if surfaces.has(neighbour_key):
					neighbour_sum += float(surfaces[neighbour_key])
					neighbour_count += 1
		if neighbour_count == 0:
			continue
		var current_surface: float = surfaces[key]
		var candidate := Vector3i(column.x, int(current_surface), column.z)
		var desired := -1
		var target_surface := neighbour_sum / float(neighbour_count)
		if target_surface > current_surface + 0.05:
			desired = int(_stroke_settings["material"])
		elif target_surface < current_surface - 0.05:
			candidate.y = int(current_surface) - 1
			desired = 0
		else:
			continue
		if candidate.y < 0 or candidate.y >= PATCH_SIZE.y:
			continue
		var distance := Vector2(float(column.x) - center.x, float(column.z) - center.z).length()
		if distance > radius:
			continue
		candidates.append({"position": candidate, "desired": desired, "amount": float(_stroke_settings["strength"]) * duration * pow(maxf(0.0, 1.0 - distance / radius), lerpf(1.0, 4.0, float(_stroke_settings["falloff"])))})
		region_min.x = mini(region_min.x, candidate.x); region_min.y = mini(region_min.y, candidate.y); region_min.z = mini(region_min.z, candidate.z)
		region_max.x = maxi(region_max.x, candidate.x + 1); region_max.y = maxi(region_max.y, candidate.y + 1); region_max.z = maxi(region_max.z, candidate.z + 1)
	if candidates.is_empty():
		return
	_current_region_min = region_min
	var local: Object = _clone_region(voxels, region_min, region_max)
	var changed := false
	for item in candidates:
		var position: Vector3i = item["position"]
		var local_pos := position - region_min
		var current := int(local.get_voxel(local_pos.x, local_pos.y, local_pos.z, PatchGenerator.CHANNEL_TYPE))
		var desired: int = item["desired"]
		if (desired == 0 and current == 0) or (desired != 0 and current != 0):
			continue
		var key := _stroke_key(position)
		_stroke_accumulated[key] = float(_stroke_accumulated.get(key, 0.0)) + float(item["amount"])
		if float(_stroke_accumulated[key]) < 1.0:
			continue
		_stroke_accumulated[key] = float(_stroke_accumulated[key]) - 1.0
		_remember_stroke_original(position)
		local.set_voxel(desired, local_pos.x, local_pos.y, local_pos.z, PatchGenerator.CHANNEL_TYPE)
		changed = true
	if changed:
		_write_region(local, region_min)

func _vertical_columns(center: Vector3, radius: float) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var min_x := maxi(0, floori(center.x - radius))
	var max_x := mini(PATCH_SIZE.x, ceili(center.x + radius) + 1)
	var min_z := maxi(0, floori(center.z - radius))
	var max_z := mini(PATCH_SIZE.z, ceili(center.z + radius) + 1)
	for x in range(min_x, max_x):
		for z in range(min_z, max_z):
			if Vector2(float(x) - center.x, float(z) - center.z).length() <= radius:
				result.append(Vector3i(x, 0, z))
	return result

func _stroke_columns(center: Vector3, radius: float) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var axis := _stroke_front_axis
	var extent := ceili(radius) + 1
	var center_cell := Vector3i(floori(center.x), floori(center.y), floori(center.z))
	if axis == 1:
		for x in range(maxi(0, center_cell.x - extent), mini(PATCH_SIZE.x, center_cell.x + extent + 1)):
			for z in range(maxi(0, center_cell.z - extent), mini(PATCH_SIZE.z, center_cell.z + extent + 1)):
				if Vector2(float(x) - center.x, float(z) - center.z).length() <= radius: result.append(Vector3i(x, 0, z))
	elif axis == 0:
		for y in range(maxi(0, center_cell.y - extent), mini(PATCH_SIZE.y, center_cell.y + extent + 1)):
			for z in range(maxi(0, center_cell.z - extent), mini(PATCH_SIZE.z, center_cell.z + extent + 1)):
				if Vector2(float(y) - center.y, float(z) - center.z).length() <= radius: result.append(Vector3i(0, y, z))
	else:
		for x in range(maxi(0, center_cell.x - extent), mini(PATCH_SIZE.x, center_cell.x + extent + 1)):
			for y in range(maxi(0, center_cell.y - extent), mini(PATCH_SIZE.y, center_cell.y + extent + 1)):
				if Vector2(float(x) - center.x, float(y) - center.y).length() <= radius: result.append(Vector3i(x, y, 0))
	return result

func _column_distance(column: Vector3i, center: Vector3) -> float:
	if _stroke_front_axis == 1: return Vector2(float(column.x) - center.x, float(column.z) - center.z).length()
	if _stroke_front_axis == 0: return Vector2(float(column.y) - center.y, float(column.z) - center.z).length()
	return Vector2(float(column.x) - center.x, float(column.y) - center.y).length()

func _column_cell(column: Vector3i, coordinate: int) -> Vector3i:
	if _stroke_front_axis == 0: return Vector3i(coordinate, column.y, column.z)
	if _stroke_front_axis == 1: return Vector3i(column.x, coordinate, column.z)
	return Vector3i(column.x, column.y, coordinate)

func _column_key(column: Vector3i) -> String:
	return "%d,%d,%d" % [column.x, column.y, column.z]

func _ensure_front(column: Vector3i, center: Vector3) -> void:
	var key := _column_key(column)
	if _stroke_fronts.has(key): return
	var center_coordinate := floori(center[_stroke_front_axis])
	var max_coordinate := PATCH_SIZE[_stroke_front_axis]
	var reach := ceili(float(_stroke_settings["radius"])) + 1
	var found := -1
	var coordinate := center_coordinate
	while coordinate >= 0 and coordinate < max_coordinate and (coordinate - center_coordinate) * _stroke_front_sign <= reach:
		var cell := _column_cell(column, coordinate)
		if int(voxels.get_voxel(cell.x, cell.y, cell.z, PatchGenerator.CHANNEL_TYPE)) != 0:
			found = coordinate
			break
		coordinate += _stroke_front_sign
	if found < 0:
		coordinate = center_coordinate - _stroke_front_sign
		while coordinate >= 0 and coordinate < max_coordinate and (center_coordinate - coordinate) * _stroke_front_sign <= reach:
			var cell := _column_cell(column, coordinate)
			if int(voxels.get_voxel(cell.x, cell.y, cell.z, PatchGenerator.CHANNEL_TYPE)) != 0:
				found = coordinate
				break
			coordinate -= _stroke_front_sign
	if found < 0:
		_stroke_fronts[key] = clampi(center_coordinate, 0, max_coordinate - 1)
	else:
		if _stroke_tool == SCULPT_TOOL_RAISE:
			# Seed on the exposed end of the contiguous mass, rather than the
			# first solid cell in front of a cave. This grows the local surface
			# while retaining enclosed voids behind it.
			var exposed := found + _stroke_front_sign
			while exposed >= 0 and exposed < max_coordinate and (exposed - found) * _stroke_front_sign <= reach:
				var exposed_cell := _column_cell(column, exposed)
				if int(voxels.get_voxel(exposed_cell.x, exposed_cell.y, exposed_cell.z, PatchGenerator.CHANNEL_TYPE)) == 0:
					break
				found = exposed
				exposed += _stroke_front_sign
		_stroke_fronts[key] = found + _stroke_front_sign if _stroke_tool == SCULPT_TOOL_RAISE else found

func _front_region(columns: Array[Vector3i]) -> Array[Vector3i]:
	var min_pos := Vector3i(PATCH_SIZE.x, PATCH_SIZE.y, PATCH_SIZE.z)
	var max_pos := Vector3i.ZERO
	for column in columns:
		var front := int(_stroke_fronts[_column_key(column)])
		var cell := _column_cell(column, front)
		var adjacent := _column_cell(column, front + _stroke_front_sign)
		min_pos.x = mini(min_pos.x, mini(cell.x, adjacent.x)); min_pos.y = mini(min_pos.y, mini(cell.y, adjacent.y)); min_pos.z = mini(min_pos.z, mini(cell.z, adjacent.z))
		max_pos.x = maxi(max_pos.x, maxi(cell.x, adjacent.x) + 1); max_pos.y = maxi(max_pos.y, maxi(cell.y, adjacent.y) + 1); max_pos.z = maxi(max_pos.z, maxi(cell.z, adjacent.z) + 1)
	min_pos.x = clampi(min_pos.x, 0, PATCH_SIZE.x - 1); min_pos.y = clampi(min_pos.y, 0, PATCH_SIZE.y - 1); min_pos.z = clampi(min_pos.z, 0, PATCH_SIZE.z - 1)
	max_pos.x = clampi(max_pos.x, min_pos.x + 1, PATCH_SIZE.x); max_pos.y = clampi(max_pos.y, min_pos.y + 1, PATCH_SIZE.y); max_pos.z = clampi(max_pos.z, min_pos.z + 1, PATCH_SIZE.z)
	return [min_pos, max_pos]

func _advance_front(local: Object, column: Vector3i) -> bool:
	var key := _column_key(column)
	var coordinate := int(_stroke_fronts[key])
	var cell := _column_cell(column, coordinate)
	if coordinate < 0 or coordinate >= PATCH_SIZE[_stroke_front_axis]:
		return false
	var local_cell := cell - _current_region_min
	var current := int(local.get_voxel(local_cell.x, local_cell.y, local_cell.z, PatchGenerator.CHANNEL_TYPE))
	var changed := false
	if _stroke_tool == SCULPT_TOOL_RAISE:
		if current == 0:
			_remember_stroke_original(cell)
			local.set_voxel(int(_stroke_settings["material"]), local_cell.x, local_cell.y, local_cell.z, PatchGenerator.CHANNEL_TYPE)
			changed = true
			coordinate += _stroke_front_sign
		else:
			coordinate += _stroke_front_sign
	else:
		# A newly exposed void is the stable end of the dig front. Do not walk
		# through it and unexpectedly remove a distant floor or wall behind it.
		if current == 0:
			return false
		_remember_stroke_original(cell)
		local.set_voxel(0, local_cell.x, local_cell.y, local_cell.z, PatchGenerator.CHANNEL_TYPE)
		changed = true
		coordinate -= _stroke_front_sign
	_stroke_fronts[key] = coordinate
	return changed

func _stroke_target_height(position: Vector3i, center: Vector3) -> float:
	if _stroke_tool == SCULPT_TOOL_LEVEL:
		var level_point: Vector3 = _stroke_reference.get("point", center)
		return level_point.y
	var point: Vector3 = _stroke_reference.get("point", center)
	var slope_x := float(_stroke_reference.get("slope_x", 0.0))
	var slope_z := float(_stroke_reference.get("slope_z", 0.0))
	return point.y + slope_x * (float(position.x) - point.x) + slope_z * (float(position.z) - point.z)

func _sphere_region_for_radius(center: Vector3, radius: float) -> Array[Vector3i]:
	var min_pos := Vector3i(floori(center.x - radius), floori(center.y - radius), floori(center.z - radius))
	var max_pos := Vector3i(ceili(center.x + radius) + 1, ceili(center.y + radius) + 1, ceili(center.z + radius) + 1)
	min_pos.x = maxi(0, min_pos.x); min_pos.y = maxi(0, min_pos.y); min_pos.z = maxi(0, min_pos.z)
	max_pos.x = mini(PATCH_SIZE.x, max_pos.x); max_pos.y = mini(PATCH_SIZE.y, max_pos.y); max_pos.z = mini(PATCH_SIZE.z, max_pos.z)
	return [min_pos, max_pos]

func _clone_region(source: Object, region_min: Vector3i, region_max: Vector3i) -> Object:
	var size := region_max - region_min
	var out: Object = ClassDB.instantiate("VoxelBuffer")
	out.create(size.x, size.y, size.z)
	out.copy_channel_from_area(source, region_min, region_max, Vector3i.ZERO, PatchGenerator.CHANNEL_TYPE)
	return out

func _write_region(local: Object, region_min: Vector3i) -> void:
	_current_region_min = region_min
	voxels.copy_channel_from_area(local, Vector3i.ZERO, local.get_size(), region_min, PatchGenerator.CHANNEL_TYPE)
	terrain.get_voxel_tool().paste(region_min, local, 1)
	_dirty = true

func _remember_stroke_original(position: Vector3i) -> void:
	var key := _stroke_key(position)
	if not _stroke_before.has(key):
		_stroke_before[key] = int(voxels.get_voxel(position.x, position.y, position.z, PatchGenerator.CHANNEL_TYPE))
		_stroke_positions.append(position)

func _stroke_changed_count() -> int:
	var count := 0
	for position in _stroke_positions:
		var key := _stroke_key(position)
		if _stroke_before.has(key) and int(_stroke_before[key]) != int(voxels.get_voxel(position.x, position.y, position.z, PatchGenerator.CHANNEL_TYPE)):
			count += 1
	return count

func _stroke_bounds() -> Array[Vector3i]:
	var min_pos := _stroke_positions[0]
	var max_pos := _stroke_positions[0] + Vector3i.ONE
	for position in _stroke_positions:
		min_pos.x = mini(min_pos.x, position.x); min_pos.y = mini(min_pos.y, position.y); min_pos.z = mini(min_pos.z, position.z)
		max_pos.x = maxi(max_pos.x, position.x + 1); max_pos.y = maxi(max_pos.y, position.y + 1); max_pos.z = maxi(max_pos.z, position.z + 1)
	return [min_pos, max_pos]

func _restore_stroke() -> void:
	if _stroke_positions.is_empty():
		return
	var region := _stroke_bounds()
	var region_min: Vector3i = region[0]
	var region_max: Vector3i = region[1]
	var restored: Object = _clone_region(voxels, region_min, region_max)
	for position in _stroke_positions:
		var key := _stroke_key(position)
		if _stroke_before.has(key):
			var local_pos := position - region_min
			restored.set_voxel(int(_stroke_before[key]), local_pos.x, local_pos.y, local_pos.z, PatchGenerator.CHANNEL_TYPE)
	_write_region(restored, region_min)

func _clear_stroke() -> void:
	_stroke_active = false
	_stroke_tool = ""
	_stroke_settings.clear()
	_stroke_reference.clear()
	_stroke_normal = Vector3.UP
	_stroke_front_distance = 0.0
	_stroke_fronts.clear()
	_stroke_before.clear()
	_stroke_positions.clear()
	_stroke_accumulated.clear()
	_stroke_segments.clear()
	_stroke_pending_time = 0.0
	_stroke_input_center = Vector3.ZERO

func _stroke_key(position: Vector3i) -> String:
	return "%d,%d,%d" % [position.x, position.y, position.z]

func _find_surface_hit(center: Vector3, normal: Vector3, radius: float) -> Dictionary:
	var best_distance := INF
	var best_point := Vector3.ZERO
	var horizontal := Vector2(normal.x, normal.z).length()
	if absf(normal.y) >= horizontal:
		var center_x := floori(center.x)
		var center_z := floori(center.z)
		var surface_y := _surface_y_near(voxels, center_x, center_z, center.y, radius + 1.0) if normal.y >= 0.0 else _column_floor_y(voxels, center_x, center_z)
		if surface_y >= 0.0 and absf(surface_y - center.y) <= radius + 1.0:
			best_distance = (surface_y - center.y) * (surface_y - center.y)
			best_point = Vector3(center.x, surface_y, center.z)
	else:
		var axis := 0
		if absf(normal.y) > absf(normal.x) and absf(normal.y) >= absf(normal.z): axis = 1
		elif absf(normal.z) > absf(normal.x): axis = 2
		var direction := 1 if (normal[axis] >= 0.0) else -1
		var center_cell := Vector3i(floori(center.x), floori(center.y), floori(center.z))
		var extent := ceili(radius) + 1
		for x in range(maxi(0, center_cell.x - extent), mini(PATCH_SIZE.x, center_cell.x + extent + 1)):
			for y in range(maxi(0, center_cell.y - extent), mini(PATCH_SIZE.y, center_cell.y + extent + 1)):
				for z in range(maxi(0, center_cell.z - extent), mini(PATCH_SIZE.z, center_cell.z + extent + 1)):
					var cell := Vector3i(x, y, z)
					if int(voxels.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE)) == 0:
						continue
					var neighbour := cell
					neighbour[axis] += direction
					if neighbour[axis] < 0 or neighbour[axis] >= PATCH_SIZE[axis] or int(voxels.get_voxel(neighbour.x, neighbour.y, neighbour.z, PatchGenerator.CHANNEL_TYPE)) != 0:
						continue
					var candidate := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
					candidate[axis] = float(cell[axis] + (1 if direction > 0 else 0))
					var distance := candidate.distance_squared_to(center)
					if distance <= (radius + 1.0) * (radius + 1.0) and distance < best_distance:
						best_distance = distance
						best_point = candidate
	if best_distance == INF:
		return {"valid": false, "error": "no nearby surface hit"}
	return {"valid": true, "point": best_point}

func _fit_surface_slopes(point: Vector3, radius: float) -> Vector2:
	var center_x := floori(point.x)
	var center_z := floori(point.z)
	var extent := ceili(radius)
	var xx := 0.0
	var xz := 0.0
	var zz := 0.0
	var yx := 0.0
	var yz := 0.0
	for x in range(maxi(0, center_x - extent), mini(PATCH_SIZE.x, center_x + extent + 1)):
		for z in range(maxi(0, center_z - extent), mini(PATCH_SIZE.z, center_z + extent + 1)):
			var surface_y := _surface_y_near(voxels, x, z, point.y, radius + 1.0)
			if surface_y < 0.0:
				continue
			var dx := float(x) - point.x
			var dz := float(z) - point.z
			var dy := surface_y - point.y
			var weight := 1.0 / (1.0 + dx * dx + dz * dz)
			xx += weight * dx * dx
			xz += weight * dx * dz
			zz += weight * dz * dz
			yx += weight * dx * dy
			yz += weight * dz * dy
	var determinant := xx * zz - xz * xz
	if absf(determinant) < 0.000001:
		return Vector2.ZERO
	return Vector2((yx * zz - yz * xz) / determinant, (yz * xx - yx * xz) / determinant)

func _column_surface_y(source: Object, x: int, z: int) -> float:
	for y in range(PATCH_SIZE.y - 1, -1, -1):
		if int(source.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE)) != 0:
			return float(y + 1)
	return -1.0

func _surface_y_near(source: Object, x: int, z: int, center_y: float, reach: float) -> float:
	if x < 0 or z < 0 or x >= PATCH_SIZE.x or z >= PATCH_SIZE.z:
		return -1.0
	var start := clampi(floori(center_y), 0, PATCH_SIZE.y - 1)
	var limit := ceili(maxf(reach, 1.0))
	if int(source.get_voxel(x, start, z, PatchGenerator.CHANNEL_TYPE)) != 0:
		var top := start
		while top + 1 < PATCH_SIZE.y and int(source.get_voxel(x, top + 1, z, PatchGenerator.CHANNEL_TYPE)) != 0:
			top += 1
		return float(top + 1)
	for y in range(start + 1, mini(PATCH_SIZE.y, start + limit + 1)):
		if int(source.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE)) != 0:
			var top := y
			while top + 1 < PATCH_SIZE.y and int(source.get_voxel(x, top + 1, z, PatchGenerator.CHANNEL_TYPE)) != 0:
				top += 1
			return float(top + 1)
	for y in range(start - 1, maxi(-1, start - limit - 1), -1):
		if int(source.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE)) != 0:
			return float(y + 1)
	return -1.0

func _column_floor_y(source: Object, x: int, z: int) -> float:
	for y in PATCH_SIZE.y:
		if int(source.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE)) != 0:
			return float(y)
	return -1.0

func _sphere_region(center: Vector3, radius: float) -> Array[Vector3i]:
	var min_pos := Vector3i(floori(center.x - radius), floori(center.y - radius), floori(center.z - radius))
	var max_pos := Vector3i(ceili(center.x + radius) + 1, ceili(center.y + radius) + 1, ceili(center.z + radius) + 1)
	min_pos.x = maxi(0, min_pos.x); min_pos.y = maxi(0, min_pos.y); min_pos.z = maxi(0, min_pos.z)
	max_pos.x = mini(PATCH_SIZE.x, max_pos.x); max_pos.y = mini(PATCH_SIZE.y, max_pos.y); max_pos.z = mini(PATCH_SIZE.z, max_pos.z)
	return [min_pos, max_pos]

func _simulate_sphere(center: Vector3, radius: float, remove: bool) -> Dictionary:
	if not _backend_ready or voxels == null or not center.is_finite() or not is_finite(radius) or radius <= 0.0 or radius > 8.0:
		return {}
	if center.x < 0.0 or center.y < 0.0 or center.z < 0.0 or center.x >= PATCH_SIZE.x or center.y >= PATCH_SIZE.y or center.z >= PATCH_SIZE.z:
		return {}
	var region := _sphere_region(center, radius)
	var region_min: Vector3i = region[0]
	var region_max: Vector3i = region[1]
	var before_full: Object = _clone_buffer(voxels)
	var after_full: Object = _clone_buffer(voxels)
	var buffer_tool = after_full.get_voxel_tool()
	buffer_tool.channel = PatchGenerator.CHANNEL_TYPE
	buffer_tool.mode = 2
	buffer_tool.value = 0 if remove else 2
	buffer_tool.do_sphere(center, radius)
	var changed: Array[Vector3i] = []
	for x in range(region_min.x, region_max.x):
		for y in range(region_min.y, region_max.y):
			for z in range(region_min.z, region_max.z):
				if before_full.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE) != after_full.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE):
					changed.append(Vector3i(x, y, z))
	return {"region": region, "before": before_full, "after": after_full, "changed": changed}

func _clone_buffer(source: Object) -> Object:
	var copy: Object = ClassDB.instantiate("VoxelBuffer")
	copy.create(PATCH_SIZE.x, PATCH_SIZE.y, PATCH_SIZE.z)
	copy.copy_channel_from(source, PatchGenerator.CHANNEL_TYPE)
	return copy

func _extract_region(source: Object, region_min: Vector3i, region_max: Vector3i) -> Object:
	var size := region_max - region_min
	var out: Object = ClassDB.instantiate("VoxelBuffer")
	out.create(size.x, size.y, size.z)
	out.copy_channel_from_area(source, region_min, region_max, Vector3i.ZERO, PatchGenerator.CHANNEL_TYPE)
	return out

func _apply_command_region(command: Dictionary, region: Object) -> void:
	var region_min: Vector3i = command["min"]
	var region_size: Vector3i = command["size"]
	voxels.copy_channel_from_area(region, Vector3i.ZERO, region_size, region_min, PatchGenerator.CHANNEL_TYPE)
	terrain.get_voxel_tool().paste(region_min, region, 1)

func _command_bytes(command: Dictionary) -> int:
	var size: Vector3i = command["size"]
	return size.x * size.y * size.z * VOXEL_BYTES * 2

func _stack_bytes(stack: Array[Dictionary]) -> int:
	var total := 0
	for command in stack: total += _command_bytes(command)
	return total
