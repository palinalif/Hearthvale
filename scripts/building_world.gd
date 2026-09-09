extends RefCounted
class_name BuildingWorld

## Authoritative M1 cottage recipe. Rendering is deliberately outside this
## object: the document contains only bounded, serializable design data.

signal changed

const SCHEMA_VERSION := 1
const GENERATOR_VERSION := "m1-cottage-v1"
const STYLE_ID := "riverside_cottage"
const HOME_DESIGN_ORDER: Array[String] = ["riverside_cottage", "woodland_lodge", "village_gable"]
const HOME_DESIGNS := {
	"riverside_cottage": {"name": "Riverside Cottage", "shape_id": "classic_gable", "style_id": "riverside_cottage", "summary": "Balanced gable • stone and plaster", "dimensions": Vector3(18.0, 7.0, 14.0), "roof_profile": "gentle_gable", "wall_material_id": "stone_plaster", "roof_material_id": "terracotta"},
	"woodland_lodge": {"name": "Woodland Lodge", "shape_id": "longhouse", "style_id": "woodland_lodge", "summary": "Broad low lodge • timber frame", "dimensions": Vector3(22.0, 6.0, 11.0), "roof_profile": "swept_gable", "wall_material_id": "timber", "roof_material_id": "moss_tile"},
	"village_gable": {"name": "Village Gable", "shape_id": "tall_gable", "style_id": "village_gable", "summary": "Narrow tall home • steep slate roof", "dimensions": Vector3(12.0, 9.0, 16.0), "roof_profile": "steep_gable", "wall_material_id": "chalk_white", "roof_material_id": "slate"},
}
const HISTORY_LIMIT := 50
const HISTORY_BYTES_LIMIT := 8 * 1024 * 1024
const DOCUMENT_BYTES_LIMIT := 256 * 1024
const MAX_BUILDINGS := 8
const MAX_SURFACES := 64
const MAX_DETAILS := 256
const MINIATURE_SCALE := 0.25
const WINDOW_HALF_WIDTH := 1.375
const WINDOW_SHUTTER_HALF_WIDTH := 1.91
const WINDOW_CORNER_CLEARANCE := 0.5
const WINDOW_GAP := 0.5
const WINDOW_TARGET_SPACING := 5.0
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
	var candidate: Dictionary = validator._copy(document)
	if not validator._validate_document(candidate): return false
	validator._upgrade_editable_doors(candidate)
	return validator._validate_document(candidate)

func _init() -> void:
	_document = {"schema_version": SCHEMA_VERSION, "generator_version": GENERATOR_VERSION, "revision": 0, "next_id": 1, "buildings": []}
	var building := _new_cottage("building-1", Vector3(18.0, 7.0, 14.0), Vector3(22.0, 8.0, 18.0), 1042)
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
	var candidate: Dictionary = _copy(document)
	if not _validate_document(candidate): return false
	_upgrade_editable_doors(candidate)
	if not _validate_document(candidate): return false
	_document = candidate
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

static func home_catalogue() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for design_id in HOME_DESIGN_ORDER:
		var design: Dictionary = (HOME_DESIGNS[design_id] as Dictionary).duplicate(true)
		design["id"] = design_id
		result.append(design)
	return result

func preview_home_design(design_id: String, target: Transform3D, wall_material_id: String = "", roof_material_id: String = "") -> Dictionary:
	if not HOME_DESIGNS.has(design_id) or not target.origin.is_finite(): return {}
	var design: Dictionary = HOME_DESIGNS[design_id]
	var building := _new_cottage("preview-" + design_id, design["dimensions"], target.origin, 1042)
	_apply_home_design(building, design)
	if not wall_material_id.is_empty(): _apply_wall_material(building, wall_material_id)
	if not roof_material_id.is_empty(): _apply_roof_material(building, roof_material_id)
	building["transform"] = _transform_from_transform(target, target.origin)
	return _resolved_building(building)

func create_home_at(design_id: String, target: Transform3D, expected_revision: int = -1, wall_material_id: String = "", roof_material_id: String = "") -> String:
	if expected_revision >= 0 and expected_revision != get_revision(): return ""
	if not HOME_DESIGNS.has(design_id) or not target.origin.is_finite() or not _valid_transform_data(_transform_from_transform(target, target.origin)): return ""
	if (_document["buildings"] as Array).size() >= MAX_BUILDINGS: return ""
	var design: Dictionary = HOME_DESIGNS[design_id]
	var before := _copy(_document) as Dictionary
	var new_id := _allocate_id("building")
	var building := _new_cottage(new_id, design["dimensions"], target.origin, 1042 + _next_id * 37)
	_apply_home_design(building, design)
	if not wall_material_id.is_empty(): _apply_wall_material(building, wall_material_id)
	if not roof_material_id.is_empty(): _apply_roof_material(building, roof_material_id)
	building["transform"] = _transform_from_transform(target, target.origin)
	_freshen_home_ids(building)
	var total_details := (building.get("details", []) as Array).size()
	for building_value in _document.get("buildings", []): total_details += ((building_value as Dictionary).get("details", []) as Array).size()
	if total_details > MAX_DETAILS:
		_document = before
		return ""
	(_document["buildings"] as Array).append(building)
	if not _record_change(before): return ""
	return new_id

func resize(building_id: String, dimensions: Vector3) -> bool:
	if not _valid_dimensions(dimensions): return false
	var index := _building_index(building_id)
	if index < 0: return false
	var before := _copy(_document) as Dictionary
	var buildings: Array = _document["buildings"]
	var building: Dictionary = buildings[index]
	building["dimensions"] = _vec(dimensions)
	_reflow_automatic_windows(building)
	_refresh_buckets(building)
	buildings[index] = building
	return _record_change(before)

## Convert a building to the authored miniature presentation scale.  This is a
## document transform edit, so the origin, rotation, dimensions, anchors and
## all manual detail records remain untouched and the existing whole-record
## history machinery makes the conversion undoable.
func set_miniature_scale(building_id: String) -> bool:
	var index := _building_index(building_id)
	if index < 0: return false
	var buildings: Array = _document["buildings"]
	var building: Dictionary = buildings[index]
	var current_transform: Dictionary = building.get("transform", {})
	var current_scale := _as_vec(current_transform.get("scale", [1.0, 1.0, 1.0]))
	var miniature_scale := Vector3.ONE * MINIATURE_SCALE
	if current_scale.is_equal_approx(miniature_scale): return false
	var before := _copy(_document) as Dictionary
	var updated_transform: Dictionary = _copy(current_transform)
	updated_transform["scale"] = _vec(miniature_scale)
	building["transform"] = updated_transform
	buildings[index] = building
	return _record_change(before)

func preview_resize(building_id: String, dimensions: Vector3) -> Dictionary:
	if not _valid_dimensions(dimensions): return {}
	var index := _building_index(building_id)
	if index < 0: return {}
	var building: Dictionary = _copy((_document["buildings"] as Array)[index])
	building["dimensions"] = _vec(dimensions)
	_reflow_automatic_windows(building)
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

func resize_detail(building_id: String, detail_id: String, size: Vector2) -> bool:
	if not size.is_finite(): return false
	var index := _building_index(building_id)
	if index < 0: return false
	var buildings: Array = _document["buildings"]
	var building: Dictionary = buildings[index]
	var detail_index := _detail_index(building, detail_id)
	if detail_index < 0: return false
	var details: Array = building["details"]
	var detail: Dictionary = details[detail_index]
	if str(detail.get("state", "")) == "suppressed" or str(detail.get("kind", "")) not in ["window", "door"]: return false
	var minimum := Vector2(1.0, 1.0) if str(detail.get("kind", "")) == "window" else Vector2(1.5, 2.5)
	var maximum := Vector2(4.0, 5.0) if str(detail.get("kind", "")) == "window" else Vector2(3.5, 5.5)
	if size.x < minimum.x or size.y < minimum.y or size.x > maximum.x or size.y > maximum.y: return false
	var before := _copy(_document) as Dictionary
	var overrides: Dictionary = detail.get("override", {})
	overrides["size"] = [size.x, size.y]
	detail["override"] = overrides
	if bool(detail.get("generated", false)) and str(detail.get("state", "")) == "automatic": detail["state"] = "modified_locked"
	details[detail_index] = detail
	building["details"] = details
	_refresh_buckets(building)
	# Reject a size that no longer fits its supporting wall. The original
	# recipe is restored atomically, so a failed preview can never orphan it.
	var resolved: Array = _resolved_details(building)
	if detail_index >= resolved.size() or bool((resolved[detail_index] as Dictionary).get("needs_placement", true)):
		_document = before
		return false
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
	return set_wall_material(building_id, material_id)

func set_wall_material(building_id: String, material_id: String) -> bool:
	if material_id.is_empty(): return false
	var index := _building_index(building_id)
	if index < 0: return false
	var before := _copy(_document) as Dictionary
	var buildings: Array = _document["buildings"]
	var building: Dictionary = buildings[index]
	_apply_wall_material(building, material_id)
	buildings[index] = building
	return _record_change(before)

func set_roof_material(building_id: String, material_id: String) -> bool:
	if material_id.is_empty(): return false
	var index := _building_index(building_id)
	if index < 0: return false
	var before := _copy(_document) as Dictionary
	var buildings: Array = _document["buildings"]
	var building: Dictionary = buildings[index]
	_apply_roof_material(building, material_id)
	buildings[index] = building
	return _record_change(before)

func duplicate_building(building_id: String, offset: Vector3 = Vector3(4.0, 0.0, 4.0)) -> String:
	var source := get_building(building_id)
	if source.is_empty(): return ""
	var target: Transform3D = source["transform"]
	target.origin += offset
	return duplicate_building_at(building_id, target)

func duplicate_building_at(building_id: String, target: Transform3D, expected_revision: int = -1) -> String:
	if expected_revision >= 0 and expected_revision != get_revision(): return ""
	if not target.origin.is_finite() or not _valid_transform_data(_transform_from_transform(target, target.origin)): return ""
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
	copy["transform"] = _transform_from_transform(target, target.origin)
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
	details.append(_door("door-left-0", "wall-left", dimensions))
	var building := {"id": building_id, "name": "Riverside Cottage", "schema_version": SCHEMA_VERSION, "generator_version": GENERATOR_VERSION, "dimensions": _vec(dimensions), "transform": _transform(position, MINIATURE_SCALE), "seed": seed, "shape_id": "classic_gable", "style_id": STYLE_ID, "roof_profile": "gentle_gable", "material_id": "stone_plaster", "wall_material_id": "stone_plaster", "roof_material_id": "terracotta", "material_overrides": {"shell": "stone_plaster", "roof": "terracotta"}, "surfaces": surfaces, "details": details, "automatic_defaults": [], "overrides": {}, "exclusions": [], "modified_locked": [], "suppressed": [], "manual_attachments": []}
	_reflow_automatic_windows(building)
	_refresh_buckets(building)
	return building

func _apply_home_design(building: Dictionary, design: Dictionary) -> void:
	building["name"] = str(design["name"])
	building["dimensions"] = _vec(design["dimensions"])
	building["shape_id"] = str(design["shape_id"])
	building["style_id"] = str(design["style_id"])
	building["roof_profile"] = str(design["roof_profile"])
	building["material_id"] = str(design["wall_material_id"])
	building["wall_material_id"] = str(design["wall_material_id"])
	building["roof_material_id"] = str(design["roof_material_id"])
	building["material_overrides"] = {"shell": building["wall_material_id"], "roof": building["roof_material_id"]}
	_reflow_automatic_windows(building)
	_refresh_buckets(building)

func _apply_wall_material(building: Dictionary, material_id: String) -> void:
	building["material_id"] = material_id
	building["wall_material_id"] = material_id
	var material_overrides: Dictionary = building.get("material_overrides", {})
	material_overrides["shell"] = material_id
	building["material_overrides"] = material_overrides

func _apply_roof_material(building: Dictionary, material_id: String) -> void:
	building["roof_material_id"] = material_id
	var material_overrides: Dictionary = building.get("material_overrides", {})
	material_overrides["roof"] = material_id
	building["material_overrides"] = material_overrides

func _freshen_home_ids(building: Dictionary) -> void:
	var id_map := {}
	for surface_index in (building["surfaces"] as Array).size():
		var surface: Dictionary = (building["surfaces"] as Array)[surface_index]
		var old_surface_id := str(surface["id"])
		var fresh_surface_id := _allocate_id("surface")
		id_map[old_surface_id] = fresh_surface_id
		surface["id"] = fresh_surface_id
		(building["surfaces"] as Array)[surface_index] = surface
	for detail_index in (building["details"] as Array).size():
		var detail: Dictionary = (building["details"] as Array)[detail_index]
		var fresh_detail_id := _allocate_id("detail")
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
		(building["details"] as Array)[detail_index] = detail
	_refresh_buckets(building)

## Slots are persistent recipe metadata, never attachment identities. Dormant
## slots keep their IDs and exclusions, so shrink/grow cannot resurrect a
## suppressed window or discard an edit. Older recipes opt in on resize only.
func _reflow_automatic_windows(building: Dictionary) -> void:
	var dimensions := _as_vec(building["dimensions"])
	var details: Array = building.get("details", [])
	building["automatic_layout"] = {"version": 1}
	for surface_value in building.get("surfaces", []):
		var surface: Dictionary = surface_value
		if str(surface.get("kind", "")) != "wall" or not str(surface.get("orientation", "")) in ["front", "back"]: continue
		var surface_id := str(surface["id"])
		var count := maxi(1, floori((dimensions.x - WINDOW_CORNER_CLEARANCE * 2.0) / WINDOW_TARGET_SPACING))
		if dimensions.x < (WINDOW_HALF_WIDTH + WINDOW_CORNER_CLEARANCE) * 2.0 or dimensions.y < 4.2 or bool(surface.get("deleted", false)) or not _surface_fits(building, surface, dimensions): count = 0
		var slots := {}
		for detail_value in details:
			var detail: Dictionary = detail_value
			if not bool(detail.get("generated", false)) or str(detail.get("kind", "")) != "window": continue
			var default_anchor: Dictionary = (detail.get("default", {}) as Dictionary).get("anchor", detail.get("anchor", {}))
			if str(default_anchor.get("surface_id", "")) != surface_id: continue
			var slot := int(detail.get("layout_slot", slots.size()))
			detail["layout_slot"] = slot
			slots[slot] = detail
		for slot in count:
			if slots.has(slot): continue
			# Namespaced by the independently allocated building/surface identity.
			var detail_id := "%s-auto-%s-%d" % [building["id"], surface_id, slot]
			var detail := _window(detail_id, surface_id, 0.5, 0.48)
			detail["layout_slot"] = slot
			details.append(detail)
			slots[slot] = detail
		for slot_value in slots:
			var slot := int(slot_value)
			var detail: Dictionary = slots[slot]
			detail["layout_active"] = slot < count
			if str(detail.get("state", "")) != "automatic": continue
			if slot >= count: continue
			var u := (float(slot) + 0.5) / float(count)
			var anchor := {"surface_id": surface_id, "policy": "proportional", "u": u, "v": clampf(0.48, 2.1 / dimensions.y, 1.0 - 1.7 / dimensions.y), "fixed_offset": WINDOW_CORNER_CLEARANCE}
			detail["anchor"] = anchor
			detail["default"] = {"id": detail["id"], "asset_id": detail["asset_id"], "u": u, "v": anchor["v"], "anchor": anchor.duplicate(true)}
	building["details"] = details

func _window(detail_id: String, surface_id: String, u: float, v: float) -> Dictionary:
	var default_anchor := {"surface_id": surface_id, "policy": "proportional", "u": u, "v": v, "fixed_offset": 1.25}
	return {"id": detail_id, "kind": "window", "asset_id": "window_wood", "state": "automatic", "generated": true, "anchor": default_anchor.duplicate(true), "default": {"id": detail_id, "asset_id": "window_wood", "u": u, "v": v, "anchor": default_anchor}, "needs_placement": false}

func _door(detail_id: String, surface_id: String, dimensions: Vector3) -> Dictionary:
	var v := clampf(2.45 / dimensions.y, 0.0, 1.0)
	var default_anchor := {"surface_id": surface_id, "policy": "proportional", "u": 0.5, "v": v, "fixed_offset": 1.5}
	return {"id": detail_id, "kind": "door", "asset_id": "door_timber", "state": "automatic", "generated": true, "anchor": default_anchor.duplicate(true), "default": {"id": detail_id, "asset_id": "door_timber", "u": 0.5, "v": v, "anchor": default_anchor}, "needs_placement": false}

func _upgrade_editable_doors(document: Dictionary) -> void:
	var buildings = document.get("buildings", [])
	if not buildings is Array: return
	var total := 0
	for building_value in buildings:
		if building_value is Dictionary and (building_value as Dictionary).get("details", null) is Array:
			total += ((building_value as Dictionary)["details"] as Array).size()
	for building_value in buildings:
		if not building_value is Dictionary: continue
		var building: Dictionary = building_value
		var details = building.get("details", null)
		if not details is Array: continue
		var has_door := false
		for detail_value in details:
			if detail_value is Dictionary and str((detail_value as Dictionary).get("kind", "")) == "door": has_door = true
		if has_door or total >= MAX_DETAILS: continue
		var dimensions = building.get("dimensions", null)
		if not _valid_vec_data(dimensions): continue
		var left_id := ""
		for surface_value in building.get("surfaces", []):
			if surface_value is Dictionary and str((surface_value as Dictionary).get("orientation", "")) == "left" and str((surface_value as Dictionary).get("kind", "")) == "wall":
				left_id = str((surface_value as Dictionary).get("id", "")); break
		if left_id.is_empty(): continue
		var door_id := "%s-door-0" % str(building.get("id", "building"))
		var suffix := 1
		while _detail_index(building, door_id) >= 0:
			door_id = "%s-door-%d" % [str(building.get("id", "building")), suffix]; suffix += 1
		(details as Array).append(_door(door_id, left_id, _as_vec(dimensions)))
		building["details"] = details
		_refresh_buckets(building)
		total += 1

func _resolved_building(building: Dictionary) -> Dictionary:
	var result: Dictionary = _copy(building)
	result["dimensions"] = _as_vec(building.get("dimensions", [0, 0, 0]))
	result["transform"] = _as_transform(building.get("transform", {}))
	result["shape_id"] = str(building.get("shape_id", "classic_gable"))
	result["wall_material_id"] = str(building.get("wall_material_id", building.get("material_id", "stone_plaster")))
	result["roof_material_id"] = str(building.get("roof_material_id", "terracotta"))
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
		if not needs and str(detail.get("state", "")) != "suppressed":
			var local: Vector3 = _resolve_position(surface, anchor, dimensions)
			var orientation := str(surface.get("orientation", "front"))
			var tangential := absf(local.x) if orientation in ["front", "back"] else absf(local.z)
			var extent := dimensions.x if orientation in ["front", "back"] else dimensions.z
			var footprint := _detail_footprint(detail)
			needs = tangential + footprint.x > extent * 0.5 or local.y - footprint.y < 0.0 or local.y + footprint.y > dimensions.y
		var position = null
		# Deleted support keeps its identity and orientation. Retain the intended
		# position for recovery tools while needs_placement still prevents render;
		# replacing it with null would make reattachment lose proportional intent.
		if not surface.is_empty(): position = _resolve_position(surface, anchor, dimensions)
		detail["resolved_position"] = position
		detail["needs_placement"] = needs
		var dormant := str(detail.get("state", "")) == "automatic" and not bool(detail.get("layout_active", true))
		if dormant: detail["needs_placement"] = false
		detail["visible"] = str(detail.get("state", "")) != "suppressed" and not dormant
		detail["show_shutters"] = false
		result.append(detail)
	# Preserve all authored choices. Automatic windows yield to their footprints
	# instead of painting over moved windows, boxes or manually added shutters.
	for index in result.size():
		var detail: Dictionary = result[index]
		if str(detail.get("state", "")) == "automatic" or not _placed_visible(detail): continue
		for other_index in index:
			var other: Dictionary = result[other_index]
			if str(other.get("state", "")) == "automatic": continue
			if _details_overlap(detail, other, 0.0):
				detail["needs_placement"] = true
				detail["placement_reason"] = "attachment_overlap"
				break
	for index in result.size():
		var detail: Dictionary = result[index]
		if str(detail.get("state", "")) != "automatic" or not _placed_visible(detail): continue
		for other_index in result.size():
			if other_index == index: continue
			var other: Dictionary = result[other_index]
			if str(other.get("state", "")) == "automatic" and other_index > index: continue
			# A moved-then-suppressed window excludes its chosen location too.
			# Otherwise a previously blocked automatic slot can immediately fill
			# the opening the player just removed.
			if _details_overlap(detail, other, WINDOW_GAP, true):
				detail["visible"] = false
				detail["layout_blocked"] = true
				break
	for detail in result:
		if not _placed_visible(detail) or str(detail.get("kind", "")) != "window" or str(detail.get("asset_id", "")).contains("round"): continue
		var surface := _surface(building, str(detail["anchor"]["surface_id"]))
		var local: Vector3 = detail["resolved_position"]
		var tangent := local.x if str(surface.get("orientation", "")) in ["front", "back"] else local.z
		var extent := dimensions.x if str(surface.get("orientation", "")) in ["front", "back"] else dimensions.z
		var fits := absf(tangent) + WINDOW_SHUTTER_HALF_WIDTH + WINDOW_CORNER_CLEARANCE <= extent * 0.5
		for other in result:
			if str(other["id"]) == str(detail["id"]) or not _placed_visible(other) or str(other["anchor"]["surface_id"]) != str(detail["anchor"]["surface_id"]): continue
			var other_local: Vector3 = other["resolved_position"]
			var other_tangent := other_local.x if str(surface.get("orientation", "")) in ["front", "back"] else other_local.z
			var other_half := WINDOW_SHUTTER_HALF_WIDTH if str(other.get("kind", "")) == "window" and not str(other.get("asset_id", "")).contains("round") else _detail_footprint(other).x
			if absf(other_local.y - local.y) < _detail_footprint(detail).y + _detail_footprint(other).y and absf(other_tangent - tangent) < WINDOW_SHUTTER_HALF_WIDTH + other_half + WINDOW_GAP: fits = false
		detail["show_shutters"] = fits
	return result

func _placed_visible(detail: Dictionary) -> bool:
	return bool(detail.get("visible", false)) and not bool(detail.get("needs_placement", false)) and detail.get("resolved_position") is Vector3

func _details_overlap(left: Dictionary, right: Dictionary, gap: float, reserve_suppression: bool = false) -> bool:
	var excluded_window := reserve_suppression and str(right.get("state", "")) == "suppressed" and str(right.get("kind", "")) == "window" and right.get("resolved_position") is Vector3
	if not _placed_visible(left) or not (_placed_visible(right) or excluded_window) or str(left["anchor"]["surface_id"]) != str(right["anchor"]["surface_id"]): return false
	var left_position: Vector3 = left["resolved_position"]
	var right_position: Vector3 = right["resolved_position"]
	var delta := left_position - right_position
	var left_size := _detail_footprint(left)
	var right_size := _detail_footprint(right)
	# Surface-normal coordinates match because both positions were resolved on
	# the same wall; the remaining horizontal delta is its tangent distance.
	return maxf(absf(delta.x), absf(delta.z)) < left_size.x + right_size.x + gap and absf(delta.y) < left_size.y + right_size.y

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
	var size := _detail_size(detail)
	if kind == "flower_box": return Vector2(0.8, 0.2)
	if kind == "shutter": return Vector2(0.33, 1.45)
	if kind == "door": return size * 0.5 + Vector2(0.38, 0.0)
	if asset.contains("round"): return size * 0.5 + Vector2(0.3, 0.3)
	return size * 0.5 + Vector2(0.375, 0.67)

func _detail_size(detail: Dictionary) -> Vector2:
	var override: Dictionary = detail.get("override", {})
	var value = override.get("size", null)
	if value is Array and (value as Array).size() == 2 and _valid_number(value[0]) and _valid_number(value[1]):
		return Vector2(float(value[0]), float(value[1]))
	if str(detail.get("kind", "")) == "door": return Vector2(1.75, 3.7)
	if str(detail.get("asset_id", "")).contains("round"): return Vector2(1.5, 1.5)
	return Vector2(2.0, 2.8)

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
		for field in ["shape_id", "style_id", "roof_profile", "material_id", "wall_material_id", "roof_material_id"]:
			if building.has(field) and str(building[field]).is_empty(): return false
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
			var override: Dictionary = detail.get("override", {})
			if override.has("size"):
				var size = override["size"]
				if not size is Array or (size as Array).size() != 2 or not _valid_number(size[0]) or not _valid_number(size[1]) or float(size[0]) <= 0.0 or float(size[1]) <= 0.0: return false
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

func _transform(position: Vector3, uniform_scale: float = 1.0) -> Dictionary:
	return {"position": _vec(position), "rotation": [0.0, 0.0, 0.0], "scale": _vec(Vector3.ONE * uniform_scale)}

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
