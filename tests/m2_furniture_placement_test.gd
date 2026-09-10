extends SceneTree

var checks := 0
var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-furniture-placement-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene._player_restored, "native street-furniture scene ready")
	if not scene._player_restored:
		_finish()
		return
	scene.set_process(false)
	var before: Dictionary = scene.landscape_state.document()
	var history_before: int = scene._history_tags.size()

	await _press(JOY_BUTTON_DPAD_UP)
	scene._build_catalogue_buttons[3].grab_focus()
	await _press(JOY_BUTTON_A)
	_check(scene._hamlet_catalogue_open and scene._hamlet_catalogue_buttons.size() == 9, "Hamlet details exposes final nine composition choices")
	_check(scene._hamlet_catalogue_buttons[5].text.begins_with("Village bench") and scene._hamlet_catalogue_buttons[6].text.begins_with("Path lantern") and scene._hamlet_catalogue_buttons[7].text.begins_with("Wooden signpost") and scene._hamlet_catalogue_buttons[8].text.begins_with("Barrel planter"), "all four street-furniture choices are visually named")
	_check(scene._hamlet_catalogue_panel.get_global_rect().end.y <= scene._prompt_bar.get_global_rect().position.y + 1.0, "final nine-choice Hamlet catalogue stays above the controller prompt bar")

	scene._hamlet_catalogue_buttons[5].grab_focus()
	await _press(JOY_BUTTON_A)
	_check(scene.furniture_placement_active and scene.furniture_style_id == "bench" and scene.view_context == "terrain", "bench selection enters world placement")
	_aim(Vector2(36.0, 34.0))
	_check(scene.furniture_placement_valid and scene.composition_visual.stats().preview_cells >= 0, "bench gets a valid live placement preview")
	scene._rotate_furniture(1)
	_check(scene.furniture_yaw_quarters == 1 and scene.landscape_state.document() == before, "furniture rotation remains preview-only")
	await _press(JOY_BUTTON_A)
	_check(not scene.furniture_placement_active and scene.landscape_state.composition.size() == 1, "A commits the bench")
	var bench: Dictionary = scene.landscape_state.composition[0]
	_check(bench.kind == "furniture" and bench.style_id == "bench" and int(bench.yaw_quarters) == 1, "bench saves kind style and orientation")
	_check(scene._history_tags.size() == history_before + 1, "bench placement is one landscape undo transaction")
	_check(scene.composition_visual.stats().furniture_count == 1 and scene.composition_visual.stats().furniture_geometry_cells > 0, "bench builds fine disposable presentation")

	var styles := [
		["lantern", Vector2(0.5, 0.5), Vector2(34.0, 34.0)],
		["signpost", Vector2(0.625, 0.625), Vector2(32.0, 34.0)],
		["barrel_planter", Vector2(0.75, 0.75), Vector2(30.0, 34.0)],
	]
	for entry in styles:
		scene.furniture_style_id = entry[0]
		scene.furniture_size = entry[1]
		scene.furniture_yaw_quarters = 0
		scene._begin_furniture_placement()
		_aim(entry[2])
		_check(scene.furniture_placement_valid, "%s has a valid placement target" % entry[0])
		_check(scene._commit_furniture(), "%s commits through the shared placement transaction" % entry[0])
	_check(scene.landscape_state.composition.size() == 4 and scene.composition_visual.stats().furniture_count == 4, "all four furniture styles coexist in saved authority and presentation")
	var after: Dictionary = scene.landscape_state.document()
	var saved := JSON.stringify(after)
	_check(scene._save_all() and scene._reload_all(), "street-furniture save and reload succeeds")
	_check(JSON.stringify(scene.landscape_state.document()) == saved and scene.composition_visual.stats().furniture_count == 4, "reload preserves and rebuilds all furniture records")

	var cancel_before := JSON.stringify(scene.landscape_state.document())
	scene.furniture_style_id = "bench"
	scene.furniture_size = Vector2(1.5, 0.625)
	scene._begin_furniture_placement()
	_aim(Vector2(28.0, 34.0))
	await _press(JOY_BUTTON_B)
	_check(not scene.furniture_placement_active and JSON.stringify(scene.landscape_state.document()) == cancel_before, "B cancels furniture preview without authority drift")

	var home: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var home_center: Vector3 = (home["transform"] as Transform3D).origin
	scene._begin_furniture_placement()
	_aim(Vector2(home_center.x, home_center.z))
	_check(not scene.furniture_placement_valid and scene.furniture_placement_reason.contains("home"), "street furniture cannot be placed inside a home")
	await _press(JOY_BUTTON_A)
	_check(scene.furniture_placement_active and scene.landscape_state.composition.size() == 4, "invalid home-overlap furniture cannot commit")
	scene._cancel_furniture_placement()
	_finish()

func _aim(point: Vector2) -> void:
	scene.cursor = Vector3(point.x, 8.0, point.y)
	scene.terrain_cursor = scene.cursor
	scene._update_brush_preview()
	scene._update_furniture_validity()
	scene._update_furniture_preview()

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
