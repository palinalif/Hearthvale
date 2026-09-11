extends RefCounted

## Authoritative facade picking: no whole-house box across an empty courtyard.
const Massing = preload("res://scripts/m2_house_massing.gd")
const Placement = preload("res://scripts/wall_attachment_placement.gd")

static func walls(view: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for support in view.get("surfaces", []):
		if str(support.get("kind", "")) != "wall" or bool(support.get("deleted", false)): continue
		var runs: Array = support.get("exposed_wall_runs", [Placement.wall_geometry(view, support)])
		for run in runs:
			if run.is_empty(): continue
			var item: Dictionary = run.duplicate(true)
			item["surface_id"] = str(support["id"])
			item["massing_level"] = int(support.get("massing_level", item.get("massing_level", 0)))
			item["edge_owners"] = support.get("edge_owners", item.get("edge_owners", []))
			result.append(item)
	return result

static func pick_wall(runs: Array[Dictionary], origin: Vector3, direction: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var nearest := INF
	for run in runs:
		var orientation := str(run["orientation"])
		var axis := 2 if orientation in ["front", "back"] else 0
		var tangent_axis := 0 if axis == 2 else 2
		var sign_value := -1.0 if orientation in ["front", "left"] else 1.0
		if direction[axis] * sign_value >= -0.00001: continue
		var distance := (float(run["normal"]) - origin[axis]) / direction[axis]
		if distance < 0 or distance >= nearest: continue
		var point := origin + direction * distance
		if point[tangent_axis] < float(run["tangent_min"]) or point[tangent_axis] > float(run["tangent_max"]): continue
		if point.y < float(run["bottom"]) or point.y > float(run["top"]): continue
		nearest = distance
		best = {"kind": "wall", "surface_id": run["surface_id"], "position": point, "distance": distance, "run": run}
	return best

static func section_at(view: Dictionary, point: Vector3, roof: bool = false) -> String:
	var best := ""
	var best_top := -INF
	for item in Massing.sections_for(view):
		var rect := Massing.section_rect(item).grow(0.26)
		if not rect.has_point(Vector2(point.x, point.z)): continue
		var top := Massing.section_top(item)
		if not roof and (point.y < Massing.section_bottom(item) - 0.01 or point.y > top + 0.01): continue
		if roof and Massing.section_bottom(item) > point.y: continue
		if top > best_top:
			best_top = top
			best = str(item["id"])
	return best
