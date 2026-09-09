extends "res://tests/m1_ui_glyph_render_test.gd"

## Keep the complete inherited Mobile render suite and append the first M2
## placement states: a rotated valid ghost and a text-labelled hard overlap.

func _finish() -> void:
	if scene and is_instance_valid(scene) and scene._player_restored and failures == 0:
		scene._cancel_current_edit("M2 placement render")
		scene._set_view_context("building")
		scene._begin_building_placement()
		scene._rotate_building_preview(1)
		scene._rotate_building_preview(1)
		scene._update_camera()
		scene._update_presentation()
		scene._refresh_controller_hud()
		check(scene.building_placement_valid, "rotated M2 placement capture is valid")
		check(scene.building_placement_ghost.transform.is_equal_approx(scene.building_placement_transform), "rendered M2 ghost agrees with candidate transform")
		await _capture("18-m2-rotated-home-preview")

		var source: Dictionary = scene.building_world.get_building(scene.building_placement_source_id)
		scene.building_placement_target = (source["transform"] as Transform3D).origin
		scene._update_building_preview_transform()
		scene._update_camera()
		scene._update_presentation()
		scene._refresh_controller_hud()
		check(not scene.building_placement_valid and scene.building_placement_reason.begins_with("Overlaps"), "rendered invalid state carries an overlap reason")
		check(scene.target_label.text.contains("Overlaps"), "overlap reason is visible as text")
		await _capture("19-m2-invalid-overlap")
		scene._cancel_building_placement()

		scene._set_view_context("terrain")
		scene._open_build_catalogue()
		check(scene._build_catalogue_panel.visible and scene._build_catalogue_buttons.size() == 3, "rendered global build catalogue exposes all categories")
		await _capture("20-m2-build-catalogue")
		scene._open_outdoor_catalogue()
		check(scene._outdoor_catalogue_panel.visible and scene._outdoor_catalogue_buttons.size() == 3, "rendered outdoor catalogue exposes usable planting tools")
		await _capture("21-m2-outdoor-catalogue")
		scene._return_to_build_catalogue()
		scene._open_home_catalogue()
		check(scene._home_catalogue_panel.visible and scene._home_catalogue_buttons.size() == 3, "rendered M2 residential catalogue exposes all designs")
		await _capture("22-m2-home-catalogue")
		scene._close_home_catalogue(false)
	super._finish()
