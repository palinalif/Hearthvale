extends SceneTree

var checks := 0
var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-fence-placement-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene._player_restored, "native fence scene ready")
	if not scene._player_restored:
		_finish()
		return
	scene.set_process(false)
	var before: Dictionary = scene.landscape_state.document()
	var history_before: int = scene._history_tags.size()

	await _press(JOY_BUTTON_DPAD_UP)
	scene._build_catalogue_buttons[3].grab_focus()
	await _press(JOY_BUTTON_A)
	_check(scene._hamlet_catalogue_open and scene._hamlet_catalogue_buttons.size() == 5, "Hamlet details includes three gardens, fence, and gate")
	_check(scene._hamlet_catalogue_buttons[3].text.begins_with("Rustic timber fence") and scene._hamlet_catalogue_buttons[4].text.begins_with("Rustic garden gate"), "both rustic fence choices are visually named")
	scene._hamlet_catalogue_buttons[3].grab_focus()
	await _press(JOY_BUTTON_A)
	_check(scene.fence_placement_active and scene.fence_style_id == "rustic_fence", "fence selection enters world placement")
	_aim(Vector2(36.0, 36.0))
	_check(scene.fence_placement_valid and scene.composition_visual.stats().preview_cells > 0, "fence has a valid live preview")
	scene._rotate_fence(1)
	_check(scene.fence_yaw_quarters == 1 and scene.landscape_state.document() == before, "fence quarter-turn is preview-only")
	await _press(JOY_BUTTON_A)
	_check(not scene.fence_placement_active and scene.landscape_state.composition.size() == 1, "A commits rustic fence")
	var fence: Dictionary = scene.landscape_state.composition[0]
	_check(fence.kind == "fence" and fence.style_id == "rustic_fence" and int(fence.yaw_quarters) == 1, "fence saves style and orientation")
	_check(scene._history_tags.size() == history_before + 1, "fence placement is one undo transaction")
	_check(scene.composition_visual.stats().fence_count == 1 and scene.composition_visual.stats().fence_geometry_cells > 0, "committed fence rebuilds disposable geometry")
	var after_fence: Dictionary = scene.landscape_state.document()
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(scene.landscape_state.document() == before, "fence undo restores exact landscape")
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	_check(scene.landscape_state.document() == after_fence, "fence redo restores exact landscape")

	scene.fence_style_id = "rustic_gate"
	scene.fence_size = Vector2(1.5, 0.375)
	scene.fence_yaw_quarters = 0
	scene._begin_fence_placement()
	_aim(Vector2(33.0, 36.0))
	_check(scene.fence_placement_valid, "matching gate can be placed independently")
	await _press(JOY_BUTTON_A)
	_check(scene.landscape_state.composition.size() == 2 and scene.landscape_state.composition[1].style_id == "rustic_gate", "gate commits as its own stable composition record")
	_check(scene.composition_visual.stats().fence_count == 2, "fence renderer includes fence and gate together")

	var cancel_before := JSON.stringify(scene.landscape_state.document())
	scene.fence_style_id = "rustic_fence"
	scene.fence_size = Vector2(3.0, 0.25)
	scene._begin_fence_placement()
	_aim(Vector2(31.0, 36.0))
	await _press(JOY_BUTTON_B)
	_check(not scene.fence_placement_active and JSON.stringify(scene.landscape_state.document()) == cancel_before, "B cancels fence preview without document drift")

	var home: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var home_center: Vector3 = (home["transform"] as Transform3D).origin
	scene._begin_fence_placement()
	_aim(Vector2(home_center.x, home_center.z))
	_check(not scene.fence_placement_valid and scene.fence_placement_reason.contains("home"), "fence cannot run through a home")
	await _press(JOY_BUTTON_A)
	_check(scene.fence_placement_active and scene.landscape_state.composition.size() == 2, "invalid home-overlap fence cannot commit")
	scene._cancel_fence_placement()
	_finish()

func _aim(point: Vector2) -> void:
	scene.cursor = Vector3(point.x, 8.0, point.y)
	scene.terrain_cursor = scene.cursor
	scene._update_brush_preview()
	scene._update_fence_validity()
	scene._update_fence_preview()

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
