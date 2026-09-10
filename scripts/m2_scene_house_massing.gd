extends "res://scripts/m2_scene_window_customization.gd"

## Townscaper-inspired structural editing. Players author simple rectangular
## masses; local adjacency determines the joined shell. This stays above the
## existing house/detail systems so old saves remain plain single-section homes.
const HouseMassing = preload("res://scripts/m2_house_massing.gd")
const HouseMassingVisual = preload("res://scripts/m2_house_massing_visual.gd")

var _house_shape_button: Button
var _house_shape_picker: PanelContainer
var _house_shape_buttons: Array[Button] = []
var _house_shape_remove_button: Button
var _house_shape_picker_open := false

var portion_placement_active := false
var portion_offset := Vector3.ZERO
var portion_size := Vector3.ZERO
var portion_revision := -1
var portion_valid := false
var portion_reason := ""

func _ready() -> void:
	super._ready()
	_install_house_shape_action()
	_build_house_shape_picker()
	_refresh_massing_shells()

func _install_house_shape_action() -> void:
	if not _building_panel: return
	var margin := _building_panel.get_child(0) as MarginContainer
	var box := margin.get_child(0) as VBoxContainer
	_house_shape_button = Button.new()
	_house_shape_button.name = "HouseShapeAction"
	_house_shape_button.text = "House shape"
	_house_shape_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_house_shape_button.focus_mode = Control.FOCUS_ALL
	_house_shape_button.custom_minimum_size = Vector2(0, 29)
	_house_shape_button.pressed.connect(_open_house_shape_picker)
	box.add_child(_house_shape_button)
	var duplicate_button: Button = null
	for button in _building_buttons:
		if button.text.begins_with("Duplicate"):
			duplicate_button = button
			break
	if duplicate_button:
		box.move_child(_house_shape_button, duplicate_button.get_index() + 1)
		var index := _building_buttons.find(duplicate_button)
		_building_buttons.insert(index + 1, _house_shape_button)
	else:
		_building_buttons.append(_house_shape_button)
	for button in _building_buttons: button.custom_minimum_size.y = 29
	box.add_theme_constant_override("separation", 1)

func _build_house_shape_picker() -> void:
	_house_shape_picker = _make_catalogue_panel("HouseShapePicker", Vector2(520, 430))
	var box := _catalogue_box(_house_shape_picker)
	box.add_theme_constant_override("separation", 5)
	_add_catalogue_heading(box, "HOUSE SHAPE", "Simple masses auto-join walls and roofs")
	for spec in HouseMassing.PRESETS:
		var button := Button.new()
		button.text = str(spec["label"])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(470, 40)
		button.focus_mode = Control.FOCUS_ALL
		button.set_meta("massing_preset", str(spec["id"]))
		button.pressed.connect(_apply_house_shape_preset.bind(str(spec["id"])))
		box.add_child(button)
		_house_shape_buttons.append(button)
	var add_button := Button.new()
	add_button.text = "Add house portion"
	add_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_button.custom_minimum_size = Vector2(470, 42)
	add_button.focus_mode = Control.FOCUS_ALL
	add_button.pressed.connect(_begin_portion_placement)
	box.add_child(add_button)
	_house_shape_buttons.append(add_button)
	_house_shape_remove_button = Button.new()
	_house_shape_remove_button.text = "Remove last portion"
	_house_shape_remove_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_house_shape_remove_button.custom_minimum_size = Vector2(470, 42)
	_house_shape_remove_button.focus_mode = Control.FOCUS_ALL
	_house_shape_remove_button.pressed.connect(_remove_last_portion)
	box.add_child(_house_shape_remove_button)
	_house_shape_buttons.append(_house_shape_remove_button)

func _input(event: InputEvent) -> void:
	if portion_placement_active and not menu_open:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_cancel_portion_placement()
		elif event.is_action_pressed("m1_pause"):
			_cancel_portion_placement(); super._input(event)
		elif event.is_action_pressed("m1_accept"):
			_commit_portion_placement()
		elif event.is_action_pressed("m1_cycle_left"):
			_resize_portion("x", -1)
		elif event.is_action_pressed("m1_cycle_right"):
			_resize_portion("x", 1)
		elif event.is_action_pressed("m1_height_up"):
			_resize_portion("z", 1)
		elif event.is_action_pressed("m1_height_down"):
			_resize_portion("z", -1)
		elif event.is_action_pressed("m1_precision"):
			precision_mode = not precision_mode
			_set_status("Portion placement precision %s" % ("ON" if precision_mode else "OFF"))
		get_viewport().set_input_as_handled()
		return
	if _house_shape_picker_open and not menu_open:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_close_house_shape_picker(true)
		elif event.is_action_pressed("m1_pause"):
			_close_house_shape_picker(false); super._input(event)
		elif event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner()
			if focus in _house_shape_buttons: (focus as Button).pressed.emit()
		elif event.is_action_pressed("m1_height_up") or event.is_action_pressed("ui_up"):
			_move_focus(_house_shape_buttons, -1)
		elif event.is_action_pressed("m1_height_down") or event.is_action_pressed("ui_down"):
			_move_focus(_house_shape_buttons, 1)
		get_viewport().set_input_as_handled()
		return
	super._input(event)

func _read_camera_and_cursor(delta: float) -> void:
	if not portion_placement_active:
		super._read_camera_and_cursor(delta)
		return
	var move := Vector2(Input.get_axis("m1_move_left", "m1_move_right"), Input.get_axis("m1_move_up", "m1_move_down"))
	if move.length() > 0.05:
		var view := building_world.get_building(selected_building_id)
		var transform_value = view.get("transform", Transform3D.IDENTITY)
		if transform_value is Transform3D:
			var forward := Vector3(sin(camera_yaw), 0, cos(camera_yaw))
			var right := Vector3(forward.z, 0, -forward.x)
			var speed := 2.2 if precision_mode else 4.5
			var world_delta := (right * move.x + forward * move.y) * delta * speed
			var local_delta := (transform_value as Transform3D).basis.inverse() * world_delta
			portion_offset.x += local_delta.x
			portion_offset.z += local_delta.z
			var snap := HouseMassing.CELL if precision_mode else HouseMassing.CELL * 2.0
			portion_offset.x = snappedf(portion_offset.x, snap)
			portion_offset.z = snappedf(portion_offset.z, snap)
			_update_portion_preview()
	var orbit_x := Input.get_axis("m1_orbit_left", "m1_orbit_right")
	var orbit_y := Input.get_axis("m1_orbit_up", "m1_orbit_down")
	camera_yaw += orbit_x * delta * 2.2
	camera_pitch = clampf(camera_pitch + orbit_y * delta * 1.5, 0.10, 1.35)
	var zoom := Input.get_axis("m1_zoom_out", "m1_zoom_in")
	camera_distance = clampf(camera_distance - zoom * delta * 18.0, 5.0, 52.0)

func _open_house_shape_picker() -> void:
	if selected_building_id.is_empty(): return
	_house_shape_picker_open = true
	tools_open = true
	if _building_panel: _building_panel.visible = false
	_house_shape_picker.visible = true
	var view := building_world.get_building(selected_building_id)
	_house_shape_remove_button.disabled = HouseMassing.sections_for(view).size() <= 1
	if not _house_shape_buttons.is_empty(): _house_shape_buttons[0].grab_focus()
	_set_status("House shape • presets or add a portion • A choose / B back")
	_refresh_controller_hud()

func _close_house_shape_picker(return_to_options: bool) -> void:
	_house_shape_picker_open = false
	if _house_shape_picker: _house_shape_picker.visible = false
	if return_to_options:
		tools_open = true
		if _building_panel: _building_panel.visible = true
		if _house_shape_button: _house_shape_button.grab_focus()
	else:
		tools_open = false
		get_viewport().gui_release_focus()
	_refresh_controller_hud()

func _apply_house_shape_preset(preset_id: String) -> bool:
	var index := building_world._building_index(selected_building_id)
	if index < 0: return false
	var before: Dictionary = building_world._copy(building_world._document)
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[index]
	if preset_id == "rectangle":
		building.erase("massing_sections")
		building.erase("massing_preset")
	else:
		var view := building_world.get_building(selected_building_id)
		building["massing_sections"] = _serialize_sections(HouseMassing.preset_sections(view, preset_id))
		building["massing_preset"] = preset_id
	buildings[index] = building
	var ok := building_world._record_change(before)
	_close_house_shape_picker(false)
	if ok:
		_record_history("building")
		_presentation_key = ""
		_update_presentation()
		_set_status("House shape: %s" % HouseMassing.shape_name(building_world.get_building(selected_building_id)))
	else:
		_set_status("House shape unchanged")
	return ok

func _begin_portion_placement() -> void:
	var view := building_world.get_building(selected_building_id)
	if view.is_empty(): return
	var sections := HouseMassing.sections_for(view)
	if sections.size() >= HouseMassing.MAX_SECTIONS:
		_set_status("This house already has the maximum number of portions")
		return
	_close_house_shape_picker(false)
	var bounds := HouseMassing.union_bounds(sections)
	var dimensions: Vector3 = view.get("dimensions", Vector3(12, 6, 10))
	portion_size = Vector3(snappedf(clampf(dimensions.x * 0.40, 4.0, 8.0), HouseMassing.CELL), dimensions.y, snappedf(clampf(dimensions.z * 0.42, 4.0, 8.0), HouseMassing.CELL))
	portion_offset = Vector3(bounds.end.x + portion_size.x * 0.5, 0.0, bounds.get_center().y)
	portion_revision = building_world.get_revision()
	portion_placement_active = true
	_update_portion_preview()
	_set_status("Add house portion • LS move • left/right width • up/down depth • A join / B cancel")
	_refresh_controller_hud()

func _resize_portion(axis: String, direction: int) -> void:
	if not portion_placement_active or direction == 0: return
	var step := HouseMassing.CELL if precision_mode else 1.0
	if axis == "x": portion_size.x = clampf(portion_size.x + float(direction) * step, HouseMassing.MIN_PORTION_SIZE, HouseMassing.MAX_PORTION_SIZE)
	else: portion_size.z = clampf(portion_size.z + float(direction) * step, HouseMassing.MIN_PORTION_SIZE, HouseMassing.MAX_PORTION_SIZE)
	_update_portion_preview()

func _update_portion_preview() -> void:
	if not portion_placement_active: return
	var view := building_world.get_building(selected_building_id)
	if view.is_empty() or building_world.get_revision() != portion_revision:
		portion_valid = false
		portion_reason = "House changed; cancel and restart"
	else:
		var sections := HouseMassing.sections_for(view)
		var candidate := _candidate_portion("preview")
		portion_valid = HouseMassing.can_add_portion(sections, candidate)
		portion_reason = "Needs a shared wall with the house" if not portion_valid else _portion_world_reason(view, _sections_with_candidate(sections, candidate))
		portion_valid = portion_valid and portion_reason.is_empty()
	_presentation_key = ""
	_refresh_massing_shells()
	_refresh_controller_hud()

func _commit_portion_placement() -> bool:
	if not portion_placement_active: return false
	_update_portion_preview()
	if not portion_valid:
		_set_status("Cannot add portion: %s" % portion_reason)
		return false
	var index := building_world._building_index(selected_building_id)
	if index < 0: return false
	var before: Dictionary = building_world._copy(building_world._document)
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[index]
	var view := building_world.get_building(selected_building_id)
	var sections := HouseMassing.sections_for(view)
	var portion_id := building_world._allocate_id("portion")
	sections.append(_candidate_portion(portion_id))
	building["massing_sections"] = _serialize_sections(sections)
	building["massing_preset"] = "custom"
	buildings[index] = building
	var ok := building_world._record_change(before)
	_clear_portion_placement()
	if ok:
		_record_history("building")
		_presentation_key = ""
		_update_presentation()
		_set_status("House portion joined • %d total portions" % HouseMassing.sections_for(building_world.get_building(selected_building_id)).size())
	else:
		_set_status("House portion could not be saved")
	return ok

func _cancel_portion_placement() -> void:
	if not portion_placement_active: return
	_clear_portion_placement()
	_presentation_key = ""
	_update_presentation()
	_set_status("House portion cancelled")
	_refresh_controller_hud()

func _clear_portion_placement() -> void:
	portion_placement_active = false
	portion_offset = Vector3.ZERO
	portion_size = Vector3.ZERO
	portion_revision = -1
	portion_valid = false
	portion_reason = ""

func _remove_last_portion() -> bool:
	var index := building_world._building_index(selected_building_id)
	if index < 0: return false
	var view := building_world.get_building(selected_building_id)
	var sections := HouseMassing.sections_for(view)
	if sections.size() <= 1:
		_set_status("This house has no added portions")
		return false
	var before: Dictionary = building_world._copy(building_world._document)
	sections.pop_back()
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[index]
	if sections.size() <= 1:
		building.erase("massing_sections")
		building.erase("massing_preset")
	else:
		building["massing_sections"] = _serialize_sections(sections)
		building["massing_preset"] = "custom"
	buildings[index] = building
	var ok := building_world._record_change(before)
	_close_house_shape_picker(false)
	if ok:
		_record_history("building")
		_presentation_key = ""
		_update_presentation()
		_set_status("Removed last house portion")
	return ok

func _candidate_portion(portion_id: String) -> Dictionary:
	return {"id": portion_id, "offset": Vector3(portion_offset.x, 0.0, portion_offset.z), "size": Vector3(portion_size.x, portion_size.y, portion_size.z)}

func _sections_with_candidate(sections: Array[Dictionary], candidate: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for section in sections: result.append(section.duplicate(true))
	result.append(candidate.duplicate(true))
	return result

func _portion_world_reason(view: Dictionary, sections: Array[Dictionary]) -> String:
	var world_rect := _world_rect_for_sections(view, sections)
	if world_rect.position.x < BUILDING_WORLD_MIN or world_rect.position.y < BUILDING_WORLD_MIN or world_rect.end.x > BUILDING_WORLD_MAX or world_rect.end.y > BUILDING_WORLD_MAX:
		return "Outside editable world"
	for other in building_world.get_buildings():
		if str(other.get("id", "")) == selected_building_id: continue
		var other_rect := _world_rect_for_sections(other, HouseMassing.sections_for(other))
		if _rects_overlap(world_rect, other_rect): return "Overlaps %s" % str(other.get("name", "another home"))
	return ""

func _world_rect_for_sections(view: Dictionary, sections: Array[Dictionary]) -> Rect2:
	var transform_value = view.get("transform", Transform3D.IDENTITY)
	if not transform_value is Transform3D: return Rect2()
	var bounds := HouseMassing.union_bounds(sections)
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for corner in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
		var world := (transform_value as Transform3D) * Vector3(corner.x, 0.0, corner.y)
		minimum = minimum.min(Vector2(world.x, world.z))
		maximum = maximum.max(Vector2(world.x, world.z))
	return Rect2(minimum, maximum - minimum)

func _rects_overlap(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x - 0.05 and a.end.x > b.position.x + 0.05 and a.position.y < b.end.y - 0.05 and a.end.y > b.position.y + 0.05

func _serialize_sections(sections: Array[Dictionary]) -> Array:
	var result: Array = []
	for section in sections:
		var offset: Vector3 = section["offset"]
		var size: Vector3 = section["size"]
		result.append({"id": str(section.get("id", "section")), "offset": [offset.x, offset.y, offset.z], "size": [size.x, size.y, size.z]})
	return result

func _preview_massing_view(view: Dictionary) -> Dictionary:
	if not portion_placement_active or str(view.get("id", "")) != selected_building_id: return view
	var preview := view.duplicate(true)
	var sections := HouseMassing.sections_for(view)
	sections.append(_candidate_portion("preview"))
	preview["massing_sections"] = _serialize_sections(sections)
	preview["massing_preset"] = "custom"
	return preview

func _update_presentation() -> void:
	super._update_presentation()
	_refresh_massing_shells()
	_refresh_house_shape_label()

func _refresh_house_shape_label() -> void:
	if not _house_shape_button or not building_world: return
	var view := building_world.get_building(selected_building_id)
	_house_shape_button.text = "House shape: %s" % HouseMassing.shape_name(view) if not view.is_empty() else "House shape"

func _refresh_massing_shells() -> void:
	if not building_world: return
	for id_value in cottage_visuals.keys():
		var building_id := str(id_value)
		var visual := cottage_visuals.get(building_id, null) as Node3D
		if not is_instance_valid(visual): continue
		var view := building_world.get_building(building_id)
		if view.is_empty(): continue
		view = _preview_massing_view(view)
		_refresh_massing_shell_for_visual(visual, view)

func _refresh_massing_shell_for_visual(visual: Node3D, view: Dictionary) -> void:
	var active := HouseMassing.sections_for(view).size() > 1
	var existing := visual.get_node_or_null("M2JoinedMassing") as Node3D
	if not active:
		if existing: visual.remove_child(existing); existing.queue_free()
		_set_native_shell_visible(visual, true)
		_remove_portion_ghost(visual)
		return
	if not existing:
		existing = HouseMassingVisual.new()
		existing.name = "M2JoinedMassing"
		visual.add_child(existing)
	_set_native_shell_visible(visual, false)
	var wall_id := str(view.get("wall_material_id", view.get("material_id", "stone_plaster")))
	var roof_id := str(view.get("roof_material_id", "terracotta"))
	var wall_colour: Color = SURFACE_MATERIAL_COLOURS.get(wall_id, Color("#e7cfab"))
	var palette := _massing_roof_palette(roof_id)
	var roof_edge: Color = (palette[0] as Color).darkened(0.14)
	existing.show_view(view, wall_colour, palette, roof_edge)
	if portion_placement_active and str(view.get("id", "")) == selected_building_id: _refresh_portion_ghost(visual)
	else: _remove_portion_ghost(visual)
	# The single-rectangle masonry helpers are superseded by the union shell.
	_remove_raised_foundation(str(view.get("id", "")))
	_remove_raised_quoins(str(view.get("id", "")))
	if _world_mesh_highlight_id == str(view.get("id", "")) and view_context == "terrain" and existing.has_method("set_highlight"):
		existing.set_highlight(true, TERRAIN_HOUSE_OUTLINE_GROW_AMOUNT)

func _massing_roof_palette(material_id: String) -> Array:
	if EXTRA_ROOF_PALETTES.has(material_id): return (EXTRA_ROOF_PALETTES[material_id] as Array).duplicate()
	var base: Color = SURFACE_MATERIAL_COLOURS.get(material_id, Color("#b9654c"))
	return [base.darkened(0.05), base.lightened(0.06), base.darkened(0.13)]

func _set_native_shell_visible(visual: Node3D, visible: bool) -> void:
	for child in visual.get_children():
		if child == visual.get_node_or_null("M2JoinedMassing") or str(child.name) == "M2PortionGhost": continue
		if _is_native_shell_node(str(child.name)): (child as Node3D).visible = visible

func _is_native_shell_node(node_name: String) -> bool:
	for prefix in ["Foundation", "Wall", "LogCourses", "Trim_", "Cornice_", "RoofTiles_", "GableLeft_", "GableRight_", "CornerQuoins", "Crafted", "GableVent", "LodgeLogEnds", "TudorWallFrame", "GableFinials", "RidgeCourses", "RoofEdgeLip", "M2RoofDesign"]:
		if node_name.begins_with(prefix): return true
	return false

func _refresh_portion_ghost(visual: Node3D) -> void:
	_remove_portion_ghost(visual)
	var ghost := MeshInstance3D.new()
	ghost.name = "M2PortionGhost"
	var mesh := BoxMesh.new()
	mesh.size = portion_size
	ghost.mesh = mesh
	ghost.position = portion_offset + Vector3(0.0, portion_size.y * 0.5, 0.0)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.38, 0.78, 0.48, 0.28) if portion_valid else Color(0.88, 0.32, 0.28, 0.30)
	material.roughness = 0.85
	ghost.material_override = material
	visual.add_child(ghost)

func _remove_portion_ghost(visual: Node3D) -> void:
	var ghost := visual.get_node_or_null("M2PortionGhost")
	if ghost: visual.remove_child(ghost); ghost.queue_free()

func _set_world_mesh_highlight(building_id: String) -> void:
	super._set_world_mesh_highlight(building_id)
	for id_value in cottage_visuals.keys():
		var id := str(id_value)
		var visual := cottage_visuals.get(id, null) as Node3D
		if not is_instance_valid(visual): continue
		var massing := visual.get_node_or_null("M2JoinedMassing")
		if massing and massing.has_method("set_highlight"):
			massing.set_highlight(view_context == "terrain" and id == building_id and not building_id.is_empty(), TERRAIN_HOUSE_OUTLINE_GROW_AMOUNT)

func _cancel_current_edit(reason: String) -> void:
	if portion_placement_active: _clear_portion_placement()
	if _house_shape_picker_open:
		_house_shape_picker_open = false
		if _house_shape_picker: _house_shape_picker.visible = false
	super._cancel_current_edit(reason)
	_refresh_massing_shells()

func _set_view_context(next_context: String, reason: String = "Context changed") -> bool:
	if next_context != "building" and portion_placement_active: _cancel_portion_placement()
	if next_context != "building" and _house_shape_picker_open: _close_house_shape_picker(false)
	return super._set_view_context(next_context, reason)

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if _house_shape_picker: _house_shape_picker.visible = _house_shape_picker_open and not menu_open
	if _house_shape_picker_open:
		if _building_panel: _building_panel.visible = false
		if _tool_card: _tool_card.visible = false
		_tool_name.text = "House shape"
		_tool_meta.text = "Rectangle • L • T • U • custom portions"
		_set_prompts([["UP/DOWN", "Choose"], ["A", "Apply"], ["B", "Back"]])
	elif portion_placement_active:
		_tool_name.text = "Add house portion"
		_tool_meta.text = "%s • %.1f × %.1f" % ["Valid join" if portion_valid else portion_reason, portion_size.x, portion_size.z]
		_set_prompts([["LS", "Move"], ["◀▶", "Width"], ["▲▼", "Depth"], ["A", "Join"], ["B", "Cancel"], ["L3", "Precision"], ["RS", "Orbit"]])
