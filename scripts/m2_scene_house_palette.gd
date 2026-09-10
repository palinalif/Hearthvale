extends "res://scripts/m2_scene_raised_foundation.gd"

## M2 house styling: fresh homes arrive with a varied, saved palette and a
## smaller authored footprint. Accent colour is one building-level choice used
## by doors, window joinery, shutters and small accessory timber.

const ACCENT_MATERIALS: Array[String] = [
	"deep_teal",
	"sage_green",
	"dusty_blue",
	"oxblood",
	"ochre",
	"plum",
]
const ACCENT_COLOURS := {
	"deep_teal": Color("#557a70"),
	"sage_green": Color("#738267"),
	"dusty_blue": Color("#657b8d"),
	"oxblood": Color("#7b4944"),
	"ochre": Color("#a37b43"),
	"plum": Color("#74586f"),
}
const SMALL_HOME_DIMENSIONS := {
	"riverside_cottage": Vector3(15.0, 6.0, 12.0),
	"woodland_lodge": Vector3(18.0, 5.0, 9.5),
	"village_gable": Vector3(10.0, 7.5, 13.0),
}
const HOME_PALETTE_STYLE_OFFSET := {
	"riverside_cottage": 0,
	"woodland_lodge": 2,
	"village_gable": 4,
}

var _accent_colour_button: Button
var _catalogue_accent_choices: Dictionary = {}
var _catalogue_palette_key := -1
var building_placement_accent_material_id := ""
var building_placement_default_dimensions := Vector3.ZERO
var _building_placement_preview_view: Dictionary = {}

func _ready() -> void:
	super._ready()
	_install_accent_colour_action()
	_extend_surface_picker_with_accents()
	_update_home_catalogue_copy()
	_apply_all_house_accents()

func _install_accent_colour_action() -> void:
	if not _building_panel: return
	var margin := _building_panel.get_child(0) as MarginContainer
	var box := margin.get_child(0) as VBoxContainer
	_add_building_button(box, "Accent colour", _open_accent_colour_picker)
	_accent_colour_button = box.get_child(box.get_child_count() - 1) as Button
	_accent_colour_button.custom_minimum_size.y = 36
	var roof_button: Button = null
	for button in _building_buttons:
		if button.text.begins_with("Roof colour"):
			roof_button = button
			break
	if roof_button:
		box.move_child(_accent_colour_button, roof_button.get_index() + 1)
		_building_buttons.erase(_accent_colour_button)
		var roof_index := _building_buttons.find(roof_button)
		_building_buttons.insert(roof_index + 1, _accent_colour_button)
	box.add_theme_constant_override("separation", 3)
	for button in _building_buttons:
		button.custom_minimum_size.y = 36

func _extend_surface_picker_with_accents() -> void:
	if not _surface_material_picker_panel: return
	var box := _catalogue_box(_surface_material_picker_panel)
	for material_id in ACCENT_MATERIALS:
		var button := Button.new()
		button.text = material_id.replace("_", " ").capitalize()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(380, 44)
		button.focus_mode = Control.FOCUS_ALL
		button.icon = _colour_swatch(ACCENT_COLOURS[material_id])
		button.set_meta("material_id", material_id)
		button.focus_entered.connect(_preview_surface_material.bind(material_id))
		button.pressed.connect(_commit_surface_material.bind(material_id))
		button.visible = false
		box.add_child(button)
		_surface_material_picker_buttons.append(button)

func _update_home_catalogue_copy() -> void:
	if not _home_catalogue_panel: return
	var box := _catalogue_box(_home_catalogue_panel)
	if box.get_child_count() > 1 and box.get_child(1) is Label:
		(box.get_child(1) as Label).text = "Fresh homes start varied • adjust walls and roof before preview"
	for design_id in _catalogue_buttons_by_id:
		_refresh_catalogue_button(str(design_id))

func _open_home_catalogue() -> void:
	_prepare_catalogue_palettes()
	super._open_home_catalogue()

func _prepare_catalogue_palettes() -> void:
	var key: int = int(building_world.get_document().get("next_id", 1))
	_catalogue_palette_key = key
	var seed: int = _next_home_seed()
	for design_id_value in _catalogue_designs.keys():
		var design_id := str(design_id_value)
		var palette: Dictionary = _palette_for_seed(seed, design_id)
		_catalogue_wall_choices[design_id] = palette["wall"]
		_catalogue_roof_choices[design_id] = palette["roof"]
		_catalogue_accent_choices[design_id] = palette["accent"]
		_refresh_catalogue_button(design_id)

func _refresh_catalogue_button(design_id: String) -> void:
	super._refresh_catalogue_button(design_id)
	if not _catalogue_buttons_by_id.has(design_id): return
	var button: Button = _catalogue_buttons_by_id[design_id]
	var accent: String = str(_catalogue_accent_choices.get(design_id, _palette_for_seed(_next_home_seed(), design_id)["accent"]))
	var dims: Vector3 = _default_home_dimensions(design_id)
	button.text += "\nAccent: %s   Size: %.0f×%.1f×%.1f" % [accent.replace("_", " ").capitalize(), dims.x, dims.y, dims.z]
	button.custom_minimum_size.y = 96

func _next_home_seed() -> int:
	var next_id: int = int(building_world.get_document().get("next_id", 1))
	return 1042 + (next_id + 1) * 37

func _palette_for_seed(seed: int, design_id: String) -> Dictionary:
	var style_offset: int = int(HOME_PALETTE_STYLE_OFFSET.get(design_id, 0))
	var wall_index: int = posmod(seed * 17 + style_offset * 3, WALL_MATERIALS.size())
	var roof_index: int = posmod(seed * 11 + style_offset * 5 + 1, ROOF_MATERIALS.size())
	var accent_index: int = posmod(seed * 7 + style_offset * 2 + 3, ACCENT_MATERIALS.size())
	var wall_id: String = WALL_MATERIALS[wall_index]
	var accent_id: String = ACCENT_MATERIALS[accent_index]
	# Avoid the rare near-tone pairing so the accessory colour still reads at
	# miniature scale. Walk the same deterministic palette rather than rerolling.
	for offset in ACCENT_MATERIALS.size():
		var candidate: String = ACCENT_MATERIALS[posmod(accent_index + offset, ACCENT_MATERIALS.size())]
		if _accent_contrasts(wall_id, candidate):
			accent_id = candidate
			break
	return {"wall": wall_id, "roof": ROOF_MATERIALS[roof_index], "accent": accent_id}

func _accent_contrasts(wall_id: String, accent_id: String) -> bool:
	if not SURFACE_MATERIAL_COLOURS.has(wall_id) or not ACCENT_COLOURS.has(accent_id): return true
	var wall: Color = SURFACE_MATERIAL_COLOURS[wall_id]
	var accent: Color = ACCENT_COLOURS[accent_id]
	var channel_delta: float = maxf(absf(wall.r - accent.r), maxf(absf(wall.g - accent.g), absf(wall.b - accent.b)))
	return channel_delta >= 0.18

func _default_home_dimensions(design_id: String) -> Vector3:
	var value = SMALL_HOME_DIMENSIONS.get(design_id, null)
	if value is Vector3: return value
	for design_value in BuildingWorldScript.home_catalogue():
		var design: Dictionary = design_value
		if str(design.get("id", "")) == design_id: return design.get("dimensions", Vector3(18, 7, 14))
	return Vector3(18, 7, 14)

func _design_record(design_id: String) -> Dictionary:
	for design_value in BuildingWorldScript.home_catalogue():
		var design: Dictionary = design_value
		if str(design.get("id", "")) == design_id: return design
	return {}

func _begin_new_building_placement(design_id: String, wall_material_id: String = "", roof_material_id: String = "") -> void:
	var palette: Dictionary = _palette_for_seed(_next_home_seed(), design_id)
	if wall_material_id.is_empty(): wall_material_id = str(palette["wall"])
	if roof_material_id.is_empty(): roof_material_id = str(palette["roof"])
	var current_key: int = int(building_world.get_document().get("next_id", 1))
	var accent_id: String = str(_catalogue_accent_choices.get(design_id, palette["accent"])) if _catalogue_palette_key == current_key else str(palette["accent"])
	super._begin_new_building_placement(design_id, wall_material_id, roof_material_id)
	if not building_placement_active or building_placement_operation != "new": return
	building_placement_accent_material_id = accent_id
	building_placement_default_dimensions = _default_home_dimensions(design_id)
	_building_placement_preview_view = _preview_styled_home(design_id, building_placement_transform, wall_material_id, roof_material_id, accent_id, _next_home_seed())
	if not _building_placement_preview_view.is_empty() and building_placement_ghost:
		building_placement_ghost.show_source(_building_placement_preview_view, building_world.get_revision())
		_update_building_preview_transform()
		_apply_accent_to_visual(building_placement_ghost, _building_placement_preview_view, accent_id)

func _preview_styled_home(design_id: String, target: Transform3D, wall_id: String, roof_id: String, accent_id: String, seed: int) -> Dictionary:
	var design: Dictionary = _design_record(design_id)
	if design.is_empty(): return {}
	var dimensions: Vector3 = _default_home_dimensions(design_id)
	var building: Dictionary = building_world._new_cottage("preview-" + design_id, dimensions, target.origin, seed)
	building_world._apply_home_design(building, design)
	building["dimensions"] = [dimensions.x, dimensions.y, dimensions.z]
	building_world._reflow_automatic_windows(building)
	building_world._refresh_buckets(building)
	building_world._apply_wall_material(building, wall_id)
	building_world._apply_roof_material(building, roof_id)
	building["accent_material_id"] = accent_id
	var material_overrides: Dictionary = building.get("material_overrides", {})
	material_overrides["accent"] = accent_id
	building["material_overrides"] = material_overrides
	building["transform"] = building_world._transform_from_transform(target, target.origin)
	return building_world._resolved_building(building)

func _building_footprint(transform_value: Transform3D, dimensions: Vector3) -> Dictionary:
	var effective_dimensions: Vector3 = dimensions
	if building_placement_active and building_placement_operation == "new" and building_placement_default_dimensions != Vector3.ZERO and transform_value.is_equal_approx(building_placement_transform):
		effective_dimensions = building_placement_default_dimensions
	return super._building_footprint(transform_value, effective_dimensions)

func _commit_building_placement() -> bool:
	if not building_placement_active or building_placement_operation != "new":
		return super._commit_building_placement()
	_update_building_placement_validity()
	if not building_placement_valid:
		_set_status("Cannot place home: %s" % building_placement_reason)
		return false
	var placed_id: String = _create_styled_home(
		building_placement_design_id,
		building_placement_transform,
		building_placement_revision,
		building_placement_wall_material_id,
		building_placement_roof_material_id,
		building_placement_accent_material_id
	)
	var ok: bool = not placed_id.is_empty()
	if ok:
		selected_building_id = placed_id
		selected_detail_id = ""
		selected_surface_id = ""
		_record_history("building")
	_clear_building_placement()
	_set_status("New home placed" if ok else "Home placement rejected")
	_update_presentation()
	return ok

func _create_styled_home(design_id: String, target: Transform3D, expected_revision: int, wall_id: String, roof_id: String, accent_id: String) -> String:
	if expected_revision >= 0 and expected_revision != building_world.get_revision(): return ""
	var design: Dictionary = _design_record(design_id)
	if design.is_empty() or not target.origin.is_finite(): return ""
	if (building_world._document["buildings"] as Array).size() >= BuildingWorldScript.MAX_BUILDINGS: return ""
	var before: Dictionary = building_world._copy(building_world._document)
	var new_id: String = building_world._allocate_id("building")
	var seed: int = 1042 + building_world._next_id * 37
	var dimensions: Vector3 = _default_home_dimensions(design_id)
	var building: Dictionary = building_world._new_cottage(new_id, dimensions, target.origin, seed)
	building_world._apply_home_design(building, design)
	building["dimensions"] = [dimensions.x, dimensions.y, dimensions.z]
	building_world._reflow_automatic_windows(building)
	building_world._refresh_buckets(building)
	building_world._apply_wall_material(building, wall_id)
	building_world._apply_roof_material(building, roof_id)
	building["accent_material_id"] = accent_id
	var material_overrides: Dictionary = building.get("material_overrides", {})
	material_overrides["accent"] = accent_id
	building["material_overrides"] = material_overrides
	building["transform"] = building_world._transform_from_transform(target, target.origin)
	building_world._freshen_home_ids(building)
	var total_details := (building.get("details", []) as Array).size()
	for building_value in building_world._document.get("buildings", []):
		total_details += ((building_value as Dictionary).get("details", []) as Array).size()
	if total_details > BuildingWorldScript.MAX_DETAILS:
		building_world._document = before
		return ""
	(building_world._document["buildings"] as Array).append(building)
	if not building_world._record_change(before): return ""
	return new_id

func _clear_building_placement() -> void:
	super._clear_building_placement()
	building_placement_accent_material_id = ""
	building_placement_default_dimensions = Vector3.ZERO
	_building_placement_preview_view.clear()

func _open_accent_colour_picker() -> void:
	_open_surface_material_picker("accent")

func _open_surface_material_picker(kind: String) -> void:
	if kind != "accent":
		super._open_surface_material_picker(kind)
		return
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty(): return
	_surface_material_picker_kind = "accent"
	_surface_material_picker_original = _accent_material_id(view)
	_surface_material_picker_preview = _surface_material_picker_original
	_surface_material_picker_open = true
	tools_open = true
	if _building_panel: _building_panel.visible = false
	_surface_material_picker_panel.visible = true
	var candidates := _surface_material_candidates()
	for button in _surface_material_picker_buttons:
		button.visible = button in candidates
		button.disabled = not button.visible
	var focus_button: Button = null
	for button in candidates:
		if str(button.get_meta("material_id", "")) == _surface_material_picker_original:
			focus_button = button
			break
	if focus_button == null and not candidates.is_empty(): focus_button = candidates[0]
	if focus_button: focus_button.grab_focus()
	_set_status("Choose accent colour • doors, windows & shutters • A apply / B cancel")
	_apply_surface_material_preview()
	_refresh_controller_hud()

func _surface_material_candidates() -> Array:
	if _surface_material_picker_kind != "accent": return super._surface_material_candidates()
	var result: Array = []
	for button in _surface_material_picker_buttons:
		if str(button.get_meta("material_id", "")) in ACCENT_MATERIALS: result.append(button)
	return result

func _apply_surface_material_preview() -> void:
	if _surface_material_picker_kind != "accent":
		super._apply_surface_material_preview()
		_apply_all_house_accents()
		return
	_apply_all_house_accents()

func _commit_surface_material(material_id: String) -> void:
	if _surface_material_picker_kind != "accent":
		super._commit_surface_material(material_id)
		return
	var changed: bool = _set_building_accent(selected_building_id, material_id)
	_close_surface_material_picker()
	if changed: _record_history("building")
	_set_status("Accent colour updated" if changed else "Accent colour unchanged")
	_presentation_key = ""
	_update_presentation()

func _set_building_accent(building_id: String, accent_id: String) -> bool:
	if accent_id not in ACCENT_MATERIALS: return false
	var index: int = building_world._building_index(building_id)
	if index < 0: return false
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[index]
	if _accent_material_id(building_world._resolved_building(building)) == accent_id: return false
	var before: Dictionary = building_world._copy(building_world._document)
	building["accent_material_id"] = accent_id
	var material_overrides: Dictionary = building.get("material_overrides", {})
	material_overrides["accent"] = accent_id
	building["material_overrides"] = material_overrides
	buildings[index] = building
	return building_world._record_change(before)

func _accent_material_id(view: Dictionary) -> String:
	var explicit: String = str(view.get("accent_material_id", ""))
	if explicit.is_empty():
		explicit = str((view.get("material_overrides", {}) as Dictionary).get("accent", ""))
	if explicit in ACCENT_MATERIALS: return explicit
	var seed: int = int(view.get("seed", 0))
	return ACCENT_MATERIALS[posmod(seed * 7 + 3, ACCENT_MATERIALS.size())]

func _update_presentation() -> void:
	super._update_presentation()
	_apply_all_house_accents()

func _apply_all_house_accents() -> void:
	if not building_world: return
	for building_id_value in cottage_visuals.keys():
		var building_id := str(building_id_value)
		var view: Dictionary = building_world.get_building(building_id)
		var visual: Node = cottage_visuals.get(building_id) as Node
		if view.is_empty() or not is_instance_valid(visual): continue
		var accent_id: String = _accent_material_id(view)
		if _surface_material_picker_open and _surface_material_picker_kind == "accent" and building_id == selected_building_id:
			accent_id = _surface_material_picker_preview
		_apply_accent_to_visual(visual, view, accent_id)
	if building_placement_active and building_placement_ghost and building_placement_ghost.visible:
		if building_placement_operation == "new" and not _building_placement_preview_view.is_empty():
			_apply_accent_to_visual(building_placement_ghost, _building_placement_preview_view, building_placement_accent_material_id)
		elif not building_placement_source_id.is_empty():
			var source: Dictionary = building_world.get_building(building_placement_source_id)
			if not source.is_empty():
				_apply_accent_to_visual(building_placement_ghost, source, _accent_material_id(source))

func _apply_accent_to_visual(visual: Node, view: Dictionary, accent_id: String) -> void:
	if not ACCENT_COLOURS.has(accent_id): return
	var colour: Color = ACCENT_COLOURS[accent_id]
	var door_ids: Dictionary = {}
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("kind", "")) == "door":
			door_ids[str(detail.get("id", ""))] = true
	_recolour_accessory_nodes(visual, door_ids, colour)

func _recolour_accessory_nodes(node: Node, door_ids: Dictionary, colour: Color) -> void:
	for child in node.get_children():
		var child_name := str(child.name)
		var accessory: bool = child_name == "GableVent" or child_name.begins_with("Joinery_") or child_name.begins_with("Shutters_") or child_name.begins_with("ManualShutter_") or child_name.begins_with("FlowerBox_") or child_name.begins_with("DoorJoinery_") or child_name.begins_with("PorchBrackets_")
		if not accessory and child_name.begins_with("Detail_"):
			accessory = door_ids.has(child_name.trim_prefix("Detail_"))
		if accessory and child is GeometryInstance3D:
			var geometry := child as GeometryInstance3D
			var material: Material = geometry.material_override
			if material is StandardMaterial3D and (material as StandardMaterial3D).albedo_color != colour:
				(material as StandardMaterial3D).albedo_color = colour
		_recolour_accessory_nodes(child, door_ids, colour)
