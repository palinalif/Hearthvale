extends RefCounted
class_name M2MassingWallSurfaces

const Massing = preload("res://scripts/m2_house_massing.gd")
const SURFACE_LIMIT := 64
const EPSILON := 0.051

## Generate missing ground-floor facades as well as upper-floor runs. Keep
## the four original supports as stable anchors, but restrict them to exposed
## geometry; an old rectangle is not an editable courtyard wall.
static func desired_upper_surfaces(view: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var sections: Array[Dictionary] = Massing.sections_for(view)
	var ground := Massing.sections_on_level(sections, 0)
	if ground.size() > 1:
		var runs: Array[Dictionary] = []
		_append_level_runs(runs, ground, 0)
		for run in runs:
			var covered := false
			for support in view.get("surfaces", []):
				if str(support.get("kind", "")) != "wall" or bool(support.get("massing_wall", false)) or bool(support.get("deleted", false)): continue
				if _legacy_covers_run(view, support, run): covered = true; break
			if not covered: result.append(run)
	var top_level: int = Massing.max_level(sections)
	for level in range(1, top_level + 1):
		var level_sections: Array[Dictionary] = Massing.sections_on_level(sections, level)
		if level_sections.is_empty(): continue
		_append_level_runs(result, level_sections, level)
	return result

static func sync_building(world: RefCounted, building: Dictionary) -> bool:
	var desired: Array[Dictionary] = desired_upper_surfaces(building)
	var old_surfaces: Array = building.get("surfaces", [])
	var base_surfaces: Array[Dictionary] = []
	var old_generated: Array[Dictionary] = []
	for value in old_surfaces:
		if not value is Dictionary: continue
		var support: Dictionary = value
		if bool(support.get("massing_wall", false)): old_generated.append(support.duplicate(true))
		else: base_surfaces.append(support.duplicate(true))

	var ground_runs: Array[Dictionary] = []
	var ground := Massing.sections_on_level(Massing.sections_for(building), 0)
	if ground.size() > 1: _append_level_runs(ground_runs, ground, 0)
	for support in base_surfaces:
		if str(support.get("kind", "")) != "wall": continue
		support.erase("exposed_wall_runs")
		if ground.size() <= 1: continue
		var exposure: Array[Dictionary] = []
		var original := _legacy_geometry(building, support)
		for run in ground_runs:
			if not _same_plane(original, run): continue
			var piece: Dictionary = run.duplicate(true)
			piece["tangent_min"] = maxf(float(original["tangent_min"]), float(run["tangent_min"]))
			piece["tangent_max"] = minf(float(original["tangent_max"]), float(run["tangent_max"]))
			if float(piece["tangent_max"]) > float(piece["tangent_min"]): exposure.append(piece)
		support["exposed_wall_runs"] = exposure

	var anchored_ids: Dictionary = {}
	for detail_value in building.get("details", []):
		if not detail_value is Dictionary: continue
		var detail: Dictionary = detail_value
		var anchor: Dictionary = detail.get("anchor", {})
		anchored_ids[str(anchor.get("surface_id", ""))] = true

	var orphan_count := 0
	for old in old_generated:
		if anchored_ids.has(str(old.get("id", ""))): orphan_count += 1
	if base_surfaces.size() + desired.size() + orphan_count > SURFACE_LIMIT: return false

	var used_ids: Dictionary = {}
	var generated: Array[Dictionary] = []
	for spec_value in desired:
		var spec: Dictionary = spec_value
		var matched: Dictionary = _matching_surface(old_generated, used_ids, spec)
		var id: String = str(matched.get("id", ""))
		if id.is_empty(): id = world._allocate_id("surface")
		used_ids[id] = true
		var support: Dictionary = spec.duplicate(true)
		support["id"] = id
		support["deleted"] = false
		generated.append(support)

	# A removed wall with authored content remains as a deleted support. The
	# normal BuildingWorld recovery path will mark its details Needs placement.
	for old_value in old_generated:
		var old: Dictionary = old_value
		var old_id: String = str(old.get("id", ""))
		if used_ids.has(old_id) or not anchored_ids.has(old_id): continue
		old["deleted"] = true
		generated.append(old)

	var surfaces: Array = []
	for support in base_surfaces: surfaces.append(support)
	for support in generated: surfaces.append(support)
	if surfaces.size() > SURFACE_LIMIT: return false
	building["surfaces"] = surfaces
	return true

static func _append_level_runs(result: Array[Dictionary], sections: Array[Dictionary], level: int) -> void:
	var bounds: Rect2 = Massing.union_bounds(sections)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0: return
	var x_count: int = maxi(1, ceili(bounds.size.x / Massing.CELL))
	var z_count: int = maxi(1, ceili(bounds.size.y / Massing.CELL))
	var cells: Dictionary = {}
	for x_index in x_count:
		for z_index in z_count:
			var x: float = bounds.position.x + (float(x_index) + 0.5) * Massing.CELL
			var z: float = bounds.position.y + (float(z_index) + 0.5) * Massing.CELL
			var vertical: Dictionary = _vertical_at(sections, x, z)
			if not vertical.is_empty(): cells[Vector2i(x_index, z_index)] = vertical

	var groups: Dictionary = {}
	var directions := {
		"front": Vector2i(0, -1),
		"back": Vector2i(0, 1),
		"left": Vector2i(-1, 0),
		"right": Vector2i(1, 0),
	}
	for key_value in cells.keys():
		var key: Vector2i = key_value
		var vertical: Dictionary = cells[key]
		var center_x: float = bounds.position.x + (float(key.x) + 0.5) * Massing.CELL
		var center_z: float = bounds.position.y + (float(key.y) + 0.5) * Massing.CELL
		for orientation_value in directions.keys():
			var orientation: String = str(orientation_value)
			var direction: Vector2i = directions[orientation]
			if cells.has(key + direction): continue
			var normal: float = 0.0
			var tangent_start: float = 0.0
			var tangent_end: float = 0.0
			if orientation in ["front", "back"]:
				normal = center_z + (-Massing.CELL * 0.5 if orientation == "front" else Massing.CELL * 0.5)
				tangent_start = center_x - Massing.CELL * 0.5
				tangent_end = center_x + Massing.CELL * 0.5
			else:
				normal = center_x + (-Massing.CELL * 0.5 if orientation == "left" else Massing.CELL * 0.5)
				tangent_start = center_z - Massing.CELL * 0.5
				tangent_end = center_z + Massing.CELL * 0.5
			var group_key: String = "%d|%s|%d|%d|%d" % [level, orientation, roundi(normal / Massing.CELL), roundi(float(vertical["bottom"]) / Massing.CELL), roundi(float(vertical["top"]) / Massing.CELL)]
			if not groups.has(group_key): groups[group_key] = []
			(groups[group_key] as Array).append({"orientation": orientation, "normal": normal, "bottom": float(vertical["bottom"]), "top": float(vertical["top"]), "start": tangent_start, "end": tangent_end})

	var ordered_keys: Array = groups.keys()
	ordered_keys.sort()
	for group_key_value in ordered_keys:
		var group_key: String = str(group_key_value)
		var faces: Array = groups[group_key]
		faces.sort_custom(func(a: Dictionary, b: Dictionary): return float(a["start"]) < float(b["start"]))
		var runs: Array[Dictionary] = []
		for face_value in faces:
			var face: Dictionary = face_value
			if runs.is_empty() or float(face["start"]) > float(runs[-1]["end"]) + EPSILON:
				runs.append(face.duplicate(true))
			else:
				var tail: Dictionary = runs[-1]
				tail["end"] = maxf(float(tail["end"]), float(face["end"]))
				runs[-1] = tail
		for run_index in runs.size():
			var run: Dictionary = runs[run_index]
			var orientation: String = str(run["orientation"])
			var span: float = float(run["end"]) - float(run["start"])
			if span <= EPSILON: continue
			result.append({
				"kind": "wall",
				"orientation": orientation,
				"extent_axis": "x" if orientation in ["front", "back"] else "z",
				"min_extent": 0.5,
				"deleted": false,
				"massing_wall": true,
				"massing_level": level,
				"edge_owners": _edge_owners(sections, run),
				"massing_key": "%s|run:%d" % [group_key, run_index],
				"tangent_min": float(run["start"]),
				"tangent_max": float(run["end"]),
				"bottom": float(run["bottom"]),
				"top": float(run["top"]),
				"normal": float(run["normal"]),
			})

static func _vertical_at(sections: Array[Dictionary], x: float, z: float) -> Dictionary:
	var point := Vector2(x, z)
	var found := false
	var bottom := INF
	var top := -INF
	for section_value in sections:
		var section: Dictionary = section_value
		var rect: Rect2 = Massing.section_rect(section)
		if point.x < rect.position.x - EPSILON or point.x > rect.end.x + EPSILON or point.y < rect.position.y - EPSILON or point.y > rect.end.y + EPSILON: continue
		found = true
		bottom = minf(bottom, Massing.section_bottom(section))
		top = maxf(top, Massing.section_top(section))
	return {"bottom": bottom, "top": top} if found else {}

static func _matching_surface(existing: Array[Dictionary], used_ids: Dictionary, desired: Dictionary) -> Dictionary:
	var desired_key: String = str(desired.get("massing_key", ""))
	for support_value in existing:
		var support: Dictionary = support_value
		var id: String = str(support.get("id", ""))
		if used_ids.has(id): continue
		if str(support.get("massing_key", "")) == desired_key: return support

	var best: Dictionary = {}
	var best_overlap := 0.0
	for support_value in existing:
		var support: Dictionary = support_value
		var id: String = str(support.get("id", ""))
		if used_ids.has(id): continue
		if int(support.get("massing_level", -1)) != int(desired.get("massing_level", -2)): continue
		if str(support.get("orientation", "")) != str(desired.get("orientation", "")): continue
		if absf(float(support.get("normal", 99999.0)) - float(desired.get("normal", -99999.0))) > EPSILON: continue
		var overlap: float = minf(float(support.get("tangent_max", 0.0)), float(desired.get("tangent_max", 0.0))) - maxf(float(support.get("tangent_min", 0.0)), float(desired.get("tangent_min", 0.0)))
		if overlap > best_overlap:
			best_overlap = overlap
			best = support
	if not best.is_empty(): return best
	# When a simple facade moves with its section, keep its identity. Do not
	# guess across a split/merged wall with multiple possible owners.
	var owners: Array = desired.get("edge_owners", [])
	if owners.size() == 1:
		for support in existing:
			if used_ids.has(str(support.get("id", ""))): continue
			if int(support.get("massing_level", -1)) != int(desired.get("massing_level", -2)): continue
			if str(support.get("orientation", "")) != str(desired.get("orientation", "")): continue
			if support.get("edge_owners", []) == owners: return support
	return best

static func _edge_owners(sections: Array[Dictionary], run: Dictionary) -> Array[String]:
	var owners: Array[String] = []
	var orientation := str(run["orientation"])
	for section in sections:
		var rect := Massing.section_rect(section)
		var normal: float = rect.position.y if orientation == "front" else rect.end.y if orientation == "back" else rect.position.x if orientation == "left" else rect.end.x
		if absf(normal - float(run["normal"])) > 0.001: continue
		var low: float = rect.position.x if orientation in ["front", "back"] else rect.position.y
		var high: float = rect.end.x if orientation in ["front", "back"] else rect.end.y
		if minf(high, float(run["end"])) <= maxf(low, float(run["start"])): continue
		owners.append(str(section["id"]))
	owners.sort()
	return owners

static func _legacy_geometry(view: Dictionary, support: Dictionary) -> Dictionary:
	var size := Massing.storey_height(view)
	var dimensions: Vector3 = Massing.core_section(view)["size"]
	var orientation := str(support.get("orientation", ""))
	var front := orientation in ["front", "back"]
	var tangent := dimensions.x if front else dimensions.z
	var normal := (dimensions.z if front else dimensions.x) * (-0.5 if orientation in ["front", "left"] else 0.5)
	return {"orientation": orientation, "normal": normal, "tangent_min": -tangent * 0.5, "tangent_max": tangent * 0.5, "bottom": 0.0, "top": size}

static func _same_plane(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("orientation", "")) == str(b.get("orientation", "")) and absf(float(a.get("normal", INF)) - float(b.get("normal", -INF))) < 0.001

static func _legacy_covers_run(view: Dictionary, support: Dictionary, run: Dictionary) -> bool:
	var geometry := _legacy_geometry(view, support)
	return _same_plane(geometry, run) and float(geometry["tangent_min"]) <= float(run["tangent_min"]) + 0.001 and float(geometry["tangent_max"]) >= float(run["tangent_max"]) - 0.001 and float(geometry["top"]) >= float(run["top"]) - 0.001
