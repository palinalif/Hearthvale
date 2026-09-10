extends "res://scripts/m2_scene_editing_ux.gd"

## Reopen an existing upper-floor portion with the same preview controls used
## to place it. Replace its record in place; never add a second overlapping part.
var _edit_floors_button: Button
var _floor_edit_picker: PanelContainer
var _floor_edit_buttons: Array[Button] = []
var _floor_edit_candidates: Array[Dictionary] = []
var _floor_edit_picker_open := false
var _editing_portion_id := ""
var _editing_portion_building_id := ""
var _floor_edit_move_accumulator := Vector3.ZERO
var _floor_edit_highlight: MeshInstance3D

func _ready() -> void:
	super._ready()
	_install_floor_editor()

func _install_floor_editor() -> void:
	var home_box := _catalogue_box(_building_panel)
	_edit_floors_button = Button.new()
	_edit_floors_button.name = "EditFloorsAction"
	_edit_floors_button.text = "Edit floors"
	_edit_floors_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_edit_floors_button.focus_mode = Control.FOCUS_ALL
	_edit_floors_button.custom_minimum_size.y = 42
	_edit_floors_button.pressed.connect(_open_floor_edit_picker)
	_edit_floors_button.focus_entered.connect(_queue_home_option_reveal)
	home_box.add_child(_edit_floors_button)
	home_box.move_child(_edit_floors_button, _house_shape_button.get_index() + 1)
	_building_buttons.insert(_building_buttons.find(_house_shape_button) + 1, _edit_floors_button)
	_floor_edit_picker = _make_catalogue_panel("FloorEditPicker", Vector2(360, 260))
	var box := _catalogue_box(_floor_edit_picker)
	var title := Label.new()
	title.text = "EDIT FLOORS"
	box.add_child(title)
	for index in HouseMassing.MAX_SECTIONS:
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size.y = 42
		button.visible = false
		button.focus_entered.connect(_preview_floor_selection.bind(index))
		button.pressed.connect(_choose_floor_to_edit.bind(index))
		box.add_child(button)
		_floor_edit_buttons.append(button)
	_bound_home_option_panel(_floor_edit_picker, _floor_edit_buttons, "FloorEditScroll")
	_refresh_floor_edit_action()

func _refresh_floor_edit_action() -> void:
	if not _edit_floors_button or not building_world: return
	var view: Dictionary = building_world.get_building(selected_building_id)
	_edit_floors_button.disabled = view.is_empty() or HouseMassing.floor_count(view) <= 1

func _open_floor_edit_picker() -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	_floor_edit_candidates.clear()
	for section in HouseMassing.sections_for(view):
		if HouseMassing.section_level(section) > 0: _floor_edit_candidates.append(section)
	if _floor_edit_candidates.is_empty(): return
	_floor_edit_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return HouseMassing.section_level(a) < HouseMassing.section_level(b))
	var counts: Dictionary = {}
	for section in _floor_edit_candidates:
		var level := HouseMassing.section_level(section)
		counts[level] = int(counts.get(level, 0)) + 1
	var ordinals: Dictionary = {}
	for index in _floor_edit_buttons.size():
		var button := _floor_edit_buttons[index]
		button.visible = index < _floor_edit_candidates.size()
		button.disabled = not button.visible
		if not button.visible: continue
		var level := HouseMassing.section_level(_floor_edit_candidates[index])
		ordinals[level] = int(ordinals.get(level, 0)) + 1
		button.text = "Floor %d" % (level + 1)
		if int(counts[level]) > 1: button.text += " · Part %d" % int(ordinals[level])
	_floor_edit_picker_open = true
	tools_open = true
	_building_panel.visible = false
	_floor_edit_picker.visible = true
	_floor_edit_buttons[0].grab_focus()
	_layout_home_options()
	_refresh_controller_hud()

func _preview_floor_selection(index: int) -> void:
	if not _floor_edit_picker_open or index >= _floor_edit_candidates.size(): return
	_clear_floor_edit_highlight()
	var visual := cottage_visuals.get(selected_building_id) as Node3D
	if not visual: return
	var section: Dictionary = _floor_edit_candidates[index]
	var size: Vector3 = section["size"]
	_floor_edit_highlight = MeshInstance3D.new()
	_floor_edit_highlight.name = "FloorEditHighlight"
	var mesh := BoxMesh.new()
	mesh.size = size + Vector3.ONE * 0.06
	_floor_edit_highlight.mesh = mesh
	_floor_edit_highlight.position = (section["offset"] as Vector3) + Vector3(0, size.y * 0.5, 0)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 0.75, 0.25, 0.18)
	_floor_edit_highlight.material_override = material
	_floor_edit_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(_floor_edit_highlight)

func _clear_floor_edit_highlight() -> void:
	if is_instance_valid(_floor_edit_highlight):
		_floor_edit_highlight.get_parent().remove_child(_floor_edit_highlight)
		_floor_edit_highlight.queue_free()
	_floor_edit_highlight = null

func _choose_floor_to_edit(index: int) -> void:
	if index < _floor_edit_candidates.size():
		_begin_existing_portion_edit(str(_floor_edit_candidates[index]["id"]))

func _close_floor_edit_picker(return_to_home: bool) -> void:
	_floor_edit_picker_open = false
	if _floor_edit_picker: _floor_edit_picker.visible = false
	_clear_floor_edit_highlight()
	tools_open = return_to_home
	if _building_panel: _building_panel.visible = return_to_home
	if return_to_home: _edit_floors_button.grab_focus()
	else: get_viewport().gui_release_focus()
	_refresh_controller_hud()

func _begin_existing_portion_edit(section_id: String) -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	for section in HouseMassing.sections_for(view):
		if str(section["id"]) != section_id or HouseMassing.section_level(section) == 0: continue
		_close_floor_edit_picker(false)
		_close_house_shape_picker(false)
		_editing_portion_id = section_id
		_editing_portion_building_id = selected_building_id
		portion_level = HouseMassing.section_level(section)
		portion_offset = section["offset"]
		portion_size = section["size"]
		_floor_edit_move_accumulator = portion_offset
		portion_revision = building_world.get_revision()
		portion_placement_active = true
		_update_portion_preview()
		return

func _replacement_sections(view: Dictionary) -> Array[Dictionary]:
	var sections: Array[Dictionary] = HouseMassing.sections_for(view)
	for index in sections.size():
		if str(sections[index]["id"]) == _editing_portion_id:
			sections[index] = _candidate_portion(_editing_portion_id)
			return sections
	return []

func _update_portion_preview() -> void:
	if _editing_portion_id.is_empty():
		super._update_portion_preview()
		return
	var view: Dictionary = building_world.get_building(selected_building_id)
	portion_reason = ""
	if view.is_empty() or selected_building_id != _editing_portion_building_id or building_world.get_revision() != portion_revision:
		portion_reason = "House changed; cancel and reopen"
	else:
		var sections := _replacement_sections(view)
		if sections.is_empty(): portion_reason = "This portion no longer exists"
		elif not portion_size.is_finite() or not portion_offset.is_finite() or minf(portion_size.x, portion_size.z) < HouseMassing.MIN_PORTION_SIZE or maxf(portion_size.x, portion_size.z) > HouseMassing.MAX_PORTION_SIZE:
			portion_reason = "Outside portion size limits"
		else:
			# Check the edited floor AND any floors it supports before committing.
			for section in sections:
				var level := HouseMassing.section_level(section)
				if level > 0 and not HouseMassing._is_supported_by_level(sections, HouseMassing.section_rect(section), level - 1):
					portion_reason = "Floor %d needs support below" % (level + 1)
					break
			if portion_reason.is_empty(): portion_reason = _portion_world_reason(view, sections)
	portion_valid = portion_reason.is_empty()
	_presentation_key = ""
	_refresh_massing_shells()
	_refresh_controller_hud()

func _preview_massing_view(view: Dictionary) -> Dictionary:
	if _editing_portion_id.is_empty(): return super._preview_massing_view(view)
	if not portion_placement_active or str(view.get("id", "")) != _editing_portion_building_id: return view
	var sections := _replacement_sections(view)
	if sections.is_empty(): return view
	var preview := view.duplicate(true)
	preview["massing_sections"] = _serialize_sections(sections)
	preview["massing_preset"] = "custom"
	return preview

func _commit_portion_placement() -> bool:
	if _editing_portion_id.is_empty(): return super._commit_portion_placement()
	if not portion_placement_active: return false
	_update_portion_preview()
	if not portion_valid:
		_set_status(portion_reason)
		return false
	var index: int = building_world._building_index(_editing_portion_building_id)
	if index < 0: return false
	var before: Dictionary = building_world.get_document()
	var old_next_id: int = building_world._next_id
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[index]
	var sections := _replacement_sections(building_world.get_building(_editing_portion_building_id))
	var serialized := _serialize_sections(sections)
	if serialized == building.get("massing_sections", []):
		_cancel_portion_placement()
		return false
	building["massing_sections"] = serialized
	building["massing_preset"] = "custom"
	if not _sync_surface_record(building):
		building_world._document = before
		building_world._next_id = old_next_id
		portion_valid = false
		portion_reason = "Too many editable wall runs"
		_refresh_controller_hud()
		return false
	building_world._refresh_buckets(building)
	buildings[index] = building
	var ok: bool = building_world._record_change(before)
	if not ok: building_world._next_id = old_next_id
	_clear_portion_placement()
	if ok: _record_history("building")
	_presentation_key = ""
	_update_presentation()
	_set_status("Floor updated" if ok else "Floor unchanged")
	return ok

func _clear_portion_placement() -> void:
	super._clear_portion_placement()
	_editing_portion_id = ""
	_editing_portion_building_id = ""
	_floor_edit_move_accumulator = Vector3.ZERO

func _input(event: InputEvent) -> void:
	if _shutting_down: return
	if _blocked_until_accept_release:
		super._input(event)
		return
	if _floor_edit_picker_open and not menu_open:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_close_floor_edit_picker(true)
		elif event.is_action_pressed("m1_pause"):
			_close_floor_edit_picker(false)
			super._input(event)
		elif event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner() as Button
			if focus in _floor_edit_buttons and not focus.disabled: focus.pressed.emit()
		elif event.is_action_pressed("m1_height_up") or event.is_action_pressed("ui_up"): _move_focus(_floor_edit_buttons, -1)
		elif event.is_action_pressed("m1_height_down") or event.is_action_pressed("ui_down"): _move_focus(_floor_edit_buttons, 1)
		get_viewport().set_input_as_handled()
		return
	super._input(event)

func _read_camera_and_cursor(delta: float) -> void:
	if _editing_portion_id.is_empty() or not portion_placement_active:
		super._read_camera_and_cursor(delta)
		return
	var view: Dictionary = building_world.get_building(selected_building_id)
	var transform_value: Transform3D = view.get("transform", Transform3D.IDENTITY)
	var move := Vector2(Input.get_axis("m1_move_left", "m1_move_right"), Input.get_axis("m1_move_up", "m1_move_down"))
	if move.length() > 0.05:
		var forward := Vector3(sin(camera_yaw), 0, cos(camera_yaw))
		var right := Vector3(forward.z, 0, -forward.x)
		_floor_edit_move_accumulator += transform_value.basis.inverse() * ((right * move.x + forward * move.y) * delta * (2.2 if precision_mode else 4.5))
		var snap := HouseMassing.CELL if precision_mode else HouseMassing.CELL * 2.0
		portion_offset.x = snappedf(_floor_edit_move_accumulator.x, snap)
		portion_offset.z = snappedf(_floor_edit_move_accumulator.z, snap)
		_update_portion_preview()
	camera_yaw += Input.get_axis("m1_orbit_left", "m1_orbit_right") * delta * 2.2
	camera_pitch = clampf(camera_pitch + Input.get_axis("m1_orbit_up", "m1_orbit_down") * delta * 1.5, 0.10, 1.35)
	camera_distance = clampf(camera_distance - Input.get_axis("m1_zoom_out", "m1_zoom_in") * delta * 18.0, 5.0, 52.0)

func _cancel_current_edit(reason: String) -> void:
	if _floor_edit_picker_open: _close_floor_edit_picker(false)
	super._cancel_current_edit(reason)

func _set_view_context(next_context: String, reason: String = "Context changed") -> bool:
	if next_context != "building" and _floor_edit_picker_open: _close_floor_edit_picker(false)
	return super._set_view_context(next_context, reason)

func _update_presentation() -> void:
	super._update_presentation()
	_refresh_floor_edit_action()

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if _floor_edit_picker_open:
		_building_panel.visible = false
		_tool_card.visible = false
		_set_prompts([["UP/DOWN", "Floor"], ["A", "Edit"], ["B", "Back"]])
	elif not _editing_portion_id.is_empty() and portion_placement_active:
		_tool_card.visible = not menu_open
		_tool_name.text = "Edit floor %d" % (portion_level + 1)
		_tool_meta.visible = true
		_tool_meta.text = "%.1f × %.1f" % [portion_size.x, portion_size.z] if portion_valid else portion_reason
		_set_prompts([["LS", "Move"], ["◀▶", "Width"], ["▲▼", "Depth"], ["A", "Apply"], ["B", "Cancel"], ["RS", "Orbit"]])
