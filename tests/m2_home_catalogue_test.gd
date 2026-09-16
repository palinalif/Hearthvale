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
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)

	var starting_context: String = scene.view_context
	await _press(JOY_BUTTON_DPAD_UP)
	check(scene._browser_open and scene._browser_world_mode and scene._build_browser.visible and scene.tools_open, "D-pad Up opens current world build browser")
	check(scene.view_context == starting_context, "opening world browser does not require entering an existing home")
	check(_category_ids() == ["homes", "paths", "outdoor"] and scene._build_browser.category == "homes", "world browser exposes Homes Paths and Outdoor")
	check(_card("riverside_cottage") != null and _card("woodland_lodge") != null and _card("village_gable") != null, "Homes exposes all three residential designs by stable ID")
	for design in catalogue:
		var design_id := str(design["id"])
		check(scene._catalogue_wall_choices.has(design_id) and str(scene._catalogue_wall_choices[design_id]) in scene.WALL_MATERIALS, "home browser prepares valid wall palette for " + design_id)
		check(scene._catalogue_roof_choices.has(design_id) and str(scene._catalogue_roof_choices[design_id]) in scene._roof_material_choices(), "home browser prepares valid roof palette for " + design_id)
		check(scene._catalogue_accent_choices.has(design_id) and str(scene._catalogue_accent_choices[design_id]) in scene.ACCENT_MATERIALS, "home browser prepares valid accent palette for " + design_id)
	var home_card := _card("woodland_lodge")
	if home_card:
		var item: Dictionary = home_card.get_meta("item", {})
		check(str(item.get("kind", "")) == "home" and str(item.get("name", "")).contains("Woodland"), "home card carries player-facing name and home kind")
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	check(scene._build_browser.category == "paths", "RB reaches Paths & bridges")
	check(_card("packed_earth") != null and _card("timber") != null, "Paths exposes path and bridge choices")
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	check(scene._build_browser.category == "outdoor", "RB reaches Outdoor")
	check(_card("cottage_flowers") != null and _card("rustic_fence") != null and _card("bench") != null and _card("foliage") != null, "Outdoor exposes garden fence furniture and planting tools")
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	check(scene._build_browser.category == "homes", "LB returns to Homes")

	# Existing-home options remain compact; new construction belongs to the browser.
	scene._close_build_browser()
	scene._set_view_context("building", "test")
	scene._open_building_panel()
	await process_frame
	var home_action_labels: Array[String] = []
	for button in scene._building_buttons: home_action_labels.append(button.text)
	check(_has_prefix(home_action_labels, "Duplicate") and _has_prefix(home_action_labels, "Wall colour") and _has_prefix(home_action_labels, "Roof colour") and _has_prefix(home_action_labels, "Accent colour"), "home options expose existing-home duplication and colours")
	check(not _has_prefix(home_action_labels, "Add window") and not _has_prefix(home_action_labels, "Add door"), "new openings live in build browser rather than retired action rows")
	check(scene._building_panel.get_global_rect().end.y <= scene._prompt_bar.get_global_rect().position.y + 1.0, "compact home options stay above controller prompt bar")
	scene._close_building_panel()

	# Select a home through the current player-facing browser and preserve its deterministic palette.
	await _press(JOY_BUTTON_DPAD_UP)
	check(scene._browser_open and scene._build_browser.category == "homes", "world browser reopens on Homes")
	home_card = _card("woodland_lodge")
	check(home_card != null, "woodland lodge card is selectable")
	if home_card == null:
		await _finish()
		return
	var chosen_wall: String = str(scene._catalogue_wall_choices["woodland_lodge"])
	var chosen_roof: String = str(scene._catalogue_roof_choices["woodland_lodge"])
	var chosen_accent: String = str(scene._catalogue_accent_choices["woodland_lodge"])
	var before: String = scene.building_world.serialize_document()
	var previous_selection: String = scene.selected_building_id
	home_card.grab_focus()
	await _press(JOY_BUTTON_A)
	check(scene.building_placement_active and scene.building_placement_operation == "new", "choosing browser home enters new-home placement instead of duplication")
	check(scene.building_placement_design_id == "woodland_lodge" and scene.building_world.serialize_document() == before, "home browser preview is pure authoritative data")
	check(scene.building_placement_wall_material_id == chosen_wall and scene.building_placement_roof_material_id == chosen_roof and scene.building_placement_accent_material_id == chosen_accent, "home preview uses deterministic wall roof and accent palette")
	check(str(scene.building_placement_ghost._applied_view.get("style_id", "")) == "woodland_lodge", "complete placement ghost uses chosen recipe")
	var preview_dimensions: Vector3 = scene.building_placement_ghost._applied_view.get("dimensions", Vector3.ZERO)
	check(preview_dimensions == scene.SMALL_HOME_DIMENSIONS["woodland_lodge"], "new-home preview uses smaller authored default")
	check(scene.building_placement_valid, "chosen lodge begins at valid free-placement target")
	check(scene._commit_building_placement(), "valid browser home commits")
	var lodge_id: String = scene.selected_building_id
	var lodge: Dictionary = scene.building_world.get_building(lodge_id)
	check(lodge_id != previous_selection and lodge["shape_id"] == "longhouse" and lodge["style_id"] == "woodland_lodge", "placed lodge receives independent identity and saved design")
	check(lodge["details"].any(func(detail): return detail["kind"] == "window" and detail["asset_id"] == "window_lodge") and lodge["details"].any(func(detail): return detail["kind"] == "door" and detail["asset_id"] == "door_lodge"), "lodge recipe receives lodge windows and door")
	check(lodge["wall_material_id"] == chosen_wall and lodge["roof_material_id"] == chosen_roof and lodge["accent_material_id"] == chosen_accent, "placed lodge saves browser wall roof and accent palette together")
	check(lodge["dimensions"] == scene.SMALL_HOME_DIMENSIONS["woodland_lodge"], "placed lodge keeps smaller default dimensions")
	var first_surface: String = str(lodge["surfaces"][0]["id"])
	var original_surface: String = str(scene.building_world.get_building(previous_selection)["surfaces"][0]["id"])
	check(first_surface != original_surface, "new design owns fresh surface identities")

	var alternate_wall: String = _different_choice(scene.WALL_MATERIALS, chosen_wall)
	var alternate_roof: String = _different_choice(scene._roof_material_choices(), chosen_roof)
	check(scene.building_world.set_wall_material(lodge_id, alternate_wall), "wall material changes independently")
	check(scene.building_world.set_roof_material(lodge_id, alternate_roof), "roof material changes independently")
	lodge = scene.building_world.get_building(lodge_id)
	check(lodge["wall_material_id"] == alternate_wall and lodge["roof_material_id"] == alternate_roof, "independent material selections coexist")
	check(scene.building_world.undo() and scene.building_world.get_building(lodge_id)["roof_material_id"] == chosen_roof, "roof material edit is one undo transaction")
	check(scene.building_world.redo() and scene.building_world.get_building(lodge_id)["roof_material_id"] == alternate_roof, "roof material redo restores only that choice")

	var gable_target := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * World.MINIATURE_SCALE), Vector3(8, 8, 8))
	var gable_id: String = scene.building_world.create_home_at("village_gable", gable_target, scene.building_world.get_revision())
	check(not gable_id.is_empty() and scene.building_world.get_building(gable_id)["roof_profile"] == "steep_gable", "tall village gable creates from own saved recipe")
	var gable: Dictionary = scene.building_world.get_building(gable_id)
	check(gable["details"].any(func(detail): return detail["kind"] == "window" and detail["asset_id"] == "window_tudor") and gable["details"].any(func(detail): return detail["kind"] == "door" and detail["asset_id"] == "door_tudor"), "tall home recipe receives Tudor windows and door")
	var serialized: String = scene.building_world.serialize_document()
	var restored = World.new()
	check(restored.load_serialized_document(serialized), "multi-design document reloads")
	check(restored.get_building(lodge_id)["wall_material_id"] == alternate_wall and restored.get_building(lodge_id)["roof_material_id"] == alternate_roof and restored.get_building(lodge_id)["accent_material_id"] == chosen_accent and restored.get_building(gable_id)["style_id"] == "village_gable", "reload preserves design dimensions and all three house colours")

	# Cancel via current browser route and ensure authority/selection are restored.
	var cancel_before: String = scene.building_world.serialize_document()
	var selection_before: String = scene.selected_building_id
	await _press(JOY_BUTTON_DPAD_UP)
	var riverside_card := _card("riverside_cottage")
	check(riverside_card != null, "riverside home card exists for cancel test")
	if riverside_card:
		riverside_card.grab_focus()
		await _press(JOY_BUTTON_A)
		check(scene.building_placement_active and scene.building_placement_design_id == "riverside_cottage", "cancel fixture enters home placement")
		await _press(JOY_BUTTON_B)
		check(scene._browser_open and scene._browser_world_mode and scene._build_browser.category == "homes", "B returns cancelled home to world browser")
		check(scene.building_world.serialize_document() == cancel_before and scene.selected_building_id == selection_before, "browser placement cancel restores authority and selection")
		await _press(JOY_BUTTON_B)
	await _finish()

func _card(item_id: String) -> Button:
	if not scene._build_browser: return null
	for card in scene._build_browser.cards:
		var item: Dictionary = card.get_meta("item", {})
		if str(item.get("id", "")) == item_id: return card
	return null

func _category_ids() -> Array[String]:
	var result: Array[String] = []
	for category in scene._build_browser.categories:
		result.append(str(category[0]))
	return result

func _has_prefix(labels: Array[String], prefix: String) -> bool:
	for label in labels:
		if label.begins_with(prefix): return true
	return false

func _different_choice(choices: Array, current: String) -> String:
	for value in choices:
		if str(value) != current: return str(value)
	return ""

func _press(button: JoyButton) -> void:
	var down := InputEventJoypadButton.new()
	down.button_index = button
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await process_frame
	var up := InputEventJoypadButton.new()
	up.button_index = button
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await process_frame
	await process_frame

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m2_home_catalogue_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)