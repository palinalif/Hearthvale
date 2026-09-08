extends SceneTree
## Real Mobile-renderer captures of the exported scene. Desktop rendering is
## not Thor performance or user visual approval. No player save files are used.
var scene: Node
var checks := 0
var failures := 0
var folder := ".tools/cottage-repair"

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)

func _capture(name: String) -> Image:
	for i in 4: await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(not image.is_empty() and image.get_width() >= 1000, "rendered image exists: " + name)
	check(image.save_png(folder.path_join(name + ".png")) == OK, "capture saved: " + name)
	return image

func _run() -> void:
	if RenderingServer.get_current_rendering_method() != "mobile" or DisplayServer.get_name() == "headless":
		print("COTTAGE_RENDER_UNAVAILABLE")
		quit(2)
		return
	print("COTTAGE_RENDER_START " + JSON.stringify({"method": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(), "adapter": RenderingServer.get_video_adapter_name()}))
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(folder)
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m1-repair-render-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "native world ready for rendering")
	if not scene._player_restored: _finish(); return
	scene.set_process(false)
	scene._set_view_context("building")
	var first_id: String = scene.selected_building_id
	var copy_id: String = scene.building_world.duplicate_building(first_id, Vector3(7, 0, 0))
	check(not copy_id.is_empty(), "second visible cottage created")
	scene.selected_building_id = copy_id
	scene._update_presentation()
	var a: Dictionary = scene.building_world.get_building(first_id)
	var b: Dictionary = scene.building_world.get_building(copy_id)
	var ta: Transform3D = a["transform"]
	var tb: Transform3D = b["transform"]
	var target := (ta.origin + tb.origin) * 0.5 + Vector3(0, 1.0, 0)
	scene.camera.global_position = target + Vector3(3, 5, -16)
	scene.camera.look_at(target)
	var front := ""
	for wall in b["surfaces"]:
		if str(wall.get("orientation", "")) == "front": front = str(wall["id"])
	var detail: Dictionary = {}
	for candidate in b["details"]:
		if str(candidate.get("anchor", {}).get("surface_id", "")) == front and bool(candidate.get("visible", false)) and not bool(candidate.get("needs_placement", false)):
			detail = candidate
			break
	check(not detail.is_empty(), "visible window fixture exists")
	if detail.is_empty(): _finish(); return
	scene.edit_pointer = scene.camera.unproject_position(tb * (detail["resolved_position"] as Vector3))
	scene._update_detail_hover()
	scene._update_direct_edit_hud()
	scene._refresh_controller_hud()
	scene._update_cursor_reticle()
	check(scene.hovered_detail_id == str(detail["id"]), "rendered window is the highlighted target")
	await _capture("01-window-hover")
	scene.hud.visible = false
	var baseline := await _capture("02-two-cottages-clean")
	scene.hud.visible = true
	scene._open_hovered_detail_actions()
	scene._refresh_controller_hud()
	check(not scene._building_panel.visible, "detail menu has no competing shell panel")
	await _capture("03-window-options")
	scene._begin_style_picker("colour")
	scene._preview_style_choice("colour", "berry")
	scene._refresh_controller_hud()
	check(not scene._building_panel.visible, "colour menu has no competing shell panel")
	await _capture("04-colour-picker")
	scene.hud.visible = false
	var preview := await _capture("05-colour-preview-clean")
	check(preview.get_data() != baseline.get_data(), "colour preview changes actual rendered pixels")
	scene._cancel_style_picker()
	scene._update_presentation()
	var restored := await _capture("06-colour-cancel-clean")
	check(restored.get_data() == baseline.get_data(), "cancel restores the exact two-cottage image")
	scene.hud.visible = true
	var dims: Vector3 = b["dimensions"]
	var shutter_id: String = scene.building_world.add_detail(copy_id, "shutter", front, Vector3(0, dims.y + 2, -dims.z * 0.5 - 0.02), "shutter_wood")
	check(not shutter_id.is_empty(), "recovery fixture exists")
	scene._open_needs_placement()
	scene._refresh_controller_hud()
	await _capture("07-needs-placement")
	scene._close_needs_placement()
	scene._set_view_context("terrain")
	scene.cursor = Vector3(32, 8, 28)
	scene._update_camera()
	scene._update_world_hover()
	scene._open_terrain_settings()
	scene._refresh_controller_hud()
	await _capture("08-terrain-settings")
	_finish()

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m1_playtest_repair_render_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
