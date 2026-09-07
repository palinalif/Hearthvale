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
const M1Generator = preload("res://scripts/m1_patch_generator.gd")
const SmoothNeighbourhood = preload("res://scripts/smooth_neighbourhood.gd")

var terrain: Node
var voxels: Object
## Index dimensions remain 48×32×48 for M0. M1 supplies 384×256×384 at
## eighth-unit voxels, keeping the authored world bounds at 48×32×48.
@export var patch_size: Vector3i = PATCH_SIZE
@export var voxel_scale: float = 1.0
var initial_generator: Script = PatchGenerator
var generator_id: String = PatchGenerator.GENERATOR_ID
var _backend_ready := false
var _initial_mesh_ready := false
var _revision := 0
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _history_bytes := 0
var _last_edit_command: Dictionary = {}
var _last_edit_ms := 0.0
var _last_edit_submitted_at_ms := -1
var _save_status := "never"
var _error := ""
var _dirty := false
var _checkpoint: RefCounted
@export var checkpoint_root := ""
@export var require_building_document := false
var loaded_building_document: Dictionary = {}

var _stroke_active := false
var _stroke_tool := ""
var _stroke_settings: Dictionary = {}
var _stroke_reference: Dictionary = {}
var _stroke_normal := Vector3.UP
var _stroke_front_distance := 0.0
var _stroke_before_dirty := false
var _stroke_before: Dictionary = {}
var _stroke_positions: Array[Vector3i] = []
var _stroke_changed_cells := 0
var _stroke_mutations := 0
var _stroke_accumulated: Dictionary = {}
var _stroke_fronts: Dictionary = {}
var _stroke_front_cache_center := Vector3.INF
var _stroke_front_columns: Array[Vector3i] = []
var _stroke_front_influence := PackedFloat64Array()
var _smooth_targets := PackedFloat64Array()
var _smooth_targets_dirty := true
var _stroke_front_axis := 1
var _stroke_front_sign := 1
var _stroke_segments: Array[Dictionary] = []
var _stroke_pending_time := 0.0
var _stroke_input_center := Vector3.ZERO
var _current_region_min := Vector3i.ZERO
var _defer_native_updates := false
var _pending_native_region := false
var _pending_native_min := Vector3i.ZERO
var _pending_native_max := Vector3i.ZERO

func _ready() -> void:
	if voxel_scale <= 0.0 or not is_finite(voxel_scale) or patch_size.x <= 0 or patch_size.y <= 0 or patch_size.z <= 0:
		_error = "invalid terrain grid configuration"
		return
	_checkpoint = CheckpointStore.new(checkpoint_root)
	_checkpoint.expected_generator_id = generator_id
	_checkpoint.expected_dimensions = patch_size
	_checkpoint.require_building_document = require_building_document
	if not ClassDB.class_exists("VoxelTerrain") or not ClassDB.class_exists("VoxelMesherBlocky"):
		_error = "Native VoxelTerrain/VoxelMesherBlocky unavailable"
		return
	terrain = ClassDB.instantiate("VoxelTerrain")
	terrain.bounds = AABB(Vector3.ZERO, Vector3(patch_size))
	# VoxelTerrain defaults to a 128-cell streaming cap. The fine finite
	# valley needs its full extent editable, including its outer boundaries.
	terrain.max_view_distance = maxi(128, ceili(Vector3(patch_size).length()))
	# Pinned VoxelTerrain supports mesh blocks of 16 or 32 while its native
	# data blocks stay 16. Group fine-grid surfaces to reduce draw overhead.
	if patch_size.x > 96: terrain.mesh_block_size = 32
	terrain.scale = Vector3.ONE * voxel_scale
	var generator_script: Script = initial_generator if initial_generator != null else PatchGenerator
	var mesher: Object = ClassDB.instantiate("VoxelMesherBlocky")
	mesher.library = generator_script.build_library()
	terrain.mesher = mesher
	# The deterministic patch script supplies authoritative voxel contents, but
	# the native empty generator is still needed to initialize streaming/data
	# blocks for every generator (including M1 cottage patches).
	if ClassDB.class_exists("VoxelGeneratorFlat"):
		var generator: Object = ClassDB.instantiate("VoxelGeneratorFlat")
		generator.channel = 0
		generator.height = -1.0
		generator.voxel_type = 1
		terrain.generator = generator
	add_child(terrain)
	if ClassDB.class_exists("VoxelViewer"):
		var viewer: Node3D = ClassDB.instantiate("VoxelViewer")
		viewer.position = _world_size() * 0.5
		viewer.view_distance = 64.0 / voxel_scale
		add_child(viewer)
	voxels = generator_script.generate()
	var full_area := AABB(Vector3.ZERO, Vector3(patch_size))
	var initialization_budget_ms := 45000 if patch_size.x > 96 else 15000
	var load_deadline := Time.get_ticks_msec() + initialization_budget_ms
	var tool = terrain.get_voxel_tool()
	while not tool.is_area_editable(full_area) and Time.get_ticks_msec() < load_deadline:
		await get_tree().process_frame
	if not tool.is_area_editable(full_area):
		_error = "Native terrain area did not become editable within %d ms" % initialization_budget_ms
		return
	tool.paste(Vector3i.ZERO, voxels, 1)
	while not terrain.is_area_meshed(full_area) and Time.get_ticks_msec() < load_deadline:
		await get_tree().process_frame
	if not terrain.is_area_meshed(full_area):
		_error = "Native terrain area did not mesh within %d ms" % initialization_budget_ms
		return
	_initial_mesh_ready = true
	_backend_ready = true
	ready_changed.emit(true)

func is_ready() -> bool:
	return _backend_ready

func world_size() -> Vector3:
	return _world_size()

func _world_size() -> Vector3:
	return Vector3(patch_size) * voxel_scale

func _world_to_cell(point: Vector3) -> Vector3:
	return point / voxel_scale

func _cell_to_world(point: Vector3) -> Vector3:
	return point * voxel_scale

func _world_radius_to_cells(radius: float) -> float:
	return radius / voxel_scale

func _world_center_valid(center: Vector3) -> bool:
	var extent := _world_size()
	return center.is_finite() and center.x >= 0.0 and center.y >= 0.0 and center.z >= 0.0 and center.x < extent.x and center.y < extent.y and center.z < extent.z

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
	_last_edit_command = _undo.back()
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

## Public coordinates are world units; returned positions are authoritative
## native grid cells (the same cells apply_sphere would write).
func preview_sphere(center: Vector3, radius: float, remove: bool) -> Array[Vector3i]:
	var simulation := _simulate_sphere(center, radius, remove)
	if simulation.is_empty():
		return []
	return simulation["changed"]

func begin_stroke(tool, center: Vector3, settings: Dictionary, reference_plane: Dictionary = {}) -> bool:
	if _stroke_active or not _backend_ready or voxels == null or not center.is_finite():
		return false
	if not _world_center_valid(center): return false
	var normalized_tool := _normalize_sculpt_tool(tool)
	if normalized_tool.is_empty():
		return false
	var radius_world := clampf(float(settings.get("radius", 2.0)), 0.25, 8.0)
	var radius := _world_radius_to_cells(radius_world)
	var strength := float(settings.get("strength", 1.0))
	var falloff := clampf(float(settings.get("falloff", 0.75)), 0.0, 1.0)
	if not is_finite(radius) or not is_finite(strength) or not is_finite(falloff) or strength <= 0.0:
		return false
	var stroke_reference := reference_plane.duplicate(true)
	if not stroke_reference.is_empty() and stroke_reference.get("point", null) is Vector3:
		stroke_reference["point"] = _world_to_cell(stroke_reference["point"])
	if normalized_tool == SCULPT_TOOL_LEVEL or normalized_tool == SCULPT_TOOL_SLOPE:
		if stroke_reference.is_empty():
			stroke_reference = sample_surface_plane(center, _settings_normal(settings), radius_world + 1.0)
			if stroke_reference.get("point", null) is Vector3:
				stroke_reference["point"] = _world_to_cell(stroke_reference["point"])
		if not bool(stroke_reference.get("valid", false)):
			return false
		var reference_normal = stroke_reference.get("normal", Vector3.UP)
		if not reference_normal is Vector3 or not reference_normal.is_finite() or reference_normal.length_squared() < 0.000001:
			return false
		stroke_reference["normal"] = reference_normal.normalized()
		# Height flatten needs the hit height even on a steep upward slope.
		# Its reference is horizontal. Surface flatten retains the fitted slope;
		# walls and undersides still require a different tangent-plane operation.
		var minimum_up := 0.000001 if normalized_tool == SCULPT_TOOL_LEVEL else 0.5
		if stroke_reference["normal"].y < minimum_up:
			return false
		if normalized_tool == SCULPT_TOOL_LEVEL:
			stroke_reference["normal"] = Vector3.UP
		if not stroke_reference.has("slope_x") or not stroke_reference.has("slope_z"):
			stroke_reference["slope_x"] = -reference_normal.x / maxf(absf(reference_normal.y), 0.000001)
			stroke_reference["slope_z"] = -reference_normal.z / maxf(absf(reference_normal.y), 0.000001)
	var normal := _settings_normal(settings)
	if normal.length_squared() < 0.000001:
		normal = Vector3.UP
	_stroke_active = true
	_stroke_tool = normalized_tool
	# Strength is expressed in world units per second; one grid transition is
	# voxel_scale world units, so the accumulator works in grid-cell units.
	_stroke_settings = {"radius": radius, "strength": strength / voxel_scale, "falloff": falloff, "material": clampi(int(settings.get("material", 2)), 1, 65535)}
	_stroke_reference = stroke_reference
	_stroke_normal = normal.normalized()
	_stroke_front_axis = _dominant_axis(_stroke_normal)
	_stroke_front_sign = 1 if _stroke_normal[_stroke_front_axis] >= 0.0 else -1
	_stroke_front_distance = 0.0
	_stroke_before_dirty = _dirty
	_stroke_before.clear()
	_stroke_positions.clear()
	_stroke_changed_cells = 0
	_stroke_mutations = 0
	_stroke_accumulated.clear()
	_stroke_fronts.clear()
	_stroke_segments.clear()
	_stroke_pending_time = 0.0
	_stroke_input_center = _world_to_cell(center)
	return true

func update_stroke(center: Vector3, delta_seconds: float) -> bool:
	if not _stroke_active or not center.is_finite() or not is_finite(delta_seconds) or delta_seconds < 0.0:
		return false
	if not _world_center_valid(center): return false
	var cell_center := _world_to_cell(center)
	var clamped_center := Vector3(clampf(cell_center.x, 0.0, patch_size.x - 0.001), clampf(cell_center.y, 0.0, patch_size.y - 0.001), clampf(cell_center.z, 0.0, patch_size.z - 0.001))
	_stroke_segments.append({"a": _stroke_input_center, "b": clamped_center, "duration": delta_seconds, "elapsed": 0.0})
	_stroke_input_center = clamped_center
	_stroke_pending_time += delta_seconds
	var started := Time.get_ticks_usec()
	var mutations_before := _stroke_mutations
	_defer_native_updates = true
	while _stroke_pending_time + 0.0000001 >= SCULPT_FIXED_DT:
		_consume_stroke_time(SCULPT_FIXED_DT)
		_stroke_pending_time -= SCULPT_FIXED_DT
	_defer_native_updates = false
	_flush_native_updates()
	_last_edit_ms = (Time.get_ticks_usec() - started) / 1000.0
	return _stroke_mutations != mutations_before

func end_stroke() -> bool:
	if not _stroke_active:
		return false
	if _stroke_pending_time > 0.0000001:
		_defer_native_updates = true
		_consume_stroke_time(_stroke_pending_time)
		_stroke_pending_time = 0.0
		_defer_native_updates = false
		_flush_native_updates()
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
		_dirty = _stroke_before_dirty
		_clear_stroke()
		return false
	_redo.clear()
	_history_bytes -= redo_bytes
	_undo.append({"min": region_min, "size": region_size, "before": before_region, "after": after_region})
	_last_edit_command = _undo.back()
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
	var was_dirty := _dirty
	was_dirty = _stroke_before_dirty
	_clear_stroke()
	_dirty = was_dirty
	if had_changes:
		_error = ""
		changed.emit()
	return true

func sample_surface_plane(center: Vector3, normal: Vector3 = Vector3.UP, radius: float = 3.0) -> Dictionary:
	if not _backend_ready or voxels == null or not center.is_finite() or not normal.is_finite() or not is_finite(radius) or radius <= 0.0:
		return {"valid": false, "error": "invalid surface sample"}
	if not _world_center_valid(center): return {"valid": false, "error": "surface outside terrain bounds"}
	if normal.length_squared() < 0.000001:
		return {"valid": false, "error": "surface normal is zero"}
	var query_normal := normal.normalized()
	var cell_center := _world_to_cell(center)
	var cell_radius := clampf(_world_radius_to_cells(radius), 1.0, 8.0 / voxel_scale)
	var hit := _find_surface_hit(cell_center, query_normal, cell_radius)
	if not bool(hit.get("valid", false)):
		return hit
	var point: Vector3 = hit["point"]
	var slope := _fit_surface_slopes(point, cell_radius) if absf(query_normal.y) >= 0.5 else Vector2.ZERO
	var fitted_normal := Vector3(-slope.x, 1.0, -slope.y).normalized()
	if absf(query_normal.y) < 0.5: fitted_normal = query_normal
	if query_normal.y < -0.5:
		fitted_normal = -fitted_normal
	return {"valid": true, "point": _cell_to_world(point), "normal": fitted_normal, "slope_x": slope.x, "slope_z": slope.y}

func get_stroke_state() -> Dictionary:
	var reference := _stroke_reference.duplicate(true)
	if reference.get("point", null) is Vector3: reference["point"] = _cell_to_world(reference["point"])
	return {"active": _stroke_active, "tool": _stroke_tool, "reference": reference, "changed_count": _stroke_changed_count(), "front_distance": _stroke_front_distance * voxel_scale}

## Preview only: track the edited local frontier without moving the input
## plane or raycasting through a newly opened void onto distant geometry.
func get_stroke_preview_center(world_input_center: Vector3) -> Vector3:
	if not _stroke_active or _stroke_tool not in [SCULPT_TOOL_RAISE, SCULPT_TOOL_DIG] or not world_input_center.is_finite(): return world_input_center
	var point := _world_to_cell(world_input_center)
	var column := Vector3i(point.floor())
	column[_stroke_front_axis] = 0
	var key := _column_key(column)
	if not _stroke_fronts.has(key): return world_input_center
	var coordinate := int(_stroke_fronts[key])
	var boundary_offset := 1 if (_stroke_tool == SCULPT_TOOL_RAISE and _stroke_front_sign < 0) or (_stroke_tool == SCULPT_TOOL_DIG and _stroke_front_sign > 0) else 0
	point[_stroke_front_axis] = clampf(float(coordinate + boundary_offset), 0.0, float(patch_size[_stroke_front_axis]))
	return _cell_to_world(point)

## Last committed edit, undo or redo, in backend world coordinates. Derive
## exact changed cells from the existing history buffers instead of retaining
## a second per-cell list for every transaction. Cancel leaves this unchanged.
func get_last_edit_bounds() -> AABB:
	if _last_edit_command.is_empty(): return AABB()
	return AABB(Vector3(_last_edit_command["min"]) * voxel_scale, Vector3(_last_edit_command["size"]) * voxel_scale)

func get_last_edit_cells() -> Array[Vector3]:
	var result: Array[Vector3] = []
	if _last_edit_command.is_empty(): return result
	var origin: Vector3i = _last_edit_command["min"]
	var size: Vector3i = _last_edit_command["size"]
	var before: Object = _last_edit_command["before"]
	var after: Object = _last_edit_command["after"]
	for x in size.x:
		for y in size.y:
			for z in size.z:
				if before.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE) != after.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE):
					result.append((Vector3(origin + Vector3i(x, y, z)) + Vector3.ONE * 0.5) * voxel_scale)
	return result

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

func save_world(building_document: Dictionary = {}) -> bool:
	if _stroke_active:
		_save_status = "error"; _error = "cannot save while a sculpt stroke is active"; return false
	if not _backend_ready:
		_save_status = "error"; _error = "backend not ready"; return false
	var ok: bool = _checkpoint.save(voxels, _revision, generator_id, building_document)
	_save_status = "saved" if ok else "error"
	if ok: _dirty = false
	if not ok: _error = _checkpoint.last_error
	return ok

func load_world() -> bool:
	if _stroke_active:
		_save_status = "error"; _error = "cannot load while a sculpt stroke is active"; return false
	if not _backend_ready:
		_save_status = "error"; _error = "backend not ready"; return false
	loaded_building_document = {}
	var loaded = _checkpoint.load()
	var source_store: RefCounted = _checkpoint
	var migrated := false
	if loaded == null and initial_generator == M1Generator and generator_id == M1Generator.GENERATOR_ID and patch_size == M1Generator.PATCH_SIZE and is_equal_approx(voxel_scale, M1Generator.VOXEL_SCALE):
		var legacy_store := CheckpointStore.new(checkpoint_root)
		legacy_store.expected_dimensions = M1Generator.LEGACY_PATCH_SIZE
		legacy_store.expected_generator_id = M1Generator.LEGACY_GENERATOR_ID
		legacy_store.require_building_document = require_building_document
		var legacy: Object = legacy_store.load()
		if legacy != null:
			loaded = _upsample_legacy_m1(legacy)
			source_store = legacy_store
			migrated = loaded != null
	if loaded == null:
		_save_status = "error"; _error = _checkpoint.last_error; return false
	var loaded_revision: int = source_store.loaded_revision
	voxels = loaded
	loaded_building_document = source_store.loaded_building_document.duplicate(true)
	terrain.get_voxel_tool().paste(Vector3i.ZERO, voxels, 1)
	_undo.clear(); _redo.clear(); _history_bytes = 0
	_last_edit_command = {}
	_revision = loaded_revision
	_dirty = migrated
	_save_status = "migrated" if migrated else "loaded"; _error = ""
	_last_edit_submitted_at_ms = Time.get_ticks_msec()
	changed.emit()
	return true

func _upsample_legacy_m1(source: Object) -> Object:
	if source == null or source.get_size() != M1Generator.LEGACY_PATCH_SIZE: return null
	var result: Object = ClassDB.instantiate("VoxelBuffer")
	result.create(M1Generator.PATCH_SIZE.x, M1Generator.PATCH_SIZE.y, M1Generator.PATCH_SIZE.z)
	result.set_channel_depth(PatchGenerator.CHANNEL_TYPE, source.get_channel_depth(PatchGenerator.CHANNEL_TYPE))
	# Expand every vertical material run, including caves and disconnected
	# overhangs. No sampling, surface reconstruction or save rewrite occurs.
	var dimensions: Vector3i = source.get_size()
	const FACTOR := 4
	for x in dimensions.x:
		for z in dimensions.z:
			var start := 0
			while start < dimensions.y:
				var value := int(source.get_voxel(x, start, z, PatchGenerator.CHANNEL_TYPE))
				var end := start + 1
				while end < dimensions.y and int(source.get_voxel(x, end, z, PatchGenerator.CHANNEL_TYPE)) == value: end += 1
				if value != 0:
					result.fill_area(value, Vector3i(x, start, z) * FACTOR, Vector3i(x + 1, end, z + 1) * FACTOR, PatchGenerator.CHANNEL_TYPE)
				start = end
	return result

func voxel_at(pos: Vector3i) -> int:
	if not _backend_ready or pos.x < 0 or pos.y < 0 or pos.z < 0 or pos.x >= patch_size.x or pos.y >= patch_size.y or pos.z >= patch_size.z: return 0
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
	var stationary_duration := 0.0
	var stationary_center := Vector3.ZERO
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
		if start == finish:
			if stationary_duration > 0.0 and stationary_center != start:
				_integrate_stroke_sample(stationary_center, stationary_duration)
				stationary_duration = 0.0
			stationary_center = start
			stationary_duration += consumed
		else:
			if stationary_duration > 0.0:
				_integrate_stroke_sample(stationary_center, stationary_duration)
				stationary_duration = 0.0
			_integrate_stroke_path(start.lerp(finish, alpha0), start.lerp(finish, alpha1), consumed)
		segment["elapsed"] = segment_elapsed + consumed
		_stroke_segments[0] = segment
		remaining -= consumed
		if float(segment["elapsed"]) >= segment_duration - 0.0000001:
			_stroke_segments.pop_front()
	if stationary_duration > 0.0:
		_integrate_stroke_sample(stationary_center, stationary_duration)

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
		# Each plane pass follows one connected surface transition. Subdivide
		# fast fine-grid input so its rate remains world units/sec, while every
		# pass still stops precisely at its fixed plane or a newly opened void.
		var steps := mini(patch_size.y, maxi(1, ceili(float(_stroke_settings["strength"]) * duration)))
		for _i in steps: _integrate_level_sample(center, duration / float(steps))
	else:
		_integrate_smooth_sample(center, duration)

func _integrate_front_sample(center: Vector3, duration: float) -> void:
	var radius: float = _stroke_settings["radius"]
	# A held brush keeps its footprint and falloff; only its frontier moves.
	# Reuse that footprint until input position changes, including across
	# fixed ticks spanning two input frames with identical stationary centres.
	if center != _stroke_front_cache_center:
		_stroke_front_cache_center = center
		_stroke_front_columns = _stroke_columns(center, radius)
		_stroke_front_influence.resize(_stroke_front_columns.size())
		var exponent := lerpf(1.0, 4.0, float(_stroke_settings["falloff"]))
		for i in _stroke_front_columns.size():
			var column := _stroke_front_columns[i]
			_ensure_front(column, center)
			_stroke_front_influence[i] = pow(maxf(0.0, 1.0 - _column_distance(column, center) / radius), exponent)
	var ready_columns: Array[Vector3i] = []
	var max_transitions := 0
	var rate := float(_stroke_settings["strength"]) * duration
	for i in _stroke_front_columns.size():
		var column := _stroke_front_columns[i]
		var accumulated := float(_stroke_accumulated.get(column, 0.0)) + rate * _stroke_front_influence[i]
		_stroke_accumulated[column] = accumulated
		if accumulated + 0.000001 >= 1.0:
			ready_columns.append(column)
			max_transitions = maxi(max_transitions, mini(patch_size[_stroke_front_axis], floori(accumulated + 0.000001)))
	_stroke_front_distance += float(_stroke_settings["strength"]) * duration * 0.5
	if ready_columns.is_empty():
		return
	var region := _front_region(ready_columns, max_transitions)
	var region_min: Vector3i = region[0]
	var region_max: Vector3i = region[1]
	_current_region_min = region_min
	var local: Object = _clone_region(voxels, region_min, region_max)
	var changed := false
	for column in ready_columns:
		var key := _column_key(column)
		# The local native buffer includes every transition due this sample.
		# Fine cells must not cap a 16 world-unit/sec brush at 60 cells/sec.
		var remaining := max_transitions
		while float(_stroke_accumulated[key]) + 0.000001 >= 1.0 and remaining > 0:
			_stroke_accumulated[key] = float(_stroke_accumulated[key]) - 1.0
			remaining -= 1
			var previous_front := int(_stroke_fronts[key])
			if _advance_front(local, column):
				changed = true
			elif int(_stroke_fronts[key]) == previous_front:
				# At a void or the finite boundary no work can advance. Avoid
				# accumulating an ever-larger local buffer for a stopped front.
				_stroke_accumulated[key] = 0.0
				break
	if changed:
		_write_region(local, region_min)

func _integrate_level_sample(center: Vector3, duration: float) -> void:
	var radius: float = _stroke_settings["radius"]
	var columns := _vertical_columns(center, radius)
	var candidates: Array[Dictionary] = []
	var region_min := Vector3i(patch_size.x, patch_size.y, patch_size.z)
	var region_max := Vector3i.ZERO
	var exponent := lerpf(1.0, 4.0, float(_stroke_settings["falloff"]))
	for column in columns:
		var distance := Vector2(float(column.x) - center.x, float(column.z) - center.z).length()
		if distance > radius:
			continue
		var column_key := _column_key(column)
		if not _stroke_fronts.has(column_key):
			_stroke_fronts[column_key] = _surface_y_near(voxels, column.x, column.z, center.y, radius + 2.0)
		# Keep following the same exposed surface as it moves beyond the
		# original sampling reach. Re-querying here stalled deep cuts and could
		# switch to a different floor after opening a cave.
		var surface_y := float(_stroke_fronts[column_key])
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
		if candidate.y < 0 or candidate.y >= patch_size.y:
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
		var key := _column_key(item["column"])
		_stroke_accumulated[key] = float(_stroke_accumulated.get(key, 0.0)) + float(item["amount"])
		if float(_stroke_accumulated[key]) + 0.000001 < 1.0:
			continue
		_stroke_accumulated[key] = float(_stroke_accumulated[key]) - 1.0
		_record_stroke_change(position, current, desired)
		local.set_voxel(desired, local_pos.x, local_pos.y, local_pos.z, PatchGenerator.CHANNEL_TYPE)
		if desired != 0:
			_stroke_fronts[key] = float(position.y + 1)
		else:
			var below := position - Vector3i(0, 1, 0)
			# An exposed void ends this column's front; do not cross a cave to
			# edit a disconnected floor on a later fixed tick.
			_stroke_fronts[key] = float(position.y) if below.y >= 0 and voxel_at(below) != 0 else -1.0
		changed = true
	if changed:
		_write_region(local, region_min)

func _integrate_smooth_sample(center: Vector3, duration: float) -> void:
	var radius: float = _stroke_settings["radius"]
	# Cache the connected surface being edited, not a replacement heightmap.
	# Only cache misses probe native columns. A retired front never retargets
	# a disconnected cave floor during the same held stroke.
	if center != _stroke_front_cache_center:
		_stroke_front_cache_center = center
		_stroke_front_columns = _vertical_columns(center, radius)
		_stroke_front_influence.resize(_stroke_front_columns.size())
		var exponent := lerpf(1.0, 4.0, float(_stroke_settings["falloff"]))
		for i in _stroke_front_columns.size():
			var column := _stroke_front_columns[i]
			var distance := Vector2(float(column.x) - center.x, float(column.z) - center.z).length()
			_stroke_front_influence[i] = pow(maxf(0.0, 1.0 - distance / radius), exponent)
		# Three cells cover every corner of a 5x5 neighbourhood. The halo
		# participates in the mean but is never itself a write footprint.
		for column in _vertical_columns(center, radius + 3.0):
			if not _stroke_fronts.has(column):
				_stroke_fronts[column] = _surface_y_near(voxels, column.x, column.z, center.y, radius + 2.0)
		_smooth_targets_dirty = true
	if _smooth_targets_dirty:
		_smooth_targets = SmoothNeighbourhood.means(_stroke_front_columns, _stroke_fronts)
		_smooth_targets_dirty = false
	var candidates: Array[Dictionary] = []
	var region_min := Vector3i(patch_size.x, patch_size.y, patch_size.z)
	var region_max := Vector3i.ZERO
	var rate := float(_stroke_settings["strength"]) * duration
	# All targets come from one immutable snapshot, before this tick writes.
	for i in _stroke_front_columns.size():
		var column := _stroke_front_columns[i]
		var current_surface := float(_stroke_fronts.get(column, -1.0))
		if current_surface < 0.0 or _smooth_targets[i] < 0.0 or _stroke_front_influence[i] <= 0.0: continue
		var difference := _smooth_targets[i] - current_surface
		# Native cells cannot move by 0.05 cells. Move only when a whole-cell
		# step improves the approximation; reset residual motion at rest or
		# reversal so old input cannot cause delayed up/down chatter.
		if absf(difference) <= 0.500001:
			_stroke_accumulated[column] = 0.0
			continue
		var direction := 1.0 if difference > 0.0 else -1.0
		var accumulated := float(_stroke_accumulated.get(column, 0.0))
		if accumulated * direction < 0.0: accumulated = 0.0
		accumulated += direction * rate * _stroke_front_influence[i]
		_stroke_accumulated[column] = accumulated
		if absf(accumulated) + 0.000001 < 1.0: continue
		_stroke_accumulated[column] = accumulated - direction
		var candidate := Vector3i(column.x, int(current_surface) - (1 if direction < 0.0 else 0), column.z)
		if candidate.y < 0 or candidate.y >= patch_size.y:
			_stroke_accumulated[column] = 0.0
			continue
		var desired := 0 if direction < 0.0 else int(_stroke_settings["material"])
		candidates.append({"column": column, "position": candidate, "desired": desired})
		region_min = region_min.min(candidate)
		region_max = region_max.max(candidate + Vector3i.ONE)
	# Fractional input and settled surfaces allocate no native edit buffers.
	if candidates.is_empty(): return
	_current_region_min = region_min
	var local: Object = _clone_region(voxels, region_min, region_max)
	var changed := false
	for item in candidates:
		var column: Vector3i = item["column"]
		var position: Vector3i = item["position"]
		var local_pos := position - region_min
		var current := int(local.get_voxel(local_pos.x, local_pos.y, local_pos.z, PatchGenerator.CHANNEL_TYPE))
		var desired: int = item["desired"]
		if (desired == 0 and current == 0) or (desired != 0 and current != 0):
			_stroke_fronts[column] = -1.0
			_stroke_accumulated[column] = 0.0
			_smooth_targets_dirty = true
			continue
		_record_stroke_change(position, current, desired)
		local.set_voxel(desired, local_pos.x, local_pos.y, local_pos.z, PatchGenerator.CHANNEL_TYPE)
		if desired != 0:
			_stroke_fronts[column] = float(position.y + 1)
		else:
			var below := position - Vector3i(0, 1, 0)
			_stroke_fronts[column] = float(position.y) if below.y >= 0 and voxel_at(below) != 0 else -1.0
		_smooth_targets_dirty = true
		changed = true
	if changed:
		_write_region(local, region_min)

func _vertical_columns(center: Vector3, radius: float) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var min_x := maxi(0, floori(center.x - radius))
	var max_x := mini(patch_size.x, ceili(center.x + radius) + 1)
	var min_z := maxi(0, floori(center.z - radius))
	var max_z := mini(patch_size.z, ceili(center.z + radius) + 1)
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
		for x in range(maxi(0, center_cell.x - extent), mini(patch_size.x, center_cell.x + extent + 1)):
			for z in range(maxi(0, center_cell.z - extent), mini(patch_size.z, center_cell.z + extent + 1)):
				if Vector2(float(x) - center.x, float(z) - center.z).length() <= radius: result.append(Vector3i(x, 0, z))
	elif axis == 0:
		for y in range(maxi(0, center_cell.y - extent), mini(patch_size.y, center_cell.y + extent + 1)):
			for z in range(maxi(0, center_cell.z - extent), mini(patch_size.z, center_cell.z + extent + 1)):
				if Vector2(float(y) - center.y, float(z) - center.z).length() <= radius: result.append(Vector3i(0, y, z))
	else:
		for x in range(maxi(0, center_cell.x - extent), mini(patch_size.x, center_cell.x + extent + 1)):
			for y in range(maxi(0, center_cell.y - extent), mini(patch_size.y, center_cell.y + extent + 1)):
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

func _column_key(column: Vector3i) -> Vector3i:
	return column

func _ensure_front(column: Vector3i, center: Vector3) -> void:
	var key := _column_key(column)
	if _stroke_fronts.has(key): return
	var center_coordinate := floori(center[_stroke_front_axis])
	var max_coordinate := patch_size[_stroke_front_axis]
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

func _front_region(columns: Array[Vector3i], transitions: int = 1) -> Array[Vector3i]:
	var min_pos := Vector3i(patch_size.x, patch_size.y, patch_size.z)
	var max_pos := Vector3i.ZERO
	for column in columns:
		var front := int(_stroke_fronts[_column_key(column)])
		var cell := _column_cell(column, front)
		var direction := _stroke_front_sign if _stroke_tool == SCULPT_TOOL_RAISE else -_stroke_front_sign
		var adjacent := _column_cell(column, front + direction * transitions)
		min_pos.x = mini(min_pos.x, mini(cell.x, adjacent.x)); min_pos.y = mini(min_pos.y, mini(cell.y, adjacent.y)); min_pos.z = mini(min_pos.z, mini(cell.z, adjacent.z))
		max_pos.x = maxi(max_pos.x, maxi(cell.x, adjacent.x) + 1); max_pos.y = maxi(max_pos.y, maxi(cell.y, adjacent.y) + 1); max_pos.z = maxi(max_pos.z, maxi(cell.z, adjacent.z) + 1)
	min_pos.x = clampi(min_pos.x, 0, patch_size.x - 1); min_pos.y = clampi(min_pos.y, 0, patch_size.y - 1); min_pos.z = clampi(min_pos.z, 0, patch_size.z - 1)
	max_pos.x = clampi(max_pos.x, min_pos.x + 1, patch_size.x); max_pos.y = clampi(max_pos.y, min_pos.y + 1, patch_size.y); max_pos.z = clampi(max_pos.z, min_pos.z + 1, patch_size.z)
	return [min_pos, max_pos]

func _advance_front(local: Object, column: Vector3i) -> bool:
	var key := _column_key(column)
	var coordinate := int(_stroke_fronts[key])
	var cell := _column_cell(column, coordinate)
	if coordinate < 0 or coordinate >= patch_size[_stroke_front_axis]:
		return false
	var local_cell := cell - _current_region_min
	var current := int(local.get_voxel(local_cell.x, local_cell.y, local_cell.z, PatchGenerator.CHANNEL_TYPE))
	var changed := false
	if _stroke_tool == SCULPT_TOOL_RAISE:
		if current == 0:
			_record_stroke_change(cell, current, int(_stroke_settings["material"]))
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
		_record_stroke_change(cell, current, 0)
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
	max_pos.x = mini(patch_size.x, max_pos.x); max_pos.y = mini(patch_size.y, max_pos.y); max_pos.z = mini(patch_size.z, max_pos.z)
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
	if _defer_native_updates:
		var region_max: Vector3i = region_min + local.get_size()
		if not _pending_native_region:
			_pending_native_min = region_min; _pending_native_max = region_max
			_pending_native_region = true
		else:
			_pending_native_min = _pending_native_min.min(region_min)
			_pending_native_max = _pending_native_max.max(region_max)
	else:
		terrain.get_voxel_tool().paste(region_min, local, 1)
	_dirty = true

func _flush_native_updates() -> void:
	if not _pending_native_region: return
	# Authoritative voxels already contain every time-integrated step. Publish
	# the bounded union once, avoiding repeated remesh submissions when a slow
	# frame consumes several fixed ticks. No simulation time is discarded.
	var local: Object = _clone_region(voxels, _pending_native_min, _pending_native_max)
	terrain.get_voxel_tool().paste(_pending_native_min, local, 1)
	_pending_native_region = false
	_last_edit_submitted_at_ms = Time.get_ticks_msec()

func _record_stroke_change(position: Vector3i, current: int, desired: int) -> void:
	var key := _stroke_key(position)
	if not _stroke_before.has(key):
		_stroke_before[key] = current
		_stroke_positions.append(position)
	var original := int(_stroke_before[key])
	# Track exact net differences, including smoothing a cell back to its
	# original value. Mutation count separately reports edits whose net count
	# stays equal. Neither readout scans the growing stroke every frame.
	_stroke_changed_cells += int(desired != original) - int(current != original)
	if desired != current: _stroke_mutations += 1

func _stroke_changed_count() -> int:
	return _stroke_changed_cells

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
	_stroke_front_cache_center = Vector3.INF
	_stroke_front_columns.clear()
	_stroke_front_influence.clear()
	_smooth_targets.clear()
	_smooth_targets_dirty = true
	_stroke_before.clear()
	_stroke_positions.clear()
	_stroke_changed_cells = 0
	_stroke_mutations = 0
	_stroke_accumulated.clear()
	_stroke_segments.clear()
	_stroke_pending_time = 0.0
	_stroke_input_center = Vector3.ZERO

func _stroke_key(position: Vector3i) -> Vector3i:
	return position

func _find_surface_hit(center: Vector3, normal: Vector3, radius: float) -> Dictionary:
	var horizontal := Vector2(normal.x, normal.z).length()
	if absf(normal.y) >= horizontal:
		var center_x := floori(center.x)
		var center_z := floori(center.z)
		# UP samples the exposed top below the cursor. DOWN samples the first
		# ceiling underside above it; both stay on this exact x/z column so a
		# nearby roof cannot replace the user's centre hit.
		var surface_y := _surface_y_near(voxels, center_x, center_z, center.y, radius + 1.0) if normal.y >= 0.0 else _underside_y_near(voxels, center_x, center_z, center.y, radius + 1.0)
		if surface_y >= 0.0 and absf(surface_y - center.y) <= radius + 1.0:
			return {"valid": true, "point": Vector3(center.x, surface_y, center.z)}
	else:
		var axis := _dominant_axis(normal)
		var direction := 1 if (normal[axis] >= 0.0) else -1
		var center_cell := Vector3i(floori(center.x), floori(center.y), floori(center.z))
		var limit := ceili(radius) + 1
		# Keep the two non-facing coordinates on the exact cursor line. Search
		# both directions so a cursor in air can still find the nearby wall.
		for sign in [direction, -direction]:
			for step in limit + 1:
				var coordinate: int = center_cell[axis] + int(sign) * step
				if coordinate < 0 or coordinate >= patch_size[axis]: continue
				var cell := center_cell
				cell[axis] = coordinate
				var neighbour := cell
				neighbour[axis] += sign
				if neighbour[axis] < 0 or neighbour[axis] >= patch_size[axis]: continue
				if int(voxels.get_voxel(cell.x, cell.y, cell.z, PatchGenerator.CHANNEL_TYPE)) == 0: continue
				if int(voxels.get_voxel(neighbour.x, neighbour.y, neighbour.z, PatchGenerator.CHANNEL_TYPE)) != 0: continue
				var candidate := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
				candidate[axis] = float(cell[axis] + (1 if sign > 0 else 0))
				if candidate.distance_squared_to(center) <= (radius + 1.0) * (radius + 1.0):
					return {"valid": true, "point": candidate}
	return {"valid": false, "error": "no nearby surface hit"}

func _fit_surface_slopes(point: Vector3, radius: float) -> Vector2:
	var center_x := floori(point.x)
	var center_z := floori(point.z)
	var extent := ceili(radius)
	# A plane needs distributed neighbouring samples, not every fine native
	# column. Keep the same world-space neighbourhood with at most 7x7 probes
	# so higher terrain resolution does not multiply cursor-preview CPU cost.
	var stride := maxi(1, ceili(float(extent) / 3.0))
	var xx := 0.0
	var xz := 0.0
	var zz := 0.0
	var yx := 0.0
	var yz := 0.0
	for x in range(center_x - extent, center_x + extent + 1, stride):
		if x < 0 or x >= patch_size.x: continue
		for z in range(center_z - extent, center_z + extent + 1, stride):
			if z < 0 or z >= patch_size.z: continue
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
	for y in range(patch_size.y - 1, -1, -1):
		if int(source.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE)) != 0:
			return float(y + 1)
	return -1.0

func _surface_y_near(source: Object, x: int, z: int, center_y: float, reach: float) -> float:
	if x < 0 or z < 0 or x >= patch_size.x or z >= patch_size.z:
		return -1.0
	var start := clampi(floori(center_y), 0, patch_size.y - 1)
	var limit := ceili(maxf(reach, 1.0))
	if int(source.get_voxel(x, start, z, PatchGenerator.CHANNEL_TYPE)) != 0:
		var top := start
		while top + 1 < patch_size.y and int(source.get_voxel(x, top + 1, z, PatchGenerator.CHANNEL_TYPE)) != 0:
			top += 1
		return float(top + 1)
	# An air cursor normally targets the ground immediately below it. Search
	# down first; searching upward first can select a distant cave roof.
	for y in range(start - 1, maxi(-1, start - limit - 1), -1):
		if int(source.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE)) != 0:
			return float(y + 1)
	for y in range(start + 1, mini(patch_size.y, start + limit + 1)):
		if int(source.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE)) != 0:
			var top := y
			while top + 1 < patch_size.y and int(source.get_voxel(x, top + 1, z, PatchGenerator.CHANNEL_TYPE)) != 0:
				top += 1
			return float(top + 1)
	return -1.0

func _underside_y_near(source: Object, x: int, z: int, center_y: float, reach: float) -> float:
	if x < 0 or z < 0 or x >= patch_size.x or z >= patch_size.z:
		return -1.0
	var start := clampi(floori(center_y), 0, patch_size.y - 1)
	var limit := ceili(maxf(reach, 1.0))
	# Prefer the nearest solid cell whose lower face borders air. This is the
	# underside of a ceiling, including when the cursor itself is inside it.
	for distance in limit + 1:
		var below := start - distance
		if below >= 0 and int(source.get_voxel(x, below, z, PatchGenerator.CHANNEL_TYPE)) != 0:
			if below == 0 or int(source.get_voxel(x, below - 1, z, PatchGenerator.CHANNEL_TYPE)) == 0:
				return float(below)
		var above := start + distance
		if above < patch_size.y and int(source.get_voxel(x, above, z, PatchGenerator.CHANNEL_TYPE)) != 0:
			if above == 0 or int(source.get_voxel(x, above - 1, z, PatchGenerator.CHANNEL_TYPE)) == 0:
				return float(above)
	return -1.0

func _sphere_region(center: Vector3, radius: float) -> Array[Vector3i]:
	var min_pos := Vector3i(floori(center.x - radius), floori(center.y - radius), floori(center.z - radius))
	var max_pos := Vector3i(ceili(center.x + radius) + 1, ceili(center.y + radius) + 1, ceili(center.z + radius) + 1)
	min_pos.x = maxi(0, min_pos.x); min_pos.y = maxi(0, min_pos.y); min_pos.z = maxi(0, min_pos.z)
	max_pos.x = mini(patch_size.x, max_pos.x); max_pos.y = mini(patch_size.y, max_pos.y); max_pos.z = mini(patch_size.z, max_pos.z)
	return [min_pos, max_pos]

func _simulate_sphere(center: Vector3, radius: float, remove: bool) -> Dictionary:
	if not _backend_ready or voxels == null or not center.is_finite() or not is_finite(radius) or radius <= 0.0 or radius > 8.0:
		return {}
	if not _world_center_valid(center):
		return {}
	var cell_center := _world_to_cell(center)
	var cell_radius := _world_radius_to_cells(radius)
	var region := _sphere_region(cell_center, cell_radius)
	var region_min: Vector3i = region[0]
	var region_max: Vector3i = region[1]
	var before_full: Object = _clone_buffer(voxels)
	var after_full: Object = _clone_buffer(voxels)
	var buffer_tool = after_full.get_voxel_tool()
	buffer_tool.channel = PatchGenerator.CHANNEL_TYPE
	buffer_tool.mode = 2
	buffer_tool.value = 0 if remove else 2
	buffer_tool.do_sphere(cell_center, cell_radius)
	var changed: Array[Vector3i] = []
	for x in range(region_min.x, region_max.x):
		for y in range(region_min.y, region_max.y):
			for z in range(region_min.z, region_max.z):
				if before_full.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE) != after_full.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE):
					changed.append(Vector3i(x, y, z))
	return {"region": region, "before": before_full, "after": after_full, "changed": changed}

func _clone_buffer(source: Object) -> Object:
	var copy: Object = ClassDB.instantiate("VoxelBuffer")
	copy.create(patch_size.x, patch_size.y, patch_size.z)
	copy.copy_channel_from(source, PatchGenerator.CHANNEL_TYPE)
	return copy

func _extract_region(source: Object, region_min: Vector3i, region_max: Vector3i) -> Object:
	var size := region_max - region_min
	var out: Object = ClassDB.instantiate("VoxelBuffer")
	out.create(size.x, size.y, size.z)
	out.copy_channel_from_area(source, region_min, region_max, Vector3i.ZERO, PatchGenerator.CHANNEL_TYPE)
	return out

func _apply_command_region(command: Dictionary, region: Object) -> void:
	_last_edit_command = command
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
