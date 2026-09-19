extends "res://scripts/m2_scene_multi_floor.gd"

## Final M2 integration layer for editable upper-storey facades. The M1 world is
## inherited from the scene chain; this environment only overrides the
## building-world factory so the M2-aware BuildingWorld subclass is built in place.
const M2BuildingWorldScript = preload("res://scripts/m2_building_world.gd")
const MassingSurfaces = preload("res://scripts/m2_massing_wall_surfaces.gd")

var _massing_surface_sync_revision := -1

## The base _build_world calls this factory, so the M2 world is constructed once,
## in place (no double-build of the base BuildingWorld).
func _create_building_world() -> RefCounted:
	return M2BuildingWorldScript.new()

func _apply_house_shape_preset(preset_id: String) -> bool:
	var index: int = building_world._building_index(selected_building_id)
	if index < 0: return false
	var before: Dictionary = building_world._copy(building_world._document)
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[index]
	if preset_id == "rectangle":
		building.erase("massing_sections")
		building.erase("massing_preset")
	else:
		var view: Dictionary = building_world.get_building(selected_building_id)
		building["massing_sections"] = _serialize_sections(HouseMassing.preset_sections(view, preset_id))
		building["massing_preset"] = preset_id
	if not _sync_surface_record(building):
		building_world._document = before
		_set_status("House shape has too many editable wall runs")
		return false
	building_world._refresh_buckets(building)
	buildings[index] = building
	var ok: bool = building_world._record_change(before)
	_close_house_shape_picker(false)
	if ok:
		_record_history("building")
		_presentation_key = ""
		_update_presentation()
		_set_status("House shape: %s" % HouseMassing.shape_name(building_world.get_building(selected_building_id)))
	else:
		_set_status("House shape unchanged")
	return ok

func _commit_portion_placement() -> bool:
	if not portion_placement_active: return false
	_update_portion_preview()
	if not portion_valid:
		_set_status("Cannot add portion: %s" % portion_reason)
		return false
	var index: int = building_world._building_index(selected_building_id)
	if index < 0: return false
	var committed_level: int = portion_level
	var before: Dictionary = building_world._copy(building_world._document)
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[index]
	var view: Dictionary = building_world.get_building(selected_building_id)
	var sections: Array[Dictionary] = HouseMassing.sections_for(view)
	var portion_id: String = building_world._allocate_id("portion")
	sections.append(_candidate_portion(portion_id))
	building["massing_sections"] = _serialize_sections(sections)
	building["massing_preset"] = "custom"
	if not _sync_surface_record(building):
		building_world._document = before
		_clear_portion_placement()
		_set_status("Cannot add portion: too many editable wall runs")
		return false
	building_world._refresh_buckets(building)
	buildings[index] = building
	var ok: bool = building_world._record_change(before)
	_clear_portion_placement()
	if ok:
		_record_history("building")
		_presentation_key = ""
		_update_presentation()
		if committed_level > 0:
			var updated: Dictionary = building_world.get_building(selected_building_id)
			var floor_portions: int = HouseMassing.sections_on_level(HouseMassing.sections_for(updated), committed_level).size()
			_set_status("Floor %d portion joined • %d portions on this floor" % [committed_level + 1, floor_portions])
		else:
			_set_status("House portion joined • %d total portions" % HouseMassing.sections_for(building_world.get_building(selected_building_id)).size())
	else:
		_set_status("House portion could not be saved")
	return ok

func _remove_last_portion() -> bool:
	var index: int = building_world._building_index(selected_building_id)
	if index < 0: return false
	var view: Dictionary = building_world.get_building(selected_building_id)
	var sections: Array[Dictionary] = HouseMassing.sections_for(view)
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
	if not _sync_surface_record(building):
		building_world._document = before
		return false
	building_world._refresh_buckets(building)
	buildings[index] = building
	var ok: bool = building_world._record_change(before)
	_close_house_shape_picker(false)
	if ok:
		_record_history("building")
		_presentation_key = ""
		_update_presentation()
		_set_status("Removed last house portion")
	return ok

func _sync_surface_record(building: Dictionary) -> bool:
	return MassingSurfaces.sync_building(building_world, building)

func _sync_loaded_massing_surfaces() -> void:
	if not building_world: return
	var revision: int = building_world.get_revision()
	if revision == _massing_surface_sync_revision: return
	_massing_surface_sync_revision = revision
	var buildings: Array = building_world._document.get("buildings", [])
	var changed := false
	for index in buildings.size():
		var building: Dictionary = buildings[index]
		var before_surfaces: String = JSON.stringify(building.get("surfaces", []))
		if not _sync_surface_record(building): continue
		building_world._refresh_buckets(building)
		buildings[index] = building
		changed = changed or before_surfaces != JSON.stringify(building.get("surfaces", []))
	if changed:
		building_world._document["next_id"] = building_world._next_id
		_presentation_key = ""

func _update_presentation() -> void:
	var _ul_t0 := Time.get_ticks_usec()
	var _fc_p := Time.get_ticks_usec()
	_sync_loaded_massing_surfaces()
	last_frame_costs["pres_upper_walls"] = (Time.get_ticks_usec() - _fc_p) / 1000.0
	super._update_presentation()

	var _ul_t1 := Time.get_ticks_usec()
	last_frame_costs["upd_m2_scene_upper_wall_details"] = (_ul_t1 - _ul_t0) / 1000.0
func _begin_new_attachment(kind: String) -> void:
	_sync_loaded_massing_surfaces()
	super._begin_new_attachment(kind)
	if detail_move_active:
		_set_status("Place %s • D-pad ←/→ cycles walls/floors • A place / B cancel" % kind.replace("_", " "))

func _cycle_attachment_surface(direction: int) -> void:
	super._cycle_attachment_surface(direction)
	if not detail_move_active: return
	var label: String = WallPlacement.surface_label(building_world.get_building(selected_building_id), detail_move_surface_id)
	_set_status("Support: %s • left stick move • A commit / B cancel" % label)

func _update_presentation_target_label() -> void:
	pass
