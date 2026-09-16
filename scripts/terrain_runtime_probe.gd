extends Node

const TIMEOUT_MS := 90000
const NUDGE_AFTER_MS := 15000

var _receipt_path := ""
var _started_ms := 0
var _diagnostic_nudge := false
var _nudge_attempted := false
var _nudge_info: Dictionary = {}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--terrain-ready-receipt="):
			_receipt_path = arg.trim_prefix("--terrain-ready-receipt=")
		elif arg == "--terrain-diagnostic-nudge":
			_diagnostic_nudge = true
	if _receipt_path.is_empty():
		set_process(false)
		return
	_started_ms = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var backend: Variant = scene.get("backend")
	var elapsed_ms := Time.get_ticks_msec() - _started_ms
	if _diagnostic_nudge and not _nudge_attempted and backend != null and elapsed_ms >= NUDGE_AFTER_MS:
		_nudge_attempted = true
		_nudge_info = _run_diagnostic_nudge(backend)
		print("TERRAIN_RUNTIME_NUDGE " + JSON.stringify(_nudge_info))
	if backend != null and backend.has_method("is_ready") and bool(backend.is_ready()):
		var receipt := _snapshot(backend, true)
		_write_receipt(receipt)
		print("TERRAIN_RUNTIME_READY " + JSON.stringify(receipt))
		get_tree().quit(0)
		return
	if elapsed_ms >= TIMEOUT_MS:
		var receipt := _snapshot(backend, false)
		_write_receipt(receipt)
		push_error("TERRAIN_RUNTIME_TIMEOUT " + JSON.stringify(receipt))
		get_tree().quit(2)

func _snapshot(backend: Variant, ok: bool) -> Dictionary:
	var error := ""
	var terrain_statistics: Dictionary = {}
	var startup_area := AABB()
	var viewer_info: Array[Dictionary] = []
	var readback: Dictionary = {}
	if backend != null:
		if backend.has_method("stats"):
			error = str((backend.stats() as Dictionary).get("error", ""))
		if backend.has_method("initial_mesh_area"):
			startup_area = backend.initial_mesh_area()
		var terrain: Variant = backend.get("terrain")
		if terrain != null and terrain.has_method("get_statistics"):
			terrain_statistics = terrain.get_statistics()
		readback = _readback_snapshot(backend)
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
		"readback": readback,
		"diagnostic_nudge": _nudge_info,
		"viewers": viewer_info,
	}

func _readback_snapshot(backend: Variant) -> Dictionary:
	var terrain: Variant = backend.get("terrain")
	var source: Variant = backend.get("voxels")
	if terrain == null or source == null or not terrain.has_method("get_voxel_tool"):
		return {"available": false}
	var area: AABB = backend.initial_mesh_area() if backend.has_method("initial_mesh_area") else AABB()
	var sample_pos := _find_solid_sample(source, area)
	var tool: Variant = terrain.get_voxel_tool()
	if tool == null or not tool.has_method("get_voxel"):
		return {"available": false, "sample": str(sample_pos)}
	tool.set("channel", 0)
	var source_value := int(source.get_voxel(sample_pos.x, sample_pos.y, sample_pos.z, 0))
	var terrain_value := int(tool.get_voxel(sample_pos))
	return {
		"available": true,
		"sample": str(sample_pos),
		"source_value": source_value,
		"terrain_value": terrain_value,
		"matches_source": source_value == terrain_value,
		"startup_area_editable": bool(tool.is_area_editable(area)) if tool.has_method("is_area_editable") else false,
	}

func _find_solid_sample(source: Variant, area: AABB) -> Vector3i:
	var size: Vector3i = source.get_size()
	var x := clampi(floori(area.position.x + area.size.x * 0.5), 0, maxi(0, size.x - 1))
	var z := clampi(floori(area.position.z + area.size.z * 0.5), 0, maxi(0, size.z - 1))
	var min_y := clampi(floori(area.position.y), 0, maxi(0, size.y - 1))
	var max_y := clampi(ceili(area.position.y + area.size.y) - 1, min_y, maxi(min_y, size.y - 1))
	for y in range(max_y, min_y - 1, -1):
		if int(source.get_voxel(x, y, z, 0)) != 0:
			return Vector3i(x, y, z)
	return Vector3i(x, min_y, z)

func _run_diagnostic_nudge(backend: Variant) -> Dictionary:
	var terrain: Variant = backend.get("terrain")
	var source: Variant = backend.get("voxels")
	if terrain == null or source == null or not terrain.has_method("get_voxel_tool"):
		return {"attempted": true, "available": false}
	var area: AABB = backend.initial_mesh_area() if backend.has_method("initial_mesh_area") else AABB()
	var tool: Variant = terrain.get_voxel_tool()
	if tool == null or not tool.has_method("get_voxel") or not tool.has_method("set_voxel"):
		return {"attempted": true, "available": false}
	tool.set("channel", 0)
	var sample_pos := _find_solid_sample(source, area)
	var source_value := int(source.get_voxel(sample_pos.x, sample_pos.y, sample_pos.z, 0))
	var terrain_value_before := int(tool.get_voxel(sample_pos))
	var stats_before: Dictionary = terrain.get_statistics() if terrain.has_method("get_statistics") else {}
	var editable_before := bool(tool.is_area_editable(area)) if tool.has_method("is_area_editable") else false
	# Deliberately write the same value back through VoxelTool. This should be a
	# semantic no-op, but it exercises the normal single-voxel post-edit path.
	tool.set_voxel(sample_pos, terrain_value_before)
	var terrain_value_after := int(tool.get_voxel(sample_pos))
	var stats_after: Dictionary = terrain.get_statistics() if terrain.has_method("get_statistics") else {}
	return {
		"attempted": true,
		"available": true,
		"elapsed_ms": Time.get_ticks_msec() - _started_ms,
		"sample": str(sample_pos),
		"source_value": source_value,
		"terrain_value_before": terrain_value_before,
		"terrain_value_after": terrain_value_after,
		"matches_source_before": source_value == terrain_value_before,
		"editable_before": editable_before,
		"statistics_before": stats_before,
		"statistics_immediately_after": stats_after,
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
