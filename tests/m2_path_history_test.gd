extends SceneTree

var checks := 0
var failures := 0
var scene: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-path-history-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(scene._player_restored, "path history scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)

	# Use cobblestone so this test isolates landscape history from packed-earth
	# terrain ownership, which is covered by the plaza/placement integration tests.
	scene.path_style_id = "cobblestone"
	scene._begin_path_placement()
	_aim(Vector2(34.0, 34.0))
	_check(scene.path_placement_valid, "history fixture is paintable")
	var before := JSON.stringify(scene.landscape_state.document())
	await _button_down(JOY_BUTTON_A)
	_aim(Vector2(36.0, 34.0))
	scene._sample_path_stroke()
	await _button_up(JOY_BUTTON_A)
	var painted := JSON.stringify(scene.landscape_state.document())
	_check(painted != before and not scene.landscape_state.path_cells("cobblestone").is_empty(), "paint stroke creates redoable authority")
	_check(scene.path_placement_active and not scene.path_painting, "paint tool remains open after commit")

	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(JSON.stringify(scene.landscape_state.document()) == before, "LB undo restores the exact pre-paint document")
	_check(scene.path_placement_active, "undo keeps the path tool open")
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	_check(JSON.stringify(scene.landscape_state.document()) == painted, "RB redo restores the exact painted document")
	_check(scene.path_placement_active, "redo keeps the path tool open")

	# Erase is its own history transaction and must be redoable too.
	await _press(JOY_BUTTON_X)
	_check(scene.path_erase_mode, "X enters erase mode for history verification")
	_aim(Vector2(35.0, 34.0))
	await _button_down(JOY_BUTTON_A)
	await _button_up(JOY_BUTTON_A)
	var erased := JSON.stringify(scene.landscape_state.document())
	_check(erased != painted, "erase stroke changes painted authority")
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(JSON.stringify(scene.landscape_state.document()) == painted, "LB undo restores the exact pre-erase document")
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	_check(JSON.stringify(scene.landscape_state.document()) == erased, "RB redo reapplies the exact erase document")
	_check(scene.path_erase_mode and scene.path_placement_active, "redo preserves the live erase tool mode")

	await _finish()

func _aim(point: Vector2) -> void:
	scene.cursor = Vector3(point.x, 8.0, point.y)
	scene.terrain_cursor = scene.cursor
	scene._update_brush_preview()
	scene._update_path_validity()
	scene._update_path_preview()

func _button_down(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func _button_up(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func _press(button: JoyButton) -> void:
	await _button_down(button)
	await _button_up(button)

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
