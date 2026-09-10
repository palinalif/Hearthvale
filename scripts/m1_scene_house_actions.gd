extends "res://scripts/m1_scene_resize_handles.gd"
## House operations are temporary actions inside Building, not extra world modes.
## Detail A/X stays direct; bare-shell A offers Move or the existing resize handles.
var _house_actions_open := false
var _house_actions_panel: PanelContainer
var _house_action_buttons: Array[Button] = []
var _resize_selecting := false
var _moving_house := false
var _house_move_revision := -1
var _house_move_raw := Vector3.ZERO
var _moving_visual: Node3D

func _ready() -> void:
	super._ready()
	_house_actions_panel = PanelContainer.new()
	_house_actions_panel.name = "HouseMoveResize"
	_house_actions_panel.position = Vector2(38, 212)
	_house_actions_panel.custom_minimum_size = Vector2(300, 0)
	_house_actions_panel.visible = false
	hud.add_child(_house_actions_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_house_actions_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	title.text = "HOUSE"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	for label in ["Move house", "Resize house"]:
		var button := Button.new()
		button.text = label
		button.custom_minimum_size = Vector2(0, 48)
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_choose_house_action.bind(label))
		box.add_child(button)
		_house_action_buttons.append(button)
	_update_resize_handles()

func _input(event: InputEvent) -> void:
	if _shutting_down: return
	if _blocked_until_accept_release:
		super._input(event)
		return
	if _house_actions_open and not menu_open:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_close_house_actions()
		elif event.is_action_pressed("m1_pause"):
			_set_menu(true)
		elif event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner()
			if focus in _house_action_buttons: (focus as Button).pressed.emit()
		elif event.is_action_pressed("m1_height_up") or event.is_action_pressed("ui_up"):
			_move_focus(_house_action_buttons, -1)
		elif event.is_action_pressed("m1_height_down") or event.is_action_pressed("ui_down"):
			_move_focus(_house_action_buttons, 1)
		get_viewport().set_input_as_handled()
		return
	if _idle_building():
		if _resize_selecting and event.is_action_pressed("m1_cancel"):
			_resize_selecting = false
			_handle_hover = ""
			_set_status("Resize finished; point at the house or a detail")
			_update_detail_hover()
			_update_resize_handles()
			_refresh_controller_hud()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_accept"):
			_update_detail_hover()
			if _resize_selecting:
				if not _handle_hover.is_empty(): _begin_handle_resize(_handle_hover)
			elif hovered_detail_id.is_empty() and _pointer_over_selected_shell():
				_open_house_actions()
			else:
				# A still moves the actual detail. Empty ground has no house action.
				if not hovered_detail_id.is_empty(): super._input(event)
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _open_house_actions() -> void:
	if not _idle_building() or not _house_actions_panel: return
	_resize_selecting = false
	_house_actions_open = true
	_building_actions_open = false
	_context_actions_open = false
	tools_open = true
	_clear_hover()
	_handle_hover = ""
	_house_actions_panel.visible = true
	_house_action_buttons[0].grab_focus()
	_set_status("Move this house or resize it; A choose / B back")
	_update_resize_handles()
	_refresh_controller_hud()

func _close_house_actions() -> void:
	if not _house_actions_open: return
	_house_actions_open = false
	tools_open = false
	if _house_actions_panel: _house_actions_panel.visible = false
	get_viewport().gui_release_focus()
	_update_detail_hover()
	_update_resize_handles()
	_refresh_controller_hud()

func _choose_house_action(label: String) -> void:
	if not _house_actions_open: return
	_close_house_actions()
	if label == "Move house": _begin_house_move()
	elif label == "Resize house": _enter_resize_selection()

func _enter_resize_selection() -> void:
	if not _idle_building(): return
	_resize_selecting = true
	_clear_hover()
	_set_status("Point at a side, corner or height handle; A grab / B finish resizing")
	_update_detail_hover()
	_update_resize_handles()
	_refresh_controller_hud()

func _begin_handle_resize(handle_id: String) -> void:
	if _resize_selecting: super._begin_handle_resize(handle_id)

func _handle_candidates() -> Array[Dictionary]:
	if not _resize_selecting: return []
	return super._handle_candidates()

func _update_detail_hover() -> void:
	super._update_detail_hover()
	if _resize_selecting: _clear_hover()

func _update_resize_handles() -> void:
	super._update_resize_handles()
	if not _resize_overlay or not _resize_hint: return
	if _resize_selecting: return
	_resize_overlay.visible = false
	_resize_hint.visible = false
	if _idle_building() and hovered_detail_id.is_empty() and _pointer_over_selected_shell():
		_resize_hint.text = "A  Move / Resize house"
		var viewport_size := get_viewport().get_visible_rect().size
		_resize_hint.position = Vector2(clampf(edit_pointer.x + 18, 18, viewport_size.x - 290), clampf(edit_pointer.y - 32, 24, viewport_size.y - 110))
		_resize_hint.visible = true

func _begin_house_move() -> void:
	if not _idle_building(): return
	var source: Dictionary = building_world.get_building(selected_building_id)
	if source.is_empty(): return
	_resize_selecting = false
	_house_move_revision = building_world.get_revision()
	# Reuse the accepted free-placement camera/input/ghost, but not duplication.
	super._begin_building_placement()
	if not building_placement_active: return
	_moving_house = true
	building_placement_operation = "move"
	building_placement_target = building_placement_origin
	building_placement_transform = source["transform"]
	_house_move_raw = building_placement_target
	cursor = building_placement_target
	cottage_cursor = cursor
	_update_building_preview_transform()
	_colour_view(source, building_placement_ghost)
	building_placement_ghost._apply_translucency(building_placement_ghost)
	_moving_visual = cottage_visuals.get(selected_building_id)
	if is_instance_valid(_moving_visual): _moving_visual.visible = false
	_clear_hover()
	_set_status("Move / rotate house; D-pad left/right rotate • A place / B restore")
	_update_resize_handles()
	_refresh_controller_hud()

func _read_camera_and_cursor(delta: float) -> void:
	if _moving_house:
		if building_world.get_revision() != _house_move_revision or selected_building_id != building_placement_source_id:
			_cancel_building_placement()
			_set_status("House changed; move cancelled instead of overwriting newer edits")
			return
		# Accumulate BEFORE snapping so slow stick motion cannot get stuck.
		building_placement_target = _house_move_raw
	super._read_camera_and_cursor(delta)
	if _moving_house:
		_house_move_raw = building_placement_target
		for axis in [0, 2]:
			building_placement_target[axis] = building_placement_origin[axis] + snappedf(_house_move_raw[axis] - building_placement_origin[axis], 0.125)
		cursor = building_placement_target
		cottage_cursor = cursor
		_update_building_preview_transform()

func _clamp_building_placement() -> void:
	super._clamp_building_placement()

func _commit_building_placement() -> bool:
	if not _moving_house: return super._commit_building_placement()
	var id := building_placement_source_id
	_update_building_placement_validity()
	if not building_placement_valid:
		_set_status("Cannot move home: %s" % building_placement_reason)
		return false
	var target := building_placement_transform
	_moving_house = false
	_clear_building_placement()
	selected_building_id = id
	var ok: bool = building_world.move_building_transform(id, target, _house_move_revision)
	if ok: _record_history("building")
	_finish_house_move()
	_set_status("House moved" if ok else "No house move committed")
	return ok

func _cancel_building_placement() -> void:
	var was_move := _moving_house
	_moving_house = false
	super._cancel_building_placement()
	if was_move:
		_finish_house_move()
		_set_status("House move cancelled; original position restored")

func _finish_house_move() -> void:
	if is_instance_valid(_moving_visual): _moving_visual.visible = true
	_moving_visual = null
	_house_move_revision = -1
	selected_detail_id = ""
	selected_surface_id = ""
	_presentation_key = ""
	_colour_render_key = ""
	_update_presentation()
	_restore_placement_camera()
	_reset_edit_pointer()
	_refresh_controller_hud()

func _update_presentation() -> void:
	super._update_presentation()
	if _moving_house and is_instance_valid(_moving_visual): _moving_visual.visible = false

func _cancel_current_edit(reason: String) -> void:
	_close_house_actions()
	_resize_selecting = false
	super._cancel_current_edit(reason)
	_update_resize_handles()

func _set_view_context(next_context: String, reason: String = "Context changed") -> bool:
	var changed := super._set_view_context(next_context, reason)
	if changed and view_context == "building": _set_status("A on the house: move or resize; A on a detail: move detail")
	return changed

func _cycle_building(direction: int) -> void:
	_resize_selecting = false
	super._cycle_building(direction)

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if _house_actions_panel: _house_actions_panel.visible = _house_actions_open and not menu_open
	if not _tool_name or not _prompt_row or menu_open or view_context != "building": return
	if _house_actions_open:
		if _building_panel: _building_panel.visible = false
		_tool_name.text = "House"
		_tool_meta.text = "Choose what to change"
		_set_prompts([["A", "Choose"], ["B", "Back"], ["D-PAD", "Navigate"], ["RS", "Orbit"]])
	elif _moving_house:
		_tool_name.text = "Move / rotate house"
		_tool_meta.text = "%s%s" % [building_placement_reason, " • PRECISION" if precision_mode else ""]
		_set_prompts([["A", "Place"], ["B", "Restore"], ["LS", "Move"], ["◀▶", "Rotate"], ["▲", "Snap"], ["L3", "Precision"]])
	elif _idle_building():
		if _resize_selecting:
			_set_prompts([["A", "Grab handle"], ["B", "Finish resizing"], ["LS", "Point"], ["RS", "Orbit"], ["LT/RT", "Zoom"]] if not _handle_hover.is_empty() else [["B", "Finish resizing"], ["LS", "Point at handles"], ["RS", "Orbit"], ["LT/RT", "Zoom"]])
		elif hovered_detail_id.is_empty():
			var prompts: Array = [["X", "Cottage options"], ["B", "Finish editing"], ["LS", "Point"], ["RS", "Orbit"]]
			if _pointer_over_selected_shell(): prompts.push_front(["A", "Move / Resize"])
			_set_prompts(prompts)
