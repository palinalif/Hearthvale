extends "res://scripts/m2_scene_build_browser.gd"

## Path-terrain ownership sits above the normal M2 scene stack so packed-earth
## excavation can be restored safely when cells are erased or repainted. The
## saved landscape document carries only the voxels still owned by the path
## system; direct sculpt edits release ownership before history is recorded.
const OwnedPathExcavation = preload("res://scripts/m2_path_terrain_excavation.gd")

var _path_terrain_ownership: Array = []
var _path_terrain_before: Array = []

func _commit_path_stroke() -> bool:
	if not path_painting: return false
	if path_cells.is_empty():
		_cancel_path_stroke("Empty stroke cancelled")
		return false
	if JSON.stringify(landscape_state.document()) != _path_before_serialized or _terrain_revision() != _path_terrain_revision or building_world.get_revision() != _path_building_revision:
		_cancel_path_stroke("World changed; stroke cancelled")
		return false
	if _cells_hit_home_interior(path_cells) or not _candidate_cells_fit_limits(path_cells):
		_cancel_path_stroke("Invalid stroke cancelled")
		return false
	_landscape_before = _path_before.duplicate(true)
	_landscape_before["path_terrain"] = _path_terrain_before.duplicate(true)
	var packed_before: Array = landscape_state.path_cells("packed_earth")
	var path_id := landscape_state.paint_path_cells(path_style_id, path_cells)
	if path_id < 1:
		_landscape_before.clear()
		_cancel_path_stroke("Path limit reached")
		return false
	var packed_after: Array = landscape_state.path_cells("packed_earth")
	var reconcile: Dictionary = OwnedPathExcavation.plan_packed_earth_transition(backend, packed_before, packed_after, _path_terrain_before)
	if not bool(reconcile.get("ok", false)):
		landscape_state.restore(_path_before)
		_landscape_before.clear()
		_cancel_path_stroke("Terrain reconciliation unavailable")
		return false
	var terrain_changed := false
	var changes: Array = reconcile.get("changes", [])
	if not changes.is_empty():
		if not backend or not backend.has_method("apply_voxel_changes") or not backend.apply_voxel_changes(changes):
			landscape_state.restore(_path_before)
			_landscape_before.clear()
			_cancel_path_stroke("Terrain changed; stroke cancelled")
			return false
		terrain_changed = true
	_apply_path_ownership_delta(reconcile.get("acquired", []), reconcile.get("released", []))
	landscape_state.clear_records_in_path_cells(path_cells)
	if garden_visual: garden_visual.reset_records(landscape_state.records)
	path_painting = false
	var committed_cells := path_cells.size()
	path_cells.clear()
	_path_last_sample = Vector2(NAN, NAN)
	path_visual.hide_preview()
	_path_preview_signature = ""
	_record_history("path" if terrain_changed else "landscape")
	_landscape_before.clear()
	_refresh_path_visual(true)
	_reset_path_baseline()
	var conflicts := int(reconcile.get("conflict_count", 0))
	var suffix := " • %d terrain conflict%s preserved" % [conflicts, "s" if conflicts != 1 else ""] if conflicts > 0 else ""
	_set_status("%s • %d cells painted • hold A for another stroke • LB undo%s" % [_path_style_name(), committed_cells, suffix])
	_update_path_validity()
	_update_path_preview()
	_refresh_controller_hud()
	return true

## Future erase-brush entry point. It uses the same reconciliation path as a
## material overwrite, so removing packed earth restores only owned voxels.
func erase_painted_path_cells(cell_values: Array) -> bool:
	if path_painting or stroke_active or landscape_active: return false
	var before_document := landscape_state.document()
	var before_ownership := _path_terrain_ownership.duplicate(true)
	var packed_before: Array = landscape_state.path_cells("packed_earth")
	if not landscape_state.erase_path_cells(cell_values): return false
	var packed_after: Array = landscape_state.path_cells("packed_earth")
	var reconcile: Dictionary = OwnedPathExcavation.plan_packed_earth_transition(backend, packed_before, packed_after, before_ownership)
	if not bool(reconcile.get("ok", false)):
		landscape_state.restore(before_document)
		return false
	var changes: Array = reconcile.get("changes", [])
	if not changes.is_empty() and (not backend or not backend.has_method("apply_voxel_changes") or not backend.apply_voxel_changes(changes)):
		landscape_state.restore(before_document)
		return false
	_landscape_before = before_document.duplicate(true)
	_landscape_before["path_terrain"] = before_ownership
	_apply_path_ownership_delta(reconcile.get("acquired", []), reconcile.get("released", []))
	_record_history("path" if not changes.is_empty() else "landscape")
	_landscape_before.clear()
	_refresh_path_visual(true)
	_reset_path_baseline()
	return true

func _reset_path_baseline() -> void:
	super._reset_path_baseline()
	_path_terrain_before = _path_terrain_ownership.duplicate(true)

func _record_history(tag: String) -> void:
	var before_ownership := _path_terrain_ownership.duplicate(true)
	var before_document := landscape_state.document()
	if not _landscape_before.is_empty():
		before_document = _landscape_before.duplicate(true)
		before_ownership = _normalize_path_ownership(before_document.get("path_terrain", before_ownership))
	if tag == "terrain" and backend and backend.has_method("get_last_edit_cells"):
		_release_path_ownership_for_world_cells(backend.get_last_edit_cells(), float(backend.voxel_scale))
	before_document["path_terrain"] = before_ownership
	var after_document := landscape_state.document()
	after_document["path_terrain"] = _path_terrain_ownership.duplicate(true)
	_history_tags.append(tag)
	_landscape_history.append({"before": before_document, "after": after_document})
	_building_dirty = true
	_redo_tags.clear()
	_landscape_redo.clear()
	if _history_tags.size() > 50:
		_history_tags.pop_front()
		_landscape_history.pop_front()

func _undo() -> void:
	var before_count := _history_tags.size()
	super._undo()
	if _history_tags.size() < before_count and not _landscape_redo.is_empty():
		var entry: Dictionary = _landscape_redo.back()
		var document: Dictionary = entry.get("before", {})
		_path_terrain_ownership = _normalize_path_ownership(document.get("path_terrain", []))
		_path_terrain_before = _path_terrain_ownership.duplicate(true)
	_refresh_path_visual(true)

func _redo() -> void:
	var before_count := _redo_tags.size()
	super._redo()
	if _redo_tags.size() < before_count and not _landscape_history.is_empty():
		var entry: Dictionary = _landscape_history.back()
		var document: Dictionary = entry.get("after", {})
		_path_terrain_ownership = _normalize_path_ownership(document.get("path_terrain", []))
		_path_terrain_before = _path_terrain_ownership.duplicate(true)
	_refresh_path_visual(true)

func _save_all() -> bool:
	if landscape_active:
		_set_status("Finish or cancel planting before saving")
		return false
	var ok := false
	if backend and backend.has_method("save_world"):
		var document: Dictionary = building_world.get_document()
		var landscape_document := landscape_state.document()
		landscape_document["path_terrain"] = _path_terrain_ownership.duplicate(true)
		document["landscape"] = landscape_document
		ok = backend.save_world(document)
	_set_status("World saved" if ok else "Save failed (cottage design kept in memory)")
	if ok: _building_dirty = false
	return ok

func _restore_landscape(document: Dictionary) -> void:
	super._restore_landscape(document)
	_path_terrain_ownership.clear()
	var landscape_document = document.get("landscape", null)
	if landscape_document is Dictionary:
		_path_terrain_ownership = _normalize_path_ownership((landscape_document as Dictionary).get("path_terrain", []))
	_path_terrain_before = _path_terrain_ownership.duplicate(true)
	_refresh_path_visual(true)

func path_terrain_ownership_count() -> int:
	return _path_terrain_ownership.size()

func _apply_path_ownership_delta(acquired_values: Array, released_values: Array) -> void:
	var released := {}
	for entry: Dictionary in _normalize_path_ownership(released_values):
		released[_path_ownership_key(entry["position"])] = true
	var kept: Array = []
	var occupied := {}
	for entry: Dictionary in _normalize_path_ownership(_path_terrain_ownership):
		var key := _path_ownership_key(entry["position"])
		if released.has(key): continue
		kept.append(_encode_path_ownership(entry))
		occupied[key] = true
	for entry: Dictionary in _normalize_path_ownership(acquired_values):
		var key := _path_ownership_key(entry["position"])
		if occupied.has(key): continue
		kept.append(_encode_path_ownership(entry))
		occupied[key] = true
	_path_terrain_ownership = kept

func _release_path_ownership_for_world_cells(world_cells: Array, cell_size: float) -> void:
	if not is_finite(cell_size) or cell_size <= 0.0 or world_cells.is_empty() or _path_terrain_ownership.is_empty(): return
	var changed := {}
	for point in world_cells:
		if point is Vector3:
			changed[Vector3i(floor((point as Vector3) / cell_size))] = true
	var kept: Array = []
	for entry: Dictionary in _normalize_path_ownership(_path_terrain_ownership):
		if not changed.has(entry["position"]): kept.append(_encode_path_ownership(entry))
	_path_terrain_ownership = kept

func _normalize_path_ownership(values: Array) -> Array:
	var result: Array = []
	var seen := {}
	var patch := Vector3i(384, 256, 384)
	if backend:
		var candidate = backend.get("patch_size")
		if candidate is Vector3i: patch = candidate
	for value in values:
		if not value is Dictionary: continue
		var entry: Dictionary = value
		var raw_position = entry.get("position", null)
		var position := Vector3i(-1, -1, -1)
		if raw_position is Vector3i:
			position = raw_position
		elif raw_position is Array and raw_position.size() == 3:
			if not _path_integer(raw_position[0]) or not _path_integer(raw_position[1]) or not _path_integer(raw_position[2]): continue
			position = Vector3i(int(raw_position[0]), int(raw_position[1]), int(raw_position[2]))
		if position.x < 0 or position.y < 0 or position.z < 0 or position.x >= patch.x or position.y >= patch.y or position.z >= patch.z: continue
		var material = entry.get("material", entry.get("before", 0))
		if not _path_integer(material) or int(material) <= 0 or int(material) > 65535: continue
		var key := _path_ownership_key(position)
		if seen.has(key): continue
		seen[key] = true
		result.append({"position": position, "material": int(material)})
	return result

func _encode_path_ownership(entry: Dictionary) -> Dictionary:
	var position: Vector3i = entry["position"]
	return {"position": [position.x, position.y, position.z], "material": int(entry["material"])}

func _path_ownership_key(position: Vector3i) -> String:
	return "%d:%d:%d" % [position.x, position.y, position.z]

func _path_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))

const PolishedPathVisual = preload("res://scripts/m2_path_visual_polish.gd")

func _ready() -> void:
	super._ready()
	if path_visual and is_instance_valid(path_visual):
		path_visual.queue_free()
	path_visual = PolishedPathVisual.new()
	path_visual.name = "M2PathVisual"
	add_child(path_visual)
	if backend: path_visual.attach_backend(backend)
	_path_render_signature = ""
	_refresh_path_visual(true)

func _input(event: InputEvent) -> void:
	if path_placement_active and not path_painting and not menu_open:
		if event.is_action_pressed("m1_cycle_left"):
			_adjust_path_brush(-1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_cycle_right"):
			_adjust_path_brush(1)
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _adjust_path_brush(direction: int) -> void:
	if direction == 0 or path_painting: return
	var step := PathGrid.UNIT if precision_mode else PathGrid.UNIT * 2.0
	path_width = snappedf(clampf(path_width + float(direction) * step, PathGrid.UNIT * 2.0, 8.0), PathGrid.UNIT)
	_path_preview_signature = ""
	_set_status("%s • %.3f m brush • hold A paint" % [_path_style_name(), path_width])
	_update_brush_preview()
	_update_path_validity()
	_update_path_preview()
	_refresh_controller_hud()

func _update_presentation() -> void:
	super._update_presentation()
	if path_placement_active and target_label:
