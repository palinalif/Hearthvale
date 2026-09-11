extends "res://scripts/m2_scene_style_preview_stability.gd"

## Device-playtest repairs. Keep expensive massing previews event-driven, route
## massing commits through the same surface/window repair contract as resize,
## make roof decor camera-relative and directly re-editable, and tame analog
## menu repeat without affecting D-pad navigation.
const RepairMassing = preload("res://scripts/m2_house_massing.gd")
const RepairSurfaces = preload("res://scripts/m2_massing_wall_surfaces.gd")
const RepairFacade = preload("res://scripts/facade_depth_layout.gd")

const ANALOG_NAV_INITIAL_DELAY_MS := 280
const ANALOG_NAV_REPEAT_MS := 140
const ANALOG_NAV_PRESS := 0.62
const ANALOG_NAV_RELEASE := 0.34
const ROOF_PICK_RADIUS_PX := 52.0

var _repair_portion_preview_signature := ""
var _repair_roof_accessory_edit_id := ""
var _repair_roof_accessory_original: Dictionary = {}
var _repair_nav_axis_state: Dictionary = {}
var _repair_nav_next_ms: Dictionary = {}

func _input(event: InputEvent) -> void:
	# A placed roof accessory behaves like every other authored detail: point at
	# it and press A to pick it up again. Do this before the roof surface picker.
	if not roof_accessory_placement_active and _part_idle() and event.is_action_pressed("m1_accept"):
		_update_detail_hover()
		if hovered_detail_id.is_empty():
			var accessory := _repair_pick_roof_accessory(edit_pointer)
			if not accessory.is_empty():
				_begin_existing_roof_accessory(accessory)
				get_viewport().set_input_as_handled()
				return

	# Godot emits repeated JoypadMotion events while a stick is held. Menus were
	# treating each one like a fresh D-pad press, which could skip several cards
	# in a fraction of a second. D-pad/button events never enter this throttle.
	if event is InputEventJoypadMotion and _repair_menu_has_focus():
		var motion := event as InputEventJoypadMotion
		if motion.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
			var magnitude := absf(motion.axis_value)
			var axis_key := str(motion.axis)
			if magnitude <= ANALOG_NAV_RELEASE:
				_repair_nav_axis_state.erase(axis_key)
				_repair_nav_next_ms.erase(axis_key)
				get_viewport().set_input_as_handled()
				return
			if magnitude < ANALOG_NAV_PRESS:
				get_viewport().set_input_as_handled()
				return
			var direction := 1 if motion.axis_value > 0.0 else -1
			var state_key := "%s:%d" % [axis_key, direction]
			var now := Time.get_ticks_msec()
			var previous := str(_repair_nav_axis_state.get(axis_key, ""))
			var next_allowed := int(_repair_nav_next_ms.get(axis_key, 0))
			if previous != state_key:
				_repair_nav_axis_state[axis_key] = state_key
				_repair_nav_next_ms[axis_key] = now + ANALOG_NAV_INITIAL_DELAY_MS
				super._input(event)
				return
			if now >= next_allowed:
				_repair_nav_next_ms[axis_key] = now + ANALOG_NAV_REPEAT_MS
				super._input(event)
				return
			get_viewport().set_input_as_handled()
			return

	super._input(event)

func _repair_menu_has_focus() -> bool:
	if roof_accessory_placement_active or portion_placement_active or detail_move_active or building_placement_active:
		return false
	return get_viewport().gui_get_focus_owner() != null

func _read_camera_and_cursor(delta: float) -> void:
	if roof_accessory_placement_active:
		_repair_read_roof_accessory(delta)
		return
	if portion_placement_active:
		_repair_read_portion(delta)
		return
	super._read_camera_and_cursor(delta)

func _repair_read_portion(delta: float) -> void:
	# Accumulate smooth camera-relative movement, but only rebuild when snapping
	# actually changes the candidate. Previously this rebuilt every held-stick
	# frame and reduced the Thor to single-digit FPS.
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
			var next_offset := portion_offset
			next_offset.x = snappedf(_addition_raw.x, RepairMassing.CELL)
			next_offset.z = snappedf(_addition_raw.z, RepairMassing.CELL)
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
		if transform_value is Transform3D:
			var forward := Vector3(sin(camera_yaw), 0.0, cos(camera_yaw))
			var right := Vector3(forward.z, 0.0, -forward.x)
			var world_speed := 2.0 if precision_mode else 4.5
			var local_delta := (transform_value as Transform3D).basis.inverse() * (right * move.x + forward * move.y) * delta * world_speed
			var old := Vector2(roof_accessory_u, roof_accessory_v)
			roof_accessory_u = clampf(roof_accessory_u + local_delta.x / maxf(0.001, dimensions.x * 0.72), 0.05, 0.95)
			roof_accessory_v = clampf(roof_accessory_v + local_delta.z / maxf(0.001, dimensions.z * 0.72), 0.05, 0.95)
			if not old.is_equal_approx(Vector2(roof_accessory_u, roof_accessory_v)):
				_refresh_roof_accessory_preview()
	_read_part_orbit(delta)

func _begin_portion_placement() -> void:
	_repair_portion_preview_signature = ""
	super._begin_portion_placement()

func _update_portion_preview() -> void:
	if not portion_placement_active:
		return
	var signature := str([
		selected_building_id,
		portion_revision,
		building_world.get_revision() if building_world else -1,
		portion_offset,
		portion_size,
	])
	if signature == _repair_portion_preview_signature:
		return
	_repair_portion_preview_signature = signature
	super._update_portion_preview()

func _clear_portion_placement() -> void:
	_repair_portion_preview_signature = ""
	super._clear_portion_placement()

func _commit_portion_placement() -> bool:
	if not portion_placement_active:
		return false
	_update_portion_preview()
	if not portion_valid:
		_set_status("Cannot add portion: %s" % portion_reason)
		return false
	var view: Dictionary = building_world.get_building(selected_building_id)
	var sections: Array[Dictionary] = RepairMassing.sections_for(view)
	sections.append(_candidate_portion("__allocate__"))
	var prepared := _repair_prepare_massing_document(sections, "custom", true)
	var ok := _repair_commit_prepared_massing(prepared)
	_clear_portion_placement()
	if ok:
		_record_history("building")
		_presentation_key = ""
		_update_presentation()
		_set_status("House portion joined • %d total portions" % RepairMassing.sections_for(building_world.get_building(selected_building_id)).size())
	else:
		_set_status("House portion could not be saved")
	return ok

func _apply_house_shape_preset(preset_id: String) -> bool:
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty():
		return false
	var sections: Array[Dictionary] = RepairMassing.sections_for(view) if preset_id == "rectangle" else RepairMassing.preset_sections(view, preset_id)
	if preset_id == "rectangle" and not sections.is_empty():
		sections = [sections[0]]
	var prepared := _repair_prepare_massing_document(sections, "" if preset_id == "rectangle" else preset_id, false)
	var ok := _repair_commit_prepared_massing(prepared)
	_close_house_shape_picker(false)
	if ok:
		_record_history("building")
		_presentation_key = ""
		_update_presentation()
		_set_status("House shape: %s" % RepairMassing.shape_name(building_world.get_building(selected_building_id)))
	else:
		_set_status("House shape unchanged")
	return ok

func _remove_last_portion() -> bool:
	var view: Dictionary = building_world.get_building(selected_building_id)
	var sections: Array[Dictionary] = RepairMassing.sections_for(view)
	if sections.size() <= 1:
		_set_status("This house has no added portions")
		return false
	sections.pop_back()
	var prepared := _repair_prepare_massing_document(sections, "custom" if sections.size() > 1 else "", false)
	var ok := _repair_commit_prepared_massing(prepared)
	_close_house_shape_picker(false)
	if ok:
		_record_history("building")
		_presentation_key = ""
		_update_presentation()
		_set_status("Removed last house portion")
	return ok

func _repair_prepare_massing_document(sections: Array[Dictionary], preset: String, allocate_placeholder: bool) -> Dictionary:
	if not building_world or selected_building_id.is_empty():
		return {}
	var temp = building_world.get_script().new()
	temp._document = building_world.get_document()
	temp._next_id = int(temp._document.get("next_id", building_world._next_id))
	temp._revision = building_world.get_revision()
	var index: int = temp._building_index(selected_building_id)
	if index < 0:
		return {}
	var normalized: Array[Dictionary] = []
	for value in sections:
		var section: Dictionary = value.duplicate(true)
		if allocate_placeholder and str(section.get("id", "")) == "__allocate__":
			section["id"] = temp._allocate_id("portion")
		normalized.append(section)
	var recipe: Dictionary = temp._document["buildings"][index]
	if normalized.size() <= 1:
		recipe.erase("massing_sections")
		recipe.erase("massing_preset")
	else:
		recipe["massing_sections"] = _serialize_sections(normalized)
		recipe["massing_preset"] = preset if not preset.is_empty() else "custom"
	# This is the critical contract the old add/remove/preset paths skipped.
	# Rebuild stable wall supports, then let the authoritative window layout
	# reflow onto those supports before resolving buckets/visibility.
	if not RepairSurfaces.sync_building(temp, recipe):
		return {}
	temp._reflow_automatic_windows(recipe)
	temp._refresh_buckets(recipe)
	if not temp._validate_document(temp._document):
		return {}
	return {"document": temp.get_document(), "next_id": temp._next_id}

func _repair_commit_prepared_massing(prepared: Dictionary) -> bool:
	if prepared.is_empty():
		return false
	var before: Dictionary = building_world.get_document()
	var old_next: int = building_world._next_id
	building_world._document = prepared["document"]
	building_world._next_id = int(prepared["next_id"])
	building_world._document["next_id"] = building_world._next_id
	var ok: bool = building_world._record_change(before)
	if not ok:
		building_world._document = before
		building_world._next_id = old_next
	return ok

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
	var profile := str(view.get("roof_profile", "gentle_gable"))
	var best: Dictionary = {}
	var best_distance := ROOF_PICK_RADIUS_PX
	for value in view.get("roof_accessories", []):
		if not value is Dictionary:
			continue
		var record: Dictionary = value
		var u := clampf(float(record.get("u", 0.5)), 0.05, 0.95)
		var v := clampf(float(record.get("v", 0.5)), 0.05, 0.95)
		var x := lerpf(-dimensions.x * 0.36, dimensions.x * 0.36, u)
		var z := lerpf(-dimensions.z * 0.36, dimensions.z * 0.36, v)
		var local := Vector3(x, _roof_height_at(profile, dimensions, x, z), z)
		var world := (transform_value as Transform3D) * local
		if camera.is_position_behind(world):
			continue
		var projected := camera.unproject_position(world)
		var distance := projected.distance_to(screen_point)
		if distance < best_distance:
			best_distance = distance
			best = record.duplicate(true)
	return best

func _begin_existing_roof_accessory(record: Dictionary) -> void:
	if record.is_empty():
		return
	_repair_roof_accessory_edit_id = str(record.get("id", ""))
	_repair_roof_accessory_original = record.duplicate(true)
	roof_accessory_placement_active = true
	roof_accessory_asset_id = str(record.get("asset_id", ""))
	roof_accessory_u = float(record.get("u", 0.5))
	roof_accessory_v = float(record.get("v", 0.5))
	roof_accessory_yaw = float(record.get("yaw", 0.0))
	tools_open = true
	_refresh_roof_accessory_preview()
	_set_status("Move %s • left stick camera-relative • D-pad rotate • A place / B cancel" % _roof_accessory_label(roof_accessory_asset_id))
	_refresh_controller_hud()

func _commit_roof_accessory_placement() -> bool:
	if _repair_roof_accessory_edit_id.is_empty():
		return super._commit_roof_accessory_placement()
	var index: int = building_world._building_index(selected_building_id)
	if index < 0:
		return false
	var before: Dictionary = building_world._copy(building_world._document)
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[index]
	var accessories: Array = building.get("roof_accessories", [])
	var found := false
	for accessory_index in accessories.size():
		var record: Dictionary = accessories[accessory_index]
		if str(record.get("id", "")) != _repair_roof_accessory_edit_id:
			continue
		record["u"] = clampf(roof_accessory_u, 0.05, 0.95)
		record["v"] = clampf(roof_accessory_v, 0.05, 0.95)
		record["yaw"] = roof_accessory_yaw
		accessories[accessory_index] = record
		found = true
		break
	if not found:
		return false
	building["roof_accessories"] = accessories
	buildings[index] = building
	var ok: bool = building_world._record_change(before)
	if ok:
		_record_history("building")
	_clear_roof_accessory_placement()
	_presentation_key = ""
	_update_presentation()
	_set_status("Roof accessory moved" if ok else "Roof accessory could not be moved")
	return ok

func _clear_roof_accessory_placement() -> void:
	_repair_roof_accessory_edit_id = ""
	_repair_roof_accessory_original = {}
	super._clear_roof_accessory_placement()

func _refresh_roof_accessories_for_visual(visual: Node3D, view: Dictionary, preview: Dictionary = {}) -> void:
	if _repair_roof_accessory_edit_id.is_empty():
		super._refresh_roof_accessories_for_visual(visual, view, preview)
		return
	var filtered := view.duplicate(true)
	var records: Array = []
	for value in view.get("roof_accessories", []):
		if value is Dictionary and str((value as Dictionary).get("id", "")) != _repair_roof_accessory_edit_id:
			records.append((value as Dictionary).duplicate(true))
	filtered["roof_accessories"] = records
	super._refresh_roof_accessories_for_visual(visual, filtered, preview)

func _update_presentation() -> void:
	super._update_presentation()
	_repair_postprocess_visuals()

func _refresh_massing_shell_for_visual(visual: Node3D, view: Dictionary) -> void:
	super._refresh_massing_shell_for_visual(visual, view)
	_repair_tudor_joined_frame(visual, view)
	_repair_facade_offsets(visual, view)

func _repair_postprocess_visuals() -> void:
	if not building_world:
		return
	for building_id_value in cottage_visuals.keys():
		var id := str(building_id_value)
		var visual := cottage_visuals.get(id, null) as Node3D
		var view := building_world.get_building(id)
		if visual and not view.is_empty():
			_repair_tudor_joined_frame(visual, view)
			_repair_facade_offsets(visual, view)

func _repair_facade_offsets(visual: Node3D, view: Dictionary) -> void:
	var detail_value = visual.get("_detail_unit")
	if not detail_value is Vector3:
		return
	var detail_unit: Vector3 = detail_value
	var runs := RepairFacade.wall_runs(view)
	if runs.is_empty():
		return
	_repair_shift_facade_batch(visual.get_node_or_null("M2FacadeWindowLintels") as MultiMeshInstance3D, runs, detail_unit, true)
	_repair_shift_facade_batch(visual.get_node_or_null("M2FacadePlinth") as MultiMeshInstance3D, runs, detail_unit, false)

func _repair_shift_facade_batch(node: MultiMeshInstance3D, runs: Array[Dictionary], detail_unit: Vector3, inward: bool) -> void:
	if not node or not node.multimesh or bool(node.get_meta("thor_offset_repaired", false)):
		return
	var mm := node.multimesh
	for index in mm.instance_count:
		var transform := mm.get_instance_transform(index)
		var point := transform.origin
		var best: Dictionary = {}
		var best_distance := INF
		for run in runs:
			var orientation := str(run.get("orientation", ""))
			var tangent := point.x if orientation in ["front", "back"] else point.z
			if tangent < float(run.get("tangent_min", 0.0)) - 0.5 or tangent > float(run.get("tangent_max", 0.0)) + 0.5:
				continue
			var normal_value := point.z if orientation in ["front", "back"] else point.x
			var distance := absf(normal_value - float(run.get("normal", 0.0)))
			if distance < best_distance:
				best_distance = distance
				best = run
		if best.is_empty():
			continue
		var orientation := str(best["orientation"])
		var axis := 2 if orientation in ["front", "back"] else 0
		var wall_normal := float(best["normal"])
		var current := point[axis]
		var cell := detail_unit.z if axis == 2 else detail_unit.x
		if inward:
			point[axis] = move_toward(current, wall_normal, cell)
		else:
			var outward := -1.0 if orientation in ["front", "left"] else 1.0
			point[axis] = current + outward * cell * 0.12
		transform.origin = point
		mm.set_instance_transform(index, transform)
	node.set_meta("thor_offset_repaired", true)

func _repair_tudor_joined_frame(visual: Node3D, view: Dictionary) -> void:
	var existing := visual.get_node_or_null("M2TudorJoinedFrame")
	if str(view.get("style_id", "")) != "village_gable" or RepairMassing.sections_for(view).size() <= 1:
		if existing:
			visual.remove_child(existing)
			existing.queue_free()
		_repair_filter_native_tudor(visual, view)
		return
	var signature := str([view.get("massing_sections", []), view.get("surfaces", []), view.get("details", [])])
	if existing and str(existing.get_meta("signature", "")) == signature:
		return
	if existing:
		visual.remove_child(existing)
		existing.queue_free()
	var detail_value = visual.get("_detail_unit")
	if not detail_value is Vector3:
		return
	var unit: Vector3 = detail_value
	var boxes: Array[Dictionary] = []
	for run in RepairFacade.wall_runs(view):
		var orientation := str(run["orientation"])
		var low := float(run["tangent_min"])
		var high := float(run["tangent_max"])
		var bottom := float(run["bottom"])
		var top := float(run["top"])
		var normal := float(run["normal"])
		var outward := -1.0 if orientation in ["front", "left"] else 1.0
		var normal_cell := unit.z if orientation in ["front", "back"] else unit.x
		var tangent_cell := unit.x if orientation in ["front", "back"] else unit.z
		var face := normal + outward * normal_cell * 1.05
		for tangent in [low + tangent_cell, high - tangent_cell]:
			boxes.append(_repair_axis_box(orientation, tangent, (bottom + top) * 0.5, face, tangent_cell * 2.0, maxf(unit.y, top - bottom - unit.y), normal_cell * 2.0))
		for rail_y in [bottom + 1.0, top - unit.y * 2.0]:
			var cuts := _repair_opening_cuts(view, str(run.get("surface_id", "")), orientation, rail_y, unit.y * 2.0)
			for segment in RepairFacade.subtract_intervals(low, high, cuts):
				if segment.y - segment.x < tangent_cell * 2.0:
					continue
				boxes.append(_repair_axis_box(orientation, (segment.x + segment.y) * 0.5, rail_y, face, segment.y - segment.x, unit.y * 2.0, normal_cell * 2.0))
	if boxes.is_empty():
		return
	var node_value = visual.call("_add_detail_boxes", "M2TudorJoinedFrame", boxes, Color("#634d42"))
	if node_value is Node:
		(node_value as Node).set_meta("signature", signature)

func _repair_filter_native_tudor(visual: Node3D, view: Dictionary) -> void:
	var node := visual.get_node_or_null("TudorWallFrame") as MultiMeshInstance3D
	if not node or not node.multimesh or bool(node.get_meta("opening_filtered", false)):
		return
	var openings: Array[AABB] = []
	var orientations: Dictionary = {}
	for surface_value in view.get("surfaces", []):
		if surface_value is Dictionary:
			orientations[str((surface_value as Dictionary).get("id", ""))] = str((surface_value as Dictionary).get("orientation", "front"))
	for detail_value in view.get("details", []):
		if not detail_value is Dictionary:
			continue
		var detail: Dictionary = detail_value
		var kind := str(detail.get("kind", ""))
		if kind not in ["window", "door"] or not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)):
			continue
		var local = detail.get("resolved_position", null)
		if not local is Vector3:
			continue
		var size := _repair_detail_size(detail, Vector2(1.75, 3.7) if kind == "door" else Vector2(2.0, 2.8))
		var surface_id := str((detail.get("anchor", {}) as Dictionary).get("surface_id", ""))
		var orientation := str(orientations.get(surface_id, "front"))
		var thickness := 1.0
		var box_size := Vector3(size.x + 0.18, size.y + 0.18, thickness) if orientation in ["front", "back"] else Vector3(thickness, size.y + 0.18, size.x + 0.18)
		openings.append(AABB((local as Vector3) - box_size * 0.5, box_size))
	if openings.is_empty() or not node.multimesh.mesh:
		node.set_meta("opening_filtered", true)
		return
	var mm := node.multimesh
	var mesh_box := mm.mesh.get_aabb()
	var kept: Array[Transform3D] = []
	for index in mm.instance_count:
		var transform := mm.get_instance_transform(index)
		var bounds: AABB = transform * mesh_box
		var blocked := false
		for opening in openings:
			if bounds.intersects(opening):
				blocked = true
				break
		if not blocked:
			kept.append(transform)
	mm.instance_count = kept.size()
	for index in kept.size():
		mm.set_instance_transform(index, kept[index])
	node.set_meta("opening_filtered", true)

func _repair_opening_cuts(view: Dictionary, surface_id: String, orientation: String, rail_y: float, rail_height: float) -> Array[Vector2]:
	var cuts: Array[Vector2] = []
	for value in view.get("details", []):
		if not value is Dictionary:
			continue
		var detail: Dictionary = value
		var kind := str(detail.get("kind", ""))
		if kind not in ["window", "door"] or not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)):
			continue
		if str((detail.get("anchor", {}) as Dictionary).get("surface_id", "")) != surface_id:
			continue
		var local = detail.get("resolved_position", null)
		if not local is Vector3:
			continue
		var size := _repair_detail_size(detail, Vector2(1.75, 3.7) if kind == "door" else Vector2(2.0, 2.8))
		if absf((local as Vector3).y - rail_y) > size.y * 0.5 + rail_height * 0.5:
			continue
		var tangent := (local as Vector3).x if orientation in ["front", "back"] else (local as Vector3).z
		cuts.append(Vector2(tangent - size.x * 0.5 - 0.12, tangent + size.x * 0.5 + 0.12))
	return cuts

func _repair_detail_size(detail: Dictionary, fallback: Vector2) -> Vector2:
	var overrides = detail.get("override", {})
	if overrides is Dictionary:
		var value = (overrides as Dictionary).get("size", null)
		if value is Array and (value as Array).size() == 2:
			return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return fallback

func _repair_axis_box(orientation: String, tangent: float, y: float, normal: float, tangent_size: float, y_size: float, normal_size: float) -> Dictionary:
	if orientation in ["front", "back"]:
		return {"center": Vector3(tangent, y, normal), "size": Vector3(tangent_size, y_size, normal_size), "basis": Basis.IDENTITY}
	return {"center": Vector3(normal, y, tangent), "size": Vector3(normal_size, y_size, tangent_size), "basis": Basis.IDENTITY}
