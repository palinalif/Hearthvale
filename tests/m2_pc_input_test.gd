extends SceneTree

var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scripts/m2_scene_pc_input.gd").new()
	scene.checkpoint_root = "user://m2-pc-input-test-%s" % Time.get_ticks_usec()
	scene.test_mode = true
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 15000
	while (scene.backend == null or not scene.backend.is_ready() or not scene._player_restored) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(scene.backend != null and scene.backend.is_ready(), "PC input scene becomes ready")
	if failures > 0: _finish(); return

	for action in ["m1_move_left", "m1_move_right", "m1_move_up", "m1_move_down", "m1_accept", "m1_cancel"]:
		var has_key := false
		for event in InputMap.action_get_events(action):
			if event is InputEventKey: has_key = true
		_check(has_key, "%s has a keyboard binding" % action)

	scene._set_view_context("building", "PC test")
	var point := InputEventMouseMotion.new()
	point.position = Vector2(340, 260)
	scene._input(point)
	_check(scene.edit_pointer.is_equal_approx(Vector2(340, 260)), "mouse points directly at house details")

	var right_down := InputEventMouseButton.new()
	right_down.button_index = MOUSE_BUTTON_RIGHT
	right_down.pressed = true
	scene._input(right_down)
	var yaw_before: float = scene.camera_yaw
	var orbit := InputEventMouseMotion.new()
	orbit.relative = Vector2(20, -10)
	scene._input(orbit)
	_check(scene.camera_yaw < yaw_before, "right-drag orbits the camera")
	var right_up := InputEventMouseButton.new()
	right_up.button_index = MOUSE_BUTTON_RIGHT
	right_up.pressed = false
	scene._input(right_up)

	var distance_before: float = scene.camera_distance
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	scene._input(wheel)
	_check(scene.camera_distance < distance_before, "mouse wheel zooms toward the scene")

	scene._set_view_context("terrain", "PC terrain aim test")
	scene._update_camera()
	var old_cursor: Vector3 = scene.cursor
	scene._aim_terrain_from_mouse(scene.get_viewport().get_visible_rect().size * 0.5)
	_check(not scene.cursor.is_equal_approx(old_cursor), "mouse ray aims the terrain cursor")
	_check(scene.cursor.x > 6.0, "mouse terrain aim uses the full high-resolution world bounds")

	scene.PCInputGlyph.set_keyboard_mouse_mode(true)
	var pc_prompt: Control = scene.PCInputGlyph.control("RS", "Orbit")
	_check(pc_prompt.get_child(0) is Label and (pc_prompt.get_child(0) as Label).text == "RMB drag", "PC prompt names the mouse orbit gesture")
	pc_prompt.free()
	_finish()

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: %s" % label)

func _finish() -> void:
	if scene and is_instance_valid(scene): scene.queue_free(); await process_frame; await process_frame
	print(JSON.stringify({"ok": failures == 0, "failures": failures, "pc_input": failures == 0}))
	quit(1 if failures > 0 else 0)
