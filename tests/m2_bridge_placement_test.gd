extends SceneTree

const State = preload("res://scripts/landscape_state.gd")

var checks := 0
var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-bridge-placement-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene._player_restored, "native bridge scene ready")
	if not scene._player_restored:
		_finish()
		return
	scene.set_process(false)

	var fixture := Vector3(36.0, 8.0, 40.0)
	_check(scene.landscape_state.add("foliage", fixture, 11), "bridge route has planting to clear")
	scene.garden_visual.reset_records(scene.landscape_state.records)
	var before: Dictionary = scene.landscape_state.document()
	var history_before: int = scene._history_tags.size()

	await _press(JOY_BUTTON_DPAD_UP)
	_check(scene._build_catalogue_open, "D-pad Up opens the build catalogue")
	scene._build_catalogue_buttons[1].grab_focus()
	await _press(JOY_BUTTON_A)
	_check(scene._roads_catalogue_open and scene._roads_catalogue_buttons.size() == 5, "Roads & Paths includes three paths and two bridge styles")
	_check(scene._roads_catalogue_buttons[3].text.begins_with("Timber footbridge") and scene._roads_catalogue_buttons[4].text.begins_with("Stone crossing"), "bridge styles are visually named")
	scene._roads_catalogue_buttons[3].grab_focus()
	await _press(JOY_BUTTON_A)
	_check(scene.bridge_placement_active and scene.bridge_style_id == "timber" and scene.view_context == "terrain", "bridge selection enters terrain composition placement")
	_check(scene.landscape_state.document() == before, "starting bridge placement is read-only")

	_aim(Vector2(34.0, 40.0))
	await _press(JOY_BUTTON_A)
	_check(scene.bridge_start == Vector2(34.0, 40.0), "first A anchors the near bank")
	_check(scene.landscape_state.document() == before, "first bridge anchor remains preview-only")
	_aim(Vector2(38.0, 40.0))
	_check(scene.bridge_placement_valid and scene.composition_visual.stats().preview_cells > 0, "far-bank preview is valid and has generated geometry")
	await _press(JOY_BUTTON_A)
	_check(not scene.bridge_placement_active and scene.landscape_state.bridges.size() == 1, "second A commits the bridge")
	_check(scene._history_tags.size() == history_before + 1, "bridge commit records one landscape history entry")
	_check(not _has_record_at(scene.landscape_state.records, fixture.x, fixture.z), "bridge commit clears intersecting planting atomically")
	_check(scene.composition_visual.stats().bridge_count == 1 and scene.composition_visual.stats().geometry_cells > 0, "committed bridge rebuilds disposable presentation")
	var after: Dictionary = scene.landscape_state.document()

	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(scene.landscape_state.document() == before, "undo removes bridge and restores planting")
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	_check(scene.landscape_state.document() == after, "redo restores bridge and planting removal")
	var saved := JSON.stringify(scene.landscape_state.document())
	_check(scene._save_all(), "bridge save succeeds")
	_check(scene._reload_all(), "bridge reload succeeds")
	_check(JSON.stringify(scene.landscape_state.document()) == saved, "save/reload preserves exact bridge ID style width and endpoints")
	_check(scene.composition_visual.stats().bridge_count == 1, "bridge presentation rebuilds after reload")

	var cancel_before := JSON.stringify(scene.landscape_state.document())
	var history_after_reload: int = scene._history_tags.size()
	scene._begin_bridge_placement()
	_aim(Vector2(30.0, 39.0))
	await _press(JOY_BUTTON_A)
	await _press(JOY_BUTTON_B)
	_check(not scene.bridge_placement_active and JSON.stringify(scene.landscape_state.document()) == cancel_before, "B cancels an anchored bridge without authority drift")
	_check(scene._history_tags.size() == history_after_reload, "cancelled bridge adds no history entry")

	var home: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var home_center: Vector3 = (home["transform"] as Transform3D).origin
	scene._begin_bridge_placement()
	_aim(Vector2(home_center.x - 2.0, home_center.z))
	await _press(JOY_BUTTON_A)
	_aim(Vector2(home_center.x + 2.0, home_center.z))
	_check(not scene.bridge_placement_valid and scene.bridge_placement_reason.contains("interior"), "bridge crossing a home interior is rejected with an explanation")
	await _press(JOY_BUTTON_A)
	_check(scene.bridge_placement_active and scene.landscape_state.bridges.size() == 1, "invalid bridge cannot commit")
	scene._cancel_bridge_placement()

	scene._begin_bridge_placement()
	_aim(Vector2(10.0, 10.0))
	await _press(JOY_BUTTON_A)
	_aim(Vector2(21.0, 10.0))
	_check(not scene.bridge_placement_valid and scene.bridge_placement_reason.contains("too long"), "overlong bridge span is rejected")
	scene._cancel_bridge_placement()
	_finish()

func _aim(point: Vector2) -> void:
	scene.cursor = Vector3(point.x, 8.0, point.y)
	scene.terrain_cursor = scene.cursor
	scene._update_brush_preview()
	scene._update_bridge_validity()
	scene._update_bridge_preview()

func _has_record_at(records: Array, x: float, z: float) -> bool:
	for record: Dictionary in records:
		var point := State.position_of(record)
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
