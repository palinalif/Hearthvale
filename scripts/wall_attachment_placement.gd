extends RefCounted

## Pure wall-placement math. BuildingWorld owns authoritative records.
static func wall_ids(view: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for surface_value in view.get("surfaces", []):
		var candidate: Dictionary = surface_value
		if str(candidate.get("kind", "")) != "wall" or bool(candidate.get("deleted", false)): continue
		var id := str(candidate.get("id", ""))
		if not id.is_empty(): result.append(id)
	return result

static func surface(view: Dictionary, surface_id: String) -> Dictionary:
	for surface_value in view.get("surfaces", []):
		var candidate: Dictionary = surface_value
		if str(candidate.get("id", "")) == surface_id: return candidate
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

## Manual details never silently displace one another. Automatic windows yield
## to manual placements in BuildingWorld, so they do not block the candidate.
static func position_available(view: Dictionary, detail_id: String, surface_id: String, position: Vector3, half: Vector2) -> bool:
	var clamped := clamp_to_wall(view, surface_id, position, half)
	if clamped.is_empty() or not (clamped["position"] as Vector3).is_equal_approx(position): return false
	var support := surface(view, surface_id)
	var axis := 0 if str(support.get("orientation", "")) in ["front", "back"] else 2
	for other in view.get("details", []):
		if str(other.get("id", "")) == detail_id or str(other.get("state", "")) in ["automatic", "suppressed"]: continue
		if not bool(other.get("visible", true)) or bool(other.get("needs_placement", false)): continue
		if str(other.get("anchor", {}).get("surface_id", "")) != surface_id: continue
		var other_position = other.get("resolved_position")
		if not other_position is Vector3: continue
		var other_half := footprint(str(other.get("kind", "")), str(other.get("asset_id", "")))
		if absf(position[axis] - other_position[axis]) < half.x + other_half.x and absf(position.y - other_position.y) < half.y + other_half.y: return false
	return true

static func nearest_available(view: Dictionary, detail_id: String, surface_id: String, intended: Vector3, half: Vector2) -> Dictionary:
	var initial := clamp_to_wall(view, surface_id, intended, half)
	if initial.is_empty(): return {}
	var position: Vector3 = initial["position"]
	if position_available(view, detail_id, surface_id, position, half): return initial
	var support := surface(view, surface_id)
	var axis := 0 if str(support.get("orientation", "")) in ["front", "back"] else 2
	var best: Dictionary = {}
	var best_distance := INF
	# Only used when recovering a displaced detail, never as a per-frame scan.
	for offset in range(1, 65):
		for sign_value in [-1.0, 1.0]:
			var candidate := position
			candidate[axis] += float(offset) * 0.5 * sign_value
			var clamped := clamp_to_wall(view, surface_id, candidate, half)
			if clamped.is_empty(): continue
			candidate = clamped["position"]
			if not position_available(view, detail_id, surface_id, candidate, half): continue
			var distance := candidate.distance_squared_to(intended)
			if distance < best_distance:
				best_distance = distance
				best = clamped
		if not best.is_empty(): return best
	return {}
