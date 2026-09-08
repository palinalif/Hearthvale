extends SceneTree
## Exercise the actual exported scene with held physical controller buttons.
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

func _press(button: JoyButton, duration_ms: int = 20) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	var deadline := Time.get_ticks_msec() + duration_ms
	while Time.get_ticks_msec() < deadline: await process_frame
	var release := InputEventJoypadButton.new()
	release.button_index = button
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await process_frame

func _focus_key() -> String:
	var focus := root.gui_get_focus_owner()
	return str(focus.get_meta("setting", "")) if focus else ""

func _run() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m1-settings-input-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "native exported scene ready")
	if not scene._player_restored: _finish(); return
	scene.cursor = Vector3(32, 8, 28)
	scene.camera_yaw = 0.0
	scene._update_camera()
	await process_frame
	await _press(JOY_BUTTON_X)
	check(scene.tools_open and scene._terrain_panel.visible, "X opens terrain settings away from cottage")
	check(_focus_key() == "radius", "first visit focuses Radius, not tool list")
	var radius: float = scene.brush_radius
	var tool: String = scene.sculpt_tool
	var revision: int = scene.backend.stats().revision
	await _press(JOY_BUTTON_DPAD_RIGHT)
	check(is_equal_approx(scene.brush_radius, radius + 1.0), "one Right press adjusts radius immediately")
	check(scene.sculpt_tool == tool and scene.tools_open, "adjusting radius neither cycles tool nor closes menu")
	await _press(JOY_BUTTON_DPAD_DOWN)
	check(_focus_key() == "strength", "one Down reaches Strength")
	var strength: int = scene.brush_strength_level
	await _press(JOY_BUTTON_DPAD_RIGHT, 650)
	check(scene.brush_strength_level >= strength + 3, "held Right repeats strength adjustment")
	var released: int = scene.brush_strength_level
	for i in 10: await process_frame
	check(scene.brush_strength_level == released, "repetition stops on release")
	check(scene.backend.stats().revision == revision and not scene.stroke_active, "menu adjustments do not sculpt")
	await _press(JOY_BUTTON_B)
	check(not scene.tools_open and scene.view_context == "terrain", "B returns to terrain without mode change")
	await _press(JOY_BUTTON_X)
	check(_focus_key() == "strength", "reopening remembers the last setting row")
	await _press(JOY_BUTTON_DPAD_LEFT, 1300)
	check(scene.brush_strength_level == 1, "held decrement respects minimum strength")
	await _press(JOY_BUTTON_A)
	check(not scene.tools_open and not scene.stroke_active, "A Done closes without starting a brush")
	scene._select_terrain_tool("foliage")
	await _press(JOY_BUTTON_X)
	check(_focus_key() == "radius" and scene._terrain_setting_buttons["strength"].disabled, "planting focuses radius and disables unrelated sculpt settings")
	await _press(JOY_BUTTON_B)
	_finish()

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m1_terrain_settings_input_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
