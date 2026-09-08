extends "res://scripts/m1_scene_cottage_ux.gd"
## Contextual style browsing for direct cottage editing. Variation and colour
## preview without mutating BuildingWorld; A commits one history entry, B
## restores the authored presentation without adding undo noise.

const DETAIL_COLOURS := {
	"natural": Color("#634d42"),
	"sage": Color("#557a70"),
	"blue": Color("#4f6f82"),
	"berry": Color("#8b5660"),
	"cream": Color("#d7c6a2"),
}
const DETAIL_COLOUR_LABELS := {
	"natural": "Natural wood",
	"sage": "Sage",
	"blue": "Weathered blue",
	"berry": "Berry",
	"cream": "Cream",
}

var _style_picker_mode := ""
var _style_picker_detail_id := ""
var _style_picker_original_asset := ""
var _style_picker_original_colour := "natural"
var _style_preview_asset := ""
var _style_preview_colour := "natural"
var _style_buttons: Dictionary = {}
var _detail_colour_button: Button

func _ready() -> void:
	super._ready()
	_install_style_actions()

func _install_style_actions() -> void:
	var box := _actions_box()
	if not box:
		return
	_detail_colour_button = Button.new()
	_detail_colour_button.name = "DetailColourAction"
	_detail_colour_button.text = "Colour"
	_detail_colour_button.focus_mode = Control.FOCUS_ALL
	_detail_colour_button.custom_minimum_size = Vector2(0, 42)
	_detail_colour_button.pressed.connect(_begin_style_picker.bind("colour"))
	box.add_child(_detail_colour_button)
	_tool_buttons["Detail colour"] = _detail_colour_button
	for spec in [
		["variant-classic", "Classic", "variation", "window_wood"],
		["variant-round", "Round", "variation", "window_round"],
		["colour-natural", "Natural wood", "colour", "natural"],
		["colour-sage", "Sage", "colour", "sage"],
		["colour-blue", "Weathered blue", "colour", "blue"],
		["colour-berry", "Berry", "colour", "berry"],
		["colour-cream", "Cream", "colour", "cream"],
	]:
		var button := Button.new()
		button.name = str(spec[0])
		button.text = str(spec[1])
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size = Vector2(0, 42)
		button.visible = false
		button.focus_entered.connect(_preview_style_choice.bind(str(spec[2]), str(spec[3])))
		button.pressed.connect(_commit_style_choice.bind(str(spec[2]), str(spec[3])))
		box.add_child(button)
		_style_buttons[str(spec[0])] = button

func _actions_box() -> VBoxContainer:
	if not tools_panel:
		return null
	var stack: Array[Node] = [tools_panel]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is VBoxContainer:
			return node as VBoxContainer
		for child in node.get_children():
			stack.append(child)
	return null

func _update_action_buttons() -> void:
	super._update_action_buttons()
	if _style_picker_mode != "":
		_show_style_picker_buttons()
		return
	if _detail_colour_button:
		_detail_colour_button.visible = _context_actions_open
		_detail_colour_button.disabled = not _context_actions_open
	if _context_actions_open:
		# Colour applies to windows, shutters and flower boxes. Variation is
		# currently meaningful only for windows because those are the authored
		# variants available in M1.
		if _tool_buttons.has("Replace selected"):
			var variation := _tool_buttons["Replace selected"] as Button
			variation.visible = hovered_detail_kind == "window"
			variation.disabled = not variation.visible

func _tool_choice(choice: String) -> void:
	if _context_actions_open and choice == "Replace selected":
		_begin_style_picker("variation")
		return
	super._tool_choice(choice)

func _begin_style_picker(mode: String) -> void:
	if mode not in ["variation", "colour"] or selected_detail_id.is_empty():
		return
	var detail := _selected_detail_record()
	if detail.is_empty():
		return
	_style_picker_mode = mode
	_style_picker_detail_id = selected_detail_id
	_style_picker_original_asset = str(detail.get("asset_id", "window_wood"))
	_style_picker_original_colour = str((detail.get("override", {}) as Dictionary).get("color_id", "natural"))
	_style_preview_asset = _style_picker_original_asset
	_style_preview_colour = _style_picker_original_colour
	_context_actions_open = false
	tools_open = true
	detail_open = false
	if tools_panel:
		tools_panel.visible = true
	_show_style_picker_buttons()
	var candidates := _style_candidates(mode)
	if not candidates.is_empty():
		(candidates[0] as Button).grab_focus()
	_set_status(("Choose variation" if mode == "variation" else "Choose colour") + " • browse to preview • A apply / B cancel • right stick orbit")

func _style_candidates(mode: String) -> Array:
	var result: Array = []
	for key in _style_buttons.keys():
		var button := _style_buttons[key] as Button
		if mode == "variation" and str(key).begins_with("variant-"):
			result.append(button)
		elif mode == "colour" and str(key).begins_with("colour-"):
			result.append(button)
	return result

func _show_style_picker_buttons() -> void:
	for key in _tool_buttons.keys():
		var button := _tool_buttons[key] as Button
		button.visible = false
		button.disabled = true
	for key in _style_buttons.keys():
		var button := _style_buttons[key] as Button
		var show := (_style_picker_mode == "variation" and str(key).begins_with("variant-")) or (_style_picker_mode == "colour" and str(key).begins_with("colour-"))
		button.visible = show
		button.disabled = not show

func _preview_style_choice(mode: String, value: String) -> void:
	if _style_picker_mode != mode:
		return
	if mode == "variation":
		_style_preview_asset = value
	else:
		_style_preview_colour = value
	_apply_style_preview()

func _commit_style_choice(mode: String, value: String) -> void:
	if _style_picker_mode != mode:
		return
	if mode == "variation":
		_style_preview_asset = value
	else:
		_style_preview_colour = value
	var ok := _commit_detail_style(_style_picker_detail_id, _style_preview_asset, _style_preview_colour)
	_end_style_picker()
	if ok:
		_record_history("building")
		_set_status("%s updated" % ("Variation" if mode == "variation" else "Colour"))
	else:
		_set_status("No style change")
	_update_presentation()

func _commit_detail_style(detail_id: String, asset_id: String, colour_id: String) -> bool:
	# BuildingWorld's detail records already store authored overrides. Keep this
	# as one atomic recipe mutation so browsing does not pollute undo history.
	var before: Dictionary = building_world.get_document()
	var building_index: int = building_world._building_index(selected_building_id)
	if building_index < 0:
		return false
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[building_index]
	var detail_index: int = building_world._detail_index(building, detail_id)
	if detail_index < 0:
		return false
	var details: Array = building["details"]
	var detail: Dictionary = details[detail_index]
	if str(detail.get("state", "")) == "suppressed":
		return false
	var changed := false
	if not asset_id.is_empty() and str(detail.get("asset_id", "")) != asset_id:
		detail["asset_id"] = asset_id
		changed = true
	var overrides: Dictionary = detail.get("override", {})
	if str(overrides.get("color_id", "natural")) != colour_id:
		overrides["color_id"] = colour_id
		changed = true
	if not changed:
		return false
	if bool(detail.get("generated", false)) and str(detail.get("state", "")) == "automatic":
		detail["state"] = "modified_locked"
	overrides["asset_id"] = asset_id
	detail["override"] = overrides
	details[detail_index] = detail
	building["details"] = details
	building_world._refresh_buckets(building)
	buildings[building_index] = building
	return building_world._record_change(before)

func _selected_detail_record() -> Dictionary:
	var view: Dictionary = building_world.get_building(selected_building_id)
	for value in view.get("details", []):
		var detail: Dictionary = value
		if str(detail.get("id", "")) == selected_detail_id:
			return detail
	return {}

func _handle_overlay_input(event: InputEvent) -> void:
	if _style_picker_mode != "":
		if event.is_action_pressed("m1_cancel"):
			_cancel_style_picker()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner()
			if focus is Button:
				(focus as Button).pressed.emit()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_height_down"):
			_move_focus(_style_candidates(_style_picker_mode), 1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_height_up"):
			_move_focus(_style_candidates(_style_picker_mode), -1)
			get_viewport().set_input_as_handled()
			return
	super._handle_overlay_input(event)

func _cancel_style_picker() -> void:
	if _style_picker_mode == "":
		return
	_style_preview_asset = _style_picker_original_asset
	_style_preview_colour = _style_picker_original_colour
	_end_style_picker()
	_update_presentation()
	_set_status("Style change cancelled")

func _end_style_picker() -> void:
	_style_picker_mode = ""
	_style_picker_detail_id = ""
	_style_picker_original_asset = ""
	_style_preview_asset = ""
	tools_open = false
	detail_open = false
	if tools_panel:
		tools_panel.visible = false
	for button_value in _style_buttons.values():
		(button_value as Button).visible = false
	_update_action_buttons()

func _apply_style_preview() -> void:
	if _style_picker_detail_id.is_empty():
		return
	var presentation: Dictionary = building_world.get_building(selected_building_id)
	if presentation.is_empty():
		return
	var details: Array = presentation.get("details", [])
	for index in details.size():
		var detail: Dictionary = details[index]
		if str(detail.get("id", "")) != _style_picker_detail_id:
			continue
		detail["asset_id"] = _style_preview_asset
		var overrides: Dictionary = detail.get("override", {})
		overrides["color_id"] = _style_preview_colour
		detail["override"] = overrides
		details[index] = detail
	presentation["details"] = details
	var revision: int = building_world.get_revision()
	for visual in _selected_visual_roots():
		if visual and visual.has_method("request_revision"):
			visual.request_revision(revision)
		if visual and visual.has_method("apply_building"):
			visual.apply_building(presentation, revision)
	_apply_detail_colours(_style_picker_detail_id, _style_preview_colour)

func _update_presentation() -> void:
	super._update_presentation()
	if _style_picker_mode != "":
		_apply_style_preview()
	else:
		_apply_persisted_detail_colours()

func _apply_persisted_detail_colours() -> void:
	if not building_world:
		return
	var view: Dictionary = building_world.get_building(selected_building_id)
	for value in view.get("details", []):
		var detail: Dictionary = value
		var colour_id := str((detail.get("override", {}) as Dictionary).get("color_id", "natural"))
		if colour_id != "natural":
			_apply_detail_colours(str(detail.get("id", "")), colour_id)

func _selected_visual_roots() -> Array[Node3D]:
	var roots: Array[Node3D] = []
	if cottage_visual and is_instance_valid(cottage_visual):
		roots.append(cottage_visual)
	var selected_visual = cottage_visuals.get(selected_building_id, null)
	if selected_visual is Node3D and is_instance_valid(selected_visual) and selected_visual != cottage_visual:
		roots.append(selected_visual)
	return roots

func _apply_detail_colours(detail_id: String, colour_id: String) -> void:
	if detail_id.is_empty():
		return
	var colour: Color = DETAIL_COLOURS.get(colour_id, DETAIL_COLOURS["natural"])
	for root in _selected_visual_roots():
		for prefix in ["Joinery_", "Shutters_", "FlowerBox_", "ManualShutter_"]:
			var node := root.get_node_or_null(prefix + detail_id)
			if node is GeometryInstance3D:
				var material := StandardMaterial3D.new()
				material.albedo_color = colour
				(node as GeometryInstance3D).material_override = material
