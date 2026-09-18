extends SceneTree
## CI probe: pre-load the deep scene chain BOTTOM-UP to warm the class
## cache in the correct (parent-before-child) order. Godot's headless
## import resolves the ~54-deep path-based `extends` chain racy when it
## starts from the scene root (top-down) before its parents exist, which
## makes the later export fail with "Could not resolve class". Loading
## the chain bottom-up (as the real game build does across editor sessions)
## deterministically resolves every link; the APK build re-runs this until
## it passes, before exporting.
const CHAIN := [
  "res://scripts/m1_scene.gd",
  "res://scripts/m1_scene_placement.gd",
  "res://scripts/m1_scene_terrain_ux.gd",
  "res://scripts/m1_scene_building_camera.gd",
  "res://scripts/m1_scene_cottage_ux.gd",
  "res://scripts/m1_scene_cottage_style.gd",
  "res://scripts/m1_scene_cottage_alignment.gd",
  "res://scripts/m1_scene_cottage_resize_ux.gd",
  "res://scripts/m1_scene_ui_overhaul.gd",
  "res://scripts/m1_scene_tool_ui.gd",
  "res://scripts/m1_scene_full_ui.gd",
  "res://scripts/m1_scene_playtest_repair.gd",
  "res://scripts/m1_scene_thor_retest.gd",
  "res://scripts/m1_scene_resize_handles.gd",
  "res://scripts/m1_scene_house_actions.gd",
  "res://scripts/m1_scene_detail_resize.gd",
  "res://scripts/m2_scene_catalogue.gd",
  "res://scripts/m2_scene_paths.gd",
  "res://scripts/m2_scene_composition.gd",
  "res://scripts/m2_scene_hamlet_details.gd",
  "res://scripts/m2_scene_street_furniture.gd",
  "res://scripts/m2_scene_path_feedback.gd",
  "res://scripts/m2_scene_building_feedback.gd",
  "res://scripts/m2_scene_raised_foundation.gd",
  "res://scripts/m2_scene_house_palette.gd",
  "res://scripts/m2_scene_house_decor.gd",
  "res://scripts/m2_scene_pc_input.gd",
  "res://scripts/m2_scene_roof_design.gd",
  "res://scripts/m2_scene_roof_accessories.gd",
  "res://scripts/m2_scene_roof_options.gd",
  "res://scripts/m2_scene_roof_materials.gd",
  "res://scripts/m2_scene_terrain_house_outline.gd",
  "res://scripts/m2_scene_window_customization.gd",
  "res://scripts/m2_scene_house_massing.gd",
  "res://scripts/m2_scene_house_massing_interaction.gd",
  "res://scripts/m2_scene_joined_roof_beams.gd",
  "res://scripts/m2_scene_multi_floor.gd",
  "res://scripts/m2_scene_upper_wall_details.gd",
  "res://scripts/m2_scene_multi_floor_layout.gd",
  "res://scripts/m2_scene_auto_upper_windows.gd",
  "res://scripts/m2_scene_decor_colour.gd",
  "res://scripts/m2_scene_compact_colours.gd",
  "res://scripts/m2_scene_attachment_repair.gd",
  "res://scripts/m2_scene_window_alignment.gd",
  "res://scripts/m2_scene_house_editing.gd",
  "res://scripts/m2_scene_roof_courses.gd",
  "res://scripts/m2_scene_joined_roof_courses.gd",
  "res://scripts/m2_scene_facade_depth.gd",
  "res://scripts/m2_scene_build_browser.gd",
  "res://scripts/m2_scene_path_terrain_ownership.gd",
  "res://scripts/m2_scene_path_erase.gd",
  "res://scripts/m2_scene_style_preview_stability.gd",
  "res://scripts/m2_scene_starter_valley.gd",
  "res://scripts/m2_scene_water.gd",
]

func _init() -> void:
	for i in CHAIN.size():
		var res: GDScript = load(CHAIN[i])
		if res == null:
			push_error("chain probe: load failed at index %d: %s" % [i, CHAIN[i]])
			quit(1)
			return
	print("CHAIN_RESOLVED depth=%d" % CHAIN.size())
	quit(0)
