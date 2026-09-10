extends "res://scripts/m2_scene_compact_colours.gd"

var _attachment_preview_revision := -1

func _begin_detail_move() -> void:
	# Saved anchors contain JSON arrays. Always initialise from THIS selected
	# record, including the saved local position of a recoverable attachment.
	var detail: Dictionary = _selected_detail_record()
	if detail.is_empty(): return
	var local: Variant = detail.get("resolved_position", null)
	if not local is Vector3:
		var saved: Variant = (detail.get("anchor", {}) as Dictionary).get("local_position", null)
		local = Vector3(float(saved[0]), float(saved[1]), float(saved[2])) if saved is Array and saved.size() == 3 else Vector3.ZERO
	if not (local as Vector3).is_finite(): return
	detail_move_position = local
	_attachment_preview_revision = building_world.get_revision()
	super._begin_detail_move()

func _begin_new_attachment(kind: String) -> void:
	_attachment_preview_revision = building_world.get_revision()
	super._begin_new_attachment(kind)

func _begin_duplicate_selected_detail() -> void:
	super._begin_duplicate_selected_detail()
	if detail_move_active: _detail_free_position = detail_move_position

func _read_detail_move(delta: float) -> void:
	if not detail_move_active or resize_locked: return
	var stick := Vector2(Input.get_axis("m1_move_left", "m1_move_right"), Input.get_axis("m1_move_up", "m1_move_down"))
	# Simply picking up a window is not a request to snap it to a neighbour.
	if stick.length() <= 0.05: return
	var view: Dictionary = building_world.get_building(selected_building_id)
	var support := WallPlacement.surface(view, detail_move_surface_id)
	if support.is_empty(): return
	var orientation := str(support.get("orientation", "front"))
	var axis := 0 if orientation in ["front", "back"] else 2
	var transform_value: Transform3D = view["transform"]
	var tangent := (transform_value.basis * (Vector3.RIGHT if axis == 0 else Vector3.BACK)).normalized()
	var horizontal_sign := 1.0 if tangent.dot(camera.global_basis.x) >= 0 else -1.0
	var speed := (0.9 if precision_mode else 3.0) * pow(minf(stick.length(), 1.0), 0.45)
	_detail_free_position[axis] += stick.x * horizontal_sign * delta * speed
	_detail_free_position.y -= stick.y * delta * speed
	var half := _attachment_preview_half(_attachment_preview_detail())
	var clamped := WallPlacement.clamp_to_wall(view, detail_move_surface_id, _detail_free_position, half)
	if clamped.is_empty(): return
	_detail_free_position = clamped["position"]
	var aligned := WallAlignment.align(view, selected_detail_id, detail_move_surface_id, _detail_free_position, precision_mode)
	var final := WallPlacement.clamp_to_wall(view, detail_move_surface_id, aligned["position"], half)
	detail_move_position = final.get("position", _detail_free_position)
	_alignment_tangent = bool(aligned.get("tangent", false))
	_alignment_height = bool(aligned.get("height", false))
	_alignment_tangent_source = str(aligned.get("tangent_source", ""))
	_alignment_height_source = str(aligned.get("height_source", ""))
	_update_alignment_hud()
	_update_presentation()

func _cycle_attachment_surface(direction: int) -> void:
	if not detail_move_active or direction == 0: return
	var view: Dictionary = building_world.get_building(selected_building_id)
	var walls := WallPlacement.wall_ids(view)
	var start := walls.find(detail_move_surface_id)
	if start < 0: return
	var half := _attachment_preview_half(_attachment_preview_detail())
	for step in range(1, walls.size()):
		var next := walls[posmod(start + step * direction, walls.size())]
		var remapped := WallPlacement.remap_between_walls(view, detail_move_surface_id, next, detail_move_position, half)
		if remapped.is_empty(): continue
		detail_move_surface_id = next
		selected_surface_id = next
		detail_move_position = remapped["position"]
		_detail_free_position = detail_move_position
		_clear_alignment()
		_update_presentation()
		_set_status(WallPlacement.surface_label(view, next))
		return
	_set_status("No other wall fits this detail")

func _attachment_preview_detail() -> Dictionary:
	if placement_kind.is_empty(): return _selected_detail_record()
	if not _duplicate_source_detail.is_empty(): return _duplicate_source_detail
	return {"kind": placement_kind, "asset_id": placement_asset_id}

func _attachment_preview_half(detail: Dictionary) -> Vector2:
	if not placement_kind.is_empty() and _duplicate_source_detail.is_empty():
		return WallPlacement.footprint(placement_kind, placement_asset_id)
	return WallPlacement.footprint_for_detail(detail)

func _attachment_preview_valid() -> bool:
	var detail := _attachment_preview_detail()
	if detail.is_empty(): return false
	var view: Dictionary = building_world.get_building(selected_building_id)
	return WallPlacement.position_available(view, selected_detail_id if placement_kind.is_empty() else "", detail_move_surface_id, detail_move_position, _attachment_preview_half(detail))

func _update_placement_ghost() -> void:
	if not placement_ghost or not detail_move_active: return
	var detail := _attachment_preview_detail()
	if detail.is_empty(): return
	var view: Dictionary = building_world.get_building(selected_building_id)
	var support: Dictionary = WallPlacement.surface(view, detail_move_surface_id)
	if support.is_empty(): return
	placement_ghost.show_attachment(view.get("transform", Transform3D.IDENTITY), str(support.get("orientation", "front")), detail_move_position, str(detail.get("kind", "window")), detail, _attachment_preview_half(detail), _attachment_preview_valid(), not placement_kind.is_empty())

func _update_presentation() -> void:
	super._update_presentation()
	if detail_move_active: _update_placement_ghost()

func _commit_detail_move() -> bool:
	if not detail_move_active: return false
	if _attachment_preview_revision >= 0 and _attachment_preview_revision != building_world.get_revision():
		_cancel_detail_move()
		_set_status("Placement cancelled: house changed")
		return false
	if not _attachment_preview_valid():
		_set_status("Cannot place here: detail overlaps or does not fit")
		return false
	return super._commit_detail_move()
