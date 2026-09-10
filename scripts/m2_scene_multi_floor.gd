extends "res://scripts/m2_scene_joined_roof_beams.gd"

## Vertical extension of Townscaper-style house massing. Ground-floor portions
## use the existing workflow; upper portions reuse the same move/resize preview
## but carry a storey level and require full support from the floor below.
var portion_level := 0
var _upper_floor_portion_button: Button
var _next_storey_button: Button

func _ready() -> void:
	super._ready()
	_install_multi_floor_controls()

func _install_multi_floor_controls() -> void:
	if not _house_shape_picker or not _house_shape_remove_button: return
	var box: VBoxContainer = _catalogue_box(_house_shape_picker)
	_upper_floor_portion_button = Button.new()
	_upper_floor_portion_button.name = "UpperFloorPortionAction"
	_upper_floor_portion_button.text = "Add upper-floor portion"
	_upper_floor_portion_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_upper_floor_portion_button.focus_mode = Control.FOCUS_ALL
	_upper_floor_portion_button.custom_minimum_size = Vector2(470, 34)
	_upper_floor_portion_button.pressed.connect(_begin_upper_floor_portion)
	box.add_child(_upper_floor_portion_button)
	box.move_child(_upper_floor_portion_button, _house_shape_remove_button.get_index())
	var remove_index: int = _house_shape_buttons.find(_house_shape_remove_button)
	if remove_index >= 0: _house_shape_buttons.insert(remove_index, _upper_floor_portion_button)
	else: _house_shape_buttons.append(_upper_floor_portion_button)

	_next_storey_button = Button.new()
	_next_storey_button.name = "NextStoreyAction"
	_next_storey_button.text = "Start next storey"
	_next_storey_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_next_storey_button.focus_mode = Control.FOCUS_ALL
	_next_storey_button.custom_minimum_size = Vector2(470, 34)
	_next_storey_button.pressed.connect(_begin_next_storey)
	box.add_child(_next_storey_button)
	box.move_child(_next_storey_button, _house_shape_remove_button.get_index())
	remove_index = _house_shape_buttons.find(_house_shape_remove_button)
	if remove_index >= 0: _house_shape_buttons.insert(remove_index, _next_storey_button)
	else: _house_shape_buttons.append(_next_storey_button)

	for button in _house_shape_buttons: button.custom_minimum_size.y = 34
	box.add_theme_constant_override("separation", 3)
	_house_shape_picker.custom_minimum_size = Vector2(520, 520)

func _open_house_shape_picker() -> void:
	super._open_house_shape_picker()
	_refresh_multi_floor_controls()

func _refresh_multi_floor_controls() -> void:
	if not building_world or selected_building_id.is_empty(): return
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty(): return
	var sections: Array[Dictionary] = HouseMassing.sections_for(view)
	var top_level: int = HouseMassing.max_level(sections)
	if _upper_floor_portion_button:
		var target_floor: int = maxi(1, top_level) + 1
		_upper_floor_portion_button.text = "Add portion to floor %d" % target_floor
		_upper_floor_portion_button.disabled = sections.size() >= HouseMassing.MAX_SECTIONS
	if _next_storey_button:
		_next_storey_button.text = "Start floor %d" % (top_level + 2)
		_next_storey_button.disabled = top_level >= HouseMassing.MAX_FLOORS - 1 or sections.size() >= HouseMassing.MAX_SECTIONS

func _begin_portion_placement() -> void:
	portion_level = 0
	super._begin_portion_placement()

func _begin_upper_floor_portion() -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty(): return
	var sections: Array[Dictionary] = HouseMassing.sections_for(view)
	var target_level: int = maxi(1, HouseMassing.max_level(sections))
	_begin_portion_on_level(target_level)

func _begin_next_storey() -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty(): return
	var sections: Array[Dictionary] = HouseMassing.sections_for(view)
	var target_level: int = HouseMassing.max_level(sections) + 1
	if target_level >= HouseMassing.MAX_FLOORS:
		_set_status("This house already has the maximum number of floors")
		return
	_begin_portion_on_level(target_level)

func _begin_portion_on_level(level: int) -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty(): return
	var sections: Array[Dictionary] = HouseMassing.sections_for(view)
	if sections.size() >= HouseMassing.MAX_SECTIONS:
		_set_status("This house already has the maximum number of portions")
		return
	var support_sections: Array[Dictionary] = HouseMassing.sections_on_level(sections, level - 1)
	if support_sections.is_empty():
		_set_status("Floor %d needs floor %d beneath it" % [level + 1, level])
		return
	var support: Dictionary = _largest_section(support_sections)
	var support_size: Vector3 = support["size"]
	var dimensions: Vector3 = view.get("dimensions", Vector3(12, 6, 10))
	portion_level = level
	portion_size = Vector3(
		snappedf(clampf(minf(support_size.x, dimensions.x * 0.48), HouseMassing.MIN_PORTION_SIZE, 7.0), HouseMassing.CELL),
		dimensions.y,
		snappedf(clampf(minf(support_size.z, dimensions.z * 0.48), HouseMassing.MIN_PORTION_SIZE, 7.0), HouseMassing.CELL)
	)
	portion_offset = _find_supported_start(sections, support_sections, portion_size, level)
	portion_offset.y = float(level) * portion_size.y
	portion_revision = building_world.get_revision()
	portion_placement_active = true
	_close_house_shape_picker(false)
	_update_portion_preview()
	_set_status("Floor %d portion • LS move • left/right width • up/down depth • A join / B cancel" % (level + 1))
	_refresh_controller_hud()

func _largest_section(sections: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = sections[0]
	var best_area := -1.0
	for section in sections:
		var size: Vector3 = section["size"]
		var area := size.x * size.z
		if area > best_area:
			best_area = area
			best = section
	return best

func _find_supported_start(all_sections: Array[Dictionary], supports: Array[Dictionary], size: Vector3, level: int) -> Vector3:
	for support in supports:
		var rect: Rect2 = HouseMassing.section_rect(support)
		var half := Vector2(size.x, size.z) * 0.5
		var candidates: Array[Vector2] = [
			rect.get_center(),
			Vector2(rect.position.x + half.x, rect.position.y + half.y),
			Vector2(rect.end.x - half.x, rect.position.y + half.y),
			Vector2(rect.position.x + half.x, rect.end.y - half.y),
			Vector2(rect.end.x - half.x, rect.end.y - half.y),
		]
		for point in candidates:
			var candidate := {"id": "preview", "level": level, "offset": Vector3(point.x, float(level) * size.y, point.y), "size": size}
			if HouseMassing.can_add_portion(all_sections, candidate): return candidate["offset"]
	var fallback: Dictionary = _largest_section(supports)
	var fallback_offset: Vector3 = fallback["offset"]
	return Vector3(fallback_offset.x, float(level) * size.y, fallback_offset.z)

func _candidate_portion(portion_id: String) -> Dictionary:
	return {"id": portion_id, "level": portion_level, "offset": Vector3(portion_offset.x, float(portion_level) * portion_size.y, portion_offset.z), "size": Vector3(portion_size.x, portion_size.y, portion_size.z)}

func _serialize_sections(sections: Array[Dictionary]) -> Array:
	var result: Array = []
	for section in sections:
		var offset: Vector3 = section["offset"]
		var size: Vector3 = section["size"]
		var level: int = HouseMassing.section_level(section)
		result.append({"id": str(section.get("id", "section")), "level": level, "offset": [offset.x, float(level) * size.y, offset.z], "size": [size.x, size.y, size.z]})
	return result

func _update_portion_preview() -> void:
	if not portion_placement_active: return
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty() or building_world.get_revision() != portion_revision:
		portion_valid = false
		portion_reason = "House changed; cancel and restart"
	else:
		var sections: Array[Dictionary] = HouseMassing.sections_for(view)
		var candidate: Dictionary = _candidate_portion("preview")
		portion_valid = HouseMassing.can_add_portion(sections, candidate)
		if not portion_valid:
			portion_reason = "Needs full support from floor %d below" % portion_level if portion_level > 0 else "Needs a shared wall with the house"
		else:
			portion_reason = _portion_world_reason(view, _sections_with_candidate(sections, candidate))
		portion_valid = portion_valid and portion_reason.is_empty()
	_presentation_key = ""
	_refresh_massing_shells()
	_refresh_controller_hud()

func _commit_portion_placement() -> bool:
	var committed_level := portion_level
	var ok: bool = super._commit_portion_placement()
	if ok and committed_level > 0:
		var view: Dictionary = building_world.get_building(selected_building_id)
		var floor_portions: int = HouseMassing.sections_on_level(HouseMassing.sections_for(view), committed_level).size()
		_set_status("Floor %d portion joined • %d portions on this floor" % [committed_level + 1, floor_portions])
	return ok

func _clear_portion_placement() -> void:
	super._clear_portion_placement()
	portion_level = 0

func _refresh_portion_ghost(visual: Node3D) -> void:
	_remove_portion_ghost(visual)
	var ghost := MeshInstance3D.new()
	ghost.name = "M2PortionGhost"
	var mesh := BoxMesh.new()
	mesh.size = portion_size
	ghost.mesh = mesh
	var bottom := float(portion_level) * portion_size.y
	ghost.position = Vector3(portion_offset.x, bottom + portion_size.y * 0.5, portion_offset.z)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.38, 0.78, 0.48, 0.28) if portion_valid else Color(0.88, 0.32, 0.28, 0.30)
	material.roughness = 0.85
	ghost.material_override = material
	visual.add_child(ghost)

func _selected_building_camera_target() -> Vector3:
	if not building_world: return super._selected_building_camera_target()
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty(): return super._selected_building_camera_target()
	view = _preview_massing_view(view)
	var sections: Array[Dictionary] = HouseMassing.sections_for(view)
	if sections.size() <= 1 or resize_active: return super._selected_building_camera_target()
	var transform_value: Variant = view.get("transform", Transform3D.IDENTITY)
	if not transform_value is Transform3D: return super._selected_building_camera_target()
	var bounds: Rect2 = HouseMassing.union_bounds(sections)
	var max_top := 0.0
	for section in sections: max_top = maxf(max_top, HouseMassing.section_top(section))
	return (transform_value as Transform3D) * Vector3(bounds.get_center().x, max_top * 0.50, bounds.get_center().y)

func _building_frame_distance() -> float:
	if not building_world or not camera: return super._building_frame_distance()
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty(): return super._building_frame_distance()
	view = _preview_massing_view(view)
	var sections: Array[Dictionary] = HouseMassing.sections_for(view)
	if sections.size() <= 1 or resize_active: return super._building_frame_distance()
	var transform_value: Variant = view.get("transform", Transform3D.IDENTITY)
	if not transform_value is Transform3D: return super._building_frame_distance()
	var bounds: Rect2 = HouseMassing.union_bounds(sections)
	var max_top := 0.0
	for section in sections: max_top = maxf(max_top, HouseMassing.section_top(section))
	var scale := (transform_value as Transform3D).basis.get_scale().abs()
	var world_dims := Vector3(bounds.size.x * scale.x, max_top * 1.30 * scale.y, bounds.size.y * scale.z)
	var radius := maxf(0.5, world_dims.length() * 0.5)
	var half_fov := deg_to_rad(camera.fov * 0.5)
	return clampf(radius / maxf(0.2, sin(half_fov)) * 1.26, 7.0, BUILDING_CAMERA_MAX_DISTANCE)

func _pick_cottage(screen_position: Vector2) -> Dictionary:
	if not camera or not building_world: return {}
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var result: Dictionary = {}
	var best := INF
	for view_value in building_world.get_buildings():
		var view: Dictionary = view_value
		var transform_value: Variant = view.get("transform", Transform3D.IDENTITY)
		if not transform_value is Transform3D: continue
		var inverse := (transform_value as Transform3D).affine_inverse()
		var local_origin := inverse * ray_origin
		var local_direction := inverse.basis * ray_direction
		var distance := INF
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for section in HouseMassing.sections_for(view):
			var offset: Vector3 = section["offset"]
			var size: Vector3 = section["size"]
			var bottom: float = HouseMassing.section_bottom(section)
			var bounds := AABB(Vector3(offset.x - size.x * 0.5, bottom, offset.z - size.z * 0.5), Vector3(size.x, size.y * 1.55, size.z))
			var section_distance := _ray_box_distance(local_origin, local_direction, bounds)
			if section_distance >= 0.0: distance = minf(distance, section_distance)
			for corner_index in 8:
				var world_point := (transform_value as Transform3D) * bounds.get_endpoint(corner_index)
				if camera.is_position_behind(world_point): continue
				var point := camera.unproject_position(world_point)
				low = low.min(point)
				high = high.max(point)
		if distance == INF or distance >= best or not low.is_finite() or not high.is_finite(): continue
		best = distance
		result = {"id": str(view.get("id", "")), "distance": distance, "bounds": Rect2(low, high - low)}
	return result

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if portion_placement_active and portion_level > 0:
		_tool_name.text = "Add floor %d portion" % (portion_level + 1)
		_tool_meta.text = "%s • %.1f × %.1f" % ["Supported" if portion_valid else portion_reason, portion_size.x, portion_size.z]
		_set_prompts([["LS", "Move"], ["◀▶", "Width"], ["▲▼", "Depth"], ["A", "Join"], ["B", "Cancel"], ["L3", "Precision"], ["RS", "Orbit"]])
	elif _house_shape_picker_open:
		_tool_meta.text = "Ground shapes • stacked floors • custom portions"
