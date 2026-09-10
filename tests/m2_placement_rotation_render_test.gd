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
		check(scene._build_catalogue_panel.visible and scene._build_catalogue_buttons.size() == 4, "rendered global build catalogue exposes all four categories")
		await _capture("20-m2-build-catalogue")
		scene._open_outdoor_catalogue()
		check(scene._outdoor_catalogue_panel.visible and scene._outdoor_catalogue_buttons.size() == 3, "rendered outdoor catalogue exposes usable planting tools")
		await _capture("21-m2-outdoor-catalogue")
		scene._return_to_build_catalogue()
		scene._open_home_catalogue()
		check(scene._home_catalogue_panel.visible and scene._home_catalogue_buttons.size() == 3, "rendered M2 residential catalogue exposes all designs")
		await _capture("22-m2-home-catalogue")
		scene._close_home_catalogue(false)
		# The Thor UX repair must also be exercised by the existing real-Mobile
		# rendering gate, not only by headless state assertions.
		scene._set_view_context("building")
		scene._begin_next_storey()
		check(scene.portion_valid and scene._commit_portion_placement(), "UX fixture adds an upper floor")
		scene._update_presentation()
		scene._open_building_panel()
		scene._open_floor_edit_picker()
		check(scene._floor_edit_picker.visible, "placed floor has a visible edit entry")
		await _capture("23-m2-edit-floors")
		scene._choose_floor_to_edit(0)
		scene._resize_portion("x", 1)
		scene._update_camera()
		check(scene.portion_placement_active and not scene._editing_portion_id.is_empty(), "real Mobile shows existing floor edit preview")
		await _capture("24-m2-resize-placed-floor")
		scene._cancel_portion_placement()
		var ux_view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
		for detail_value in ux_view.get("details", []):
			var detail: Dictionary = detail_value
			if str(detail.get("kind", "")) != "window" or not bool(detail.get("visible", false)) or bool(detail.get("needs_placement", true)): continue
			scene.selected_detail_id = str(detail["id"])
			scene._begin_style_picker("colour")
			scene._preview_style_choice("colour", "berry")
			check(scene._style_picker_mode == "colour", "compact colour picker opens in real gameplay")
			await _capture("25-m2-compact-recolour")
			scene._cancel_style_picker()
			break
	super._finish()
