extends "res://scripts/m2_scene_auto_upper_windows.gd"

## Personal detail colours win over the house accent. Inherited colour remains
## a presentation default; previews never write a house colour into a detail.
const DECOR_COLOUR_PREFIXES := ["Joinery_", "Shutters_", "ManualShutter_", "FlowerBox_", "DoorJoinery_", "PorchBrackets_"]
var _decor_colour_signatures: Dictionary = {}

func _effective_decor_accent_id(view: Dictionary) -> String:
	if str(view.get("id", "")) == selected_building_id and _surface_material_picker_open and _surface_material_picker_kind == "accent":
		return _surface_material_picker_preview
	return _accent_material_id(view)

func _resolved_decor_colour(view: Dictionary, detail: Dictionary, inherited: Color) -> Color:
	var target := str(view.get("id", "")) == selected_building_id and str(detail.get("id", "")) == _style_picker_detail_id
	if target and _style_picker_mode == "colour":
		return DETAIL_COLOURS.get(_style_preview_colour, inherited)
	# The inherited variation preview synthesizes a natural-wood colour even
	# when the saved detail has no colour override. Keep inheritance intact.
	var source: Dictionary = _selected_detail_record() if target and _style_picker_mode == "variation" else detail
	var colour_id := str((source.get("override", {}) as Dictionary).get("color_id", ""))
	return DETAIL_COLOURS.get(colour_id, inherited)

func _apply_accent_to_visual(visual: Node, view: Dictionary, accent_id: String) -> void:
	if not ACCENT_COLOURS.has(accent_id): return
	var inherited: Color = ACCENT_COLOURS[accent_id]
	var colours: Dictionary = {}
	var door_ids: Dictionary = {}
	for value in view.get("details", []):
		var detail: Dictionary = value
		var id := str(detail.get("id", ""))
		colours[id] = _resolved_decor_colour(view, detail, inherited)
		if str(detail.get("kind", "")) == "door": door_ids[id] = true
	# Custom-window caches otherwise see only the saved house accent, so an
	# accent preview/cancel would leave their generated joinery stale.
	var signature := str(inherited) + "|" + str(colours)
	var key := visual.get_instance_id()
	if str(_decor_colour_signatures.get(key, "")) != signature:
		_decor_colour_signatures[key] = signature
		_window_overlay_signatures.erase(key)
		_window_adventure_signatures.erase(key)
	_apply_decor_node_colours(visual, colours, door_ids, inherited)

func _apply_decor_node_colours(node: Node, colours: Dictionary, door_ids: Dictionary, inherited: Color) -> void:
	for child in node.get_children():
		var child_name := str(child.name)
		var accessory := child_name == "GableVent"
		var colour := inherited
		for prefix in DECOR_COLOUR_PREFIXES:
			if child_name.begins_with(prefix):
				accessory = true
				colour = colours.get(child_name.trim_prefix(prefix), inherited)
				break
		if child_name.begins_with("Detail_"):
			var id := child_name.trim_prefix("Detail_")
			if door_ids.has(id):
				accessory = true
				colour = colours.get(id, inherited)
		if accessory and child is GeometryInstance3D:
			var geometry := child as GeometryInstance3D
			var material := geometry.material_override as StandardMaterial3D
			if material and not material.albedo_color.is_equal_approx(colour):
				# Never tint a resource shared by an unrelated detail or duplicate.
				var private_material := material.duplicate() as StandardMaterial3D
				private_material.albedo_color = colour
				geometry.material_override = private_material
		_apply_decor_node_colours(child, colours, door_ids, inherited)

func _custom_window_colour(view: Dictionary, detail: Dictionary) -> Color:
	var inherited: Color = ACCENT_COLOURS.get(_effective_decor_accent_id(view), Color("#557a70"))
	return _resolved_decor_colour(view, detail, inherited)

func _apply_style_preview() -> void:
	super._apply_style_preview()
	_apply_all_house_accents()

func _apply_surface_material_preview() -> void:
	super._apply_surface_material_preview()
	_refresh_custom_window_overlays()
	_refresh_window_customization()

func _commit_detail_style(detail_id: String, asset_id: String, colour_id: String) -> bool:
	# The original writer treats missing colour as natural, making an explicit
	# Natural wood choice a no-op on accent-coloured homes. Save that choice in
	# one transaction. Variation-only edits retain the original writer/path.
	if colour_id != "natural" or _style_picker_mode == "variation":
		return super._commit_detail_style(detail_id, asset_id, colour_id)
	var index: int = building_world._building_index(selected_building_id)
	if index < 0: return false
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[index]
	var detail_index: int = building_world._detail_index(building, detail_id)
	if detail_index < 0: return false
	var details: Array = building["details"]
	var detail: Dictionary = details[detail_index]
	var overrides: Dictionary = detail.get("override", {})
	if overrides.has("color_id"):
		return super._commit_detail_style(detail_id, asset_id, colour_id)
	if str(detail.get("state", "")) == "suppressed": return false
	var before: Dictionary = building_world.get_document()
	if not asset_id.is_empty(): detail["asset_id"] = asset_id
	overrides["color_id"] = "natural"
	overrides["asset_id"] = str(detail.get("asset_id", ""))
	detail["override"] = overrides
	if bool(detail.get("generated", false)) and str(detail.get("state", "")) == "automatic":
		detail["state"] = "modified_locked"
	details[detail_index] = detail
	building["details"] = details
	building_world._refresh_buckets(building)
	buildings[index] = building
	return building_world._record_change(before)
