extends "res://scripts/m2_scene_thor_repairs.gd"

## Final Thor repair layer. Keep the first device-fix pass small and add only
## the state/reset and joined-roof coordinate corrections found during review.

func _begin_portion_placement() -> void:
	_addition_raw = Vector3.ZERO
	_addition_was_active = false
	super._begin_portion_placement()

func _clear_portion_placement() -> void:
	_addition_raw = Vector3.ZERO
	_addition_was_active = false
	super._clear_portion_placement()

func _repair_read_portion(delta: float) -> void:
	if not _addition_was_active:
		_addition_raw = portion_offset
		_addition_was_active = true
	var move := Vector2(Input.get_axis("m1_move_left", "m1_move_right"), Input.get_axis("m1_move_up", "m1_move_down"))
	if move.length() > 0.05:
		var view: Dictionary = building_world.get_building(selected_building_id)
		var transform_value: Variant = view.get("transform", Transform3D.IDENTITY)
		if transform_value is Transform3D:
			var forward := Vector3(sin(camera_yaw), 0.0, cos(camera_yaw))
			var right := Vector3(forward.z, 0.0, -forward.x)
			var speed := 2.2 if precision_mode else 4.5
			var local_delta := (transform_value as Transform3D).basis.inverse() * (right * move.x + forward * move.y) * delta * speed
			_addition_raw += local_delta
			var snap := RepairMassing.CELL if precision_mode else RepairMassing.CELL * 2.0
			var next_offset := portion_offset
			next_offset.x = snappedf(_addition_raw.x, snap)
			next_offset.z = snappedf(_addition_raw.z, snap)
			if not next_offset.is_equal_approx(portion_offset):
				portion_offset = next_offset
				_update_portion_preview()
	_read_part_orbit(delta)

func _repair_read_roof_accessory(delta: float) -> void:
	var move := Vector2(Input.get_axis("m1_move_left", "m1_move_right"), Input.get_axis("m1_move_up", "m1_move_down"))
	if move.length() > 0.05:
		var view: Dictionary = building_world.get_building(selected_building_id)
		var transform_value: Variant = view.get("transform", Transform3D.IDENTITY)
		var dimensions: Vector3 = view.get("dimensions", Vector3(15.0, 6.0, 12.0))
		var span_x := maxf(0.001, dimensions.x * 0.72)
		var span_z := maxf(0.001, dimensions.z * 0.72)
		var sections: Array[Dictionary] = RepairMassing.sections_for(view)
		if sections.size() > 1:
			var bounds := RepairMassing.union_bounds(sections)
			var inset := RepairMassing.CELL * 0.75
			span_x = maxf(0.001, bounds.size.x - inset * 2.0)
			span_z = maxf(0.001, bounds.size.y - inset * 2.0)
		if transform_value is Transform3D:
			var forward := Vector3(sin(camera_yaw), 0.0, cos(camera_yaw))
			var right := Vector3(forward.z, 0.0, -forward.x)
			var world_speed := 2.0 if precision_mode else 4.5
			var local_delta := (transform_value as Transform3D).basis.inverse() * (right * move.x + forward * move.y) * delta * world_speed
			var old := Vector2(roof_accessory_u, roof_accessory_v)
			roof_accessory_u = clampf(roof_accessory_u + local_delta.x / span_x, 0.05, 0.95)
			roof_accessory_v = clampf(roof_accessory_v + local_delta.z / span_z, 0.05, 0.95)
			if not old.is_equal_approx(Vector2(roof_accessory_u, roof_accessory_v)):
				_refresh_roof_accessory_preview()
	_read_part_orbit(delta)

func _repair_pick_roof_accessory(screen_point: Vector2) -> Dictionary:
	if not camera or selected_building_id.is_empty():
		return {}
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty():
		return {}
	var transform_value: Variant = view.get("transform", Transform3D.IDENTITY)
	if not transform_value is Transform3D:
		return {}
	var dimensions: Vector3 = view.get("dimensions", Vector3(15.0, 6.0, 12.0))
	var sections: Array[Dictionary] = RepairMassing.sections_for(view)
	var joined := sections.size() > 1
	var bounds := RepairMassing.union_bounds(sections) if joined else Rect2()
	var inset := RepairMassing.CELL * 0.75
	var profile := str(view.get("roof_profile", "gentle_gable"))
	var best: Dictionary = {}
	var best_distance := ROOF_PICK_RADIUS_PX
	for value in view.get("roof_accessories", []):
		if not value is Dictionary:
			continue
		var record: Dictionary = value
		var u := clampf(float(record.get("u", 0.5)), 0.05, 0.95)
		var v := clampf(float(record.get("v", 0.5)), 0.05, 0.95)
		var x := lerpf(bounds.position.x + inset, bounds.end.x - inset, u) if joined else lerpf(-dimensions.x * 0.36, dimensions.x * 0.36, u)
		var z := lerpf(bounds.position.y + inset, bounds.end.y - inset, v) if joined else lerpf(-dimensions.z * 0.36, dimensions.z * 0.36, v)
		var y := RepairMassing.roof_height_at(view, x, z) if joined else _roof_height_at(profile, dimensions, x, z)
		var world := (transform_value as Transform3D) * Vector3(x, y, z)
		if camera.is_position_behind(world):
			continue
		var projected := camera.unproject_position(world)
		var distance := projected.distance_to(screen_point)
		if distance < best_distance:
			best_distance = distance
			best = record.duplicate(true)
	return best

func _refresh_roof_accessories_for_visual(visual: Node3D, view: Dictionary, preview: Dictionary = {}) -> void:
	# Joined accessories derive their position from the section union, so massing
	# edits must invalidate the inherited dimensions-only accessory signature.
	var massing_signature := str(view.get("massing_sections", []))
	var existing := visual.get_node_or_null("M2RoofAccessories") as Node3D
	if existing and str(existing.get_meta("massing_signature", "")) != massing_signature:
		visual.remove_child(existing)
		existing.queue_free()
	super._refresh_roof_accessories_for_visual(visual, view, preview)
	var refreshed := visual.get_node_or_null("M2RoofAccessories") as Node3D
	if refreshed:
		refreshed.set_meta("massing_signature", massing_signature)
