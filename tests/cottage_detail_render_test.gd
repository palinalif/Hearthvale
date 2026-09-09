extends "res://tests/m1_playtest_repair_render_test.gd"
## Focused current-scene visual evidence using a disposable native world.
## The full inherited interaction render suite remains a separate gate.
var baseline_script := ""

func _capture(name: String) -> Image:
	if not baseline_script.is_empty():
		var script: Script = load(baseline_script)
		for visual in scene.cottage_visuals.values():
			if visual.get_script() != script:
				var id: String = visual.building_id
				visual.set_script(script)
				visual.apply_building(scene.building_world.get_building(id), scene.building_world.get_revision())
	return await super._capture(name)

func _run() -> void:
	folder = "reports/screenshots/m1-cottage-detail"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline-visual="):
			baseline_script = argument.trim_prefix("--baseline-visual=")
			folder += "-baseline"
	if RenderingServer.get_current_rendering_method() != "mobile" or DisplayServer.get_name() == "headless":
		print("COTTAGE_DETAIL_RENDER_UNAVAILABLE")
		quit(2)
		return
	print("COTTAGE_DETAIL_RENDER " + JSON.stringify({"method": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(), "adapter": RenderingServer.get_video_adapter_name()}))
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(folder)
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m1-detail-render-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 120000
	while (not scene._player_restored or not scene.backend or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline:
		await process_frame
		if scene.backend and not scene.backend.is_ready():
			var backend_error := str(scene.backend.get("_error"))
			if not backend_error.is_empty() and backend_error != "no valid checkpoint": break
	check(scene._player_restored and scene.backend.is_ready(), "native scene ready")
	if not scene._player_restored:
		_finish()
		return
	scene.set_process(false)
	scene._set_view_context("building")
	scene._update_presentation()
	scene.hud.visible = false
	# Same normal and close framing can be replayed against an earlier renderer.
	scene.camera_yaw = PI * 1.20
	scene.camera_pitch = 0.40
	scene.camera_distance = 16.0
	scene._update_camera()
	await _capture("01-normal-clean")
	scene.camera_distance = 7.0
	scene._update_camera()
	await _capture("02-close-clean")
	var id: String = scene.selected_building_id
	var view: Dictionary = scene.building_world.get_building(id)
	var front_windows: Array = []
	for detail in view["details"]:
		if detail.get("kind", "") == "window" and detail.get("anchor", {}).get("surface_id", "") == "wall-front":
			front_windows.append(detail)
	# Manual attachments reserve horizontal wall slots in the existing recipe.
	# Lock these windows through the ordinary edit API before adding planters so
	# the fixture demonstrates both families without altering that layout policy.
	for detail in front_windows:
		check(scene.building_world.move_detail(id, str(detail["id"]), "wall-front", detail["resolved_position"]), "retain edited fixture window")
	for i in mini(3, front_windows.size()):
		var position: Vector3 = front_windows[i]["resolved_position"]
		position.y -= 2.5
		check(not scene.building_world.add_detail(id, "flower_box", "wall-front", position, "flower_box_wood").is_empty(), "editable planter fixture %d" % i)
	if front_windows.size() > 1:
		check(scene.building_world.replace_detail(id, str(front_windows[1]["id"]), "window_round"), "editable round-window fixture")
	if not front_windows.is_empty():
		check(scene.building_world.resize_detail(id, str(front_windows[0]["id"]), Vector2(2.5, 3.0)), "editable resized-window fixture")
	var door: Dictionary = {}
	for detail in scene.building_world.get_building(id)["details"]:
		if str(detail.get("kind", "")) == "door": door = detail
	check(not door.is_empty(), "editable door fixture exists")
	if not door.is_empty():
		var door_position: Vector3 = door["resolved_position"]
		door_position.z -= 2.0
		check(scene.building_world.move_detail(id, str(door["id"]), str(door["anchor"]["surface_id"]), door_position), "editable moved-door fixture")
		check(scene.building_world.resize_detail(id, str(door["id"]), Vector2(2.25, 4.0)), "editable resized-door fixture")
		scene.selected_detail_id = str(door["id"])
		check(scene._commit_detail_style(str(door["id"]), str(door["asset_id"]), "berry"), "editable recoloured-door fixture")
	check(not scene.building_world.add_detail(id, "shutter", "wall-left", Vector3(-view["dimensions"].x * 0.5 - 0.02, 3.4, 3.0), "shutter_wood").is_empty(), "editable manual-shutter fixture")
	for detail in scene.building_world.get_building(id)["details"]:
		if detail.get("kind", "") in ["flower_box", "shutter"]:
			check(detail.get("visible", false) and not detail.get("needs_placement", true), "fixture attachment is actually placed: " + str(detail["id"]))
	scene._update_presentation()
	scene._update_camera()
	var before := await _capture("03-detail-families")
	scene.camera_yaw = -PI * 0.5
	scene.camera_distance = 7.0
	scene._update_camera()
	await _capture("06-editable-openings")
	scene.camera_yaw = PI * 1.20
	scene._update_camera()
	var record: Dictionary = scene.building_world.get_document()
	scene._update_presentation()
	var repeated := await _capture("04-repeat-stability")
	check(before.get_data() == repeated.get_data(), "unchanged recipe renders identically")
	check(scene.building_world.get_document() == record, "capture and presentation preserve authority")
	check(scene.building_world.resize(id, Vector3(23, 8, 12)), "edited cottage fixture resizes")
	scene._update_presentation()
	scene.camera_distance = 9.0
	scene._update_camera()
	await _capture("05-resized-details")
	print("COTTAGE_DETAIL_RENDER_RESULT " + JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "folder": folder}))
	_finish()
