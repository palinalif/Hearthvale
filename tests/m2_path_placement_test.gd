extends SceneTree

const State = preload("res://scripts/landscape_state.gd")

var checks := 0
var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-path-placement-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene._player_restored, "native path scene ready")
	if not scene._player_restored:
		_finish()
		return
	scene.set_process(false)
	var fixture_z := -1.0
	for z in [27.0, 29.0, 31.0, 33.0]:
		if scene.landscape_state.add("foliage", Vector3(40.0, 8.0, z), 2):
			fixture_z = z
			break
	_check(fixture_z > 0.0, "path route has a planting fixture to clear")
	scene.garden_visual.reset_records(scene.landscape_state.records)
	var before: Dictionary = scene.landscape_state.document()
	var history_before: int = scene._history_tags.size()

	await _press(JOY_BUTTON_DPAD_UP)
	_check(scene._build_catalogue_open, "D-pad Up opens the build catalogue")
	scene._build_catalogue_buttons[1].grab_focus()
	await _press(JOY_BUTTON_A)
	_check(scene._roads_catalogue_open and scene._roads_catalogue_buttons.size() == 5, "Roads & Paths opens its three path styles plus two bridge styles")
	_check(scene._roads_catalogue_buttons[0].text.begins_with("Packed-earth footpath") and scene._roads_catalogue_buttons[1].text.begins_with("Cobblestone lane") and scene._roads_catalogue_buttons[2].text.begins_with("Stepping-stone trail"), "all path styles are visually named")
	scene._roads_catalogue_buttons[0].grab_focus()
	await _press(JOY_BUTTON_A)
	_check(scene.path_placement_active and scene.path_style_id == "packed_earth" and scene.view_context == "terrain", "style selection enters terrain path placement")
	_check(scene.landscape_state.document() == before, "starting path placement is read-only")

	_aim(Vector2(36.0, fixture_z))
	await _press(JOY_BUTTON_A)
	_check(scene.path_points.size() == 1, "A places the first path point")
	var preview_before: String = JSON.stringify(scene.landscape_state.document())
	scene._update_path_preview()
	_check(JSON.stringify(scene.landscape_state.document()) == preview_before and scene.path_visual.stats().preview_cells > 0, "live preview does not mutate authority and has geometry")
	_aim(Vector2(44.0, fixture_z))
	var next_point_was_valid: bool = bool(scene.path_placement_valid)
	await _press(JOY_BUTTON_A)
	_check(scene.path_points.size() == 2 and next_point_was_valid, "A adds a valid second bend/point")
	_check(scene.path_placement_reason.contains("farther"), "cursor at the latest point explains that another meaningful segment is needed")
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(scene.path_points.size() == 1 and scene.landscape_state.document() == before, "LB removes only the most recent uncommitted point")
	await _press(JOY_BUTTON_X)
	_check(scene.path_placement_active and scene.path_points.size() < 2 and scene.status_text.contains("two valid points"), "X cannot finish a path with fewer than two points")
	_aim(Vector2(44.0, fixture_z))
	await _press(JOY_BUTTON_A)
	var committed_candidate: String = JSON.stringify(scene.landscape_state.document())
	_check(JSON.stringify(scene.landscape_state.document()) == preview_before, "adding points remains preview-only")
	await _press(JOY_BUTTON_X)
	_check(not scene.path_placement_active and scene.landscape_state.paths.size() == 1, "X commits a valid path")
	_check(scene._history_tags.size() == history_before + 1, "path commit records one landscape history entry")
	var after: Dictionary = scene.landscape_state.document()
	_check(scene.landscape_state.records.size() < before.records.size() and not _has_record_at(scene.landscape_state.records, 40.0, fixture_z), "commit clears intersecting planting atomically with the path")
	_check(not committed_candidate.is_empty(), "path preview document remains serializable")

	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(scene.landscape_state.document() == before, "undo removes the path and restores cleared planting")
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	_check(scene.landscape_state.document() == after, "redo restores the path and planting removal")
	var saved := JSON.stringify(scene.landscape_state.document())
	_check(scene._save_all(), "path save succeeds")
	_check(scene._reload_all(), "path reload succeeds")
	_check(JSON.stringify(scene.landscape_state.document()) == saved, "save/reload preserves exact path ID style width and points")

	var cancel_before := JSON.stringify(scene.landscape_state.document())
	var history_after_reload: int = scene._history_tags.size()
	scene._begin_path_placement()
	_aim(Vector2(30.0, 35.0))
	await _press(JOY_BUTTON_A)
	await _press(JOY_BUTTON_B)
	_check(scene.path_placement_active and not scene.path_point_active and scene.path_points.size() == 1, "first B stops only the live next point and keeps the confirmed route")
	_check(JSON.stringify(scene.landscape_state.document()) == cancel_before and scene._history_tags.size() == history_after_reload, "stopping the live point does not mutate authority or history")
	await _press(JOY_BUTTON_B)
	_check(not scene.path_placement_active and JSON.stringify(scene.landscape_state.document()) == cancel_before and scene._history_tags.size() == history_after_reload, "second B exits path placement without document drift")

	var home: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var home_center: Vector3 = (home["transform"] as Transform3D).origin
	scene._begin_path_placement()
	_aim(Vector2(home_center.x - 3.0, home_center.z))
	await _press(JOY_BUTTON_A)
	_aim(Vector2(home_center.x + 3.0, home_center.z))
	_check(not scene.path_placement_valid and scene.path_placement_reason.contains("interior"), "home interior crossing is explained and invalid")
	await _press(JOY_BUTTON_A)
	_check(scene.path_points.size() == 1, "home interior crossing cannot add a point")
	await _press(JOY_BUTTON_X)
	_check(scene.path_placement_active and scene.landscape_state.document().paths.size() == 1, "invalid home path cannot commit")
	scene._cancel_path_placement()

	scene._begin_path_placement()
	scene.path_points = [Vector2(10.0, 10.0), Vector2(48.125, 10.0)]
	_check(not scene._commit_path() and scene.path_placement_reason == "Outside editable world", "out-of-bounds finish is rejected with a plain-language reason")
	scene._cancel_path_placement()

	scene._begin_path_placement()
	_aim(Vector2(31.0, 37.0))
	await _press(JOY_BUTTON_A)
	scene._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not scene.path_placement_active and scene.landscape_state.document() == after and scene.menu_open, "focus loss cancels the path and pauses the world")
	scene._set_menu(false)
	scene._begin_path_placement()
	scene._on_joy_connection_changed(0, false)
	_check(not scene.path_placement_active and scene.menu_open and scene.landscape_state.document() == after, "controller disconnect cannot confirm a path accidentally")
	_finish()

func _aim(point: Vector2) -> void:
	scene.cursor = Vector3(point.x, 8.0, point.y)
	scene.terrain_cursor = scene.cursor
	scene._update_brush_preview()
	scene._update_path_validity()

func _has_record_at(records: Array, x: float, z: float) -> bool:
	for record: Dictionary in records:
		var point: Vector3 = State.position_of(record)
		if is_equal_approx(point.x, x) and is_equal_approx(point.z, z): return true
	return false

func _press(button: JoyButton) -> void:
	var down := InputEventJoypadButton.new()
	down.button_index = button
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await process_frame
	var up := InputEventJoypadButton.new()
	up.button_index = button
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await process_frame

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures}))
	quit(1 if failures else 0)
