extends "res://tests/m1_resize_handles_render_test.gd"
## Preserve inherited Mobile/style/handle assertions and add the new chooser.
func _finish() -> void:
	if scene and is_instance_valid(scene) and scene._player_restored and failures == 0:
		scene._close_terrain_settings()
		scene._set_view_context("building")
		scene._update_camera()
		scene._update_resize_handles()
		check(not scene._resize_overlay.visible, "ordinary editing has no resize handles")
		scene._open_house_actions()
		scene._refresh_controller_hud()
		check(scene._house_actions_panel.visible and not scene._building_panel.visible, "only Move/Resize chooser is shown")
		await _capture("14-house-move-resize-choice")
		scene._close_house_actions()
		scene.hud.visible = false
		var baseline := await _capture("15-house-before-move")
		scene.hud.visible = true
		scene._begin_house_move()
		scene.building_placement_target += Vector3(3, 0, 2)
		scene.cursor = scene.building_placement_target
		scene._update_camera()
		scene._update_presentation()
		scene._refresh_controller_hud()
		check(scene._moving_house and not scene.cottage_visuals[scene.selected_building_id].visible, "relocation uses ghost instead of a second opaque house")
		await _capture("16-moving-whole-house")
		scene._cancel_building_placement()
		scene._update_camera()
		scene.hud.visible = false
		var cancelled := await _capture("17-house-move-cancel")
		check(baseline.get_data() == cancelled.get_data(), "move cancel restores exact rendered scene")
		scene.hud.visible = true
	super._finish()
