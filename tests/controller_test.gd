extends SceneTree

## In-tree controller regression. It drives the same InputMap actions used by
## gameplay, with a private checkpoint root so a test cannot touch production
## saves. A native backend timeout is a failure, rather than a hanging test.

var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scripts/m0_scene.gd").new()
	scene.checkpoint_root = "user://m0-controller-test-%s" % RenderingServer.get_current_rendering_method()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 15000
	while (scene.backend == null or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline:
		await process_frame
	if scene.backend == null or not scene.backend.is_ready():
		_fail("native backend ready within 15 seconds")
		_finish()
		return

	# Left stick moves the cursor in camera-relative space.
	var start_cursor: Vector3 = scene.cursor
	Input.action_press("m0_move_right")
	await process_frame
	Input.action_release("m0_move_right")
	_check(scene.cursor.distance_to(start_cursor) > 0.0, "left stick moves cursor")
	# The nonlinear response keeps fine stick nudges controllable.
	scene.cursor = Vector3(20, 5, 24)
	var full_start: Vector3 = scene.cursor
	await _axis(JOY_AXIS_LEFT_X, 1.0)
	var full_delta: float = scene.cursor.distance_to(full_start)
	scene.cursor = Vector3(20, 5, 24)
	var fine_start: Vector3 = scene.cursor
	await _axis(JOY_AXIS_LEFT_X, 0.6)
	var fine_delta: float = scene.cursor.distance_to(fine_start)
	_check(fine_delta > 0.0 and fine_delta < full_delta, "fine stick nudge moves slower than full input")

	# Right stick orbits and both triggers zoom through named actions.
	var yaw: float = scene.camera_yaw
	Input.action_press("m0_orbit_right")
	await process_frame
	Input.action_release("m0_orbit_right")
	_check(not is_equal_approx(scene.camera_yaw, yaw), "right stick orbits camera")
	var distance: float = scene.camera_distance
	Input.action_press("m0_zoom_in")
	await process_frame
	Input.action_release("m0_zoom_in")
	_check(scene.camera_distance < distance, "right trigger zooms in")

	# D-pad controls are discrete and do not paint while held.
	var radius_index: int = scene.brush_index
	await _press(JOY_BUTTON_DPAD_LEFT)
	_check(scene.brush_index == maxi(0, radius_index - 1), "dpad left changes brush radius")
	var altitude: float = scene.cursor.y
	await _press(JOY_BUTTON_DPAD_UP)
	_check(scene.cursor.y > altitude, "dpad up changes cursor altitude")

	# A creates a preview, B cancels it with no backend revision or voxel delta.
	scene.cursor = Vector3(24, 8, 24)
	var revision: int = int(scene.backend.stats().get("revision", -1))
	var voxel: int = scene.backend.voxel_at(Vector3i(24, 8, 24))
	await _press(JOY_BUTTON_A)
	_check(scene.preview_active, "A opens preview")
	await _press(JOY_BUTTON_B)
	_check(not scene.preview_active, "B cancels preview")
	_check(int(scene.backend.stats().get("revision", -2)) == revision and scene.backend.voxel_at(Vector3i(24, 8, 24)) == voxel, "cancel leaves native data unchanged")

	# A locks the exact snapped target. Fine cursor/radius/mode/height input is
	# ignored while locked, while orbit remains available for inspection.
	scene.cursor = Vector3(24.25, 8.25, 24.25)
	await _press(JOY_BUTTON_A)
	var locked_center: Vector3 = scene._preview_locked_center
	var locked_radius: float = scene._preview_locked_radius
	var locked_remove: bool = scene._preview_locked_remove
	var displayed_cells: Array[Vector3i] = scene.preview_cells.duplicate()
	var native_cells: Array[Vector3i] = scene.backend.preview_sphere(locked_center, locked_radius, locked_remove)
	_check(displayed_cells == native_cells, "displayed preview matches native changed set")
	var locked_yaw: float = scene.camera_yaw
	Input.action_press("m0_move_right"); await process_frame; Input.action_release("m0_move_right")
	await _press(JOY_BUTTON_DPAD_RIGHT); await _press(JOY_BUTTON_DPAD_UP); await _press(JOY_BUTTON_X)
	Input.action_press("m0_orbit_right"); await process_frame; Input.action_release("m0_orbit_right")
	_check(scene._preview_locked_center == locked_center and is_equal_approx(scene._preview_locked_radius, locked_radius) and scene._preview_locked_remove == locked_remove, "locked preview keeps exact target parameters")
	var brush_volume: MeshInstance3D = scene.brush_preview.get("BrushVolume")
	var affected_outline: MeshInstance3D = scene.brush_preview.get("AffectedOutline")
	_check(scene.brush_preview.visible and brush_volume.position == locked_center and is_equal_approx((brush_volume.mesh as SphereMesh).radius, locked_radius) and locked_center != scene.cursor, "brush envelope matches snapped locked target")
	_check(affected_outline.mesh != null, "affected outline has geometry")
	_check(not (scene.cursor_mesh.mesh is TorusMesh), "center marker is not a thick torus")
	_check(not is_equal_approx(scene.camera_yaw, locked_yaw), "camera still orbits while preview is locked")
	_check(not scene.preview_cells.is_empty(), "live preview reports affected native cells")
	await _press(JOY_BUTTON_A)
	var committed_revision: int = int(scene.backend.stats().get("revision", -3))
	_check(committed_revision > revision, "A commit changes native revision")
	_check(scene.backend.voxel_at(Vector3i(24, 8, 24)) != voxel, "A commit changes native voxel")
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(int(scene.backend.stats().get("redo_count", 0)) > 0, "LB undoes committed operation")
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	_check(int(scene.backend.stats().get("undo_count", 0)) > 0, "RB redoes committed operation")
	# The tunnel is empty at this target; native preview reports a real no-op.
	scene.cursor = Vector3(3, 5, 24); scene.remove_mode = true; await process_frame
	_check(scene.preview_cells.is_empty(), "empty tunnel reports no affected cells")
	var no_op_volume: MeshInstance3D = scene.brush_preview.get("BrushVolume")
	_check(scene.brush_preview.visible and no_op_volume.position == scene._snap_preview_target(scene.cursor), "no-op still shows brush volume")
	scene.cursor = Vector3(24, 8, 24)
	# X toggles ADD mode and the same preview/commit route remains bounded.
	await _press(JOY_BUTTON_X)
	_check(not scene.remove_mode, "X selects add mode")
	await _press(JOY_BUTTON_A); await _press(JOY_BUTTON_A)
	_check(int(scene.backend.stats().get("revision", -6)) > committed_revision, "ADD commit changes native revision")

	# Start opens a focused menu, where movement and A cannot edit the world.
	scene.cursor = Vector3(24, 8, 24)
	await _press(JOY_BUTTON_START)
	await process_frame
	_check(scene.menu_open, "Start opens pause menu")
	_check(not scene.brush_preview.visible, "pause menu hides brush preview")
	_check(scene.get_viewport().gui_get_focus_owner() is Button, "pause menu has controller focus")
	var first_focus: Control = scene.get_viewport().gui_get_focus_owner()
	await _press(JOY_BUTTON_DPAD_DOWN)
	_check(scene.get_viewport().gui_get_focus_owner() != first_focus, "dpad navigates pause menu")
	await _press(JOY_BUTTON_DPAD_UP)
	var menu_cursor: Vector3 = scene.cursor
	var menu_revision: int = int(scene.backend.stats().get("revision", -4))
	Input.action_press("m0_move_right"); await process_frame; Input.action_release("m0_move_right")
	await _press(JOY_BUTTON_A)
	_check(scene.cursor == menu_cursor and int(scene.backend.stats().get("revision", -5)) == menu_revision, "menu suppresses movement and commit")
	# Save and Reload are invoked through focused controller buttons.
	var save_button: Button = scene._pause_buttons["Save"]
	save_button.grab_focus(); await process_frame; await _press(JOY_BUTTON_A)
	_check(str(scene.backend.stats().get("save_status", "")) == "saved", "focused Save reports native result")
	var reload_button: Button = scene._pause_buttons["Reload"]
	reload_button.grab_focus(); await process_frame; await _press(JOY_BUTTON_A)
	_check(str(scene.backend.stats().get("save_status", "")) == "loaded", "focused Reload reports native result")
	# A focused application suspension cancels the preview and saves dirty data.
	await _press(JOY_BUTTON_B)
	await _press(JOY_BUTTON_X)
	await _press(JOY_BUTTON_A); await _press(JOY_BUTTON_A)
	await _press(JOY_BUTTON_A)
	scene._ever_focused = true
	scene._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not scene.preview_active and scene.menu_open, "focus-out cancels preview and pauses")
	_check(str(scene.backend.stats().get("save_status", "")) == "saved", "focus-out saves dirty native world")
	await _press(JOY_BUTTON_B)
	# Run the same benchmark from the menu on a private backend. One second is
	# enough because the fixture performs its first edit at t=0.
	var player_voxel: int = scene.backend.voxel_at(Vector3i(24, 8, 24))
	scene.benchmark_seconds_override = 1.0
	await _press(JOY_BUTTON_START)
	await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_A)
	# During the running fixture, B/A/D-pad are consumed and cannot restore or
	# edit the player backend behind the benchmark coroutine.
	await _press(JOY_BUTTON_B)
	await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_A)
	_check(scene._fixture_active and not scene._fixture_done, "fixture blocks controller actions while running")
	var fixture_deadline := Time.get_ticks_msec() + 15000
	while not scene._fixture_done and Time.get_ticks_msec() < fixture_deadline:
		await process_frame
	_check(scene._fixture_done, "menu fixture completes within timeout")
	_check(bool(scene._fixture_result.get("ok", false)) and int(scene._fixture_result.get("sample_count", 0)) > 0 and int(scene._fixture_result.get("edits", 0)) > 0 and int(scene._fixture_result.get("saves", 0)) > 0, "menu fixture reports successful isolated operations")
	await _press(JOY_BUTTON_A)
	var restore_deadline := Time.get_ticks_msec() + 15000
	while (not scene._player_restored or scene.backend == null or not scene.backend.is_ready()) and Time.get_ticks_msec() < restore_deadline:
		await process_frame
	_check(scene.backend != null and scene.backend.is_ready(), "fixture returns to player backend")
	_check(scene.backend.voxel_at(Vector3i(24, 8, 24)) == player_voxel, "fixture preserves player checkpoint data")
	_check(not scene.menu_open, "fixture return resumes world")

	# Disconnect always cancels a preview and pauses; reconnect cannot auto-commit.
	await _press(JOY_BUTTON_A)
	scene._on_joy_connection_changed(0, false)
	_check(not scene.preview_active and scene.menu_open and not scene.connected, "disconnect cancels preview and pauses")
	scene._on_joy_connection_changed(0, true)
	_check(not scene.preview_active and scene.menu_open and scene.connected, "reconnect does not auto-commit")

	_finish()

func _press(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	var release := InputEventJoypadButton.new()
	release.button_index = button
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await process_frame

func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	var release := InputEventJoypadMotion.new()
	release.axis = axis
	release.axis_value = 0.0
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await process_frame

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
	print(JSON.stringify({"ok": failures == 0, "failures": failures, "controller_actions": failures == 0, "preview_cancel": failures == 0, "menu_gating": failures == 0, "native_preview_cancel": failures == 0, "menu_focus_gating": failures == 0, "save_reload": failures == 0, "disconnect_cancel": failures == 0}))
	quit(1 if failures > 0 else 0)
