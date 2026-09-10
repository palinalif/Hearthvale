extends "res://scripts/m2_scene_auto_upper_windows.gd"

## Thor playtest follow-up: house accents are defaults, not a paint-over of
## individual choices. Keep previews disposable and retain the existing saves.
var _style_hidden_labels: Dictionary = {}

func _ready() -> void:
	super._ready()
	_install_inherited_colour_choice()
	for panel in [_surface_material_picker_panel, _roof_design_picker, _house_shape_picker]:
		_hide_picker_subtitle(panel)

func _install_inherited_colour_choice() -> void:
	# Preserve the legacy "natural" sentinel as inheritance. Provide a separate
	# explicit wood choice so both intentions are reachable without a migration.
	var inherited := _style_buttons.get("colour-natural") as Button
	if inherited: inherited.text = "House colour"
	var box := _actions_box()
	if not box or _style_buttons.has("colour-wood"): return
	var button := Button.new()
	button.name = "colour-wood"
	button.text = "Natural wood"
	button.icon = _colour_swatch(DETAIL_COLOURS["natural"])
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(0, 42)
	button.visible = false
	button.focus_entered.connect(_preview_style_choice.bind("colour", "wood"))
	button.pressed.connect(_commit_style_choice.bind("colour", "wood"))
	box.add_child(button)
	_style_buttons["colour-wood"] = button
	_style_button_specs["colour-wood"] = {"mode": "colour", "kind": "any", "value": "wood"}

func _visible_accent_id(view: Dictionary) -> String:
	if str(view.get("id", "")) == selected_building_id and _surface_material_picker_open and _surface_material_picker_kind == "accent":
		return _surface_material_picker_preview
	return _accent_material_id(view)

func _detail_colour_id(view: Dictionary, detail: Dictionary) -> String:
	if str(view.get("id", "")) == selected_building_id and not _style_picker_mode.is_empty() and str(detail.get("id", "")) == _style_picker_detail_id:
		return _style_preview_colour
	return str((detail.get("override", {}) as Dictionary).get("color_id", "natural"))

func _apply_accent_to_visual(visual: Node, view: Dictionary, accent_id: String) -> void:
	if not ACCENT_COLOURS.has(accent_id): return
	var accent: Color = ACCENT_COLOURS[accent_id]
	var colours: Dictionary = {"GableVent": accent}
	# Resolve once, then paint each piece once. The old broad accent pass must
	# not repaint explicit choices on every frame, including unselected homes.
	for value in view.get("details", []):
		var detail: Dictionary = value
		var colour_id := _detail_colour_id(view, detail)
		var colour: Color = accent if colour_id == "natural" else DETAIL_COLOURS.get(colour_id, DETAIL_COLOURS["natural"])
		var id := str(detail.get("id", ""))
		for prefix in ["Joinery_", "Shutters_", "ManualShutter_", "FlowerBox_", "DoorJoinery_", "PorchBrackets_"]:
			colours[prefix + id] = colour
		if str(detail.get("kind", "")) == "door": colours["Detail_" + id] = colour
	_apply_decor_colour_map(visual, colours)

func _apply_decor_colour_map(node: Node, colours: Dictionary) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D and colours.has(str(child.name)):
			var geometry := child as GeometryInstance3D
			var material := geometry.material_override as StandardMaterial3D
			if material:
				var colour := Color(colours[str(child.name)] as Color, material.albedo_color.a)
				if not material.albedo_color.is_equal_approx(colour):
					# Preserve roughness, ghost transparency and all other flags.
					var replacement := material.duplicate() as StandardMaterial3D
					replacement.albedo_color = colour
					geometry.material_override = replacement
		_apply_decor_colour_map(child, colours)

func _custom_window_colour(view: Dictionary, detail: Dictionary) -> Color:
	var colour_id := _detail_colour_id(view, detail)
	if colour_id != "natural": return DETAIL_COLOURS.get(colour_id, DETAIL_COLOURS["natural"])
	return ACCENT_COLOURS.get(_visible_accent_id(view), Color("#557a70"))

func _apply_style_preview() -> void:
	super._apply_style_preview()
	_apply_all_house_accents()

func _apply_surface_material_preview() -> void:
	super._apply_surface_material_preview()
	# Window overlays cache their input view. Accent browsing intentionally
	# does not edit that view, so invalidate these small presentation caches.
	_window_overlay_signatures.clear()
	_window_adventure_signatures.clear()
	_refresh_custom_window_overlays()
	_refresh_window_customization()

func _hide_picker_subtitle(panel: PanelContainer) -> void:
	if not panel: return
	var box := _catalogue_box(panel)
	var first := true
	for child in box.get_children():
		if child is Label:
			if first: first = false
			else: child.visible = false

func _open_surface_material_picker(kind: String) -> void:
	super._open_surface_material_picker(kind)
	if not _surface_material_picker_open: return
	var box := _catalogue_box(_surface_material_picker_panel)
	if box.get_child(0) is Label:
		(box.get_child(0) as Label).text = "DECOR COLOUR" if kind == "accent" else kind.to_upper() + " COLOUR"
	_hide_picker_subtitle(_surface_material_picker_panel)

func _begin_style_picker(mode: String) -> void:
	super._begin_style_picker(mode)
	if _style_picker_mode.is_empty(): return
	for child in _actions_box().get_children():
		if (child is Label or child is RichTextLabel) and child != _style_category_label:
			_style_hidden_labels[child] = child.visible
			child.visible = false
	if mode == "colour":
		var inherited := _style_buttons.get("colour-natural") as Button
		if inherited: inherited.icon = _colour_swatch(ACCENT_COLOURS[_visible_accent_id(building_world.get_building(selected_building_id))])
		tools_panel.size.y = minf(400.0, get_viewport().get_visible_rect().size.y - 96.0)
	_refresh_controller_hud()

func _end_style_picker() -> void:
	super._end_style_picker()
	for label in _style_hidden_labels:
		if is_instance_valid(label): label.visible = bool(_style_hidden_labels[label])
	_style_hidden_labels.clear()

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if not _style_picker_mode.is_empty() or _surface_material_picker_open:
		if _tool_card: _tool_card.visible = false
		_set_prompts([["UP/DOWN", "Browse"], ["A", "Apply"], ["B", "Cancel"], ["RS", "Orbit"]])
