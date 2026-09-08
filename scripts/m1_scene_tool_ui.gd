extends "res://scripts/m1_scene_ui_overhaul.gd"
## Compact terrain tool/settings UI. Common tool changes stay on the D-pad;
## X opens settings instead of the legacy all-actions dump.

const TERRAIN_TOOLS: Array[String] = ["raise", "dig", "smooth", "level", "slope", "foliage", "tree"]
var _terrain_panel: PanelContainer
var _terrain_tool_column: VBoxContainer
var _terrain_settings_column: VBoxContainer
var _terrain_ui_buttons: Array[Button] = []

func _ready() -> void:
	super._ready()
	_build_terrain_panel()

func _input(event: InputEvent) -> void:
	if _shutting_down:
		return
	if view_context == "terrain" and not menu_open and not tools_open and not detail_open and not stroke_active and not landscape_active:
		if event.is_action_pressed("m1_cycle_left"):
			_cycle_terrain_tool(-1)
			get_viewport().set_input_as_handled(); return
		if event.is_action_pressed("m1_cycle_right"):
			_cycle_terrain_tool(1)
			get_viewport().set_input_as_handled(); return
		if event.is_action_pressed("m1_tools"):
			_open_terrain_settings()
			get_viewport().set_input_as_handled(); return
	if tools_open and view_context == "terrain" and _terrain_panel and _terrain_panel.visible:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_close_terrain_settings()
			get_viewport().set_input_as_handled(); return
		if event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner()
			if focus is Button: (focus as Button).pressed.emit()
			get_viewport().set_input_as_handled(); return
		if event.is_action_pressed("m1_height_down"):
			_move_focus(_terrain_ui_buttons, 1)
			get_viewport().set_input_as_handled(); return
		if event.is_action_pressed("m1_height_up"):
			_move_focus(_terrain_ui_buttons, -1)
			get_viewport().set_input_as_handled(); return
	super._input(event)

func _build_terrain_panel() -> void:
	_terrain_panel = PanelContainer.new()
	_terrain_panel.name = "TerrainToolSettings"
	_terrain_panel.position = Vector2(38, 212)
	_terrain_panel.custom_minimum_size = Vector2(520, 390)
	_terrain_panel.visible = false
	hud.add_child(_terrain_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_%s" % side, 18)
	margin.add_theme_constant_override("margin_top", 16); margin.add_theme_constant_override("margin_bottom", 16)
	_terrain_panel.add_child(margin)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 22); margin.add_child(row)
	_terrain_tool_column = VBoxContainer.new(); _terrain_tool_column.custom_minimum_size = Vector2(210, 0); _terrain_tool_column.add_theme_constant_override("separation", 5); row.add_child(_terrain_tool_column)
	_terrain_settings_column = VBoxContainer.new(); _terrain_settings_column.custom_minimum_size = Vector2(240, 0); _terrain_settings_column.add_theme_constant_override("separation", 5); row.add_child(_terrain_settings_column)
	var tool_title := Label.new(); tool_title.text = "TOOLS"; tool_title.add_theme_font_size_override("font_size", 14); _terrain_tool_column.add_child(tool_title)
	for tool in TERRAIN_TOOLS:
		_add_terrain_button(_terrain_tool_column, tool.capitalize(), _select_terrain_tool.bind(tool))
	_add_terrain_button(_terrain_tool_column, "Clear planting", _select_terrain_tool.bind("clear_planting"))
	var settings_title := Label.new(); settings_title.text = "SETTINGS"; settings_title.add_theme_font_size_override("font_size", 14); _terrain_settings_column.add_child(settings_title)
	_add_terrain_button(_terrain_settings_column, "Radius −", _change_radius.bind(-1))
	_add_terrain_button(_terrain_settings_column, "Radius +", _change_radius.bind(1))
	_add_terrain_button(_terrain_settings_column, "Strength −", _change_strength.bind(-1))
	_add_terrain_button(_terrain_settings_column, "Strength +", _change_strength.bind(1))
	_add_terrain_button(_terrain_settings_column, "Falloff −", _change_falloff.bind(-1))
	_add_terrain_button(_terrain_settings_column, "Falloff +", _change_falloff.bind(1))
	_add_terrain_button(_terrain_settings_column, "Reference: next", _cycle_reference_mode)
	_add_terrain_button(_terrain_settings_column, "Keep reference", _toggle_keep_reference)

func _add_terrain_button(parent: VBoxContainer, text: String, callback: Callable) -> void:
	var button := Button.new(); button.text = text; button.focus_mode = Control.FOCUS_ALL; button.custom_minimum_size = Vector2(0, 38); button.pressed.connect(callback); parent.add_child(button); _terrain_ui_buttons.append(button)

func _open_terrain_settings() -> void:
	_cancel_current_edit("Terrain settings opened")
	tools_open = true; detail_open = false
	if tools_panel: tools_panel.visible = false
	_terrain_panel.visible = true
	_refresh_terrain_panel()
	if not _terrain_ui_buttons.is_empty(): _terrain_ui_buttons[0].grab_focus()
	_set_status("Terrain tools & settings • D-pad navigate • A choose • B/X close")

func _close_terrain_settings() -> void:
	tools_open = false
	_terrain_panel.visible = false
	get_viewport().gui_release_focus()
	_set_status("%s • D-pad ←/→ tool • X settings" % sculpt_tool.capitalize())

func _refresh_terrain_panel() -> void:
	if not _terrain_panel: return
	_terrain_panel.visible = tools_open and view_context == "terrain" and not menu_open
	for button in _terrain_ui_buttons:
		var t := button.text
		if t.begins_with("Radius"): button.text = t.split("  ")[0] + "  %.2f" % brush_radius
		elif t.begins_with("Strength"): button.text = t.split("  ")[0] + "  %d/10" % brush_strength_level
		elif t.begins_with("Falloff"): button.text = t.split("  ")[0] + "  %.1f" % brush_falloff
		elif t.begins_with("Reference:"): button.text = "Reference: %s" % reference_mode.capitalize()
		elif t.begins_with("Keep reference"): button.text = "Keep reference: %s" % ("ON" if keep_reference else "OFF")

func _cycle_terrain_tool(direction: int) -> void:
	var current := TERRAIN_TOOLS.find(sculpt_tool)
	if current < 0: current = 0
	_select_terrain_tool(TERRAIN_TOOLS[posmod(current + direction, TERRAIN_TOOLS.size())])

func _select_terrain_tool(tool: String) -> void:
	if tool in ["foliage", "tree", "clear_planting"]:
		_cancel_current_edit("Planting tool selected")
		sculpt_tool = tool; reference_mode = "ground"; _preview_key = ""
	else:
		_set_sculpt_tool(tool)
	if _terrain_panel and _terrain_panel.visible: _refresh_terrain_panel()
	_set_status("%s • D-pad ←/→ tool • X settings" % sculpt_tool.replace("_", " ").capitalize())

func _change_radius(direction: int) -> void:
	var step := 0.25 if precision_mode else 1.0
	brush_radius = clampf(brush_radius + step * direction, 0.25, 8.0); _preview_key = ""; _refresh_terrain_panel()

func _change_strength(direction: int) -> void:
	set_brush_strength_level(brush_strength_level + direction); _refresh_terrain_panel()

func _change_falloff(direction: int) -> void:
	brush_falloff = clampf(brush_falloff + 0.1 * direction, 0.0, 1.0); _preview_key = ""; _refresh_terrain_panel()

func _cycle_reference_mode() -> void:
	var modes := ["ground", "wall", "ceiling"]
	reference_mode = modes[posmod(modes.find(reference_mode) + 1, modes.size())]; _preview_key = ""; _refresh_terrain_panel()

func _toggle_keep_reference() -> void:
	keep_reference = not keep_reference
	if not keep_reference: stroke_reference.clear()
	_refresh_terrain_panel()

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if _terrain_panel: _refresh_terrain_panel()
	if view_context == "terrain" and not tools_open and not menu_open:
		_set_prompts([["A", "Sculpt"], ["B", "Cancel"], ["◀▶", "Tool"], ["X", "Settings"], ["L3", "Precision"], ["▲", "Building"]])
