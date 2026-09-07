extends RefCounted

## Pure wall-placement math for controller previews. BuildingWorld remains the
## authoritative recipe; this helper only clamps and remaps temporary local
## positions before A commits them.

static func wall_ids(view: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for surface_value in view.get("surfaces", []):
		var surface: Dictionary = surface_value
		if str(surface.get("kind", "")) != "wall" or bool(surface.get("deleted", false)):
			continue
		var id := str(surface.get("id", ""))
		if not id.is_empty(): result.append(id)
	return result

static func surface(view: Dictionary, surface_id: String) -> Dictionary:
	for surface_value in view.get("surfaces", []):
		var candidate: Dictionary = surface_value
		if str(candidate.get("id", "")) == surface_id:
			return candidate
	return {}

static func footprint(kind: String, asset_id: String = "") -> Vector2:
	if kind == "flower_box": return Vector2(0.8, 0.2)
	if kind == "shutter": return Vector2(0.33, 1.45)
	if kind == "door": return Vector2(1.5, 3.25)
	if asset_id.contains("round"): return Vector2(0.8, 0.8)
	return Vector2(1.375, 2.07)

static func clamp_to_wall(view: Dictionary, surface_id: String, local_position: Vector3, detail_footprint: Vector2) -> Dictionary:
	if not local_position.is_finite() or not detail_footprint.is_finite(): return {}
	var support := surface(view, surface_id)
	if support.is_empty() or str(support.get("kind", "")) != "wall" or bool(support.get("deleted", false)): return {}
	var dimensions = view.get("dimensions", Vector3.ZERO)
	if not dimensions is Vector3: return {}
	var dims: Vector3 = dimensions
	var orientation := str(support.get("orientation", ""))
	if orientation not in ["front", "back", "left", "right"]: return {}
	var tangent_extent := dims.x if orientation in ["front", "back"] else dims.z
	var tangent_limit := tangent_extent * 0.5 - detail_footprint.x
	var min_y := detail_footprint.y
	var max_y := dims.y - detail_footprint.y
	if tangent_limit < 0.0 or max_y < min_y: return {}
	var result := local_position
	result.y = clampf(result.y, min_y, max_y)
	match orientation:
		"front":
			result.x = clampf(result.x, -tangent_limit, tangent_limit)
			result.z = -dims.z * 0.5 - 0.02
		"back":
			result.x = clampf(result.x, -tangent_limit, tangent_limit)
			result.z = dims.z * 0.5 + 0.02
		"left":
			result.z = clampf(result.z, -tangent_limit, tangent_limit)
			result.x = -dims.x * 0.5 - 0.02
		"right":
			result.z = clampf(result.z, -tangent_limit, tangent_limit)
			result.x = dims.x * 0.5 + 0.02
	return {"surface_id": surface_id, "orientation": orientation, "position": result}

static func remap_between_walls(view: Dictionary, from_surface_id: String, to_surface_id: String, local_position: Vector3, detail_footprint: Vector2) -> Dictionary:
	var from_surface := surface(view, from_surface_id)
	var to_surface := surface(view, to_surface_id)
	if from_surface.is_empty() or to_surface.is_empty(): return {}
	var dimensions = view.get("dimensions", Vector3.ZERO)
	if not dimensions is Vector3: return {}
	var dims: Vector3 = dimensions
	var from_orientation := str(from_surface.get("orientation", ""))
	var to_orientation := str(to_surface.get("orientation", ""))
	if from_orientation not in ["front", "back", "left", "right"] or to_orientation not in ["front", "back", "left", "right"]: return {}
	var old_extent := dims.x if from_orientation in ["front", "back"] else dims.z
	var new_extent := dims.x if to_orientation in ["front", "back"] else dims.z
	var old_limit := maxf(0.001, old_extent * 0.5 - detail_footprint.x)
	var new_limit := maxf(0.0, new_extent * 0.5 - detail_footprint.x)
	var old_tangent := local_position.x if from_orientation in ["front", "back"] else local_position.z
	var ratio := clampf(old_tangent / old_limit, -1.0, 1.0)
	var remapped := local_position
	if to_orientation in ["front", "back"]: remapped.x = ratio * new_limit
	else: remapped.z = ratio * new_limit
	return clamp_to_wall(view, to_surface_id, remapped, detail_footprint)
