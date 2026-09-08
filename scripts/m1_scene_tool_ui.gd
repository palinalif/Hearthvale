extends "res://scripts/m1_scene_ui_overhaul.gd"
## Tool list plus directly adjustable setting rows. Focus is retained between
## visits; held left/right repeats without reopening a menu for each increment.
const TERRAIN_TOOLS: Array[String] = ["raise", "dig", "smooth", "level", "slope", "foliage", "tree"]
var _terrain_panel: PanelContainer
var _terrain_tool_column: VBoxContainer
var _terrain_settings_column: VBoxContainer
var _terrain_ui_buttons: Array[Button] = []
var _terrain_setting_buttons: Dictionary = {}
var _last_terrain_setting := "radius"
var _setting_repeat_direction := 0
var _setting_repeat_timer := 0.0

func _ready() -> void:
	super._ready()
	_build_terrain_panel()

func _process(delta: float) -> void:
	super._process(delta)
	if _setting_repeat_direction == 0: return
	if not tools_open or menu_open or view_context != "terrain" or not _terrain_panel.visible:
		_setting_repeat_direction = 0
		return
	var action := "m1_cycle_right" if _setting_repeat_direction > 0 else "m1_cycle_left"
	if not Input.is_action_pressed(action):
		_setting_repeat_direction = 0
		return
	_setting_repeat_timer -= delta
	if _setting_repeat_timer <= 0.0:
		_adjust_focused_setting(_setting_repeat_direction)
		_setting_repeat_timer = 0.09

func _input(event: InputEvent) -> void:
	if _shutting_down: return
	if view_context == "terrain" and not menu_open and not tools_open and not detail_open and not stroke_active and not landscape_active:
		if event.is_action_pressed("m1_cycle_left") or event.is_action_pressed("m1_cycle_right"):
			_cycle_terrain_tool(1 if event.is_action_pressed("m1_cycle_right") else -1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_tools"):
			_open_terrain_settings()
			get_viewport().set_input_as_handled()
			return
	if tools_open and view_context == "terrain" and _terrain_panel and _terrain_panel.visible:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_close_terrain_settings()
		elif event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner() as Button
			if focus and not focus.disabled: focus.pressed.emit()
		elif event.is_action_pressed("m1_height_down"):
			_move_focus(_terrain_ui_buttons, 1)
		elif event.is_action_pressed("m1_height_up"):
			_move_focus(_terrain_ui_buttons, -1)
		elif event.is_action_pressed("m1_cycle_left") or event.is_action_pressed("m1_cycle_right"):
			_setting_repeat_direction = 1 if event.is_action_pressed("m1_cycle_right") else -1
			_adjust_focused_setting(_setting_repeat_direction)
			_setting_repeat_timer = 0.35
		elif event.is_action_released("m1_cycle_left") or event.is_action_released("m1_cycle_right"):
			_setting_repeat_direction = 0
		elif event.is_action_pressed("m1_pause"):
			_close_terrain_settings()
			_set_menu(true)
		get_viewport().set_input_as_handled()
		return
	super._input(event)

func _build_terrain_panel() -> void:
	_terrain_panel = PanelContainer.new()
	_terrain_panel.name = "TerrainToolSettings"
	_terrain_panel.position = Vector2(28, 212)
	_terrain_panel.custom_minimum_size = Vector2(560, 390)
	_terrain_panel.visible = false
	hud.add_child(_terrain_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_%s" % side, 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_terrain_panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	margin.add_child(row)
	_terrain_tool_column = VBoxContainer.new()
	_terrain_tool_column.custom_minimum_size = Vector2(190, 0)
	_terrain_tool_column.add_theme_constant_override("separation", 5)
	row.add_child(_terrain_tool_column)
	_terrain_settings_column = VBoxContainer.new()
	_terrain_settings_column.custom_minimum_size = Vector2(290, 0)
	_terrain_settings_column.add_theme_constant_override("separation", 5)
	row.add_child(_terrain_settings_column)
	var title := Label.new()
	title.text = "TOOLS"
	_terrain_tool_column.add_child(title)
	for tool in TERRAIN_TOOLS:
		var button := _add_terrain_button(_terrain_tool_column, tool.capitalize(), _select_terrain_tool.bind(tool))
		button.set_meta("terrain_tool", tool)
	var clear_button := _add_terrain_button(_terrain_tool_column, "Clear planting", _select_terrain_tool.bind("clear_planting"))
	clear_button.set_meta("terrain_tool", "clear_planting")
	var settings_title := Label.new()
	settings_title.text = "LEFT / RIGHT TO ADJUST"
	settings_title.add_theme_font_size_override("font_size", 15)
	_terrain_settings_column.add_child(settings_title)
	for key in ["radius", "strength", "falloff", "reference", "keep", "height_snap"]:
		var button := _add_terrain_button(_terrain_settings_column, str(key), _close_terrain_settings)
		button.set_meta("setting", key)
		button.focus_entered.connect(_remember_setting.bind(str(key)))
		_terrain_setting_buttons[str(key)] = button
	_refresh_terrain_panel()

func _add_terrain_button(parent: VBoxContainer, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(0, 38)
	button.pressed.connect(callback)
	parent.add_child(button)
	_terrain_ui_buttons.append(button)
	return button

func _remember_setting(key: String) -> void:
	_last_terrain_setting = key
	_setting_repeat_direction = 0

func _open_terrain_settings() -> void:
	_cancel_current_edit("Terrain settings opened")
	tools_open = true
	detail_open = false
	if tools_panel: tools_panel.visible = false
	_refresh_terrain_panel()
	var focus: Button = _terrain_setting_buttons.get(_last_terrain_setting)
	if not focus or focus.disabled: focus = _terrain_setting_buttons.get("radius")
	if focus: focus.grab_focus()
	_set_status("Up/down chooses a row • left/right adjusts • hold to repeat • A done / B back")

func _close_terrain_settings() -> void:
	_setting_repeat_direction = 0
	tools_open = false
	_terrain_panel.visible = false
	get_viewport().gui_release_focus()
	_set_status("%s • D-pad left/right tool • X settings" % sculpt_tool.capitalize())

func _refresh_terrain_panel() -> void:
	if not _terrain_panel: return
	_terrain_panel.visible = tools_open and view_context == "terrain" and not menu_open
	for button in _terrain_ui_buttons:
		if not button.has_meta("terrain_tool"): continue
		var active := str(button.get_meta("terrain_tool")) == sculpt_tool
		if button.has_meta("active_tool") and bool(button.get_meta("active_tool")) == active: continue
		button.set_meta("active_tool", active)
		if active:
			var selected := UISkin.panel(Color("#42583e"), UISkin.AMBER, 7)
			selected.border_width_left = 4
			selected.content_margin_left = 12
			selected.content_margin_right = 12
			selected.content_margin_top = 6
			selected.content_margin_bottom = 6
			button.add_theme_stylebox_override("normal", selected)
		else:
			button.remove_theme_stylebox_override("normal")
	var values := {"radius": "Radius   < %.2f >" % brush_radius, "strength": "Strength   < %d / 10 >" % brush_strength_level, "falloff": "Falloff   < %.1f >" % brush_falloff, "reference": "Reference   < %s >" % reference_mode.capitalize(), "keep": "Keep plane   < %s >" % ("On" if keep_reference else "Off"), "height_snap": "Height snap   < %s >" % ("On" if height_snap_enabled else "Off")}
	var planting := sculpt_tool in ["foliage", "tree", "clear_planting"]
	for key in _terrain_setting_buttons:
		var button: Button = _terrain_setting_buttons[key]
		button.text = str(values[key])
		button.disabled = planting and str(key) != "radius"

func _adjust_focused_setting(direction: int) -> void:
	var focus := get_viewport().gui_get_focus_owner() as Button
	if not focus or focus.disabled or not _terrain_settings_column.is_ancestor_of(focus): return
	match str(focus.get_meta("setting", "")):
		"radius": _change_radius(direction)
		"strength": _change_strength(direction)
		"falloff": _change_falloff(direction)
		"reference":
			var modes: Array[String] = ["ground", "wall", "ceiling"]
			reference_mode = modes[posmod(modes.find(reference_mode) + direction, modes.size())]
			_preview_key = ""
		"keep": keep_reference = direction > 0
		"height_snap": height_snap_enabled = direction > 0
	if not keep_reference: stroke_reference.clear()
	_refresh_terrain_panel()

func _cycle_terrain_tool(direction: int) -> void:
	var current := maxi(0, TERRAIN_TOOLS.find(sculpt_tool))
	_select_terrain_tool(TERRAIN_TOOLS[posmod(current + direction, TERRAIN_TOOLS.size())])

func _select_terrain_tool(tool: String) -> void:
	var was_open := tools_open
	if tool in ["foliage", "tree", "clear_planting"]:
		_cancel_current_edit("Planting tool selected")
		sculpt_tool = tool
		reference_mode = "ground"
		_preview_key = ""
	else:
		_set_sculpt_tool(tool)
	if was_open: _close_terrain_settings()
	_set_status("%s • D-pad left/right tool • X settings" % sculpt_tool.replace("_", " ").capitalize())

func _change_radius(direction: int) -> void:
	var step := 0.25 if precision_mode else 1.0
	brush_radius = clampf(brush_radius + step * direction, 0.25, 8.0)
	_preview_key = ""
	_refresh_terrain_panel()

func _change_strength(direction: int) -> void:
	set_brush_strength_level(brush_strength_level + direction)
	_refresh_terrain_panel()

func _change_falloff(direction: int) -> void:
	brush_falloff = clampf(brush_falloff + 0.1 * direction, 0.0, 1.0)
	_preview_key = ""
	_refresh_terrain_panel()

func _cycle_reference_mode() -> void:
	var modes: Array[String] = ["ground", "wall", "ceiling"]
	reference_mode = modes[posmod(modes.find(reference_mode) + 1, modes.size())]
	_preview_key = ""
	_refresh_terrain_panel()

func _toggle_keep_reference() -> void:
	keep_reference = not keep_reference
	if not keep_reference: stroke_reference.clear()
	_refresh_terrain_panel()

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if _terrain_panel: _refresh_terrain_panel()
	if view_context == "terrain" and not menu_open:
		if tools_open and _terrain_panel and _terrain_panel.visible:
			_set_prompts([["A", "Done / choose tool"], ["B", "Back"], ["UP/DOWN", "Row"], ["LEFT/RIGHT", "Adjust (hold repeats)"]])
		elif not tools_open:
			_set_prompts([["A", "Sculpt"], ["B", "Cancel"], ["LEFT/RIGHT", "Tool"], ["X", "Settings"], ["L3", "Precision"], ["UP", "Building"]])
