extends RefCounted
class_name M2MassingWallSurfaces

const Massing = preload("res://scripts/m2_house_massing.gd")
const SURFACE_LIMIT := 64
const EPSILON := 0.051

## Returns one bounded selectable wall per contiguous exposed run on floors 2+.
## Ground-floor authored surfaces remain untouched so existing attachment IDs
## and automatic-window behaviour keep their M1 semantics.
static func desired_upper_surfaces(view: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var sections: Array[Dictionary] = Massing.sections_for(view)
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
	return best
