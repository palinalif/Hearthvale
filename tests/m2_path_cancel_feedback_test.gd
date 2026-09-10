extends SceneTree

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

	scene._begin_path_placement()
	_check(scene.path_placement_active and scene.path_point_active, "path starts with a live prospective point")
	_aim(Vector2(34.0, 34.0))
	await _press(JOY_BUTTON_A)
	_check(scene.path_points.size() == 1 and scene.path_point_active, "confirming a point immediately starts the next prospective point")

	await _press(JOY_BUTTON_B)
	_check(scene.path_placement_active, "first B keeps road placement mode active")
	_check(not scene.path_point_active, "first B stops only the live prospective point")
	_check(scene.path_points.size() == 1, "first B keeps confirmed road points")
	_check(JSON.stringify(scene.landscape_state.document()) == before and scene._history_tags.size() == history_before, "stopping a point does not mutate authority or history")

	await _press(JOY_BUTTON_A)
	_check(scene.path_placement_active and scene.path_point_active and scene.path_points.size() == 1, "A resumes extending the same confirmed route")
	await _press(JOY_BUTTON_B)
	_check(scene.path_placement_active and not scene.path_point_active, "B can stop the resumed prospective point")
	await _press(JOY_BUTTON_B)
	_check(not scene.path_placement_active, "second B exits when no point is actively being placed")
	_check(JSON.stringify(scene.landscape_state.document()) == before and scene._history_tags.size() == history_before, "two-stage exit leaves the world unchanged")

	scene._begin_path_placement()
	await _press(JOY_BUTTON_B)
	_check(scene.path_placement_active and not scene.path_point_active, "B first pauses even before the first point is confirmed")
	await _press(JOY_BUTTON_B)
	_check(not scene.path_placement_active, "B again exits an empty paused path")
	_finish()

func _aim(point: Vector2) -> void:
	scene.cursor = Vector3(point.x, 8.0, point.y)
	scene.terrain_cursor = scene.cursor
	scene._update_brush_preview()
	scene._update_path_validity()

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
