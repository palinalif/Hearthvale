extends "res://scripts/m2_building_world.gd"

const SectionEdit = preload("res://scripts/m2_section_edit.gd")
const SectionMassing = preload("res://scripts/m2_house_massing.gd")
const SectionSurfaces = preload("res://scripts/m2_massing_wall_surfaces.gd")

func preview_section_resize(building_id: String, section_id: String, candidate: Dictionary, expected_revision: int) -> Dictionary:
	if expected_revision != get_revision(): return {}
	var index := _building_index(building_id)
	if index < 0: return {}
	var view := get_building(building_id)
	var original := SectionEdit.section(view, section_id)
	if not original.is_empty() and candidate == original:
		return {"reason": "", "view": view, "document": get_document(), "revision": expected_revision}
	var reason := SectionEdit.invalid_reason(view, section_id, candidate)
	if not reason.is_empty(): return {"reason": reason}
	var temp := get_script().new() as RefCounted
	temp._document = get_document()
	temp._next_id = _next_id
	temp._revision = _revision
	var recipe: Dictionary = temp._document["buildings"][index]
	var sections := SectionEdit.replacement(view, section_id, candidate)
	if section_id == "core":
		var size: Vector3 = candidate["size"]
		if not _valid_dimensions(size): return {"reason": "Main section is outside its size limits"}
		var shift: Vector3 = candidate["offset"]
		var transform_value: Transform3D = view["transform"]
		recipe["transform"]["position"] = _vec(transform_value.origin + transform_value.basis * shift)
		recipe["dimensions"] = _vec(size)
		for item in sections: item["offset"] = (item["offset"] as Vector3) - shift
		for detail in recipe["details"]:
			var anchor: Dictionary = detail.get("anchor", {})
			if str(anchor.get("policy", "")) not in ["surface_local", "fixed_local"]: continue
			var position := _as_vec(anchor.get("local_position", [0,0,0])) - shift
			anchor["local_position"] = _vec(position)
			var overrides: Dictionary = detail.get("override", {})
			if overrides.has("local_position"): overrides["local_position"] = _vec(position)
		# Match pre-existing generated supports in the rebased coordinates.
		for support in recipe["surfaces"]:
			if not bool(support.get("massing_wall", false)): continue
			var axis := 0 if str(support["orientation"]) in ["front", "back"] else 2
			support["tangent_min"] = float(support["tangent_min"]) - shift[axis]
			support["tangent_max"] = float(support["tangent_max"]) - shift[axis]
			support["normal"] = float(support["normal"]) - shift[2 if axis == 0 else 0]
			support.erase("massing_key")
	if sections.size() == 1: recipe.erase("massing_sections"); recipe.erase("massing_preset")
	else:
		var records: Array = []
		for item in sections:
			records.append({"id": item["id"], "level": item["level"], "size": _vec(item["size"]), "offset": _vec(item["offset"])})
		recipe["massing_sections"] = records
		recipe["massing_preset"] = "custom"
	if not SectionSurfaces.sync_building(temp, recipe): return {"reason": "Too many editable wall runs"}
	temp._reflow_automatic_windows(recipe)
	temp._refresh_buckets(recipe)
	if not temp._validate_document(temp._document): return {"reason": "Section change cannot be saved"}
	return {"reason": "", "view": temp.get_building(building_id), "document": temp.get_document(), "revision": expected_revision}

func commit_section_resize(building_id: String, section_id: String, candidate: Dictionary, expected_revision: int) -> bool:
	var result := preview_section_resize(building_id, section_id, candidate, expected_revision)
	if not result.has("document"): return false
	var before := get_document()
	var old_next := _next_id
	_document = result["document"]
	_next_id = int(_document["next_id"])
	var ok := _record_change(before)
	if not ok: _next_id = old_next
	return ok
