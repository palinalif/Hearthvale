extends "res://scripts/m2_scene_house_massing.gd"

## Interaction integration for multi-portion houses. Selection, camera framing,
## placement collision and roof accessories all use the full union footprint
## instead of the legacy core rectangle.

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
	var max_height := 0.0
	for section in sections:
		var section_size: Vector3 = section["size"]
		max_height = maxf(max_height, section_size.y)
	var local_target := Vector3(bounds.get_center().x, max_height * 0.56, bounds.get_center().y)
	return (transform_value as Transform3D) * local_target

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
	var max_height := 0.0
	for section in sections:
		var section_size: Vector3 = section["size"]
		max_height = maxf(max_height, section_size.y)
	var scale := (transform_value as Transform3D).basis.get_scale().abs()
	var world_dims := Vector3(bounds.size.x * scale.x, max_height * 1.55 * scale.y, bounds.size.y * scale.z)
	var radius := maxf(0.5, world_dims.length() * 0.5)
	var half_fov := deg_to_rad(camera.fov * 0.5)
	var fit_distance := radius / maxf(0.2, sin(half_fov)) * 1.26
	return clampf(fit_distance, 7.0, BUILDING_CAMERA_MAX_DISTANCE)

func _pick_cottage(screen_position: Vector2) -> Dictionary:
	if not camera or not building_world: return {}
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var result: Dictionary = {}
	var best := INF
	for view_value in building_world.get_buildings():
		var view: Dictionary = view_value
		var transform_value: Variant = view.get("transform", Transform3D.IDENTITY)
		if not transform_value is Transform3D: continue
		var inverse := (transform_value as Transform3D).affine_inverse()
		var local_origin := inverse * origin
		var local_direction := inverse.basis * direction
		var sections: Array[Dictionary] = HouseMassing.sections_for(view)
		var distance := INF
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for section in sections:
			var offset: Vector3 = section["offset"]
			var size: Vector3 = section["size"]
			var bounds := AABB(Vector3(offset.x - size.x * 0.5, 0.0, offset.z - size.z * 0.5), Vector3(size.x, size.y * 1.60, size.z))
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

func _update_building_placement_validity() -> void:
	super._update_building_placement_validity()
	if not building_placement_active or not building_placement_valid: return
	if building_placement_operation not in ["duplicate", "move"]: return
	var source: Dictionary = building_world.get_building(building_placement_source_id)
	if source.is_empty(): return
	var sections: Array[Dictionary] = HouseMassing.sections_for(source)
	if sections.size() <= 1: return
	var target_rect := _world_rect_for_transform(sections, building_placement_transform)
	if target_rect.position.x < BUILDING_WORLD_MIN or target_rect.position.y < BUILDING_WORLD_MIN or target_rect.end.x > BUILDING_WORLD_MAX or target_rect.end.y > BUILDING_WORLD_MAX:
		building_placement_valid = false
		building_placement_reason = "Outside editable world"
		return
	for other_value in building_world.get_buildings():
		var other: Dictionary = other_value
		var other_id := str(other.get("id", ""))
		if building_placement_operation == "move" and other_id == building_placement_source_id: continue
		var other_transform: Variant = other.get("transform", Transform3D.IDENTITY)
		if not other_transform is Transform3D: continue
		var other_rect := _world_rect_for_transform(HouseMassing.sections_for(other), other_transform as Transform3D)
		if _rects_overlap(target_rect, other_rect):
			building_placement_valid = false
			building_placement_reason = "Overlaps %s" % str(other.get("name", "another home"))
			return

func _world_rect_for_transform(sections: Array[Dictionary], transform_value: Transform3D) -> Rect2:
	var bounds := HouseMassing.union_bounds(sections)
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for corner_value in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
		var corner: Vector2 = corner_value
		var world := transform_value * Vector3(corner.x, 0.0, corner.y)
		minimum = minimum.min(Vector2(world.x, world.z))
		maximum = maximum.max(Vector2(world.x, world.z))
	return Rect2(minimum, maximum - minimum)

func _build_roof_accessory(root: Node3D, view: Dictionary, record: Dictionary) -> void:
	var sections: Array[Dictionary] = HouseMassing.sections_for(view)
	if sections.size() <= 1:
		super._build_roof_accessory(root, view, record)
		return
	var bounds := HouseMassing.union_bounds(sections)
	var u := clampf(float(record.get("u", 0.5)), 0.05, 0.95)
	var v := clampf(float(record.get("v", 0.5)), 0.05, 0.95)
	var inset := HouseMassing.CELL * 0.75
	var x := lerpf(bounds.position.x + inset, bounds.end.x - inset, u)
	var z := lerpf(bounds.position.y + inset, bounds.end.y - inset, v)
	var y := HouseMassing.roof_height_at(view, x, z)
	var holder := Node3D.new()
	holder.name = "Accessory_%s" % str(record.get("id", "roof"))
	holder.position = Vector3(x, y, z)
	holder.rotation.y = float(record.get("yaw", 0.0))
	root.add_child(holder)
	var asset_id := str(record.get("asset_id", ""))
	var wall_colour: Color = SURFACE_MATERIAL_COLOURS.get(str(view.get("wall_material_id", "stone_plaster")), Color("#e7cfab"))
	var roof_palette: Array = _massing_roof_palette(str(view.get("roof_material_id", "terracotta")))
	var roof_colour: Color = roof_palette[mini(1, roof_palette.size() - 1)] as Color
	var accent_colour: Color = ACCENT_COLOURS.get(_accent_material_id(view), Color("#557a70"))
	match asset_id:
		"chimney_stone": _build_chimney(holder, Color("#9a8776"), false)
		"chimney_brick": _build_chimney(holder, Color("#9c5d4a"), true)
		"dormer_gable": _build_dormer(holder, wall_colour, roof_colour, accent_colour, true, z > bounds.get_center().y)
		"dormer_shed": _build_dormer(holder, wall_colour, roof_colour, accent_colour, false, z > bounds.get_center().y)
		"weathervane_arrow": _build_weathervane(holder, accent_colour, false)
		"weathervane_rooster": _build_weathervane(holder, accent_colour, true)
