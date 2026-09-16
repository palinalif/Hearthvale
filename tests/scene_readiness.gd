extends RefCounted

const DEFAULT_TIMEOUT_MS := 60000

static func wait_for_player(tree: SceneTree, scene: Node, timeout_ms: int = DEFAULT_TIMEOUT_MS) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not bool(scene.get("_player_restored")) and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	var ready := bool(scene.get("_player_restored"))
	if not ready:
		print("SCENE_READINESS_TIMEOUT " + JSON.stringify(snapshot(scene, timeout_ms)))
	return ready

static func snapshot(scene: Node, timeout_ms: int) -> Dictionary:
	var backend: Variant = scene.get("backend")
	var backend_ready := false
	var backend_phase := "missing"
	var backend_error := ""
	if backend != null:
		if backend.has_method("is_ready"):
			backend_ready = bool(backend.is_ready())
		if backend.has_method("stats"):
			var stats: Dictionary = backend.stats()
			backend_error = str(stats.get("error", ""))
		backend_phase = _backend_phase(backend, backend_ready)
	return {
		"timeout_ms": timeout_ms,
		"player_restored": bool(scene.get("_player_restored")),
		"restoring": bool(scene.get("_restoring")),
		"backend_exists": backend != null,
		"backend_ready": backend_ready,
		"backend_phase": backend_phase,
		"backend_error": backend_error,
		"building_world_exists": scene.get("building_world") != null,
		"landscape_state_exists": scene.get("landscape_state") != null,
		"status_text": str(scene.get("status_text")),
	}

static func _backend_phase(backend: Object, backend_ready: bool) -> String:
	if backend_ready:
		return "ready"
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
