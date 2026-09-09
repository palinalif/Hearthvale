extends SceneTree
## Physical accept/cancel/mode events reach the complete exported scene.
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

func press(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	event = InputEventJoypadButton.new()
	event.button_index = button
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func stick(value: Vector2) -> void:
	for axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		var event := InputEventJoypadMotion.new()
		event.axis = axis
		event.axis_value = value.x if axis == JOY_AXIS_LEFT_X else value.y
		Input.parse_input_event(event)
	Input.flush_buffered_events()

func aim_handle(id: String) -> bool:
	scene._update_camera()
	for item in scene._handle_candidates():
		if str(item["id"]) != id: continue
		scene.edit_pointer = item["screen"]
		scene._update_detail_hover()
		scene._update_resize_handles()
		scene._refresh_controller_hud()
		return scene._handle_hover == id
	return false

func drag(vector: Vector2, frames: int = 45) -> void:
	stick(vector)
	for i in frames:
		scene._read_camera_and_cursor(1.0 / 60.0)
		scene._update_camera()
	stick(Vector2.ZERO)

func _run() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://resize-handles-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "complete native scene ready")
	if not scene._player_restored: _finish(); return
	scene.set_process(false)
	check(scene.get_script() == preload("res://scripts/m2_scene_pc_input.gd"), "exported scene uses PC input, catalogue, house and detail resize layers")
	scene._set_view_context("building")
	scene._enter_resize_selection()
	scene.camera_yaw = PI * 0.35
	scene.camera_pitch = 0.55
	scene.camera_distance = 10.0
	check(aim_handle("right"), "visible right edge can be deliberately targeted")
	check(scene._resize_overlay.visible and not scene.resize_handles.visible, "real handles shown; legacy floating cubes hidden")
	check(scene.hovered_detail_id.is_empty() and scene._resize_hint.visible, "handle has its own unambiguous highlight/prompt")
	var overlay: Control = scene._resize_overlay
	check(overlay._world_root.visible and overlay._spheres.size() <= 9, "resize selection shows a bounded world-sphere handle set")
	for candidate in scene._handle_candidates():
		var sphere: MeshInstance3D = overlay._spheres[str(candidate["id"])]
		check(sphere.mesh == overlay._sphere_mesh and sphere.mesh is SphereMesh, "handle shares the lightweight sphere mesh")
		check(scene.camera.unproject_position(sphere.global_position).distance_to(candidate["screen"]) < 0.01, "sphere centre preserves the accepted projected hit target")
		check(sphere.material_override.no_depth_test, "accepted candidates remain visible over terrain relief without moving their hit targets")
	check(overlay._spheres["right"].material_override == overlay._materials[1], "hovered sphere has its own cream state")
	var before: String = scene.building_world.serialize_document()
	var id: String = scene.selected_building_id
	var original_view: Dictionary = scene.building_world.get_building(id)
	var history: int = scene._history_tags.size()
	var camera_before: Transform3D = scene.camera.global_transform
	await press(JOY_BUTTON_A)
	check(scene.resize_active and scene._grabbed_handle == "right", "A picks precisely the pointed side")
	scene._update_resize_handles()
	check(overlay._spheres["right"].material_override == overlay._materials[2], "grabbed sphere has its own amber state")
	var direction: Vector2 = scene._screen_direction(scene._selected_building_camera_target(), Vector3.RIGHT)
	drag(direction)
	check(scene.resize_preview_dimensions.x > scene.resize_dimensions.x, "left stick pulls right edge outward relative to camera")
	check(scene.resize_preview_dimensions.y == scene.resize_dimensions.y and scene.resize_preview_dimensions.z == scene.resize_dimensions.z, "side changes only its own dimension")
	check(scene.building_world.serialize_document() == before and scene._history_tags.size() == history, "live preview never commits intermediate steps")
	var rendered: Node3D = scene.cottage_visuals[id]
	check(rendered.transform == scene._handle_preview["view"]["transform"], "rendered preview follows one-sided shifted origin")
	var first_child: int = rendered.get_child(0).get_instance_id()
	for i in 5: scene._update_presentation()
	check(rendered.get_child(0).get_instance_id() == first_child, "stationary preview does not rebuild meshes")
	var unchanged_dims: Vector3 = scene.resize_preview_dimensions
	await press(JOY_BUTTON_DPAD_RIGHT)
	await press(JOY_BUTTON_DPAD_UP)
	check(scene.resize_preview_dimensions == unchanged_dims and scene.selected_building_id == id and scene.view_context == "building", "active handle blocks legacy axis/cottage/mode switching")
	await press(JOY_BUTTON_B)
	check(not scene.resize_active and scene.view_context == "building" and scene.building_world.serialize_document() == before, "B restores recipe and stays in cottage editing")
	check(scene.camera.global_transform.is_equal_approx(camera_before), "cancel restores the original framing")
	check(rendered._applied_view == original_view, "cancel restores actual rendered cottage")
	check(aim_handle("right"), "right handle reachable again after cancel")
	await press(JOY_BUTTON_A)
	drag(direction)
	var expected: Dictionary = scene._handle_preview["view"].duplicate(true)
	await press(JOY_BUTTON_A)
	check(not scene.resize_active and scene._history_tags.size() == history + 1, "A commits exactly one undo transaction")
	check(scene.building_world.get_building(id) == expected and rendered._applied_view == expected, "commit equals the complete preview")
	await press(JOY_BUTTON_LEFT_SHOULDER)
	check(scene.building_world.get_building(id) == original_view, "physical undo restores bounds and details together")
	await press(JOY_BUTTON_RIGHT_SHOULDER)
	check(scene.building_world.get_building(id) == expected, "physical redo restores the resized design")
	check(aim_handle("height"), "height handle is above the roof and targetable")
	await press(JOY_BUTTON_A)
	var initial: Vector3 = scene.resize_dimensions
	drag(Vector2.UP)
	check(scene.resize_preview_dimensions.y > initial.y and scene.resize_preview_dimensions.x == initial.x and scene.resize_preview_dimensions.z == initial.z, "height handle grows upward without changing footprint")
	await press(JOY_BUTTON_B)
	check(aim_handle("back_right"), "visible corner handle targetable")
	await press(JOY_BUTTON_A)
	var point: Vector3 = scene._selected_building_camera_target()
	var corner_direction: Vector2 = (scene._screen_direction(point, Vector3.RIGHT) + scene._screen_direction(point, Vector3.BACK)).normalized()
	drag(corner_direction, 90)
	check(scene.resize_preview_dimensions.x > scene.resize_dimensions.x and scene.resize_preview_dimensions.z > scene.resize_dimensions.z, "corner moves both horizontal extents")
	var original_precision: bool = scene.precision_mode
	await press(JOY_BUTTON_LEFT_STICK)
	check(scene.precision_mode != original_precision and scene.resize_active, "L3 changes precision without changing action")
	await press(JOY_BUTTON_START)
	check(scene.menu_open and not scene.resize_active, "Pause safely cancels active handle")
	check(not overlay._world_root.visible, "pause hides world spheres with their inherited overlay")
	await press(JOY_BUTTON_B)
	check(not scene.menu_open and scene.view_context == "building", "Resume keeps cottage editing")
	scene._enter_resize_selection()
	check(aim_handle("right"), "handle ready after menu cancellation")
	await press(JOY_BUTTON_A)
	scene.building_world.set_material(id, "rose_lime")
	scene._read_camera_and_cursor(1.0 / 60.0)
	check(not scene.resize_active and scene.building_world.get_building(id)["material_id"] == "rose_lime", "stale preview cannot overwrite a newer authoritative edit")
	await press(JOY_BUTTON_B)
	check(scene.view_context == "building" and not scene._resize_selecting, "B finishes resize selection before exiting building")
	await press(JOY_BUTTON_B)
	scene._update_resize_handles()
	check(scene.view_context == "terrain" and not scene._resize_overlay.visible, "idle B exits and hides all building handles")
	_finish()

func _finish() -> void:
	stick(Vector2.ZERO)
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m1_resize_handles_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
