extends "res://tests/m1_playtest_staged_render_test.gd"
## Keep ALL accepted native/Mobile/pixel gates; append actual handle captures.

func _finish() -> void:
	if scene and is_instance_valid(scene) and scene._player_restored and failures == 0:
		scene._close_terrain_settings()
		scene._set_view_context("building")
		scene._enter_resize_selection()
		scene.camera_yaw = PI * 0.35
		scene.camera_pitch = 0.55
		scene.camera_distance = 10.0
		scene._update_camera()
		scene._update_resize_handles()
		scene._refresh_controller_hud()
		check(not scene.status_text.contains("A resize"), "entry hint describes pointed handles rather than shell A")
		await _capture("09-direct-resize-handles")
		for handle_id in ["right", "back_right", "height"]:
			scene._begin_handle_resize(handle_id)
			check(scene.resize_active, "rendered handle active: " + handle_id)
			check(not scene._pointer_label.visible, "grabbed handle replaces idle crosshair: " + handle_id)
			var change := Vector3(4, 0, 0) if handle_id == "right" else Vector3(4, 0, 4) if handle_id == "back_right" else Vector3(0, 2, 0)
			scene.resize_preview_dimensions = scene.resize_dimensions + change
			scene._refresh_handle_preview()
			scene._update_camera()
			scene._update_resize_handles()
			scene._refresh_controller_hud()
			await _capture("10-resize-" + handle_id)
			scene._cancel_resize()
			check(scene._pointer_label.visible, "cancel restores pointing crosshair: " + handle_id)
		scene._update_camera()
		scene._update_resize_handles()
		await _capture("11-resize-restored")
	super._finish()
