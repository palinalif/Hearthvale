extends Node3D
class_name TerrainBackend

signal ready_changed(ready: bool)
signal changed

const PATCH_SIZE := Vector3i(48, 32, 48)
const CENTER := Vector3(24, 8, 24)
const MAX_HISTORY := 50
const MAX_HISTORY_BYTES := 128 * 1024 * 1024
const VOXEL_BYTES := 2
const PatchGenerator = preload("res://scripts/patch_generator.gd")
const CheckpointStore = preload("res://scripts/checkpoint_store.gd")

var terrain: Node
var voxels: Object
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

func _ready() -> void:
	_checkpoint = CheckpointStore.new(checkpoint_root)
	if not ClassDB.class_exists("VoxelTerrain") or not ClassDB.class_exists("VoxelMesherBlocky"):
		_error = "Native VoxelTerrain/VoxelMesherBlocky unavailable"
		return
	terrain = ClassDB.instantiate("VoxelTerrain")
	terrain.bounds = AABB(Vector3.ZERO, Vector3(PATCH_SIZE))
	var mesher: Object = ClassDB.instantiate("VoxelMesherBlocky")
	mesher.library = PatchGenerator.build_library()
	terrain.mesher = mesher
	if ClassDB.class_exists("VoxelGeneratorFlat"):
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
	voxels = PatchGenerator.generate()
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
	if not _backend_ready or voxels == null or not center.is_finite() or not is_finite(radius) or radius <= 0.0 or radius > 8.0:
		return false
	if center.x < 0.0 or center.y < 0.0 or center.z < 0.0 or center.x >= PATCH_SIZE.x or center.y >= PATCH_SIZE.y or center.z >= PATCH_SIZE.z:
		return false
	var region := _sphere_region(center, radius)
	var region_size: Vector3i = region[1] - region[0]
	var command_bytes := region_size.x * region_size.y * region_size.z * VOXEL_BYTES * 2
	var redo_bytes := _stack_bytes(_redo)
	var projected_bytes := _history_bytes - redo_bytes + command_bytes
	if _undo.size() >= MAX_HISTORY:
		projected_bytes -= _command_bytes(_undo[0])
	if projected_bytes > MAX_HISTORY_BYTES:
		return false
	var started := Time.get_ticks_usec()
	var before_full: Object = _clone_buffer(voxels)
	var after_full: Object = _clone_buffer(voxels)
	var buffer_tool = after_full.get_voxel_tool()
	buffer_tool.channel = PatchGenerator.CHANNEL_TYPE
	buffer_tool.mode = 2
	buffer_tool.value = 0 if remove else 2
	buffer_tool.do_sphere(center, radius)
	var region_min: Vector3i = region[0]
	var region_max: Vector3i = region[1]
	if not _region_differs(before_full, after_full, region_min, region_max):
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

func undo() -> bool:
	if not _backend_ready or _undo.is_empty(): return false
	var command: Dictionary = _undo.pop_back()
	_apply_command_region(command, command["before"])
	_redo.append(command)
	_revision += 1
	_dirty = true
	_last_edit_submitted_at_ms = Time.get_ticks_msec()
	changed.emit()
	return true

func redo() -> bool:
	if not _backend_ready or _redo.is_empty(): return false
	var command: Dictionary = _redo.pop_back()
	_apply_command_region(command, command["after"])
	_undo.append(command)
	_revision += 1
	_dirty = true
	_last_edit_submitted_at_ms = Time.get_ticks_msec()
	changed.emit()
	return true

func save_world() -> bool:
	if not _backend_ready:
		_save_status = "error"; _error = "backend not ready"; return false
	var ok: bool = _checkpoint.save(voxels, _revision, PatchGenerator.GENERATOR_ID)
	_save_status = "saved" if ok else "error"
	if ok: _dirty = false
	if not ok: _error = _checkpoint.last_error
	return ok

func load_world() -> bool:
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

func _sphere_region(center: Vector3, radius: float) -> Array[Vector3i]:
	var min_pos := Vector3i(floori(center.x - radius), floori(center.y - radius), floori(center.z - radius))
	var max_pos := Vector3i(ceili(center.x + radius) + 1, ceili(center.y + radius) + 1, ceili(center.z + radius) + 1)
	min_pos.x = maxi(0, min_pos.x); min_pos.y = maxi(0, min_pos.y); min_pos.z = maxi(0, min_pos.z)
	max_pos.x = mini(PATCH_SIZE.x, max_pos.x); max_pos.y = mini(PATCH_SIZE.y, max_pos.y); max_pos.z = mini(PATCH_SIZE.z, max_pos.z)
	return [min_pos, max_pos]

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

func _region_differs(a: Object, b: Object, region_min: Vector3i, region_max: Vector3i) -> bool:
	for x in range(region_min.x, region_max.x):
		for y in range(region_min.y, region_max.y):
			for z in range(region_min.z, region_max.z):
				if a.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE) != b.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE): return true
	return false

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
