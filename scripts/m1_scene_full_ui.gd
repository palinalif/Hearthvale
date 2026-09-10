extends "res://scripts/m1_scene_tool_ui.gd"
## Remaining controller-first M1 surfaces: cottage shell actions and pause/settings.

var _building_panel: PanelContainer
var _building_buttons: Array[Button] = []
var _modern_pause: PanelContainer
var _pause_stack: VBoxContainer
var _settings_open := false
var _show_context_hints := true

func _ready() -> void:
	super._ready()
	_build_building_panel()
	_build_modern_pause()
	if pause_panel: pause_panel.visible = false

func _input(event: InputEvent) -> void:
	if _shutting_down: return
	if menu_open and _modern_pause and _modern_pause.visible:
		_handle_modern_pause_input(event)
		return
	if view_context == "building" and not menu_open and not tools_open and not detail_open and not detail_move_active and not resize_active and not building_placement_active:
		if event.is_action_pressed("m1_tools") and hovered_detail_id.is_empty() and _shell_hovered:
			_open_building_panel()
			get_viewport().set_input_as_handled(); return
	if tools_open and view_context == "building" and _building_panel and _building_panel.visible:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_close_building_panel(); get_viewport().set_input_as_handled(); return
		if event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner(); if focus is Button: (focus as Button).pressed.emit()
			get_viewport().set_input_as_handled(); return
		if event.is_action_pressed("m1_height_down"):
			_move_focus(_building_buttons, 1); get_viewport().set_input_as_handled(); return
		if event.is_action_pressed("m1_height_up"):
			_move_focus(_building_buttons, -1); get_viewport().set_input_as_handled(); return
	super._input(event)

func _build_building_panel() -> void:
	_building_panel = PanelContainer.new(); _building_panel.name = "CottageShellActions"; _building_panel.position = Vector2(28, 212); _building_panel.custom_minimum_size = Vector2(330, 278); _building_panel.visible = false; hud.add_child(_building_panel)
	var margin := MarginContainer.new(); margin.add_theme_constant_override("margin_left", 18); margin.add_theme_constant_override("margin_right", 18); margin.add_theme_constant_override("margin_top", 16); margin.add_theme_constant_override("margin_bottom", 16); _building_panel.add_child(margin)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 6); margin.add_child(box)
	var title := Label.new(); title.text = "COTTAGE"; title.add_theme_font_size_override("font_size", 16); box.add_child(title)
	_add_building_button(box, "Duplicate", _begin_building_placement)
	_add_building_button(box, "Add window", _begin_new_attachment.bind("window"))
	_add_building_button(box, "Add door", _begin_new_attachment.bind("door"))
	_add_building_button(box, "Add flower box", _begin_new_attachment.bind("flower_box"))
	_add_building_button(box, "Add shutter", _begin_new_attachment.bind("shutter"))
	_add_building_button(box, "Material: warm plaster", _cycle_cottage_material)
	_add_building_button(box, "Close", _close_building_panel)

func _add_building_button(parent: VBoxContainer, label: String, callback: Callable) -> void:
	var button := Button.new(); button.text = label; button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.focus_mode = Control.FOCUS_ALL; button.custom_minimum_size = Vector2(0, 42); button.pressed.connect(callback); parent.add_child(button); _building_buttons.append(button)

func _open_building_panel() -> void:
	_cancel_current_edit("Cottage options opened")
	tools_open = true; detail_open = false
	if tools_panel: tools_panel.visible = false
	if _terrain_panel: _terrain_panel.visible = false
	_building_panel.visible = true
	if not _building_buttons.is_empty(): _building_buttons[0].grab_focus()
	_set_status("Cottage options • D-pad navigate • A choose • B/X close")

func _close_building_panel() -> void:
	tools_open = false; _building_panel.visible = false; get_viewport().gui_release_focus(); _set_status("Cottage editing")

func _cycle_cottage_material() -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	var current := str(view.get("material_id", "warm_plaster"))
	var choices: Array[String] = ["warm_plaster", "chalk_white", "moss_stone", "rose_lime"]
	var next_material: String = choices[posmod(choices.find(current) + 1, choices.size())]
	if building_world.set_material(selected_building_id, next_material): _record_history("building")
	_set_status("Cottage material: %s" % next_material.replace("_", " ").capitalize())

func _build_modern_pause() -> void:
	_modern_pause = PanelContainer.new(); _modern_pause.name = "PauseAndSettings"; _modern_pause.position = Vector2(410, 90); _modern_pause.custom_minimum_size = Vector2(460, 540); _modern_pause.visible = false; hud.add_child(_modern_pause)
	var margin := MarginContainer.new(); margin.add_theme_constant_override("margin_left", 26); margin.add_theme_constant_override("margin_right", 26); margin.add_theme_constant_override("margin_top", 22); margin.add_theme_constant_override("margin_bottom", 22); _modern_pause.add_child(margin)
	_pause_stack = VBoxContainer.new(); _pause_stack.add_theme_constant_override("separation", 10); margin.add_child(_pause_stack)
	_rebuild_pause_stack()

func _rebuild_pause_stack() -> void:
	if not _pause_stack: return
	for child in _pause_stack.get_children(): child.queue_free()
	var title := Label.new(); title.text = "SETTINGS" if _settings_open else "PAUSED"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size", 28); _pause_stack.add_child(title)
	if _settings_open:
		_pause_button("Context hints: %s" % ("ON" if _show_context_hints else "OFF"), _toggle_context_hints)
		_pause_button("Debug overlay: %s" % ("ON" if debug_label and debug_label.visible else "OFF"), _toggle_debug_from_settings)
		_pause_button("Back", _close_settings)
	else:
		_pause_button("Resume", _set_menu.bind(false))
		_pause_button("Save", _save_all)
		_pause_button("Settings", _open_settings)
		_pause_button("Reload last save", _reload_all)
		_pause_button("Quit", _quit_cleanly)
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 12)
	controls.add_child(InputGlyph.control("D-PAD"))
	controls.add_child(InputGlyph.prompt("A", "Choose"))
	controls.add_child(InputGlyph.prompt("B", "Back"))
	_pause_stack.add_child(controls)
	await get_tree().process_frame
	var first: Button = _first_pause_button()
	if first: first.grab_focus()

func _pause_button(label: String, callback: Callable) -> void:
	var button := Button.new(); button.text = label; button.focus_mode = Control.FOCUS_ALL; button.custom_minimum_size = Vector2(0, 52); button.add_theme_font_size_override("font_size", 20); button.pressed.connect(callback); _pause_stack.add_child(button)

func _first_pause_button() -> Button:
	for child in _pause_stack.get_children():
		if child is Button: return child
	return null

func _set_menu(open: bool) -> void:
	super._set_menu(open)
	if _modern_pause:
		_modern_pause.visible = open
		if open:
			_settings_open = false; _rebuild_pause_stack()
	if pause_panel: pause_panel.visible = false

func _handle_modern_pause_input(event: InputEvent) -> void:
	if event.is_action_pressed("m1_cancel"):
		if _settings_open: _close_settings()
		else: _set_menu(false)
		get_viewport().set_input_as_handled(); return
	if event.is_action_pressed("m1_accept"):
		var focus := get_viewport().gui_get_focus_owner(); if focus is Button: (focus as Button).pressed.emit()
		get_viewport().set_input_as_handled(); return
	var buttons: Array = []
	for child in _pause_stack.get_children():
		if child is Button: buttons.append(child)
	if event.is_action_pressed("m1_height_down"): _move_focus(buttons, 1); get_viewport().set_input_as_handled(); return
	if event.is_action_pressed("m1_height_up"): _move_focus(buttons, -1); get_viewport().set_input_as_handled(); return

func _open_settings() -> void:
	_settings_open = true; _rebuild_pause_stack()
func _close_settings() -> void:
	_settings_open = false; _rebuild_pause_stack()
func _toggle_context_hints() -> void:
	_show_context_hints = not _show_context_hints; _prompt_bar.visible = _show_context_hints and not menu_open; _rebuild_pause_stack()
func _toggle_debug_from_settings() -> void:
	if debug_label: debug_label.visible = not debug_label.visible
	_rebuild_pause_stack()

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if not _prompt_bar or not _tool_name: return
	_prompt_bar.visible = _show_context_hints and not menu_open
	if _building_panel: _building_panel.visible = tools_open and view_context == "building" and not _context_actions_open and not menu_open
	if menu_open or tools_open or detail_open: return
	var prompts: Array = []
	if building_placement_active:
		_tool_name.text = "Place home" if building_placement_operation == "duplicate" else "Move / rotate home"
		_tool_meta.text = "%s%s%s" % [building_placement_reason, " • SNAP" if building_rotation_snap else " • FREE", " • PRECISION" if precision_mode else ""]
		prompts = [["A", "Place"], ["B", "Cancel"], ["LS", "Move"], ["◀▶", "Rotate"], ["▲", "Snap"], ["L3", "Precision"]]
	elif detail_move_active and not placement_kind.is_empty():
		_tool_name.text = "Place %s" % placement_kind.replace("_", " ").capitalize()
		_tool_meta.text = "Wall locked • soft alignment"
		prompts = [["A", "Place"], ["B", "Cancel"], ["LS", "Move"], ["◀▶", "Wall"], ["RS", "Orbit"]]
	else:
		return
	if not _history_tags.is_empty(): prompts.append(["LB", "Undo"])
	if not _redo_tags.is_empty(): prompts.append(["RB", "Redo"])
	_set_prompts(prompts)
