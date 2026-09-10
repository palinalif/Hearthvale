extends SceneTree

var checks := 0
var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-surface-colours-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene._player_restored, "surface-colour scene ready")
	if not scene._player_restored:
		_finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	var original: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var original_wall := str(original.get("wall_material_id", original.get("material_id", "stone_plaster")))
	var original_roof := str(original.get("roof_material_id", "terracotta"))
	var original_accent := str(scene._accent_material_id(original))
	var wall_choice := _different_choice(scene.WALL_MATERIALS, original_wall)
	var roof_choices: Array[String] = scene._roof_material_choices()
	var roof_choice := "wood_shake"
	var accent_choice := _different_choice(scene.ACCENT_MATERIALS, original_accent)
	_check(not wall_choice.is_empty() and roof_choice in roof_choices and not accent_choice.is_empty(), "picker has alternate wall roof and accent colours")
	_check(roof_choices.size() == 7 and "wood_shake" in roof_choices and "standing_seam" in roof_choices and "green_roof" in roof_choices, "roof palette includes shake metal and living green finishes")
	var randomized_roofs: Dictionary = {}
	for seed in range(1000, 1100):
		randomized_roofs[str(scene._palette_for_seed(seed, "riverside_cottage")["roof"])] = true
	_check(randomized_roofs.has("wood_shake") and randomized_roofs.has("standing_seam") and randomized_roofs.has("green_roof"), "fresh-home randomization can select every added roof finish")
	var wall_button: Button = null
	var roof_button: Button = null
	var accent_button: Button = null
	for button in scene._building_buttons:
		if button.text == "Wall colour": wall_button = button
		if button.text == "Roof colour": roof_button = button
		if button.text == "Accent colour": accent_button = button
	_check(wall_button != null and roof_button != null and accent_button != null, "home options expose Wall Roof and Accent colour")

	var before_serialized: String = str(scene.building_world.serialize_document())
	scene._open_surface_material_picker("wall")
	_check(scene._surface_material_picker_open and scene._surface_material_picker_kind == "wall" and scene._surface_material_picker_panel.visible, "Wall colour opens browse picker")
	_check(scene._surface_material_candidates().size() == scene.WALL_MATERIALS.size(), "wall picker shows every wall material")
	scene._preview_surface_material(wall_choice)
	_check(scene.building_world.serialize_document() == before_serialized, "wall colour browsing is read-only")
	var visual: Node = scene.cottage_visuals.get(scene.selected_building_id, null) as Node
	_check(visual != null and str(visual._applied_view.get("wall_material_id", "")) == wall_choice, "wall colour focus previews directly on house")
	scene._cancel_surface_material_picker()
	_check(scene.building_world.serialize_document() == before_serialized and not scene._surface_material_picker_open, "B cancel restores wall colour without history")

	var history_before: int = scene._history_tags.size()
	scene._open_surface_material_picker("wall")
	scene._commit_surface_material(wall_choice)
	_check(str(scene.building_world.get_building(scene.selected_building_id).get("wall_material_id", "")) == wall_choice, "A apply persists wall colour")
	_check(scene._history_tags.size() == history_before + 1, "wall colour apply records one undo step")

	scene._open_surface_material_picker("roof")
	_check(scene._surface_material_picker_open and scene._surface_material_picker_kind == "roof", "Roof colour uses the same picker")
	_check(scene._surface_material_candidates().size() == roof_choices.size(), "roof picker shows every roof material")
	var wall_persisted := str(scene.building_world.get_building(scene.selected_building_id).get("wall_material_id", ""))
	var roof_before_preview: String = str(scene.building_world.serialize_document())
	scene._preview_surface_material(roof_choice)
	_check(scene.building_world.serialize_document() == roof_before_preview, "roof colour browsing is read-only")
	_check(visual != null and str(visual._applied_view.get("roof_material_id", "")) == roof_choice, "roof colour focus previews directly on house")
	_check(_visual_uses_extra_roof_finish(visual, scene.EXTRA_ROOF_PALETTES[roof_choice]), "wood-shake preview reaches rendered roof geometry")
	scene._commit_surface_material(roof_choice)
	var after: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	_check(str(after.get("roof_material_id", "")) == roof_choice and str(after.get("wall_material_id", "")) == wall_persisted, "roof apply persists independently from wall colour")
	_check(scene._history_tags.size() == history_before + 2, "roof colour apply records one undo step")

	var accent_before_serialized: String = str(scene.building_world.serialize_document())
	scene._open_surface_material_picker("accent")
	_check(scene._surface_material_picker_open and scene._surface_material_picker_kind == "accent", "Accent colour uses the shared browse picker")
	_check(scene._surface_material_candidates().size() == scene.ACCENT_MATERIALS.size() and scene.ACCENT_MATERIALS.size() >= 6, "accent picker exposes the expanded muted colour palette")
	scene._preview_surface_material(accent_choice)
	_check(scene.building_world.serialize_document() == accent_before_serialized, "accent browsing is read-only")
	_check(_visual_uses_accent(visual, after, scene.ACCENT_COLOURS[accent_choice]), "accent preview recolours window shutters and accessory joinery")
	scene._cancel_surface_material_picker()
	_check(scene.building_world.serialize_document() == accent_before_serialized and _visual_uses_accent(visual, after, scene.ACCENT_COLOURS[original_accent]), "B cancel restores the saved or deterministic accent")

	scene._open_surface_material_picker("accent")
	scene._commit_surface_material(accent_choice)
	after = scene.building_world.get_building(scene.selected_building_id)
	_check(str(after.get("accent_material_id", "")) == accent_choice, "A apply persists one house-level accent colour")
	_check(scene._history_tags.size() == history_before + 3, "accent colour apply records one undo step")
	_check(_visual_uses_accent(visual, after, scene.ACCENT_COLOURS[accent_choice]), "saved accent drives shutters doors and window joinery together")
	var serialized: String = scene.building_world.serialize_document()
	var restored = preload("res://scripts/building_world.gd").new()
	_check(restored.load_serialized_document(serialized) and str(restored.get_building(scene.selected_building_id).get("accent_material_id", "")) == accent_choice and str(restored.get_building(scene.selected_building_id).get("roof_material_id", "")) == roof_choice, "accent and expanded roof finish survive save and reload")
	_finish()

func _visual_uses_extra_roof_finish(visual: Node, palette: Array) -> bool:
	if not visual: return false
	var expected: Array[Color] = []
	for value in palette: expected.append(value as Color)
	return _tree_has_roof_colour(visual, expected, false)

func _tree_has_roof_colour(node: Node, expected: Array[Color], inside_custom: bool) -> bool:
	if str(node.name) == "M2RoofAccessories": return false
	var custom: bool = inside_custom or str(node.name) == "M2RoofDesign"
	if node is GeometryInstance3D:
		var name := str(node.name)
		var roof_piece := name.begins_with("RoofTiles_") or name in ["RidgeCourses", "RoofEdgeLip"] or (custom and not name.contains("Fill"))
		var material = (node as GeometryInstance3D).material_override
		if roof_piece and material is StandardMaterial3D and (material as StandardMaterial3D).albedo_color in expected: return true
	for child in node.get_children():
		if _tree_has_roof_colour(child, expected, custom): return true
	return false

func _visual_uses_accent(visual: Node, view: Dictionary, colour: Color) -> bool:
	if not visual: return false
	var door_ids := {}
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("kind", "")) == "door": door_ids[str(detail.get("id", ""))] = true
	var found_shutter := false
	var found_door := false
	var found_joinery := false
	for child in visual.get_children():
		if not child is GeometryInstance3D: continue
		var name := str(child.name)
		var material = (child as GeometryInstance3D).material_override
		if not material is StandardMaterial3D: continue
		var matches := (material as StandardMaterial3D).albedo_color == colour
		if name.begins_with("Shutters_") or name.begins_with("ManualShutter_"): found_shutter = found_shutter or matches
		if name.begins_with("Joinery_"): found_joinery = found_joinery or matches
		if name.begins_with("Detail_") and door_ids.has(name.trim_prefix("Detail_")): found_door = found_door or matches
	return found_shutter and found_door and found_joinery

func _different_choice(choices: Array, current: String) -> String:
	for value in choices:
		if str(value) != current: return str(value)
	return ""

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures}))
	quit(1 if failures else 0)
