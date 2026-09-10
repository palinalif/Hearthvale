extends SceneTree

const World = preload("res://scripts/building_world.gd")
var failures := 0
var checks := 0
var scene: Node

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	var catalogue := World.home_catalogue()
	check(catalogue.size() == 3, "catalogue exposes three residential configurations")
	var shapes := {}; var styles := {}; var footprints := {}; var roof_materials := {}; var windows := {}; var doors := {}
	for design in catalogue:
		shapes[design["shape_id"]] = true
		styles[design["style_id"]] = true
		footprints[str(Vector2(design["dimensions"].x, design["dimensions"].z))] = true
		roof_materials[design["roof_material_id"]] = true
		windows[design["window_asset_id"]] = true
		doors[design["door_asset_id"]] = true
	check(shapes.size() == 3 and styles.size() == 3 and footprints.size() == 3, "homes differ by saved shape, style and footprint")
	check(roof_materials.size() == 3, "catalogue presents independent roof material defaults")
	check(windows.size() == 3 and doors.size() == 3, "each home design owns a distinct default window and door family")

	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-home-catalogue-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "native catalogue scene ready")
	if not scene._player_restored: await _finish(); return
	scene.set_process(false)
	var open_build := InputEventAction.new()
	open_build.action = "m1_mode_switch"
	open_build.pressed = true
	var starting_context: String = scene.view_context
	scene._input(open_build)
	check(scene._build_catalogue_open and scene._build_catalogue_panel.visible and scene.tools_open, "D-pad Up opens the global build catalogue from ordinary play")
	check(scene.view_context == starting_context, "opening the build catalogue does not require entering an existing home")
	check(scene._build_catalogue_buttons.size() == 3 and scene._build_catalogue_buttons[0].text.begins_with("Buildings") and scene._build_catalogue_buttons[1].text.begins_with("Roads & paths") and scene._build_catalogue_buttons[2].text.begins_with("Outdoor decorations"), "build catalogue exposes clear top-level categories")
	scene._open_roads_catalogue()
	check(scene._roads_catalogue_open and scene._roads_catalogue_panel.visible and scene._roads_catalogue_buttons.size() == 5, "roads category opens three path styles and two simple bridge styles")
	check(scene._roads_catalogue_buttons[3].text.begins_with("Timber footbridge") and scene._roads_catalogue_buttons[4].text.begins_with("Stone crossing"), "roads category names both bridge choices")
	scene._return_to_build_catalogue()
	scene._open_outdoor_catalogue()
	check(scene._outdoor_catalogue_open and scene._outdoor_catalogue_panel.visible and scene._outdoor_catalogue_buttons.size() == 3, "outdoor category exposes the current planting tools")
	scene._choose_outdoor_tool("foliage")
	check(not scene.tools_open and not scene._outdoor_catalogue_open and scene.view_context == "terrain" and scene.sculpt_tool == "foliage", "outdoor choice returns directly to the world with its brush active")
	scene._input(open_build)
	scene._open_home_catalogue()
	check(scene._home_catalogue_open and scene._home_catalogue_returns_to_build, "Buildings opens the home catalogue from the global category hub")
	scene._close_home_catalogue(true)
	check(scene._build_catalogue_open and not scene._home_catalogue_open, "B from homes returns to build categories")
	scene._close_all_catalogues()
	check(not scene.tools_open and not scene._build_catalogue_open, "B closes the global build catalogue cleanly")
	scene._set_view_context("building")
	scene._open_building_panel()
	await process_frame
	var home_action_labels: Array[String] = []
	for button in scene._building_buttons: home_action_labels.append(button.text)
	check("Add window" in home_action_labels and "Add door" in home_action_labels, "home options expose additional structural openings")
	check(scene._building_panel.get_global_rect().end.y <= scene._prompt_bar.get_global_rect().position.y + 1.0, "expanded home options stay above the controller prompt bar")
	scene._close_building_panel()

	scene._open_home_catalogue()
	check(scene._home_catalogue_open and scene._home_catalogue_panel.visible, "Place new home opens the controller catalogue")
	check(scene._home_catalogue_buttons.size() == 3 and scene._home_catalogue_buttons.all(func(button): return button.text.contains("Walls:") and button.text.contains("Roof:")), "each catalogue entry names wall and roof choices")
	scene._home_catalogue_buttons[1].grab_focus()
	scene._cycle_catalogue_material("wall", 1)
	scene._cycle_catalogue_material("roof", 1)
	check(scene._catalogue_wall_choices["woodland_lodge"] == "chalk_white" and scene._catalogue_roof_choices["woodland_lodge"] == "slate", "catalogue adjusts wall and roof choices independently")
	var before: String = scene.building_world.serialize_document()
	var previous_selection: String = scene.selected_building_id
	scene._choose_home_design("woodland_lodge")
	check(scene.building_placement_active and scene.building_placement_operation == "new", "choosing a design enters new-home placement instead of duplication")
	check(scene.building_placement_design_id == "woodland_lodge" and scene.building_world.serialize_document() == before, "catalogue preview is pure authoritative data")
	check(str(scene.building_placement_ghost._applied_view.get("style_id", "")) == "woodland_lodge", "complete placement ghost uses the chosen recipe")
	check(scene.building_placement_valid, "chosen lodge begins at a valid free-placement target")
	check(scene._commit_building_placement(), "valid catalogue home commits")
	var lodge_id: String = scene.selected_building_id
	var lodge: Dictionary = scene.building_world.get_building(lodge_id)
	check(lodge_id != previous_selection and lodge["shape_id"] == "longhouse" and lodge["style_id"] == "woodland_lodge", "placed lodge receives an independent identity and saved design")
	check(lodge["details"].any(func(detail): return detail["kind"] == "window" and detail["asset_id"] == "window_lodge") and lodge["details"].any(func(detail): return detail["kind"] == "door" and detail["asset_id"] == "door_lodge"), "lodge recipe receives lodge windows and door")
	check(lodge["wall_material_id"] == "chalk_white" and lodge["roof_material_id"] == "slate", "placed lodge saves chosen wall and roof materials independently")
	var first_surface := str(lodge["surfaces"][0]["id"])
	var original_surface := str(scene.building_world.get_building(previous_selection)["surfaces"][0]["id"])
	check(first_surface != original_surface, "new design owns fresh surface identities")

	check(scene.building_world.set_wall_material(lodge_id, "rose_lime"), "wall material changes independently")
	check(scene.building_world.set_roof_material(lodge_id, "thatch"), "roof material changes independently")
	lodge = scene.building_world.get_building(lodge_id)
	check(lodge["wall_material_id"] == "rose_lime" and lodge["roof_material_id"] == "thatch", "independent material selections coexist")
	check(scene.building_world.undo() and scene.building_world.get_building(lodge_id)["roof_material_id"] == "slate", "roof material edit is one undo transaction")
	check(scene.building_world.redo() and scene.building_world.get_building(lodge_id)["roof_material_id"] == "thatch", "roof material redo restores only that choice")

	var gable_target := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * World.MINIATURE_SCALE), Vector3(8, 8, 8))
	var gable_id: String = scene.building_world.create_home_at("village_gable", gable_target, scene.building_world.get_revision())
	check(not gable_id.is_empty() and scene.building_world.get_building(gable_id)["roof_profile"] == "steep_gable", "tall village gable creates from its own saved recipe")
	var gable: Dictionary = scene.building_world.get_building(gable_id)
	check(gable["details"].any(func(detail): return detail["kind"] == "window" and detail["asset_id"] == "window_tudor") and gable["details"].any(func(detail): return detail["kind"] == "door" and detail["asset_id"] == "door_tudor"), "tall home recipe receives Tudor windows and door")
	var serialized: String = scene.building_world.serialize_document()
	var restored := World.new()
	check(restored.load_serialized_document(serialized), "multi-design document reloads")
	check(restored.get_building(lodge_id)["wall_material_id"] == "rose_lime" and restored.get_building(lodge_id)["roof_material_id"] == "thatch" and restored.get_building(gable_id)["style_id"] == "village_gable", "reload preserves design and independent materials")

	var cancel_before: String = scene.building_world.serialize_document()
	var selection_before: String = scene.selected_building_id
	scene._begin_new_building_placement("riverside_cottage")
	scene._cancel_building_placement()
	check(scene.building_world.serialize_document() == cancel_before and scene.selected_building_id == selection_before, "catalogue placement cancel restores authority and selection")
	await _finish()

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m2_home_catalogue_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
