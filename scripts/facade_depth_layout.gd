extends RefCounted
class_name FacadeDepthLayout

const Massing = preload("res://scripts/m2_house_massing.gd")
const EPSILON := 0.001
static var enabled := true

static func wall_runs(view: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var sections: Array[Dictionary] = Massing.sections_for(view)
	var multiple_sections := sections.size() > 1
	for value in view.get("surfaces", []):
		if not value is Dictionary: continue
		var surface: Dictionary = value
		if str(surface.get("kind", "wall")) != "wall" or bool(surface.get("deleted", false)): continue
		var surface_id := str(surface.get("id", ""))
		if bool(surface.get("massing_wall", false)):
			var run := _run_from_surface(surface)
			if not run.is_empty():
				run["surface_id"] = surface_id
				result.append(run)
			continue
		if surface.has("exposed_wall_runs"):
			var exposure = surface.get("exposed_wall_runs", [])
			if exposure is Array:
				for run_value in exposure:
					if not run_value is Dictionary: continue
					var run: Dictionary = (run_value as Dictionary).duplicate(true)
					if _valid_run(run):
						run["surface_id"] = surface_id
						result.append(run)
			continue
		if not multiple_sections:
			var legacy := _legacy_run(view, surface)
			if not legacy.is_empty():
				legacy["surface_id"] = surface_id
				result.append(legacy)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ak := "%s|%09.3f|%09.3f|%09.3f" % [str(a["orientation"]), float(a["normal"]), float(a["bottom"]), float(a["tangent_min"])]
		var bk := "%s|%09.3f|%09.3f|%09.3f" % [str(b["orientation"]), float(b["normal"]), float(b["bottom"]), float(b["tangent_min"])]
		return ak < bk)
	return result

static func shell_pieces(view: Dictionary, runs: Array[Dictionary], detail_unit: Vector3) -> Dictionary:
	var plinth: Array[Dictionary] = []
	var eave_reveals: Array[Dictionary] = []
	if not detail_unit.is_finite() or detail_unit.x <= 0.0 or detail_unit.y <= 0.0 or detail_unit.z <= 0.0:
		return {"plinth": plinth, "eave": eave_reveals}
	var door_cuts := _door_cuts(view, detail_unit)
	for run in runs:
		if not _valid_run(run): continue
		var orientation := str(run["orientation"])
		var low := float(run["tangent_min"])
		var high := float(run["tangent_max"])
		var bottom := float(run["bottom"])
		var top := float(run["top"])
		var normal := float(run["normal"])
		var normal_cell := detail_unit.z if orientation in ["front", "back"] else detail_unit.x
		var tangent_cell := detail_unit.x if orientation in ["front", "back"] else detail_unit.z
		var outward := -1.0 if orientation in ["front", "left"] else 1.0
		# A one-cell wall-top reveal gives the roof/eave a readable contact edge
		# without changing the wall or roof authority.
		var eave_depth := normal_cell
		var eave_center := normal + outward * eave_depth * 0.5
		eave_reveals.append(_axis_piece(orientation, (low + high) * 0.5, top - detail_unit.y * 0.5, eave_center, high - low, detail_unit.y, eave_depth))
		if absf(bottom) > EPSILON: continue
		var cuts: Array[Vector2] = []
		for cut_value in door_cuts.get(str(run.get("surface_id", "")), []):
			if cut_value is Vector2: cuts.append(cut_value)
		var segments := subtract_intervals(low, high, cuts)
		# Existing structural foundations project 0.25 local units. Put this
		# fine facing just outside them so it never z-fights with the shell.
		var depth := normal_cell
		var face_normal := normal + outward * (0.25 + depth * 0.5)
		for segment in segments:
			var span := segment.y - segment.x
			if span < tangent_cell * 0.5: continue
			plinth.append(_axis_piece(orientation, (segment.x + segment.y) * 0.5, detail_unit.y * 1.5, face_normal, span, detail_unit.y * 3.0, depth))
	return {"plinth": plinth, "eave": eave_reveals}

static func subtract_intervals(low: float, high: float, cuts: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if high <= low + EPSILON: return result
	cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var cursor := low
	for cut in cuts:
		var cut_low := clampf(minf(cut.x, cut.y), low, high)
		var cut_high := clampf(maxf(cut.x, cut.y), low, high)
		if cut_high <= cursor + EPSILON: continue
		if cut_low > cursor + EPSILON: result.append(Vector2(cursor, cut_low))
		cursor = maxf(cursor, cut_high)
		if cursor >= high - EPSILON: break
	if cursor < high - EPSILON: result.append(Vector2(cursor, high))
	return result

static func _door_cuts(view: Dictionary, detail_unit: Vector3) -> Dictionary:
	var orientations: Dictionary = {}
	for value in view.get("surfaces", []):
		if not value is Dictionary: continue
		var surface: Dictionary = value
		orientations[str(surface.get("id", ""))] = str(surface.get("orientation", "front"))
	var result: Dictionary = {}
	for value in view.get("details", []):
		if not value is Dictionary: continue
		var detail: Dictionary = value
		if str(detail.get("kind", "")) != "door" or not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)): continue
		var local = detail.get("resolved_position", null)
		if not local is Vector3: continue
		var surface_id := str((detail.get("anchor", {}) as Dictionary).get("surface_id", ""))
		var orientation := str(orientations.get(surface_id, "front"))
		var center := (local as Vector3).x if orientation in ["front", "back"] else (local as Vector3).z
		var size := _detail_size(detail, Vector2(1.75, 3.7))
		var margin := (detail_unit.x if orientation in ["front", "back"] else detail_unit.z) * 2.0
		if not result.has(surface_id): result[surface_id] = []
		(result[surface_id] as Array).append(Vector2(center - size.x * 0.5 - margin, center + size.x * 0.5 + margin))
	return result

static func _detail_size(detail: Dictionary, fallback: Vector2) -> Vector2:
	var overrides = detail.get("override", {})
	if overrides is Dictionary:
		var value = (overrides as Dictionary).get("size", null)
		if value is Array and (value as Array).size() == 2:
			return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return fallback

static func _axis_piece(orientation: String, tangent: float, y: float, normal: float, tangent_size: float, y_size: float, normal_size: float) -> Dictionary:
	if orientation in ["front", "back"]:
		return {"center": Vector3(tangent, y, normal), "size": Vector3(tangent_size, y_size, normal_size), "basis": Basis.IDENTITY}
	return {"center": Vector3(normal, y, tangent), "size": Vector3(normal_size, y_size, tangent_size), "basis": Basis.IDENTITY}

static func _run_from_surface(surface: Dictionary) -> Dictionary:
	var run := {
		"orientation": str(surface.get("orientation", "")),
		"normal": float(surface.get("normal", 0.0)),
		"tangent_min": float(surface.get("tangent_min", 0.0)),
		"tangent_max": float(surface.get("tangent_max", 0.0)),
		"bottom": float(surface.get("bottom", 0.0)),
		"top": float(surface.get("top", 0.0)),
	}
	return run if _valid_run(run) else {}

static func _legacy_run(view: Dictionary, surface: Dictionary) -> Dictionary:
	var dimensions: Vector3 = view.get("dimensions", Vector3.ZERO)
	if not dimensions.is_finite(): return {}
	var orientation := str(surface.get("orientation", ""))
	if orientation not in ["front", "back", "left", "right"]: return {}
	var front_back := orientation in ["front", "back"]
	var tangent := dimensions.x if front_back else dimensions.z
	var normal := (dimensions.z if front_back else dimensions.x) * (-0.5 if orientation in ["front", "left"] else 0.5)
	return {"orientation": orientation, "normal": normal, "tangent_min": -tangent * 0.5, "tangent_max": tangent * 0.5, "bottom": 0.0, "top": dimensions.y}

static func _valid_run(run: Dictionary) -> bool:
	return str(run.get("orientation", "")) in ["front", "back", "left", "right"] and float(run.get("tangent_max", 0.0)) > float(run.get("tangent_min", 0.0)) + EPSILON and float(run.get("top", 0.0)) > float(run.get("bottom", 0.0)) + EPSILON
