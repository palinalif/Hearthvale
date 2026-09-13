extends SceneTree
## Real production scene and Mobile rendering. Never reads or clears player saves.
const Planters = preload("res://scripts/m2_planter_assets.gd")
const OUTPUT := "res://reports/screenshots/m2-planters"
var scene: Node
var failures: Array[String] = []
var captures: Array[String] = []
var placed_ids: Array[int] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		if "--planter-render-child" in OS.get_cmdline_user_args():
			push_error("Actual Mobile rendering unavailable")
			quit(1)
			return
		var output: Array = []
		var status := OS.execute(OS.get_executable_path(), ["--path", ProjectSettings.globalize_path("res://"), "--rendering-method", "mobile", "--disable-vsync", "--max-fps", "60", "--script", "res://tests/m2_planter_render_test.gd", "--", "--planter-render-child"], output, true)
		var log_dir := "res://reports/logs/m2-planter-pipeline"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(log_dir))
		var text := "\n".join(output)
		var log := FileAccess.open(log_dir + "/mobile.log", FileAccess.WRITE)
		if log:
			log.store_string(text)
			log.close()
		print(text.right(6500))
		quit(1 if status != 0 or text.contains("SCRIPT ERROR") or text.contains("ERROR:") else 0)
		return
	_check(RenderingServer.get_current_rendering_method() == "mobile", "Uses actual Mobile renderer")
	root.size = Vector2i(1280, 720)
	scene = load("res://scenes/m1.tscn").instantiate()
	scene.checkpoint_root = "user://m2-planter-render-%d" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 120000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene._player_restored, "Production scene ready")
	if not scene._player_restored:
		await _finish()
		return
	_check(scene.building_world.get_buildings().size() == 3, "Existing three-home starter retained")
	await _settle(800)
	scene.set_process(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	_clean(true)
	await _capture("starter-normal")
	# Existing saved-style starter planter must resolve to the new full arrangement.
	_frame(Vector3(23.75, 8.4, 16.0), -1.3, 0.75, 4.5)
	await _capture("starter-planter-close")
	var points: Array[Vector2] = [Vector2(21, 25), Vector2(22.125, 25), Vector2(23.25, 25)]
	for index in Planters.STYLE_IDS.size():
		var style: String = Planters.STYLE_IDS[index]
		await _select_card(style)
		if not scene.furniture_placement_active: continue
		_aim(points[index])
		_check(scene.furniture_placement_valid, "Valid target for " + style)
		var ghost: MeshInstance3D = scene.composition_visual._furniture_preview_node
		_check(ghost != null and ghost.get_meta("authored_asset", "") == Planters.PATHS[style], "Preview uses exported asset " + style)
		placed_ids.append(int(scene.landscape_state.next_id))
		_check(scene._commit_furniture(), "Commit actual catalogue selection " + style)
	_clean(true)
	_frame(Vector3(22.125, 8.45, 25), -1.55, 0.73, 15.0)
	await _capture("family-normal")
	_frame(Vector3(22.125, 8.4, 25), -1.55, 0.78, 4.5)
	await _capture("family-close")
	_frame(Vector3(22.125, 8.4, 25), 1.6, 0.92, 4.5)
	await _capture("family-reverse")
	# Catalogue images come from the same runtime factory, not illustrations.
	_clean(false)
	scene._open_build_browser("outdoor", true)
	deadline = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		var complete := true
		for style: String in Planters.STYLE_IDS:
			if not scene._catalogue_thumbnails.cache.has(style): complete = false
		if complete: break
		await process_frame
	for style: String in Planters.STYLE_IDS:
		_check(scene._catalogue_thumbnails.cache.has(style), "Real catalogue thumbnail " + style)
	await _capture("catalogue")
	scene._close_build_browser()
	await _select_card("barrel_planter_herbs")
	_aim(Vector2(22.125, 23.75))
	var before := JSON.stringify(scene.landscape_state.document())
	_frame(Vector3(22.125, 8.4, 24.6), -1.55, 0.85, 5.5)
	scene._refresh_controller_hud()
	await _capture("placement-preview")
	_check(JSON.stringify(scene.landscape_state.document()) == before, "Capturing placement never changes authority")
	scene._cancel_furniture_placement()
	_clean(true)
	# Additional requested inspection: current, unchanged procedural garden assets.
	for entry: Array in [["kitchen", Vector3(16, 8.3, 33.75), 0.6], ["flowers", Vector3(30.25, 8.3, 35), 1.6], ["herbs", Vector3(20.25, 8.3, 21), -1.6]]:
		_frame(entry[1], float(entry[2]), 0.92, 5.0)
		await _capture("garden-" + str(entry[0]) + "-inspection")
	await _finish()

func _select_card(style: String) -> void:
	print("PLANTER_SELECT_BEFORE " + JSON.stringify({"style":style, "menu":scene.menu_open, "browser":scene._browser_open, "blocked":scene._blocked_until_accept_release, "restoring":scene._restoring, "detail_active":scene.detail_placement_active}))
	scene.hud.visible = true
	scene._open_build_browser("outdoor", true)
	await _settle(100)
	var selected: Button
	for card: Button in scene._build_browser.cards:
		if str(card.get_meta("item")["id"]) == style: selected = card
	_check(selected != null, "Catalogue card exists " + style)
	if selected == null: return
	selected.grab_focus()
	await _press(JOY_BUTTON_A)
	print("PLANTER_SELECT_AFTER " + JSON.stringify({"wanted":style, "actual":scene.furniture_style_id, "menu":scene.menu_open, "browser":scene._browser_open, "blocked":scene._blocked_until_accept_release, "detail_active":scene.detail_placement_active}))
	_check(scene.furniture_placement_active and scene.furniture_style_id == style, "Controller selects " + style)

func _press(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	await _settle(80)

func _aim(point: Vector2) -> void:
	scene.cursor = Vector3(point.x, 8.0, point.y)
	scene.terrain_cursor = scene.cursor
	scene._update_brush_preview()
	scene._update_furniture_validity()
	scene._update_furniture_preview()

func _frame(target: Vector3, yaw: float, pitch: float, distance: float) -> void:
	scene.view_context = "terrain"
	scene.cursor = target - Vector3.UP * 2.0
	scene._free_camera_y = target.y
	scene._terrain_camera_goal_y = target.y
	scene._free_camera_valid = true
	scene.camera_yaw = yaw
	scene.camera_pitch = pitch
	scene.camera_distance = distance
	scene._update_camera()

func _clean(enabled: bool) -> void:
	scene.hud.visible = not enabled
	for name in ["brush_preview", "cursor_reticle", "reference_plane", "terrain_hit_marker", "terrain_edit_preview"]:
		var node = scene.get(name)
		if node != null: node.visible = not enabled

func _settle(milliseconds: int) -> void:
	var deadline := Time.get_ticks_msec() + milliseconds
	var frames := 0
	while frames < 3 or Time.get_ticks_msec() < deadline:
		await process_frame
		frames += 1

func _capture(label: String) -> void:
	await _settle(350)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := OUTPUT + "/" + label + ".png"
	_check(not image.is_empty() and image.save_png(path) == OK, "Saved actual game image " + label)
	captures.append(path)

func _finish() -> void:
	var receipt := {"ok": failures.is_empty(), "messages": failures, "renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name(), "engine": Engine.get_version_info(), "size": [1280, 720], "checkpoint_root": scene.checkpoint_root if scene else "", "physical_thor": false, "visual_approval": false, "captures": captures, "assets": {}}
	for style: String in Planters.STYLE_IDS:
		receipt.assets[style] = {"mesh": Planters.PATHS[style], "mesh_sha256": FileAccess.get_sha256(Planters.PATHS[style])}
	var file := FileAccess.open(OUTPUT + "/receipt.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(receipt, "\t"))
		file.close()
	print("PLANTER_MOBILE_CAPTURE " + JSON.stringify(receipt))
	if is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	quit(0 if failures.is_empty() else 1)
