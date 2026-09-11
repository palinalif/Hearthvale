extends RefCounted

## Pure wall-placement math. BuildingWorld owns authoritative records.
## Legacy walls span the original rectangular house. Generated massing walls
## carry explicit tangent/vertical bounds so the same placement tools work on
## upper storeys and stepped/joined facades.
static func wall_ids(view: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for surface_value in view.get("surfaces", []):
		var candidate: Dictionary = surface_value
		if str(candidate.get("kind", "")) != "wall" or bool(candidate.get("deleted", false)): continue
		if candidate.has("exposed_wall_runs") and (candidate["exposed_wall_runs"] as Array).is_empty(): continue
		var id := str(candidate.get("id", ""))
		if not id.is_empty(): result.append(id)
	return result

static func surface(view: Dictionary, surface_id: String) -> Dictionary:
	for surface_value in view.get("surfaces", []):
		var candidate: Dictionary = surface_value
		if str(candidate.get("id", "")) == surface_id: return candidate
	return {}

static func surface_label(view: Dictionary, surface_id: String) -> String:
	var support: Dictionary = surface(view, surface_id)
	if support.is_empty(): return surface_id
	var orientation: String = str(support.get("orientation", "wall")).capitalize()
	if bool(support.get("massing_wall", false)):
		return "Floor %d %s" % [int(support.get("massing_level", 0)) + 1, orientation]
	return orientation

static func footprint(kind: String, asset_id: String = "") -> Vector2:
	if kind == "flower_box": return Vector2(0.8, 0.2)
	if kind == "shutter": return Vector2(0.33, 1.45)
	if kind == "door": return Vector2(1.5, 3.25)
	if asset_id.contains("round"): return Vector2(0.8, 0.8)
	return Vector2(1.375, 2.07)

static func detail_size(detail: Dictionary) -> Vector2:
	var value = (detail.get("override", {}) as Dictionary).get("size", null)
	if value is Array and (value as Array).size() == 2: return Vector2(float(value[0]), float(value[1]))
	if str(detail.get("kind", "")) == "door": return Vector2(1.75, 3.7)
	if str(detail.get("asset_id", "")).contains("round"): return Vector2(1.5, 1.5)
	return Vector2(2.0, 2.8)

static func footprint_for_detail(detail: Dictionary) -> Vector2:
	var kind := str(detail.get("kind", "window"))
	if kind not in ["window", "door"]: return footprint(kind, str(detail.get("asset_id", "")))
	var size := detail_size(detail)
	if kind == "door": return size * 0.5 + Vector2(0.38, 0.0)
	if str(detail.get("asset_id", "")).contains("round"): return size * 0.5 + Vector2(0.3, 0.3)
	return size * 0.5 + Vector2(0.375, 0.67)

static func wall_geometry(view: Dictionary, support: Dictionary) -> Dictionary:
	var dimensions = view.get("dimensions", Vector3.ZERO)
	if not dimensions is Vector3: return {}
	var dims: Vector3 = dimensions
	var orientation: String = str(support.get("orientation", ""))
	if orientation not in ["front", "back", "left", "right"]: return {}
	if bool(support.get("massing_wall", false)):
		var tangent_min: float = float(support.get("tangent_min", 0.0))
		var tangent_max: float = float(support.get("tangent_max", 0.0))
		var bottom: float = float(support.get("bottom", 0.0))
		var top: float = float(support.get("top", 0.0))
		var normal: float = float(support.get("normal", 0.0))
		if tangent_max <= tangent_min or top <= bottom: return {}
		return {"orientation": orientation, "tangent_min": tangent_min, "tangent_max": tangent_max, "bottom": bottom, "top": top, "normal": normal}
	var tangent_extent: float = dims.x if orientation in ["front", "back"] else dims.z
	var normal: float = 0.0
	if orientation == "front": normal = -dims.z * 0.5
	elif orientation == "back": normal = dims.z * 0.5
	elif orientation == "left": normal = -dims.x * 0.5
	else: normal = dims.x * 0.5
	return {"orientation": orientation, "tangent_min": -tangent_extent * 0.5, "tangent_max": tangent_extent * 0.5, "bottom": 0.0, "top": dims.y, "normal": normal}

static func clamp_to_wall(view: Dictionary, surface_id: String, local_position: Vector3, detail_footprint: Vector2) -> Dictionary:
	if not local_position.is_finite() or not detail_footprint.is_finite(): return {}
	var support := surface(view, surface_id)
	if support.is_empty() or str(support.get("kind", "")) != "wall" or bool(support.get("deleted", false)): return {}
	if support.has("exposed_wall_runs"):
		var nearest: Dictionary = {}
		var distance := INF
		for run in support["exposed_wall_runs"]:
			var candidate := _clamp_geometry(run, surface_id, local_position, detail_footprint)
			if candidate.is_empty(): continue
			var next_distance := (candidate["position"] as Vector3).distance_squared_to(local_position)
			if next_distance < distance: nearest = candidate; distance = next_distance
		return nearest
	return _clamp_geometry(wall_geometry(view, support), surface_id, local_position, detail_footprint)

static func _clamp_geometry(geometry: Dictionary, surface_id: String, local_position: Vector3, detail_footprint: Vector2) -> Dictionary:
	if geometry.is_empty(): return {}
	var orientation: String = str(geometry["orientation"])
	var tangent_min: float = float(geometry["tangent_min"]) + detail_footprint.x
	var tangent_max: float = float(geometry["tangent_max"]) - detail_footprint.x
	var min_y: float = float(geometry["bottom"]) + detail_footprint.y
	var max_y: float = float(geometry["top"]) - detail_footprint.y
	if tangent_max < tangent_min or max_y < min_y: return {}
	var result := local_position
	result.y = clampf(result.y, min_y, max_y)
	var normal: float = float(geometry["normal"])
	match orientation:
		"front":
			result.x = clampf(result.x, tangent_min, tangent_max)
			result.z = normal - 0.02
		"back":
			result.x = clampf(result.x, tangent_min, tangent_max)
			result.z = normal + 0.02
		"left":
			result.z = clampf(result.z, tangent_min, tangent_max)
			result.x = normal - 0.02
		"right":
			result.z = clampf(result.z, tangent_min, tangent_max)
			result.x = normal + 0.02
	return {"surface_id": surface_id, "orientation": orientation, "position": result}

static func remap_between_walls(view: Dictionary, from_surface_id: String, to_surface_id: String, local_position: Vector3, detail_footprint: Vector2) -> Dictionary:
	var from_surface := surface(view, from_surface_id)
	var to_surface := surface(view, to_surface_id)
	if from_surface.is_empty() or to_surface.is_empty(): return {}
	var from_geometry: Dictionary = wall_geometry(view, from_surface)
	var to_geometry: Dictionary = wall_geometry(view, to_surface)
	if from_geometry.is_empty() or to_geometry.is_empty(): return {}
	var from_orientation: String = str(from_geometry["orientation"])
	var to_orientation: String = str(to_geometry["orientation"])
	var old_min: float = float(from_geometry["tangent_min"]) + detail_footprint.x
	var old_max: float = float(from_geometry["tangent_max"]) - detail_footprint.x
	var new_min: float = float(to_geometry["tangent_min"]) + detail_footprint.x
	var new_max: float = float(to_geometry["tangent_max"]) - detail_footprint.x
	var old_y_min: float = float(from_geometry["bottom"]) + detail_footprint.y
	var old_y_max: float = float(from_geometry["top"]) - detail_footprint.y
	var new_y_min: float = float(to_geometry["bottom"]) + detail_footprint.y
	var new_y_max: float = float(to_geometry["top"]) - detail_footprint.y
	if new_max < new_min or new_y_max < new_y_min: return {}
	var old_tangent: float = local_position.x if from_orientation in ["front", "back"] else local_position.z
	var ratio: float = 0.5 if old_max <= old_min else clampf(inverse_lerp(old_min, old_max, old_tangent), 0.0, 1.0)
	var vertical_ratio: float = 0.5 if old_y_max <= old_y_min else clampf(inverse_lerp(old_y_min, old_y_max, local_position.y), 0.0, 1.0)
	var remapped := local_position
	var new_tangent: float = lerpf(new_min, new_max, ratio)
	if to_orientation in ["front", "back"]: remapped.x = new_tangent
	else: remapped.z = new_tangent
	remapped.y = lerpf(new_y_min, new_y_max, vertical_ratio)
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
		if not same_wall_plane(view, surface_id, str(other.get("anchor", {}).get("surface_id", ""))): continue
		var other_position = other.get("resolved_position")
		if not other_position is Vector3: continue
		var other_half := footprint_for_detail(other)
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

## A joined wall and a retained legacy anchor may describe the same plane.
## Different surface IDs must not allow authored details to overlap there.
static func same_wall_plane(view: Dictionary, a_id: String, b_id: String) -> bool:
	if a_id == b_id: return true
	var a := wall_geometry(view, surface(view, a_id))
	var b := wall_geometry(view, surface(view, b_id))
	return not a.is_empty() and not b.is_empty() and str(a["orientation"]) == str(b["orientation"]) and absf(float(a["normal"]) - float(b["normal"])) < 0.001
