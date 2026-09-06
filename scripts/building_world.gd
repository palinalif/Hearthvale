extends RefCounted
class_name BuildingWorld

## Authoritative M1 cottage recipe. Rendering is deliberately outside this
## object: the document contains only bounded, serializable design data.

signal changed

const SCHEMA_VERSION := 1
const GENERATOR_VERSION := "m1-cottage-v1"
const STYLE_ID := "riverside_cottage"
const HISTORY_LIMIT := 50
const HISTORY_BYTES_LIMIT := 8 * 1024 * 1024
const DOCUMENT_BYTES_LIMIT := 256 * 1024
const MAX_BUILDINGS := 8
const MAX_SURFACES := 64
const MAX_DETAILS := 256
const MIN_DIMENSIONS := Vector3(4.0, 4.0, 4.0)
const MAX_DIMENSIONS := Vector3(32.0, 18.0, 32.0)

var _document: Dictionary
var _revision := 0
var _next_id := 1
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _history_bytes := 0

static func validate_document(document: Dictionary) -> bool:
	var validator := BuildingWorld.new()
	return validator._validate_document(document)

func _init() -> void:
	_document = {"schema_version": SCHEMA_VERSION, "generator_version": GENERATOR_VERSION, "revision": 0, "next_id": 1, "buildings": []}
	var building := _new_cottage("building-1", Vector3(18.0, 10.0, 14.0), Vector3(22.0, 8.0, 18.0), 1042)
	_document["buildings"] = [building]
	_next_id = 2
	_document["next_id"] = _next_id

func get_revision() -> int:
	return _revision

func get_document() -> Dictionary:
	return _copy(_document) as Dictionary

func serialize_document() -> String:
	var serialized := JSON.stringify(_document)
	return serialized if serialized.to_utf8_buffer().size() <= DOCUMENT_BYTES_LIMIT else ""

func load_serialized_document(serialized: String) -> bool:
	if serialized.to_utf8_buffer().size() > DOCUMENT_BYTES_LIMIT: return false
	var parsed = JSON.parse_string(serialized)
	return parsed is Dictionary and load_document(parsed as Dictionary)

func load_document(document: Dictionary) -> bool:
	if not _validate_document(document): return false
	_document = _copy(document) as Dictionary
	_revision = maxi(_revision + 1, int(_document.get("revision", 0)))
	_next_id = maxi(_next_id, maxi(int(_document.get("next_id", 1)), 1))
	_document["revision"] = _revision
	_document["next_id"] = _next_id
	_undo_stack.clear()
	_redo_stack.clear()
	_history_bytes = 0
	changed.emit()
	return true

func get_buildings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for building_value in _document["buildings"]:
		result.append(_resolved_building(building_value as Dictionary))
	return result

func get_building(building_id: String) -> Dictionary:
	var index := _building_index(building_id)
	if index < 0: return {}
	return _resolved_building((_document["buildings"] as Array)[index] as Dictionary)

func resize(building_id: String, dimensions: Vector3) -> bool:
	if not _valid_dimensions(dimensions): return false
	var index := _building_index(building_id)
	if index < 0: return false
	var before := _copy(_document) as Dictionary
	var buildings: Array = _document["buildings"]
	var building: Dictionary = buildings[index]
	building["dimensions"] = _vec(dimensions)
	_refresh_buckets(building)
	buildings[index] = building
	return _record_change(before)

func preview_resize(building_id: String, dimensions: Vector3) -> Dictionary:
	if not _valid_dimensions(dimensions): return {}
	var index := _building_index(building_id)
	if index < 0: return {}
	var building: Dictionary = _copy((_document["buildings"] as Array)[index])
	building["dimensions"] = _vec(dimensions)
	var resolved := _resolved_details(building)
	var needs: Array[String] = []
	for detail_value in resolved:
		var detail: Dictionary = detail_value
		if bool(detail.get("needs_placement", false)): needs.append(str(detail.get("id", "")))
	return {"building_id": building_id, "dimensions": dimensions, "details": resolved, "needs_placement": needs, "revision": _revision}

func move_detail(building_id: String, detail_id: String, surface_id: String, local_position: Vector3) -> bool:
	var state := _detail_state(building_id, detail_id)
	return _set_detail_anchor(building_id, detail_id, surface_id, local_position, "manual" if state == "manual" else "modified_locked")

func reattach_detail(building_id: String, detail_id: String, surface_id: String, local_position: Vector3) -> bool:
	if not local_position.is_finite() or not _surface_exists(building_id, surface_id): return false
	return _set_detail_anchor(building_id, detail_id, surface_id, local_position, "manual" if _detail_state(building_id, detail_id) == "manual" else "modified_locked")

func replace_detail(building_id: String, detail_id: String, asset_id: String) -> bool:
	if asset_id.is_empty(): return false
	var index := _building_index(building_id)
	if index < 0: return false
	var buildings: Array = _document["buildings"]
	var building: Dictionary = buildings[index]
	var detail_index := _detail_index(building, detail_id)
	if detail_index < 0: return false
	var current_detail: Dictionary = (building["details"] as Array)[detail_index]
	if str(current_detail.get("state", "")) == "suppressed": return false
	var before := _copy(_document) as Dictionary
	var details: Array = building["details"]
	var detail: Dictionary = details[detail_index]
	if detail.get("state", "") == "suppressed": return false
	detail["asset_id"] = asset_id
	detail["state"] = "manual" if str(detail.get("state", "")) == "manual" else "modified_locked"
	var asset_override: Dictionary = detail.get("override", {})
	asset_override["asset_id"] = asset_id
	detail["override"] = asset_override
	details[detail_index] = detail
	building["details"] = details
	_refresh_buckets(building)
	buildings[index] = building
	return _record_change(before)

func suppress_detail(building_id: String, detail_id: String, suppressed: bool = true) -> bool:
	var index := _building_index(building_id)
	if index < 0: return false
	var buildings: Array = _document["buildings"]
	var building: Dictionary = buildings[index]
	var detail_index := _detail_index(building, detail_id)
	if detail_index < 0: return false
	var before := _copy(_document) as Dictionary
	var details: Array = building["details"]
	var detail: Dictionary = details[detail_index]
	if suppressed and str(detail.get("state", "")) == "suppressed": return false
	if not suppressed and str(detail.get("state", "")) != "suppressed": return false
	if suppressed:
		detail["suppressed_from_state"] = detail.get("state", "automatic")
		detail["state"] = "suppressed"
		var suppression_override: Dictionary = detail.get("override", {})
		suppression_override["suppressed"] = true
		detail["override"] = suppression_override
	else:
		detail["state"] = str(detail.get("suppressed_from_state", "automatic"))
		detail.erase("suppressed_from_state")
		var restored_override: Dictionary = detail.get("override", {})
		restored_override.erase("suppressed")
		if restored_override.is_empty(): detail.erase("override")
		else: detail["override"] = restored_override
	details[detail_index] = detail
	building["details"] = details
	_refresh_buckets(building)
	buildings[index] = building
	return _record_change(before)

func add_detail(building_id: String, kind: String, surface_id: String, local_position: Vector3, asset_id: String = "") -> String:
	if kind.is_empty() or not local_position.is_finite() or not _surface_exists(building_id, surface_id): return ""
	var index := _building_index(building_id)
	if index < 0: return ""
	var current_details: Array = ((_document["buildings"] as Array)[index] as Dictionary).get("details", [])
	var total_details := 0
	for building_value in _document.get("buildings", []): total_details += (building_value as Dictionary).get("details", []).size()
	if current_details.size() >= MAX_DETAILS or total_details >= MAX_DETAILS: return ""
	var before := _copy(_document) as Dictionary
	var detail_id := _allocate_id("detail")
	var detail := {"id": detail_id, "kind": kind, "asset_id": asset_id if not asset_id.is_empty() else kind, "state": "manual", "generated": false, "anchor": {"surface_id": surface_id, "policy": "surface_local", "local_position": _vec(local_position)}, "needs_placement": false}
	var buildings: Array = _document["buildings"]
	var building: Dictionary = buildings[index]
	var details: Array = building["details"]
	details.append(detail)
	building["details"] = details
	_refresh_buckets(building)
	buildings[index] = building
	if not _record_change(before): return ""
	return detail_id

func delete_surface(building_id: String, surface_id: String) -> bool:
	var index := _building_index(building_id)
	if index < 0: return false
	var buildings: Array = _document["buildings"]
	var building: Dictionary = buildings[index]
	var surface_index := _surface_index(building, surface_id)
	if surface_index < 0: return false
	var before := _copy(_document) as Dictionary
	var surfaces: Array = building["surfaces"]
	var surface: Dictionary = surfaces[surface_index]
	surface["deleted"] = true
	surfaces[surface_index] = surface
	building["surfaces"] = surfaces
	_refresh_buckets(building)
	buildings[index] = building
	return _record_change(before)

func set_material(building_id: String, material_id: String) -> bool:
	if material_id.is_empty(): return false
	var index := _building_index(building_id)
	if index < 0: return false
	var before := _copy(_document) as Dictionary
	var buildings: Array = _document["buildings"]
	var building: Dictionary = buildings[index]
	building["material_id"] = material_id
	building["material_overrides"] = {"shell": material_id}
	buildings[index] = building
	return _record_change(before)

func duplicate_building(building_id: String, offset: Vector3 = Vector3(4.0, 0.0, 4.0)) -> String:
	var index := _building_index(building_id)
	if index < 0 or (_document["buildings"] as Array).size() >= MAX_BUILDINGS: return ""
	var before := _copy(_document) as Dictionary
	var source: Dictionary = (_document["buildings"] as Array)[index]
	var total_details := 0
	for building_value in _document.get("buildings", []): total_details += (building_value as Dictionary).get("details", []).size()
	if total_details + (source.get("details", []) as Array).size() > MAX_DETAILS: return ""
	var copy: Dictionary = _copy(source)
	var id_map := {}
	var new_id := _allocate_id("building")
	copy["id"] = new_id
	copy["name"] = str(copy.get("name", "Cottage")) + " Copy"
	var copy_transform := _as_transform(copy.get("transform", {}))
	copy["transform"] = _transform_from_transform(copy_transform, copy_transform.origin + offset)
	for surface_index in (copy["surfaces"] as Array).size():
		var surface: Dictionary = (copy["surfaces"] as Array)[surface_index]
		var old_surface_id := str(surface["id"])
		var fresh_surface_id := _allocate_id("surface")
		id_map[old_surface_id] = fresh_surface_id
		surface["id"] = fresh_surface_id
		(copy["surfaces"] as Array)[surface_index] = surface
	for detail_index in (copy["details"] as Array).size():
		var detail: Dictionary = (copy["details"] as Array)[detail_index]
		var old_detail_id := str(detail["id"])
		var fresh_detail_id := _allocate_id("detail")
		id_map[old_detail_id] = fresh_detail_id
		detail["id"] = fresh_detail_id
		var anchor: Dictionary = detail.get("anchor", {})
		anchor["surface_id"] = id_map.get(str(anchor.get("surface_id", "")), anchor.get("surface_id", ""))
		detail["anchor"] = anchor
		var original_default = detail.get("default", null)
		if original_default is Dictionary:
			var remapped_default: Dictionary = _copy(original_default)
			remapped_default["id"] = fresh_detail_id
			var default_anchor: Dictionary = remapped_default.get("anchor", {})
			default_anchor["surface_id"] = id_map.get(str(default_anchor.get("surface_id", "")), default_anchor.get("surface_id", ""))
			remapped_default["anchor"] = default_anchor
			detail["default"] = remapped_default
		var detail_override: Dictionary = detail.get("override", {})
		if detail_override.has("surface_id"): detail_override["surface_id"] = id_map.get(str(detail_override["surface_id"]), detail_override["surface_id"])
		detail["override"] = detail_override
		(copy["details"] as Array)[detail_index] = detail
	copy["automatic_defaults"] = _remap_defaults(copy.get("automatic_defaults", []), id_map)
	copy["modified_locked"] = _remap_id_array(copy.get("modified_locked", []), id_map)
	copy["suppressed"] = _remap_id_array(copy.get("suppressed", []), id_map)
	copy["manual_attachments"] = _remap_detail_records(copy.get("manual_attachments", []), id_map)
	copy["overrides"] = _remap_overrides(copy.get("overrides", {}), id_map)
	_refresh_buckets(copy)
	(_document["buildings"] as Array).append(copy)
	if not _record_change(before): return ""
	return new_id

func undo() -> bool:
	if _undo_stack.is_empty(): return false
	var entry: Dictionary = _undo_stack.pop_back()
	_redo_stack.append(entry)
	var preserved_next_id := _next_id
	_document = _copy(entry["before"]) as Dictionary
	_revision += 1
	_document["revision"] = _revision
	_next_id = maxi(preserved_next_id, int(_document.get("next_id", _next_id)))
	_document["next_id"] = _next_id
	changed.emit()
	return true

func redo() -> bool:
	if _redo_stack.is_empty(): return false
	var entry: Dictionary = _redo_stack.pop_back()
	_undo_stack.append(entry)
	var preserved_next_id := _next_id
	_document = _copy(entry["after"]) as Dictionary
	_revision += 1
	_document["revision"] = _revision
	_next_id = maxi(preserved_next_id, int(_document.get("next_id", _next_id)))
	_document["next_id"] = _next_id
	changed.emit()
	return true

func is_revision_current(candidate_revision: int) -> bool:
	return candidate_revision == _revision

func accept_mesh_result(result_revision: int) -> bool:
	return is_revision_current(result_revision)

func _new_cottage(building_id: String, dimensions: Vector3, position: Vector3, seed: int) -> Dictionary:
	var surfaces: Array = [
		{"id": "wall-front", "kind": "wall", "orientation": "front", "extent_axis": "x", "min_extent": 5.0, "deleted": false},
		{"id": "wall-back", "kind": "wall", "orientation": "back", "extent_axis": "x", "min_extent": 5.0, "deleted": false},
		{"id": "wall-left", "kind": "wall", "orientation": "left", "extent_axis": "z", "min_extent": 5.0, "deleted": false},
		{"id": "wall-right", "kind": "wall", "orientation": "right", "extent_axis": "z", "min_extent": 5.0, "deleted": false},
		{"id": "roof-left", "kind": "roof", "orientation": "left", "extent_axis": "x", "min_extent": 5.0, "deleted": false},
		{"id": "roof-right", "kind": "roof", "orientation": "right", "extent_axis": "x", "min_extent": 5.0, "deleted": false},
	]
	var details: Array = []
	for index in 3:
		details.append(_window("window-front-%d" % index, "wall-front", 0.18 + float(index) * 0.32, 0.48))
	for index in 3:
		details.append(_window("window-back-%d" % index, "wall-back", 0.18 + float(index) * 0.32, 0.48))
	var building := {"id": building_id, "name": "Riverside Cottage", "schema_version": SCHEMA_VERSION, "generator_version": GENERATOR_VERSION, "dimensions": _vec(dimensions), "transform": _transform(position), "seed": seed, "style_id": STYLE_ID, "roof_profile": "gabled", "material_id": "stone_plaster", "material_overrides": {}, "surfaces": surfaces, "details": details, "automatic_defaults": [], "overrides": {}, "exclusions": [], "modified_locked": [], "suppressed": [], "manual_attachments": []}
	_refresh_buckets(building)
	return building

func _window(detail_id: String, surface_id: String, u: float, v: float) -> Dictionary:
	var default_anchor := {"surface_id": surface_id, "policy": "proportional", "u": u, "v": v, "fixed_offset": 1.25}
	return {"id": detail_id, "kind": "window", "asset_id": "window_wood", "state": "automatic", "generated": true, "anchor": default_anchor.duplicate(true), "default": {"id": detail_id, "asset_id": "window_wood", "u": u, "v": v, "anchor": default_anchor}, "needs_placement": false}

func _resolved_building(building: Dictionary) -> Dictionary:
	var result: Dictionary = _copy(building)
	result["dimensions"] = _as_vec(building.get("dimensions", [0, 0, 0]))
	result["transform"] = _as_transform(building.get("transform", {}))
	result["details"] = _resolved_details(building)
	return result

func _resolved_details(building: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dimensions := _as_vec(building.get("dimensions", [0, 0, 0]))
	for detail_value in building.get("details", []):
		var detail: Dictionary = _copy(detail_value)
		var anchor: Dictionary = detail.get("anchor", {})
		var surface := _surface(building, str(anchor.get("surface_id", "")))
		var needs := str(detail.get("state", "")) != "suppressed" and (surface.is_empty() or bool(surface.get("deleted", false)) or not _surface_fits(building, surface, dimensions))
		if not needs and str(anchor.get("policy", "")) in ["fixed_local", "surface_local"]:
			var local := _as_vec(anchor.get("local_position", [0, 0, 0]))
			var orientation := str(surface.get("orientation", "front"))
			var tangential := absf(local.x) if orientation in ["front", "back"] else absf(local.z)
			var extent := dimensions.x if orientation in ["front", "back"] else dimensions.z
			var footprint := _detail_footprint(detail)
			needs = tangential + footprint.x > extent * 0.5 or local.y - footprint.y < 0.0 or local.y + footprint.y > dimensions.y
		var position = null
		if not needs: position = _resolve_position(surface, anchor, dimensions)
		detail["resolved_position"] = position
		detail["needs_placement"] = needs
		detail["visible"] = str(detail.get("state", "")) != "suppressed"
		result.append(detail)
	return result

func _resolve_position(surface: Dictionary, anchor: Dictionary, dimensions: Vector3):
	var policy := str(anchor.get("policy", "proportional"))
	if policy in ["fixed_local", "surface_local"]:
		var local := _as_vec(anchor.get("local_position", [0, 0, 0]))
		var orientation := str(surface.get("orientation", "front"))
		var half_x := dimensions.x * 0.5
		var half_z := dimensions.z * 0.5
		match orientation:
			"front": local.z = -half_z - 0.02
			"back": local.z = half_z + 0.02
			"left": local.x = -half_x - 0.02
			"right": local.x = half_x + 0.02
		return local
	var u := clampf(float(anchor.get("u", 0.5)), 0.0, 1.0)
	var v := clampf(float(anchor.get("v", 0.5)), 0.0, 1.0)
	var offset := float(anchor.get("fixed_offset", 1.25))
	var half_x := dimensions.x * 0.5
	var half_z := dimensions.z * 0.5
	var orientation := str(surface.get("orientation", "front"))
	match orientation:
		"front": return Vector3(lerpf(-half_x + offset, half_x - offset, u), dimensions.y * v, -half_z - 0.02)
		"back": return Vector3(lerpf(-half_x + offset, half_x - offset, u), dimensions.y * v, half_z + 0.02)
		"left": return Vector3(-half_x - 0.02, dimensions.y * v, lerpf(-half_z + offset, half_z - offset, u))
		"right": return Vector3(half_x + 0.02, dimensions.y * v, lerpf(-half_z + offset, half_z - offset, u))
	return Vector3.ZERO

func _surface_fits(building: Dictionary, surface: Dictionary, dimensions: Vector3) -> bool:
	var axis := str(surface.get("extent_axis", "x"))
	var extent := dimensions.x if axis == "x" else dimensions.z
	return extent >= float(surface.get("min_extent", 0.0))

func _detail_footprint(detail: Dictionary) -> Vector2:
	var kind := str(detail.get("kind", "window"))
	var asset := str(detail.get("asset_id", ""))
	if kind == "flower_box": return Vector2(0.8, 0.2)
	if kind == "door": return Vector2(1.5, 3.25)
	if asset.contains("round"): return Vector2(0.65, 0.65)
	return Vector2(1.1, 1.5)

func _set_detail_anchor(building_id: String, detail_id: String, surface_id: String, local_position: Vector3, state: String) -> bool:
	if not local_position.is_finite() or not _surface_exists(building_id, surface_id): return false
	var index := _building_index(building_id)
	if index < 0: return false
	var buildings: Array = _document["buildings"]
	var building: Dictionary = buildings[index]
	var detail_index := _detail_index(building, detail_id)
	if detail_index < 0: return false
	if str((building["details"] as Array)[detail_index].get("state", "")) == "suppressed": return false
	var before := _copy(_document) as Dictionary
	var details: Array = building["details"]
	var detail: Dictionary = details[detail_index]
	detail["state"] = state
	detail["anchor"] = {"surface_id": surface_id, "policy": "surface_local", "local_position": _vec(local_position)}
	var anchor_override: Dictionary = detail.get("override", {})
	anchor_override["surface_id"] = surface_id
	anchor_override["local_position"] = _vec(local_position)
	detail["override"] = anchor_override
	details[detail_index] = detail
	building["details"] = details
	_refresh_buckets(building)
	buildings[index] = building
	return _record_change(before)

func _record_change(before: Dictionary) -> bool:
	var after: Dictionary = _copy(_document) as Dictionary
	if JSON.stringify(before) == JSON.stringify(after): return false
	if not _validate_document(after):
		_document = before
		return false
	if JSON.stringify(after).to_utf8_buffer().size() > DOCUMENT_BYTES_LIMIT:
		_document = before
		return false
	var bytes: int = _estimate(before) + _estimate(after)
	var redo_bytes := 0
	for redo_entry in _redo_stack: redo_bytes += int((redo_entry as Dictionary).get("bytes", 0))
	var available_history := _history_bytes - redo_bytes
	if bytes > HISTORY_BYTES_LIMIT or available_history + bytes > HISTORY_BYTES_LIMIT and _undo_stack.is_empty():
		_document = before
		return false
	var trim_count := 0
	var trim_bytes := 0
	while available_history - trim_bytes + bytes > HISTORY_BYTES_LIMIT and trim_count < _undo_stack.size():
		trim_bytes += int(_undo_stack[trim_count].get("bytes", 0))
		trim_count += 1
	if available_history - trim_bytes + bytes > HISTORY_BYTES_LIMIT:
		_document = before
		return false
	for index in trim_count: _undo_stack.pop_front()
	_history_bytes = available_history - trim_bytes
	_redo_stack.clear()
	var entry: Dictionary = {"before": before, "after": after, "bytes": bytes}
	_undo_stack.append(entry)
	_history_bytes += bytes
	if _undo_stack.size() > HISTORY_LIMIT:
		_history_bytes -= int(_undo_stack.pop_front().get("bytes", 0))
	_revision += 1
	_document["revision"] = _revision
	_document["next_id"] = _next_id
	changed.emit()
	return true

func _validate_document(document: Dictionary) -> bool:
	if JSON.stringify(document).to_utf8_buffer().size() > DOCUMENT_BYTES_LIMIT: return false
	if not _valid_int(document.get("schema_version", null)) or int(document["schema_version"]) != SCHEMA_VERSION: return false
	if str(document.get("generator_version", "")) != GENERATOR_VERSION: return false
	if not _valid_int(document.get("revision", null)) or not _valid_int(document.get("next_id", null)) or int(document["revision"]) < 0 or int(document["next_id"]) < 1: return false
	var buildings = document.get("buildings", null)
	if not buildings is Array or (buildings as Array).size() > MAX_BUILDINGS: return false
	var ids := {}
	var all_ids := {}
	var detail_count := 0
	for building_value in buildings:
		if not building_value is Dictionary: return false
		var building: Dictionary = building_value
		var building_id := str(building.get("id", ""))
		if not _valid_int(building.get("schema_version", null)) or int(building["schema_version"]) != SCHEMA_VERSION or building_id.is_empty() or ids.has(building_id) or all_ids.has(building_id): return false
		ids[building_id] = true
		all_ids[building_id] = true
		var dimensions = building.get("dimensions", null)
		if not _valid_vec_data(dimensions) or not _valid_transform_data(building.get("transform", null)): return false
		if not _valid_dimensions(_as_vec(dimensions)): return false
		var surfaces = building.get("surfaces", null)
		if not surfaces is Array or (surfaces as Array).size() > MAX_SURFACES: return false
		var surface_ids := {}
		for surface_value in surfaces:
			if not surface_value is Dictionary or str((surface_value as Dictionary).get("id", "")).is_empty() or surface_ids.has(str((surface_value as Dictionary)["id"])) or all_ids.has(str((surface_value as Dictionary)["id"])): return false
			var surface: Dictionary = surface_value
			var orientation := str(surface.get("orientation", ""))
			var expected_axis := "x" if str(surface.get("kind", "")) == "roof" or orientation in ["front", "back"] else "z" if orientation in ["left", "right"] else ""
			if not ["wall", "roof"].has(str(surface.get("kind", ""))) or not ["front", "back", "left", "right"].has(orientation) or str(surface.get("extent_axis", "")) != expected_axis or not _valid_number(surface.get("min_extent", null)) or float(surface.get("min_extent", 0.0)) < 0.0 or not (surface.get("deleted", null) is bool): return false
			surface_ids[str((surface_value as Dictionary)["id"])] = true
			all_ids[str((surface_value as Dictionary)["id"])] = true
		var details = building.get("details", null)
		if not details is Array: return false
		detail_count += (details as Array).size()
		if detail_count > MAX_DETAILS: return false
		var detail_ids := {}
		for detail_value in details:
			if not detail_value is Dictionary: return false
			var detail: Dictionary = detail_value
			if str(detail.get("id", "")).is_empty() or detail_ids.has(str(detail["id"])) or all_ids.has(str(detail["id"])) or not ["automatic", "modified_locked", "suppressed", "manual"].has(str(detail.get("state", ""))): return false
			detail_ids[str(detail["id"])] = true
			all_ids[str(detail["id"])] = true
			if str(detail.get("asset_id", "")).is_empty() or not detail.get("anchor", null) is Dictionary: return false
			var anchor: Dictionary = detail["anchor"]
			var anchor_surface := str(anchor.get("surface_id", ""))
			if not surface_ids.has(anchor_surface) or not ["proportional", "surface_local", "fixed_local"].has(str(anchor.get("policy", ""))): return false
			if str(anchor.get("policy", "")) == "proportional":
				if not _valid_number(anchor.get("u", null)) or not _valid_number(anchor.get("v", null)) or not _valid_number(anchor.get("fixed_offset", null)): return false
			else:
				if not _valid_vec_data(anchor.get("local_position", null)): return false
			if detail.has("default"):
				var default_record = detail.get("default")
				if not default_record is Dictionary or str(default_record.get("id", "")).is_empty() or str(default_record.get("asset_id", "")).is_empty() or not default_record.get("anchor", null) is Dictionary: return false
				var default_anchor: Dictionary = default_record["anchor"]
				if not surface_ids.has(str(default_anchor.get("surface_id", ""))) or str(default_anchor.get("policy", "")) != "proportional" or not _valid_number(default_anchor.get("u", null)) or not _valid_number(default_anchor.get("v", null)) or not _valid_number(default_anchor.get("fixed_offset", null)): return false
			if detail.has("override") and not detail.get("override") is Dictionary: return false
	return true

func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _valid_int(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and is_equal_approx(float(value), roundf(float(value)))

func _valid_vec_data(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 3: return false
	for component in value:
		if not _valid_number(component): return false
	return true

func _valid_transform_data(value: Variant) -> bool:
	if not value is Dictionary: return false
	var data: Dictionary = value
	return _valid_vec_data(data.get("position", null)) and _valid_vec_data(data.get("rotation", null)) and _valid_vec_data(data.get("scale", null)) and _as_vec(data["scale"]).x > 0.0 and _as_vec(data["scale"]).y > 0.0 and _as_vec(data["scale"]).z > 0.0

func _building_index(building_id: String) -> int:
	var buildings: Array = _document.get("buildings", [])
	for index in buildings.size():
		if str((buildings[index] as Dictionary).get("id", "")) == building_id: return index
	return -1

func _detail_index(building: Dictionary, detail_id: String) -> int:
	var details: Array = building.get("details", [])
	for index in details.size():
		if str((details[index] as Dictionary).get("id", "")) == detail_id: return index
	return -1

func _surface_index(building: Dictionary, surface_id: String) -> int:
	var surfaces: Array = building.get("surfaces", [])
	for index in surfaces.size():
		if str((surfaces[index] as Dictionary).get("id", "")) == surface_id: return index
	return -1

func _surface(building: Dictionary, surface_id: String) -> Dictionary:
	var index := _surface_index(building, surface_id)
	return {} if index < 0 else (building["surfaces"] as Array)[index] as Dictionary

func _surface_exists(building_id: String, surface_id: String) -> bool:
	var index := _building_index(building_id)
	if index < 0: return false
	var surface := _surface((_document["buildings"] as Array)[index], surface_id)
	return not surface.is_empty() and not bool(surface.get("deleted", false))

func _detail_state(building_id: String, detail_id: String) -> String:
	var index := _building_index(building_id)
	if index < 0: return ""
	var building: Dictionary = (_document["buildings"] as Array)[index]
	var detail_index := _detail_index(building, detail_id)
	return "" if detail_index < 0 else str((building["details"] as Array)[detail_index].get("state", ""))

func _refresh_buckets(building: Dictionary) -> void:
	var resolved := _resolved_details(building)
	var detail_records: Array = building.get("details", [])
	for detail_index in detail_records.size():
		var detail: Dictionary = detail_records[detail_index]
		if detail_index < resolved.size(): detail["needs_placement"] = bool((resolved[detail_index] as Dictionary).get("needs_placement", false))
		detail_records[detail_index] = detail
	building["details"] = detail_records
	var defaults: Array = []
	var modified: Array[String] = []
	var suppressed: Array[String] = []
	var manual: Array = []
	var overrides := {}
	for detail_value in building.get("details", []):
		var detail: Dictionary = detail_value
		var id := str(detail.get("id", ""))
		if detail.has("override"): overrides[id] = _copy(detail["override"])
		if bool(detail.get("generated", false)):
			var default_record: Dictionary = _copy(detail.get("default", {}))
			default_record["id"] = id
			if not default_record.has("anchor"): default_record["anchor"] = _copy(detail.get("anchor", {}))
			defaults.append(default_record)
		if str(detail.get("state", "")) == "modified_locked": modified.append(id)
		if str(detail.get("state", "")) == "suppressed": suppressed.append(id)
		if str(detail.get("state", "")) == "manual": manual.append(_copy(detail))
	building["automatic_defaults"] = defaults
	building["overrides"] = overrides
	building["modified_locked"] = modified
	building["suppressed"] = suppressed
	building["manual_attachments"] = manual
	building["exclusions"] = suppressed.duplicate()

func _allocate_id(prefix: String) -> String:
	var id := "%s-%d" % [prefix, _next_id]
	while _id_exists(id):
		_next_id += 1
		id = "%s-%d" % [prefix, _next_id]
	_next_id += 1
	_document["next_id"] = _next_id
	return id

func _id_exists(candidate: String) -> bool:
	for building_value in _document.get("buildings", []):
		var building: Dictionary = building_value
		if str(building.get("id", "")) == candidate: return true
		for surface_value in building.get("surfaces", []):
			if str((surface_value as Dictionary).get("id", "")) == candidate: return true
		for detail_value in building.get("details", []):
			if str((detail_value as Dictionary).get("id", "")) == candidate: return true
	return false

func _valid_dimensions(value: Vector3) -> bool:
	return value.is_finite() and value.x >= MIN_DIMENSIONS.x and value.y >= MIN_DIMENSIONS.y and value.z >= MIN_DIMENSIONS.z and value.x <= MAX_DIMENSIONS.x and value.y <= MAX_DIMENSIONS.y and value.z <= MAX_DIMENSIONS.z

func _vec(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func _as_vec(value: Variant) -> Vector3:
	if value is Vector3: return value
	if value is Array and (value as Array).size() == 3: return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO

func _transform(position: Vector3) -> Dictionary:
	return {"position": _vec(position), "rotation": [0.0, 0.0, 0.0], "scale": [1.0, 1.0, 1.0]}

func _transform_from_transform(value: Transform3D, position: Vector3) -> Dictionary:
	return {"position": _vec(position), "rotation": _vec(value.basis.get_euler()), "scale": _vec(value.basis.get_scale())}

func _as_transform(value: Variant) -> Transform3D:
	if value is Transform3D: return value
	if not value is Dictionary: return Transform3D.IDENTITY
	var data: Dictionary = value
	var position := _as_vec(data.get("position", [0, 0, 0]))
	var rotation := _as_vec(data.get("rotation", [0, 0, 0]))
	var scale := _as_vec(data.get("scale", [1, 1, 1]))
	return Transform3D(Basis.from_euler(rotation).scaled(scale), position)

func _estimate(value: Variant) -> int:
	return JSON.stringify(value).length()

func _copy(value: Variant) -> Variant:
	if value is Dictionary:
		var dictionary := {}
		for key in (value as Dictionary).keys(): dictionary[key] = _copy((value as Dictionary)[key])
		return dictionary
	if value is Array:
		var array := []
		for item in value: array.append(_copy(item))
		return array
	return value

func _remap_id_array(values: Variant, id_map: Dictionary) -> Array:
	var result: Array = []
	for value in values if values is Array else []: result.append(id_map.get(str(value), value))
	return result

func _remap_defaults(values: Variant, id_map: Dictionary) -> Array:
	var result: Array = []
	for value in values if values is Array else []:
		var record: Dictionary = _copy(value)
		record["id"] = id_map.get(str(record.get("id", "")), record.get("id", ""))
		var anchor: Dictionary = record.get("anchor", {})
		anchor["surface_id"] = id_map.get(str(anchor.get("surface_id", "")), anchor.get("surface_id", ""))
		record["anchor"] = anchor
		result.append(record)
	return result

func _remap_detail_records(values: Variant, id_map: Dictionary) -> Array:
	var result: Array = []
	for value in values if values is Array else []:
		var detail: Dictionary = _copy(value)
		detail["id"] = id_map.get(str(detail.get("id", "")), detail.get("id", ""))
		var anchor: Dictionary = detail.get("anchor", {})
		anchor["surface_id"] = id_map.get(str(anchor.get("surface_id", "")), anchor.get("surface_id", ""))
		detail["anchor"] = anchor
		result.append(detail)
	return result

func _remap_overrides(values: Variant, id_map: Dictionary) -> Dictionary:
	var result := {}
	if values is Dictionary:
		for key in (values as Dictionary).keys(): result[id_map.get(str(key), key)] = _copy((values as Dictionary)[key])
	return result
