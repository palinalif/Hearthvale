extends SceneTree

## Focused controller contract for painted-path cancellation. A live stroke is
## preview-only: B cancels that stroke and keeps the tool open; B again while
## idle closes the path tool. Neither action may mutate saved authority/history.
var checks := 0
var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-path-feedback-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene._player_restored, "path feedback scene ready")
	if not scene._player_restored:
		_finish()
		return
	scene.set_process(false)
	var before := JSON.stringify(scene.landscape_state.document())
	var history_before: int = scene._history_tags.size()

	scene.path_style_id = "packed_earth"
	scene.path_width = 0.75
	scene._begin_path_placement()
	_check(scene.path_placement_active and not scene.path_painting, "path tool opens idle with no live stroke")
	_aim(Vector2(34.0, 34.0))
	await _button_down(JOY_BUTTON_A)
	_check(scene.path_painting and not scene.path_cells.is_empty(), "holding A starts a live painted-cell stroke")
	_aim(Vector2(35.0, 34.0))
	_check(scene._sample_path_stroke() and scene.path_cells.size() > 1, "moving while held extends the live stroke")
	_check(JSON.stringify(scene.landscape_state.document()) == before and scene._history_tags.size() == history_before, "live stroke remains preview-only")

	await _press(JOY_BUTTON_B)
	_check(scene.path_placement_active, "first B keeps path painting mode active")
	_check(not scene.path_painting and scene.path_cells.is_empty(), "first B cancels only the live stroke")
	_check(JSON.stringify(scene.landscape_state.document()) == before and scene._history_tags.size() == history_before, "stroke cancellation changes neither authority nor history")
	await _button_up(JOY_BUTTON_A)
	_check(scene.path_placement_active and JSON.stringify(scene.landscape_state.document()) == before, "late A release after cancellation cannot commit the discarded stroke")

	await _button_down(JOY_BUTTON_A)
	_check(scene.path_painting and not scene.path_cells.is_empty(), "A can immediately start another stroke after cancellation")
	await _press(JOY_BUTTON_B)
	_check(scene.path_placement_active and not scene.path_painting, "B cancels a replacement live stroke")
	await _button_up(JOY_BUTTON_A)
	await _press(JOY_BUTTON_B)
	_check(not scene.path_placement_active, "B while idle closes painted-path mode")
	_check(JSON.stringify(scene.landscape_state.document()) == before and scene._history_tags.size() == history_before, "cancel then close leaves the world unchanged")

	scene._begin_path_placement()
	_check(scene.path_placement_active and not scene.path_painting, "path tool can reopen after close")
	await _press(JOY_BUTTON_B)
	_check(not scene.path_placement_active, "idle B closes an empty path tool in one press")
	_check(JSON.stringify(scene.landscape_state.document()) == before and scene._history_tags.size() == history_before, "empty-tool close is read-only")
	_finish()

func _aim(point: Vector2) -> void:
	scene.cursor = Vector3(point.x, 8.0, point.y)
	scene.terrain_cursor = scene.cursor
	scene._update_brush_preview()
	scene._update_path_validity()

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
	Input.action_release("m1_accept")
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures}))
	quit(1 if failures else 0)
