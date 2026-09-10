extends SceneTree
## Physical D-pad input must follow displayed rows, including the recovery entry.
var scene: Node
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)

func _press(button: JoyButton) -> void:
	var down := InputEventJoypadButton.new()
	down.button_index = button
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await process_frame
	var up := InputEventJoypadButton.new()
	up.button_index = button
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await process_frame

func _focus_text() -> String:
	var button := root.gui_get_focus_owner() as Button
	return button.text if button else ""

func _run() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://recovery-dpad-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "exported native scene ready")
	if not scene._player_restored: _finish(); return
	scene._set_view_context("building")
	var view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var wall := ""
	for surface in view["surfaces"]:
		if str(surface.get("orientation", "")) == "front": wall = str(surface["id"])
	var dims: Vector3 = view["dimensions"]
	var first: String = scene.building_world.add_detail(scene.selected_building_id, "shutter", wall, Vector3(-2, dims.y + 2, -dims.z * 0.5 - 0.02), "shutter_wood")
	var second: String = scene.building_world.add_detail(scene.selected_building_id, "shutter", wall, Vector3(2, dims.y + 2, -dims.z * 0.5 - 0.02), "shutter_wood")
	check(not first.is_empty() and not second.is_empty() and scene._needs_details().size() == 2, "two unsupported attachments retained")
	scene.edit_pointer = Vector2(10, 10)
	await process_frame
	await _press(JOY_BUTTON_X)
	check(scene._building_panel.visible and _focus_text() == "Place new home", "physical X opens home options on Place new home")
	await _press(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text().begins_with("Duplicate"), "first Down follows displayed Duplicate row")
	await _press(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text().begins_with("House shape"), "second Down follows House shape row")
	await _press(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "Add window", "third Down follows displayed window row")
	await _press(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "Add door", "fourth Down follows displayed door row")
	await _press(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "Add flower box", "fifth Down follows displayed flower-box row")
	await _press(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "Add shutter", "sixth Down follows shutter row")
	await _press(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "Wall colour", "seventh Down follows wall colour row")
	await _press(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "Roof colour", "eighth Down follows roof colour row")
	await _press(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "Roof design", "ninth Down follows roof design row")
	await _press(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "Roof decor", "tenth Down follows roof decor row")
	await _press(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "Accent colour", "eleventh Down follows shared accent colour row")
	await _press(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner() == scene._needs_action, "twelfth Down reaches Needs placement before Close")
	await _press(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "Close", "Close follows Needs placement")
	await _press(JOY_BUTTON_DPAD_UP)
	check(root.gui_get_focus_owner() == scene._needs_action, "Up from Close returns to Needs placement")
	await _press(JOY_BUTTON_A)
	check(scene._needs_open and scene._needs_box.is_ancestor_of(root.gui_get_focus_owner()), "A opens recovery tray with controller focus")
	var first_button := root.gui_get_focus_owner()
	await _press(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner() != first_button and scene._needs_box.is_ancestor_of(root.gui_get_focus_owner()), "Down selects the second actual recovery item")
	await _press(JOY_BUTTON_DPAD_UP)
	check(root.gui_get_focus_owner() == first_button, "Up selects the first recovery item without leaving Building")
	await _press(JOY_BUTTON_DPAD_DOWN)
	var label := _focus_text()
	await _press(JOY_BUTTON_A)
	check(scene.detail_move_active and label.contains(scene.selected_detail_id), "A picks precisely the D-pad-selected item")
	await _press(JOY_BUTTON_B)
	check(not scene.detail_move_active and scene._needs_details().size() == 2, "B preserves both recoverable records")
	check(scene.view_context == "building", "D-pad Up inside menus never switches world context")
	_finish()

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m1_recovery_dpad_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
