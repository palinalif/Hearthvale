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

func _changed_pixel_count(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size(): return a.get_width() * a.get_height()
	var a_data := a.get_data()
	var b_data := b.get_data()
	var changed := 0
	for offset in range(0, a_data.size(), 4):
		if a_data[offset] != b_data[offset] or a_data[offset + 1] != b_data[offset + 1] or a_data[offset + 2] != b_data[offset + 2] or a_data[offset + 3] != b_data[offset + 3]: changed += 1
	return changed

func _startup_diagnostics(started: int, frames: int, max_gap_ms: int) -> Dictionary:
	var result := {"elapsed_ms": Time.get_ticks_msec() - started, "frames": frames, "max_frame_gap_ms": max_gap_ms, "player_restored": bool(scene._player_restored), "scene_status": str(scene.status_text), "restoring": bool(scene._restoring), "paused": paused, "window_focused": root.has_focus()}
	if scene.backend:
		result["backend"] = scene.backend.stats()
		var terrain: Node = scene.backend.terrain
		if terrain:
			var area := AABB(Vector3.ZERO, Vector3(scene.backend.patch_size))
			result["editable"] = terrain.get_voxel_tool().is_area_editable(area)
			result["meshed"] = terrain.is_area_meshed(area)
	return result

func _run() -> void:
	if RenderingServer.get_current_rendering_method() != "mobile" or DisplayServer.get_name() == "headless":
		print("COTTAGE_RENDER_UNAVAILABLE")
		quit(2)
		return
	print("COTTAGE_RENDER_START " + JSON.stringify({"method": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(), "adapter": RenderingServer.get_video_adapter_name()}))
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(folder)
	DirAccess.make_dir_recursive_absolute("reports/screenshots/m2-home-details")
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m1-repair-render-%s" % Time.get_ticks_usec()
	var started := Time.get_ticks_msec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	var next_report := 0
	var last_frame := Time.get_ticks_msec()
	var max_gap_ms := 0
	var frames := 0
	while not scene._player_restored and Time.get_ticks_msec() < deadline:
		await process_frame
		var now := Time.get_ticks_msec()
		frames += 1
		max_gap_ms = maxi(max_gap_ms, now - last_frame)
		last_frame = now
		if now >= next_report:
			print("COTTAGE_STARTUP " + JSON.stringify(_startup_diagnostics(started, frames, max_gap_ms)))
			next_report = now + 5000
		if scene.backend and not scene.backend.is_ready() and not str(scene.backend.get("_error")).is_empty():
			break
	print("COTTAGE_STARTUP_FINAL " + JSON.stringify(_startup_diagnostics(started, frames, max_gap_ms)))
	check(scene.backend != null and scene.backend.is_ready() and scene._player_restored, "native world ready for rendering")
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
	scene._dock_style_picker_away_from_target()
	var window_screen: Vector2 = scene.camera.unproject_position(tb * (detail["resolved_position"] as Vector3))
	check(not scene.tools_panel.get_global_rect().grow(20).has_point(window_screen), "colour picker docks away from the edited window")
	check(scene._highlighted_detail_geometry_count() > 0, "edited window mesh receives the amber silhouette outline")
	var picker_image := await _capture("04-colour-picker")
	check(picker_image.save_png("reports/screenshots/m2-home-details/window-colour-picker.png") == OK, "window picker review capture saved")
	scene.hud.visible = false
	var preview := await _capture("05-colour-preview-clean")
	check(preview.get_data() != baseline.get_data(), "colour preview changes actual rendered pixels")
	scene._cancel_style_picker()
	scene._update_presentation()
	var restored := await _capture("06-colour-cancel-clean")
	# D3D12 may vary one or two boundary pixels between otherwise identical frames.
	check(_changed_pixel_count(restored, baseline) <= 4, "cancel restores the two-cottage image within raster tolerance")
	scene.hud.visible = true
	var door: Dictionary = {}
	for candidate in scene.building_world.get_building(copy_id)["details"]:
		if str(candidate.get("kind", "")) == "door" and bool(candidate.get("visible", false)): door = candidate; break
	check(not door.is_empty(), "visible door fixture exists")
	if not door.is_empty():
		scene.selected_detail_id = str(door["id"])
		scene.hovered_detail_id = str(door["id"])
		scene.hovered_detail_kind = "door"
		var door_world: Vector3 = tb * (door["resolved_position"] as Vector3)
		var door_outward: Vector3 = (tb.basis * Vector3.LEFT).normalized()
		scene.camera.global_position = door_world + door_outward * 10.0 + Vector3(0, 1.0, 0)
		scene.camera.look_at(door_world)
		scene._update_direct_edit_hud()
		scene._begin_style_picker("variation")
		scene._preview_style_choice("variation", "door_tudor_arch")
		scene._refresh_controller_hud()
		scene._dock_style_picker_away_from_target()
		var door_screen: Vector2 = scene.camera.unproject_position(door_world)
		check(scene._style_candidates("variation").size() == 6, "expanded door variation category is available")
		check(not scene.tools_panel.get_global_rect().grow(20).has_point(door_screen), "variation picker docks away from the edited door")
		var door_picker_image := await _capture("07-door-variations")
		check(door_picker_image.save_png("reports/screenshots/m2-home-details/door-variations.png") == OK, "door variation review capture saved")
		scene._cancel_style_picker()
	var dims: Vector3 = b["dimensions"]
	var shutter_id: String = scene.building_world.add_detail(copy_id, "shutter", front, Vector3(0, dims.y + 2, -dims.z * 0.5 - 0.02), "shutter_wood")
	check(not shutter_id.is_empty(), "recovery fixture exists")
	scene._open_needs_placement()
	scene._refresh_controller_hud()
	await _capture("08-needs-placement")
	scene._close_needs_placement()
	scene._set_view_context("terrain")
	scene.cursor = ta.origin
	scene.terrain_cursor = scene.cursor
	scene.camera_yaw = 0.65
	scene.camera_pitch = 0.42
	scene.camera_distance = 18.0
	scene._update_camera()
	scene._update_world_hover()
	check(str(scene._world_hover.get("id", "")) == first_id, "terrain cursor targets the cottage")
	var house_outline_count := 0
	for child in (scene.cottage_visuals[first_id] as Node3D).get_children():
		if child is GeometryInstance3D and (child as GeometryInstance3D).material_overlay != null: house_outline_count += 1
	check(house_outline_count > 0, "terrain hover outlines actual house geometry")
	var house_hover_image := await _capture("09-house-mesh-hover")
	check(house_hover_image.save_png("reports/screenshots/m2-home-details/house-mesh-hover.png") == OK, "house mesh-hover review capture saved")
	scene._open_terrain_settings()
	scene._refresh_controller_hud()
	await _capture("10-terrain-settings")
	_finish()

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m1_playtest_repair_render_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
