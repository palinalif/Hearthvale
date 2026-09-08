extends SceneTree

var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scripts/m1_scene_building_camera.gd").new()
	scene.checkpoint_root = "user://m1-building-camera-test-%s" % Time.get_ticks_usec()
	scene.test_mode = true
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 15000
	while (scene.backend == null or not scene.backend.is_ready() or not scene._player_restored) and Time.get_ticks_msec() < deadline:
		await process_frame
	if scene.backend == null or not scene.backend.is_ready():
		_fail("M1 backend becomes ready")
		_finish()
		return

	var terrain_cursor: Vector3 = scene.cursor
	var terrain_yaw: float = scene.camera_yaw
	var terrain_pitch: float = scene.camera_pitch
	var terrain_distance: float = scene.camera_distance
	_check(scene._set_view_context("building", "camera test"), "enter building context")
	await process_frame
	var target: Vector3 = scene._selected_building_camera_target()
	_check(scene.cursor.is_equal_approx(target), "building entry frames selected cottage")
	_check(scene.camera_distance < terrain_distance, "building entry uses cottage-scale framing")

	# Moving the edit cursor must not move the orbit centre.
	var stable_target: Vector3 = scene._selected_building_camera_target()
	Input.action_press("m1_move_right")
	await process_frame
	Input.action_release("m1_move_right")
	await process_frame
	_check(scene._selected_building_camera_target().is_equal_approx(stable_target), "building orbit target ignores edit cursor movement")

	# Right stick remains live while the contextual action overlay is open.
	scene.detail_open = true
	if scene.tools_panel: scene.tools_panel.visible = true
	var overlay_yaw: float = scene.camera_yaw
	Input.action_press("m1_orbit_right")
	await process_frame
	Input.action_release("m1_orbit_right")
	await process_frame
	_check(not is_equal_approx(scene.camera_yaw, overlay_yaw), "camera orbits while building actions are open")
	var overlay_distance: float = scene.camera_distance
	Input.action_press("m1_zoom_in")
	await process_frame
	Input.action_release("m1_zoom_in")
	await process_frame
	_check(scene.camera_distance < overlay_distance, "camera zooms while building actions are open")

	# R3 reframe keeps the user's chosen orbit angle.
	scene.detail_open = false
	if scene.tools_panel: scene.tools_panel.visible = false
	scene.camera_yaw = 0.73
	scene.camera_pitch = 0.51
	scene.camera_distance = 20.0
	scene._focus_selected_building()
	_check(is_equal_approx(scene.camera_yaw, 0.73) and is_equal_approx(scene.camera_pitch, 0.51), "R3 reframe preserves orbit angle")
	_check(is_equal_approx(scene.camera_distance, scene._building_frame_distance()), "R3 reframe restores fit distance")

	# The camera should actually look at the selected cottage centre.
	scene._update_camera()
	var look_direction: Vector3 = (-scene.camera.global_transform.basis.z).normalized()
	var expected_direction: Vector3 = (scene._selected_building_camera_target() - scene.camera.global_position).normalized()
	_check(look_direction.dot(expected_direction) > 0.999, "building camera looks at selected cottage centre")

	# Leaving building mode restores the terrain view exactly.
	_check(scene._set_view_context("terrain", "camera test complete"), "return to terrain context")
	await process_frame
	_check(scene.cursor.is_equal_approx(terrain_cursor), "terrain cursor restored")
	_check(is_equal_approx(scene.camera_yaw, terrain_yaw) and is_equal_approx(scene.camera_pitch, terrain_pitch) and is_equal_approx(scene.camera_distance, terrain_distance), "terrain camera restored exactly")

	_finish()

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: %s" % label)

func _fail(label: String) -> void:
	failures += 1
	print("FAIL: %s" % label)

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene.queue_free()
		await process_frame
		await process_frame
	print(JSON.stringify({"ok": failures == 0, "failures": failures, "building_camera": failures == 0}))
	quit(1 if failures > 0 else 0)
