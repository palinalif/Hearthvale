extends SceneTree

## Bounded in-tree M1 route check. Inputs are delivered through InputMap events
## so the test exercises the same controller paths as a physical pad.

var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scripts/m1_scene.gd").new()
	# Keep each bounded run isolated from checkpoints produced by older grid
	# resolutions or an interrupted test process.
	scene.checkpoint_root = "user://m1-controller-test-%s-%s" % [RenderingServer.get_current_rendering_method(), Time.get_ticks_usec()]
	scene.test_mode = true
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 30000
	while (scene.backend == null or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(scene.backend != null and scene.backend.is_ready(), "native backend ready")
	if scene.backend == null or not scene.backend.is_ready():
		if scene.backend: print("BACKEND: %s" % JSON.stringify(scene.backend.stats()))
		_finish(); return
	_check(scene.backend.patch_size == Vector3i(96, 64, 96), "M1 uses doubled native terrain resolution")
	_check(is_equal_approx(float(scene.backend.voxel_scale), 0.5), "M1 preserves authored world scale")

	var cursor_start: Vector3 = scene.cursor
	await _axis(JOY_AXIS_LEFT_X, 1.0)
	_check(scene.cursor.distance_to(cursor_start) > 0.0, "left stick moves cursor")
	var yaw_start: float = scene.camera_yaw
	await _axis(JOY_AXIS_RIGHT_X, 1.0)
	_check(not is_equal_approx(scene.camera_yaw, yaw_start), "right stick orbits")
	var zoom_start: float = scene.camera_distance
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_check(scene.camera_distance < zoom_start, "right trigger zooms")
	var y_start: float = scene.cursor.y
	await _press(JOY_BUTTON_DPAD_UP)
	_check(scene.cursor.y > y_start, "dpad changes height")

	# Open details and move the selected window through the focused action.
	await _press(JOY_BUTTON_X)
	for _i in 17: await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_A)
	_check(scene.detail_move_active, "Move action opens detail preview")
	var move_start: Vector3 = scene.detail_move_position
	var cursor_during_move: Vector3 = scene.cursor
	var yaw_during_move: float = scene.camera_yaw
	await _axis(JOY_AXIS_LEFT_X, 1.0)
	_check(scene.detail_move_position != move_start, "detail preview follows stick")
	_check(scene.cursor == cursor_during_move, "detail move does not pan world cursor")
	await _axis(JOY_AXIS_RIGHT_X, 1.0)
	_check(scene.camera_yaw != yaw_during_move, "detail move still orbits camera")
	await _press(JOY_BUTTON_B)
	_check(not scene.detail_move_active, "B cancels detail move")

	# Reopen, choose Move, then commit and verify the authoritative state changed.
	await _press(JOY_BUTTON_X)
	for _i in 17: await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_A)
	var detail_id := str(scene.selected_detail_id)
	var before_move: Dictionary = scene.building_world.get_building("building-1")
	await _axis(JOY_AXIS_LEFT_X, 1.0)
	await _press(JOY_BUTTON_A)
	var after_move: Dictionary = scene.building_world.get_building("building-1")
	_check(not scene.detail_move_active and before_move != after_move, "A commits detail move")
	_check(not detail_id.is_empty(), "selected detail has stable id")

	# Resize preview is read-only until A and can be cancelled with B.
	await _press(JOY_BUTTON_A)
	var dimensions_before: Vector3 = scene.building_world.get_building("building-1")["dimensions"]
	await _press(JOY_BUTTON_DPAD_UP)
	_check(scene.resize_active and scene.resize_preview_dimensions.y > dimensions_before.y, "resize preview changes height")
	await _press(JOY_BUTTON_B)
	_check(not scene.resize_active and scene.building_world.get_building("building-1")["dimensions"] == dimensions_before, "resize B cancels without mutation")

	# Start focuses a pause menu and D-pad navigation stays inside it.
	await _press(JOY_BUTTON_START)
	_check(scene.menu_open and scene.get_viewport().gui_get_focus_owner() is Button, "Start opens focused pause menu")
	var focus_before: Control = scene.get_viewport().gui_get_focus_owner()
	await _press(JOY_BUTTON_DPAD_DOWN)
	_check(scene.get_viewport().gui_get_focus_owner() != focus_before, "D-pad navigates pause menu")
	var save_button: Button = scene._pause_buttons["Save"]
	save_button.grab_focus(); await process_frame; await _press(JOY_BUTTON_A)
	_check(str(scene.backend.stats().get("save_status", "")) == "saved", "Save stores native terrain and cottage document")
	var reload_button: Button = scene._pause_buttons["Reload"]
	reload_button.grab_focus(); await process_frame; await _press(JOY_BUTTON_A)
	_check(str(scene.backend.stats().get("save_status", "")) == "loaded", "Reload restores native terrain and cottage document")
	await _press(JOY_BUTTON_B)
	_check(not scene.menu_open, "B closes pause menu")
	await _press(JOY_BUTTON_BACK)
	await process_frame
	_check(scene.view_context == "terrain" and scene.brush_preview.visible, "terrain aiming shows influence volume")
	_check(scene.brush_preview.BrushVolume != null and scene.brush_preview.BrushVolume.visible, "influence volume remains visible without exact stamp")
	_check(scene.preview_cells.size() > 0, "terrain surface has exposed influence highlights")
	_check(scene.preview_center.y <= scene.cursor.y, "influence center follows sampled surface")
	await _press(JOY_BUTTON_START)
	_check(scene.menu_open and not scene.brush_preview.visible, "pause hides terrain preview")
	await _press(JOY_BUTTON_B)
	await _press(JOY_BUTTON_BACK)
	# An interrupted held A cannot leak a second commit until its release is
	# observed; this mirrors focus loss or controller disconnect behavior.
	var held := InputEventJoypadButton.new(); held.button_index = JOY_BUTTON_A; held.pressed = true
	Input.parse_input_event(held); Input.flush_buffered_events(); await process_frame
	scene._cancel_current_edit("test interruption")
	var repeated := InputEventJoypadButton.new(); repeated.button_index = JOY_BUTTON_A; repeated.pressed = true
	Input.parse_input_event(repeated); Input.flush_buffered_events(); await process_frame
	_check(not scene.stroke_active, "interrupted A stays blocked while held")
	var released := InputEventJoypadButton.new(); released.button_index = JOY_BUTTON_A; released.pressed = false
	Input.parse_input_event(released); Input.flush_buffered_events(); await process_frame

	_finish()

func _press(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button; event.pressed = true
	Input.parse_input_event(event); Input.flush_buffered_events(); await process_frame
	var release := InputEventJoypadButton.new()
	release.button_index = button; release.pressed = false
	Input.parse_input_event(release); Input.flush_buffered_events(); await process_frame

func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis; event.axis_value = value
	Input.parse_input_event(event); Input.flush_buffered_events(); await process_frame
	var release := InputEventJoypadMotion.new()
	release.axis = axis; release.axis_value = 0.0
	Input.parse_input_event(release); Input.flush_buffered_events(); await process_frame

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: %s" % label)

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene.queue_free()
		await process_frame
		await process_frame
	print(JSON.stringify({"ok": failures == 0, "failures": failures, "controller_actions": failures == 0, "detail_move": failures == 0, "resize_cancel": failures == 0, "menu_focus": failures == 0}))
	quit(1 if failures > 0 else 0)
