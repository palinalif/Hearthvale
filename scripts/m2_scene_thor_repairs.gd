extends "res://scripts/m2_scene_style_preview_stability.gd"

## Focused Thor playtest repairs. Keep heavy previews event-driven, preserve
## authoritative massing/window data, tame analog menu repeat, and make placed
## roof accessories directly editable again.
const RepairMassing = preload("res://scripts/m2_house_massing.gd")
const RepairSurfaces = preload("res://scripts/m2_massing_wall_surfaces.gd")

const ANALOG_NAV_INITIAL_DELAY_MS := 280
const ANALOG_NAV_REPEAT_MS := 140
const ANALOG_NAV_PRESS := 0.62
const ANALOG_NAV_RELEASE := 0.34
const ROOF_PICK_RADIUS_PX := 52.0

var _repair_portion_preview_signature := ""
var _repair_roof_accessory_edit_id := ""
var _repair_nav_axis_state: Dictionary = {}
var _repair_nav_next_ms: Dictionary = {}

func _input(event: InputEvent) -> void:
	if not roof_accessory_placement_active and _part_idle() and event.is_action_pressed("m1_accept"):
		_update_detail_hover()
		if hovered_detail_id.is_empty():
			var accessory: Dictionary = _repair_pick_roof_accessory(edit_pointer)
			if not accessory.is_empty():
				_begin_existing_roof_accessory(accessory)
				get_viewport().set_input_as_handled()
				return

	if event is InputEventJoypadMotion and _repair_menu_has_focus():
		var motion := event as InputEventJoypadMotion
		if motion.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
			var magnitude: float = absf(motion.axis_value)
			var axis_key: String = str(motion.axis)
			if magnitude <= ANALOG_NAV_RELEASE:
				_repair_nav_axis_state.erase(axis_key)
				_repair_nav_next_ms.erase(axis_key)
				get_viewport().set_input_as_handled()
				return
			if magnitude < ANALOG_NAV_PRESS:
				get_viewport().set_input_as_handled()
				return
			var direction: int = 1 if motion.axis_value > 0.0 else -1
			var state_key: String = "%s:%d" % [axis_key, direction]
			var now: int = Time.get_ticks_msec()
			var previous: String = str(_repair_nav_axis_state.get(axis_key, ""))
			var next_allowed: int = int(_repair_nav_next_ms.get(axis_key, 0))
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
			var speed: float = 2.2 if precision_mode else 4.5
			var local_delta := (transform_value as Transform3D).basis.inverse() * (right * move.x + forward * move.y) * delta * speed
			_addition_raw += local_delta
			var snap: float = RepairMassing.CELL if precision_mode else RepairMassing.CELL * 2.0
			var next_offset := portion_offset
			next_offset.x = snappedf(_addition_raw.x, snap)
			next_offset.z = snappedf(_addition_raw.z, snap)
			if not next_offset.is_equal_approx(portion_offset):
				portion_offset = next_offset
				_update_portion_preview()
	_read_part_orbit(delta)

func _repair_read_roof_accessory(delta: float) -> void:
	# The final stability subclass supplies joined-house coordinate spans. This
	# fallback keeps rectangular houses camera-relative as well.
	var move := Vector2(Input.get_axis("m1_move_left", "m1_move_right"), Input.get_axis("m1_move_up", "m1_move_down"))
	if move.length() > 0.05:
		var view: Dictionary = building_world.get_building(selected_building_id)
		var transform_value: Variant = view.get("transform", Transform3D.IDENTITY)
		var dimensions: Vector3 = view.get("dimensions", Vector3(15.0, 6.0, 12.0))
		if transform_value is Transform3D:
			var forward := Vector3(sin(camera_yaw), 0.0, cos(camera_yaw))
			var right := Vector3(forward.z, 0.0, -forward.x)
			var world_speed: float = 2.0 if precision_mode else 4.5
			var local_delta := (transform_value as Transform3D).basis.inverse() * (right * move.x + forward * move.y) * delta * world_speed
			var old := Vector2(roof_accessory_u, roof_accessory_v)
			roof_accessory_u = clampf(roof_accessory_u + local_delta.x / maxf(0.001, dimensions.x * 0.72), 0.05, 0.95)
			roof_accessory_v = clampf(roof_accessory_v + local_delta.z / maxf(0.001, dimensions.z * 0.72), 0.05, 0.95)
			if not old.is_equal_approx(Vector2(roof_accessory_u, roof_accessory_v)):
				_refresh_roof_accessory_preview()
	_read_part_orbit(delta)

func _begin_portion_placement() -> void:
	_repair_portion_preview_signature = ""
	_addition_raw = Vector3.ZERO
	_addition_was_active = false
	super._begin_portion_placement()

func _update_portion_preview() -> void:
	if not portion_placement_active:
		return
	var revision: int = building_world.get_revision() if building_world else -1
	var signature: String = str([selected_building_id, portion_revision, revision, portion_offset, portion_size])
	if signature == _repair_portion_preview_signature:
		return
	_repair_portion_preview_signature = signature
	super._update_portion_preview()

func _clear_portion_placement() -> void:
	_repair_portion_preview_signature = ""
	_addition_raw = Vector3.ZERO
	_addition_was_active = false
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
	var prepared: Dictionary = _repair_prepare_massing_document(sections, "custom", true)
	var ok: bool = _repair_commit_prepared_massing(prepared)
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
	var prepared: Dictionary = _repair_prepare_massing_document(sections, "" if preset_id == "rectangle" else preset_id, false)
	var ok: bool = _repair_commit_prepared_massing(prepared)
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
	var prepared: Dictionary = _repair_prepare_massing_document(sections, "custom" if sections.size() > 1 else "", false)
	var ok: bool = _repair_commit_prepared_massing(prepared)
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
	var temp := building_world.get_script().new() as RefCounted
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
	var profile: String = str(view.get("roof_profile", "gentle_gable"))
	var best: Dictionary = {}
	var best_distance: float = ROOF_PICK_RADIUS_PX
	for value in view.get("roof_accessories", []):
		if not value is Dictionary:
			continue
		var record: Dictionary = value
		var u: float = clampf(float(record.get("u", 0.5)), 0.05, 0.95)
		var v: float = clampf(float(record.get("v", 0.5)), 0.05, 0.95)
		var x: float = lerpf(-dimensions.x * 0.36, dimensions.x * 0.36, u)
		var z: float = lerpf(-dimensions.z * 0.36, dimensions.z * 0.36, v)
		var local := Vector3(x, _roof_height_at(profile, dimensions, x, z), z)
		var world := (transform_value as Transform3D) * local
		if camera.is_position_behind(world):
			continue
		var distance: float = camera.unproject_position(world).distance_to(screen_point)
		if distance < best_distance:
			best_distance = distance
			best = record.duplicate(true)
	return best

func _begin_existing_roof_accessory(record: Dictionary) -> void:
	if record.is_empty():
		return
	_repair_roof_accessory_edit_id = str(record.get("id", ""))
	roof_accessory_placement_active = true
	roof_accessory_asset_id = str(record.get("asset_id", ""))
	roof_accessory_u = float(record.get("u", 0.5))
	roof_accessory_v = float(record.get("v", 0.5))
	roof_accessory_yaw = float(record.get("yaw", 0.0))
	tools_open = false
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
	super._clear_roof_accessory_placement()

func _refresh_roof_accessories_for_visual(visual: Node3D, view: Dictionary, preview: Dictionary = {}) -> void:
	if _repair_roof_accessory_edit_id.is_empty():
		super._refresh_roof_accessories_for_visual(visual, view, preview)
		return
	var filtered: Dictionary = view.duplicate(true)
	var records: Array = []
	for value in view.get("roof_accessories", []):
		if value is Dictionary and str((value as Dictionary).get("id", "")) != _repair_roof_accessory_edit_id:
			records.append((value as Dictionary).duplicate(true))
	filtered["roof_accessories"] = records
	super._refresh_roof_accessories_for_visual(visual, filtered, preview)
