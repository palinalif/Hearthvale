extends RefCounted

const DEFAULT_TIMEOUT_MS := 30000

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
	if backend != null and backend.has_method("is_ready"):
		backend_ready = bool(backend.is_ready())
	return {
		"timeout_ms": timeout_ms,
		"player_restored": bool(scene.get("_player_restored")),
		"restoring": bool(scene.get("_restoring")),
		"backend_exists": backend != null,
		"backend_ready": backend_ready,
		"building_world_exists": scene.get("building_world") != null,
		"landscape_state_exists": scene.get("landscape_state") != null,
		"status_text": str(scene.get("status_text")),
	}
