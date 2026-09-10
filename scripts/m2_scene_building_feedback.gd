extends "res://scripts/m2_scene_path_feedback.gd"
## M2 playtest corrections for direct building-detail editing.

var _duplicate_detail_button: Button
var _duplicate_source_detail: Dictionary = {}

func _ready() -> void:
	super._ready()
	_install_duplicate_detail_action()

func _install_duplicate_detail_action() -> void:
	var box := _actions_box()
	if not box: return
	_duplicate_detail_button = Button.new()
	_duplicate_detail_button.name = "DuplicateDetailAction"
	_duplicate_detail_button.text = "Duplicate"
	_duplicate_detail_button.focus_mode = Control.FOCUS_ALL
	_duplicate_detail_button.custom_minimum_size = Vector2(0, 42)
	_duplicate_detail_button.pressed.connect(_begin_duplicate_selected_detail)
	box.add_child(_duplicate_detail_button)
	_tool_buttons["Duplicate selected detail"] = _duplicate_detail_button

func _update_action_buttons() -> void:
	super._update_action_buttons()
	if not _duplicate_detail_button: return
	var show := _context_actions_open and not selected_detail_id.is_empty() and hovered_detail_kind in ["window", "door", "shutter", "flower_box"]
	_duplicate_detail_button.visible = show
	_duplicate_detail_button.disabled = not show

func _begin_duplicate_selected_detail() -> void:
	if not _context_actions_open or selected_detail_id.is_empty(): return
	var source := _selected_detail_record()
	if source.is_empty(): return
	var kind := str(source.get("kind", ""))
	if kind not in ["window", "door", "shutter", "flower_box"]: return
	_duplicate_source_detail = source.duplicate(true)
	_context_actions_open = false
	_begin_new_attachment(kind)
	if not detail_move_active:
		_duplicate_source_detail.clear()
		return
	placement_asset_id = str(source.get("asset_id", placement_asset_id))
	var surface_id := str((source.get("anchor", {}) as Dictionary).get("surface_id", detail_move_surface_id))
	var source_position = source.get("resolved_position", null)
	var view: Dictionary = building_world.get_building(selected_building_id)
	if source_position is Vector3 and not surface_id.is_empty():
		var support := WallPlacement.surface(view, surface_id)
		var half := WallPlacement.footprint_for_detail(source)
		var axis := 0 if str(support.get("orientation", "front")) in ["front", "back"] else 2
		var intended: Vector3 = source_position
		intended[axis] += half.x * 2.0 + 0.25
		var available := WallPlacement.nearest_available(view, "", surface_id, intended, half)
		if available.is_empty():
			intended = source_position
			intended[axis] -= half.x * 2.0 + 0.25
			available = WallPlacement.nearest_available(view, "", surface_id, intended, half)
		if not available.is_empty():
			selected_surface_id = surface_id
			detail_move_surface_id = surface_id
			detail_move_original_surface_id = surface_id
			detail_move_position = available["position"]
	_set_status("Duplicate %s • left stick place on wall • A place / B cancel" % kind.replace("_", " "))
	_update_presentation()

func _commit_detail_move() -> bool:
	if _duplicate_source_detail.is_empty() or placement_kind.is_empty():
		return super._commit_detail_move()
	if not detail_move_active: return false
	var source_id := str(_duplicate_source_detail.get("id", ""))
	var kind := str(_duplicate_source_detail.get("kind", placement_kind))
	var new_id := _duplicate_detail_at(source_id, detail_move_surface_id, detail_move_position)
	var ok := not new_id.is_empty()
	detail_move_active = false
	if ok:
		selected_detail_id = new_id
		selected_surface_id = detail_move_surface_id
		_record_history("building")
	else:
		selected_detail_id = placement_previous_detail_id
		selected_surface_id = placement_previous_surface_id
	_duplicate_source_detail.clear()
	_clear_placement_state()
	_set_status(("%s duplicated" % kind.replace("_", " ").capitalize()) if ok else "Duplicate placement rejected")
	super._update_presentation()
	return ok

func _duplicate_detail_at(source_id: String, surface_id: String, local_position: Vector3) -> String:
	if source_id.is_empty() or surface_id.is_empty() or not local_position.is_finite(): return ""
	var building_index: int = building_world._building_index(selected_building_id)
	if building_index < 0: return ""
	var total_details := 0
	for value in building_world._document.get("buildings", []): total_details += ((value as Dictionary).get("details", []) as Array).size()
	if total_details >= 256: return ""
	var before: Dictionary = building_world.get_document()
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[building_index]
	var source_index: int = building_world._detail_index(building, source_id)
	if source_index < 0: return ""
	var source: Dictionary = (building["details"] as Array)[source_index]
	if str(source.get("state", "")) == "suppressed": return ""
	var copy: Dictionary = source.duplicate(true)
	var new_id: String = building_world._allocate_id("detail")
	copy["id"] = new_id
	copy["state"] = "manual"
	copy["generated"] = false
	copy["needs_placement"] = false
	copy.erase("default")
	copy.erase("suppressed_from_state")
	copy["anchor"] = {"surface_id": surface_id, "policy": "surface_local", "local_position": [local_position.x, local_position.y, local_position.z]}
	var overrides: Dictionary = (copy.get("override", {}) as Dictionary).duplicate(true)
	overrides.erase("surface_id")
	overrides.erase("local_position")
	overrides.erase("suppressed")
	if not str(copy.get("asset_id", "")).is_empty(): overrides["asset_id"] = str(copy["asset_id"])
	if overrides.is_empty(): copy.erase("override")
	else: copy["override"] = overrides
	var details: Array = building["details"]
	details.append(copy)
	building["details"] = details
	building_world._refresh_buckets(building)
	buildings[building_index] = building
	if not building_world._record_change(before): return ""
	return new_id

func _cancel_detail_move() -> void:
	var duplicating := not _duplicate_source_detail.is_empty()
	super._cancel_detail_move()
	if duplicating: _duplicate_source_detail.clear()

func _cancel_current_edit(reason: String) -> void:
	_duplicate_source_detail.clear()
	super._cancel_current_edit(reason)
