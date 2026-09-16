extends Node

const TIMEOUT_MS := 90000

var _receipt_path := ""
var _started_ms := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--terrain-ready-receipt="):
			_receipt_path = arg.trim_prefix("--terrain-ready-receipt=")
			break
	if _receipt_path.is_empty():
		set_process(false)
		return
	_started_ms = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var backend: Variant = scene.get("backend")
	if backend != null and backend.has_method("is_ready") and bool(backend.is_ready()):
		var receipt := _snapshot(backend, true)
		_write_receipt(receipt)
		print("TERRAIN_RUNTIME_READY " + JSON.stringify(receipt))
		get_tree().quit(0)
		return
	if Time.get_ticks_msec() - _started_ms >= TIMEOUT_MS:
		var receipt := _snapshot(backend, false)
		_write_receipt(receipt)
		push_error("TERRAIN_RUNTIME_TIMEOUT " + JSON.stringify(receipt))
		get_tree().quit(2)

func _snapshot(backend: Variant, ok: bool) -> Dictionary:
	var error := ""
	var terrain_statistics: Dictionary = {}
	var startup_area := AABB()
	var viewer_info: Array[Dictionary] = []
	if backend != null:
		if backend.has_method("stats"):
			error = str((backend.stats() as Dictionary).get("error", ""))
		if backend.has_method("initial_mesh_area"):
			startup_area = backend.initial_mesh_area()
		var terrain: Variant = backend.get("terrain")
		if terrain != null and terrain.has_method("get_statistics"):
			terrain_statistics = terrain.get_statistics()
		for child in backend.get_children():
			if child != null and child.get_class() == "VoxelViewer":
				viewer_info.append({
					"position": str((child as Node3D).position),
					"global_position": str((child as Node3D).global_position),
					"view_distance": int(child.get("view_distance")),
					"requires_visuals": bool(child.get("requires_visuals")),
				})
	return {
		"ok": ok,
		"elapsed_ms": Time.get_ticks_msec() - _started_ms,
		"backend_exists": backend != null,
		"backend_ready": ok,
		"phase": _backend_phase(backend, ok),
		"error": error,
		"renderer": RenderingServer.get_current_rendering_method(),
		"display": DisplayServer.get_name(),
		"startup_mesh_area": {
			"position": str(startup_area.position),
			"size": str(startup_area.size),
		},
		"terrain_statistics": terrain_statistics,
		"viewers": viewer_info,
	}

func _backend_phase(backend: Variant, ready: bool) -> String:
	if ready:
		return "ready"
	if backend == null:
		return "waiting_scene_backend"
	var terrain: Variant = backend.get("terrain")
	if terrain == null:
		return "creating_native_terrain"
	var voxels: Variant = backend.get("voxels")
	if voxels == null:
		return "generating_authoritative_voxels"
	var patch_size_value: Variant = backend.get("patch_size")
	if not patch_size_value is Vector3i:
		return "unknown"
	var full_area: AABB = AABB(Vector3.ZERO, Vector3(patch_size_value))
	var mesh_area: AABB = backend.initial_mesh_area() if backend.has_method("initial_mesh_area") else full_area
	if terrain.has_method("get_voxel_tool"):
		var tool: Variant = terrain.get_voxel_tool()
		if tool != null and tool.has_method("is_area_editable") and not tool.is_area_editable(full_area):
			return "waiting_editable"
	if terrain.has_method("is_area_meshed") and not terrain.is_area_meshed(mesh_area):
		return "waiting_meshed"
	return "finalizing"

func _write_receipt(receipt: Dictionary) -> void:
	var file := FileAccess.open(_receipt_path, FileAccess.WRITE)
	if file == null:
		push_error("Unable to write terrain runtime receipt: " + _receipt_path)
		return
	file.store_string(JSON.stringify(receipt, "\t") + "\n")
	file.close()
