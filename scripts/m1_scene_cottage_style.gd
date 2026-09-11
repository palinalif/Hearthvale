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
const DETAIL_VARIATIONS := [
	["variant-window-classic", "Cottage casement", "window", "window_wood"],
	["variant-window-round", "Round window", "window", "window_round"],
	["variant-window-diamond", "Cottage diamond", "window", "window_cottage_diamond"],
	["variant-window-lodge", "Lodge lattice", "window", "window_lodge"],
	["variant-window-lodge-cross", "Lodge cross-braced", "window", "window_lodge_cross"],
	["variant-window-tudor", "Tudor leaded", "window", "window_tudor"],
	["variant-window-tudor-tall", "Tudor tall diamond", "window", "window_tudor_tall"],
	["variant-door-cottage", "Cottage plank", "door", "door_timber"],
	["variant-door-stable", "Cottage stable", "door", "door_cottage_stable"],
	["variant-door-lodge", "Lodge braced", "door", "door_lodge"],
	["variant-door-lodge-split", "Lodge split plank", "door", "door_lodge_split"],
	["variant-door-tudor", "Tudor panelled", "door", "door_tudor"],
	["variant-door-tudor-arch", "Tudor arched panel", "door", "door_tudor_arch"],
	["variant-shutter-mixed", "Hand-built mix", "shutter", "shutter_wood"],
	["variant-shutter-boarded", "Boarded shutters", "shutter", "shutter_boarded"],
	["variant-shutter-louvered", "Louvered shutters", "shutter", "shutter_louvered"],
	["variant-shutter-braced", "Diagonal-braced shutters", "shutter", "shutter_braced"],
	["variant-flower-box-mixed", "Garden mix", "flower_box", "flower_box_wood"],
	["variant-flower-box-timber", "Timber trough", "flower_box", "flower_box_timber"],
	["variant-flower-box-bracketed", "Bracketed planter", "flower_box", "flower_box_bracketed"],
	["variant-flower-box-woven", "Woven planter", "flower_box", "flower_box_woven"],
]

var _style_picker_mode := ""
var _style_picker_detail_id := ""
var _style_picker_original_asset := ""
var _style_picker_original_colour := "natural"
var _style_preview_asset := ""
var _style_preview_colour := "natural"
var _style_preview_signature := ""
var _style_buttons: Dictionary = {}
var _style_button_specs: Dictionary = {}
var _detail_colour_button: Button
var _style_category_label: Label
var _style_picker_original_panel_position := Vector2.ZERO
var _style_picker_original_panel_size := Vector2.ZERO

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
	_style_category_label = Label.new()
	_style_category_label.name = "DetailStyleCategory"
	_style_category_label.add_theme_font_size_override("font_size", 18)
	_style_category_label.visible = false
	box.add_child(_style_category_label)
	var specs: Array = DETAIL_VARIATIONS.duplicate(true)
	for colour_id in DETAIL_COLOURS:
		specs.append(["colour-" + str(colour_id), DETAIL_COLOUR_LABELS[colour_id], "any", str(colour_id)])
	for spec in specs:
		var button := Button.new()
		button.name = str(spec[0])
		button.text = str(spec[1])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size = Vector2(0, 42)
		button.visible = false
		var mode := "colour" if str(spec[0]).begins_with("colour-") else "variation"
		button.focus_entered.connect(_preview_style_choice.bind(mode, str(spec[3])))
		button.pressed.connect(_commit_style_choice.bind(mode, str(spec[3])))
		if mode == "colour": button.icon = _colour_swatch(DETAIL_COLOURS[str(spec[3])])
		box.add_child(button)
		_style_buttons[str(spec[0])] = button
		_style_button_specs[str(spec[0])] = {"mode": mode, "kind": str(spec[2]), "value": str(spec[3])}

func _colour_swatch(colour: Color) -> Texture2D:
	var image := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	return ImageTexture.create_from_image(image)

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
		# Every placeable building detail shares the categorized variations and
		# colour browsers.
		if _tool_buttons.has("Replace selected"):
			var variation := _tool_buttons["Replace selected"] as Button
			variation.visible = hovered_detail_kind in ["window", "door", "shutter", "flower_box"]
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
	_style_preview_signature = ""
	if tools_panel:
		_style_picker_original_panel_position = tools_panel.position
		_style_picker_original_panel_size = tools_panel.size
	_context_actions_open = false
	tools_open = true
	detail_open = false
	if tools_panel:
		tools_panel.visible = true
		tools_panel.size = Vector2(380, minf(440, get_viewport().get_visible_rect().size.y - 48.0))
	_show_style_picker_buttons()
	var candidates := _style_candidates(mode)
	if not candidates.is_empty():
		(candidates[0] as Button).grab_focus()
	call_deferred("_dock_style_picker_away_from_target")
	_set_status(("Choose variation" if mode == "variation" else "Choose colour") + " • browse to preview • A apply / B cancel • right stick orbit")

func _style_candidates(mode: String) -> Array:
	var result: Array = []
	var kind := str(_selected_detail_record().get("kind", ""))
	for key in _style_buttons.keys():
		var button := _style_buttons[key] as Button
		var spec: Dictionary = _style_button_specs[key]
		if str(spec["mode"]) == mode and (mode == "colour" or str(spec["kind"]) == kind): result.append(button)
	return result

func _show_style_picker_buttons() -> void:
	for key in _tool_buttons.keys():
		var button := _tool_buttons[key] as Button
		button.visible = false
		button.disabled = true
	for key in _style_buttons.keys():
		var button := _style_buttons[key] as Button
		var show := button in _style_candidates(_style_picker_mode)
		button.visible = show
		button.disabled = not show
	if _style_category_label:
		_style_category_label.visible = not _style_picker_mode.is_empty()
		if _style_picker_mode == "colour": _style_category_label.text = "COLOUR"
		else: _style_category_label.text = "%s STYLES" % str(_selected_detail_record().get("kind", "DETAIL")).to_upper()

func _preview_style_choice(mode: String, value: String) -> void:
	if _style_picker_mode != mode:
		return
	if mode == "variation":
		_style_preview_asset = value
	else:
		_style_preview_colour = value
	# Route the changed preview through the complete presentation stack once so
	# roof/facade finishers are applied before the preview is considered stable.
	_update_presentation()

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
	_set_style_detail_highlight(false)
	_style_picker_mode = ""
	_style_picker_detail_id = ""
	_style_picker_original_asset = ""
	_style_preview_asset = ""
	_style_preview_signature = ""
	tools_open = false
	detail_open = false
	if tools_panel:
		tools_panel.visible = false
		tools_panel.position = _style_picker_original_panel_position
		tools_panel.size = _style_picker_original_panel_size
	if _style_category_label: _style_category_label.visible = false
	for button_value in _style_buttons.values():
		(button_value as Button).visible = false
	_update_action_buttons()

func _update_camera() -> void:
	super._update_camera()
	if not _style_picker_mode.is_empty(): _dock_style_picker_away_from_target()

func _dock_style_picker_away_from_target() -> void:
	if _style_picker_mode.is_empty() or not tools_panel or not camera: return
	var detail := _selected_detail_record()
	var local = detail.get("resolved_position", null)
	var view: Dictionary = building_world.get_building(selected_building_id)
	var transform_value = view.get("transform", Transform3D.IDENTITY)
	if not local is Vector3 or not transform_value is Transform3D: return
	var world: Vector3 = (transform_value as Transform3D) * (local as Vector3)
	if camera.is_position_behind(world): return
	var target := camera.unproject_position(world)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_size := tools_panel.size
	var margin := 24.0
	var x: float = viewport_size.x - panel_size.x - margin if target.x < viewport_size.x * 0.5 else margin
	var y := clampf(target.y - panel_size.y * 0.5, margin, maxf(margin, viewport_size.y - panel_size.y - margin))
	tools_panel.position = Vector2(x, y)

func _set_style_detail_highlight(enabled: bool) -> void:
	if _style_picker_detail_id.is_empty(): return
	for visual in _selected_visual_roots():
		if visual.has_method("set_detail_highlight"): visual.set_detail_highlight(_style_picker_detail_id, enabled)

func _highlighted_detail_geometry_count() -> int:
	var count := 0
	for visual in _selected_visual_roots():
		for child in visual.get_children():
			if child is GeometryInstance3D and (child as GeometryInstance3D).material_overlay != null: count += 1
	return count

func _apply_style_preview() -> void:
	if _style_picker_detail_id.is_empty():
		return
	var revision: int = building_world.get_revision()
	var signature := "%s|%s|%s|%s|%d" % [selected_building_id, _style_picker_detail_id, _style_preview_asset, _style_preview_colour, revision]
	if signature == _style_preview_signature:
		return
	var presentation: Dictionary = building_world.get_building(selected_building_id)
	if presentation.is_empty():
		return
	_style_preview_signature = signature
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
	for visual in _selected_visual_roots():
		if visual and visual.has_method("request_revision"):
			visual.request_revision(revision)
		if visual and visual.has_method("apply_building"):
			visual.apply_building(presentation, revision)
	_apply_detail_colours(_style_picker_detail_id, _style_preview_colour)
	_set_style_detail_highlight(true)

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
	var target_kind := ""
	if building_world and not selected_building_id.is_empty():
		for detail in building_world.get_building(selected_building_id).get("details", []):
			if str(detail.get("id", "")) == detail_id:
				target_kind = str(detail.get("kind", ""))
				break
	for root in _selected_visual_roots():
		for prefix in ["Joinery_", "Shutters_", "FlowerBox_", "ManualShutter_"]:
			var node := root.get_node_or_null(prefix + detail_id)
			if node is GeometryInstance3D:
				var material := StandardMaterial3D.new()
				material.albedo_color = colour
				(node as GeometryInstance3D).material_override = material
		if target_kind == "door":
			for prefix in ["Detail_", "DoorJoinery_"]:
				var door_node := root.get_node_or_null(prefix + detail_id)
				if door_node is GeometryInstance3D:
					var door_material := StandardMaterial3D.new()
					door_material.albedo_color = colour
					(door_node as GeometryInstance3D).material_override = door_material