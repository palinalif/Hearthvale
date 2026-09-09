extends SceneTree
## Actual Mobile-renderer proof for the four player-editable building-detail
## families. Uses the exported gameplay scene without touching player saves.

var scene: Node
var checks := 0
var failures := 0
const OUTPUT := "reports/screenshots/m2-home-details/decoration-variants.png"

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)

func _run() -> void:
	if RenderingServer.get_current_rendering_method() != "mobile" or DisplayServer.get_name() == "headless":
		print("M2_DECORATION_RENDER_UNAVAILABLE")
		quit(2)
		return
	print("M2_DECORATION_RENDER_START " + JSON.stringify({"method": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(), "adapter": RenderingServer.get_video_adapter_name()}))
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUTPUT.get_base_dir())
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-decoration-render-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(scene.backend != null and scene.backend.is_ready() and scene._player_restored, "native gameplay world becomes renderable")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building")
	var building_id: String = scene.selected_building_id
	var building: Dictionary = scene.building_world.get_building(building_id)
	var front := ""
	for surface in building.get("surfaces", []):
		if str(surface.get("orientation", "")) == "front": front = str(surface.get("id", ""))
	var window: Dictionary = {}
	for candidate in building.get("details", []):
		if str(candidate.get("anchor", {}).get("surface_id", "")) != front: continue
		if window.is_empty() and str(candidate.get("kind", "")) == "window" and bool(candidate.get("visible", false)): window = candidate
	_check(not front.is_empty() and not window.is_empty(), "front window fixture exists")
	if front.is_empty() or window.is_empty():
		await _finish()
		return
	_check(scene.building_world.replace_detail(building_id, str(window["id"]), "window_cottage_diamond"), "diamond window selected")
	var dimensions: Vector3 = building["dimensions"]
	var door_id: String = scene.building_world.add_detail(building_id, "door", front, Vector3(0, 1.85, -dimensions.z * 0.5 - 0.02), "door_cottage_stable")
	_check(not door_id.is_empty(), "stable door selected")
	var shutter_id: String = scene.building_world.add_detail(building_id, "shutter", front, Vector3(-8.0, 4.0, -dimensions.z * 0.5 - 0.02), "shutter_louvered")
	var box_id: String = scene.building_world.add_detail(building_id, "flower_box", front, Vector3(6.0, 1.25, -dimensions.z * 0.5 - 0.02), "flower_box_woven")
	_check(not shutter_id.is_empty() and not box_id.is_empty(), "louvered shutter and woven planter selected")
	scene._update_presentation()
	await process_frame
	var visual: Node3D = scene.cottage_visuals.get(building_id)
	_check(visual != null and visual.has_node("Joinery_" + str(window["id"])), "diamond window joinery reaches the presentation")
	_check(visual != null and visual.has_node("DoorJoinery_" + door_id), "stable door joinery reaches the presentation")
	_check(visual != null and visual.has_node("ManualShutter_" + shutter_id), "louvered shutter reaches the presentation")
	_check(visual != null and visual.has_node("FlowerBox_" + box_id), "woven planter reaches the presentation")
	scene.hud.visible = false
	var transform: Transform3D = building["transform"]
	var target: Vector3 = transform.origin + Vector3(0, 3.0, 0)
	scene.camera.global_position = target + Vector3(0, 2.0, -12.0)
	scene.camera.look_at(target)
	for frame in 6: await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(not image.is_empty() and image.get_size() == Vector2i(1280, 720), "Mobile frame is captured at the target UI resolution")
	_check(image.save_png(OUTPUT) == OK, "variant review capture is saved")
	await _finish()

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("M2_DECORATION_RENDER_RESULT " + JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "output": OUTPUT}))
	quit(1 if failures else 0)
