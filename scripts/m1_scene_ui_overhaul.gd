extends "res://scripts/m1_scene_cottage_resize_ux.gd"
## Controller-first presentation layer for M1. The game world stays visible;
## controls shown on screen describe only the action available right now.
const UISkin = preload("res://scripts/ui/m1_ui_skin.gd")
const UIGlyph = preload("res://scripts/ui/m1_ui_glyph.gd")
var _hud_theme: Theme
var _tool_icon: Control

var _mode_pill: PanelContainer
var _mode_label: Label
var _tool_card: PanelContainer
var _tool_name: Label
var _tool_meta: Label
var _prompt_bar: PanelContainer
var _prompt_row: HBoxContainer
var _toast_panel: PanelContainer
var _toast_label: Label
var _last_toast := ""

func _ready() -> void:
	super._ready()
	_build_controller_hud()
	_refresh_controller_hud()

func _process(delta: float) -> void:
	super._process(delta)
	_refresh_controller_hud()

func _setup_input_map() -> void:
	super._setup_input_map()
	# D-pad Up is the approved top-level Terrain <-> Building context switch.
	# Height editing moves to Y while actively resizing, so the same physical
	# control never means both "change mode" and "change height".
	_ensure_action("m1_mode_switch")
	_button("m1_mode_switch", JOY_BUTTON_DPAD_UP)
	_key("m1_mode_switch", KEY_TAB)
	_ensure_action("m1_resize_height_up")
	_button("m1_resize_height_up", JOY_BUTTON_Y)
	_key("m1_resize_height_up", KEY_E)

func _input(event: InputEvent) -> void:
	if _shutting_down:
		return
	if event.is_action_pressed("m1_mode_switch") and not menu_open and not tools_open and not detail_open and not detail_move_active and not resize_active and not building_placement_active:
		_set_view_context("terrain" if view_context == "building" else "building", "Mode switched")
		get_viewport().set_input_as_handled()
		return
	if resize_active and event.is_action_pressed("m1_resize_height_up"):
		var step := 0.25 if precision_mode else 1.0
		resize_accumulator.y = minf(resize_accumulator.y + step, BuildingWorldScript.MAX_DIMENSIONS.y)
		resize_preview_dimensions.y = snappedf(resize_accumulator.y, step)
		_set_status("Resize height %.1f • Y taller / D-pad down shorter • A apply / B cancel" % resize_preview_dimensions.y)
		get_viewport().set_input_as_handled()
		return
	super._input(event)

func _build_controller_hud() -> void:
	_hud_theme = UISkin.make_theme()
	# Hide the prototype's verbose diagnostic labels during ordinary play. They
	# remain alive for tests/debugging and can still be inspected with F1.
	if status_label: status_label.visible = false
	if context_label: context_label.visible = false
	if target_label: target_label.visible = false

	_mode_pill = PanelContainer.new()
	_mode_pill.name = "ModePill"
	_mode_pill.position = Vector2(28, 24)
	_mode_pill.custom_minimum_size = Vector2(210, 52)
	hud.add_child(_mode_pill)
	var mode_margin := MarginContainer.new()
	for side in ["left", "right"]: mode_margin.add_theme_constant_override("margin_%s" % side, 16)
	mode_margin.add_theme_constant_override("margin_top", 10)
	mode_margin.add_theme_constant_override("margin_bottom", 10)
	_mode_pill.add_child(mode_margin)
	_mode_label = Label.new()
	_mode_label.add_theme_font_size_override("font_size", 18)
	mode_margin.add_child(_mode_label)

	_tool_card = PanelContainer.new()
	_tool_card.name = "ActiveToolCard"
	_tool_card.position = Vector2(28, 92)
	_tool_card.custom_minimum_size = Vector2(250, 94)
	hud.add_child(_tool_card)
	var tool_margin := MarginContainer.new()
	for side in ["left", "right"]: tool_margin.add_theme_constant_override("margin_%s" % side, 16)
	tool_margin.add_theme_constant_override("margin_top", 12)
	tool_margin.add_theme_constant_override("margin_bottom", 12)
	_tool_card.add_child(tool_margin)
	var tool_box := VBoxContainer.new()
	tool_box.add_theme_constant_override("separation", 5)
	tool_margin.add_child(tool_box)
	var tool_heading := HBoxContainer.new()
	tool_heading.add_theme_constant_override("separation", 9)
	tool_box.add_child(tool_heading)
	_tool_icon = UIGlyph.new()
	tool_heading.add_child(_tool_icon)
	_tool_name = Label.new(); _tool_name.add_theme_font_size_override("font_size", 22); tool_heading.add_child(_tool_name)
	_tool_meta = Label.new(); _tool_meta.add_theme_font_size_override("font_size", 16); _tool_meta.add_theme_color_override("font_color", UISkin.MUTED); tool_box.add_child(_tool_meta)

	_toast_panel = PanelContainer.new()
	_toast_panel.name = "ContextToast"
	_toast_panel.position = Vector2(390, 24)
	_toast_panel.custom_minimum_size = Vector2(500, 46)
	hud.add_child(_toast_panel)
	var toast_margin := MarginContainer.new(); toast_margin.add_theme_constant_override("margin_left", 14); toast_margin.add_theme_constant_override("margin_right", 14); toast_margin.add_theme_constant_override("margin_top", 8); toast_margin.add_theme_constant_override("margin_bottom", 8); _toast_panel.add_child(toast_margin)
	_toast_label = Label.new(); _toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _toast_label.add_theme_font_size_override("font_size", 16); _toast_label.custom_minimum_size.x = 470; _toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; toast_margin.add_child(_toast_label)

	_prompt_bar = PanelContainer.new()
	_prompt_bar.name = "ContextPromptBar"
	_prompt_bar.position = Vector2(20, 654)
	_prompt_bar.custom_minimum_size = Vector2(1240, 54)
	hud.add_child(_prompt_bar)
	var prompt_margin := MarginContainer.new(); prompt_margin.add_theme_constant_override("margin_left", 16); prompt_margin.add_theme_constant_override("margin_right", 16); prompt_margin.add_theme_constant_override("margin_top", 12); prompt_margin.add_theme_constant_override("margin_bottom", 12); _prompt_bar.add_child(prompt_margin)
	_prompt_row = HBoxContainer.new(); _prompt_row.add_theme_constant_override("separation", 18); prompt_margin.add_child(_prompt_row)

func _refresh_controller_hud() -> void:
	if not _mode_label or not _tool_name or not _prompt_row:
		return
	# Later scene layers add their own contextual panels. Inherit the same skin
	# without changing their controls, callbacks, or focus ownership.
	for surface in hud.get_children():
		if surface is Control and surface.theme != _hud_theme:
			surface.theme = _hud_theme
	_tool_icon.symbol = sculpt_tool if view_context == "terrain" else "cottage"
	_mode_pill.visible = not menu_open
	_tool_card.visible = not menu_open
	_prompt_bar.visible = not menu_open
	_toast_panel.visible = not menu_open and not status_text.is_empty()
	_mode_label.text = "▲  %s" % ("TERRAIN" if view_context == "terrain" else "BUILDING")
	_mode_label.modulate = Color("#b7e6ae") if view_context == "terrain" else Color("#f2c982")
	if view_context == "terrain":
		_tool_name.text = sculpt_tool.capitalize()
		if sculpt_tool in ["foliage", "tree", "clear_planting"]:
			_tool_meta.text = "Planting • X tools"
		else:
			_tool_meta.text = "Radius %.2f   Strength %d/10%s" % [brush_radius, brush_strength_level, "   PRECISION" if precision_mode else ""]
	else:
		_tool_name.text = "Cottage"
		if detail_move_active: _tool_name.text = "Move %s" % selected_detail_id
		elif resize_active: _tool_name.text = "Resize cottage"
		elif not hovered_detail_kind.is_empty(): _tool_name.text = hovered_detail_kind.replace("_", " ").capitalize()
		_tool_meta.text = "Orbit with right stick • triggers zoom"
	_toast_label.text = status_text
	var prompts: Array = []
	if tools_open or detail_open:
		prompts = [["A", "Choose"], ["B", "Close"], ["D-PAD", "Navigate"], ["RS", "Orbit"] if view_context == "building" else ["", ""]]
	elif detail_move_active:
		prompts = [["A", "Place"], ["B", "Restore"], ["LS", "Move"], ["RS", "Orbit"], ["R3", "Reframe"]]
	elif resize_active:
		prompts = [["A", "Apply"], ["B", "Cancel"], ["LS", "Resize"], ["Y", "Taller"], ["▼", "Shorter"], ["◀▶", "Axis"]]
	elif view_context == "building":
		if not hovered_detail_id.is_empty(): prompts = [["A", "Move"], ["X", "Options"], ["RS", "Orbit"], ["RT/LT", "Zoom"], ["▲", "Terrain"]]
		elif _shell_hovered: prompts = [["A", "Resize"], ["X", "Options"], ["RS", "Orbit"], ["R3", "Reframe"], ["▲", "Terrain"]]
		else: prompts = [["LS", "Point"], ["RS", "Orbit"], ["RT/LT", "Zoom"], ["R3", "Reframe"], ["▲", "Terrain"]]
	else:
		prompts = [["A", "Sculpt"], ["B", "Cancel"], ["X", "Tools"], ["L3", "Precision"], ["▲", "Building"]]
	_set_prompts(prompts)

func _set_prompts(prompts: Array) -> void:
	var signature := JSON.stringify(prompts)
	if _prompt_row.get_meta("signature", "") == signature:
		return
	_prompt_row.set_meta("signature", signature)
	for child in _prompt_row.get_children():
		_prompt_row.remove_child(child)
		child.queue_free()
	for entry_value in prompts:
		var entry: Array = entry_value
		if entry.size() < 2 or str(entry[0]).is_empty(): continue
		var group := HBoxContainer.new(); group.add_theme_constant_override("separation", 7); _prompt_row.add_child(group)
		var key := Label.new(); key.text = str(entry[0]); UISkin.badge(key); group.add_child(key)
		var text := Label.new(); text.text = str(entry[1]); text.add_theme_font_size_override("font_size", 16); text.add_theme_color_override("font_color", UISkin.INK); group.add_child(text)
