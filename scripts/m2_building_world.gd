extends "res://scripts/building_world.gd"
class_name M2BuildingWorld

## M2 keeps the M1 document schema, but generated massing walls can describe a
## bounded facade run instead of implicitly spanning the original rectangle.
## All legacy surfaces fall straight through to BuildingWorld behaviour.

func _surface_geometry(surface: Dictionary, dimensions: Vector3) -> Dictionary:
	var orientation: String = str(surface.get("orientation", ""))
	if orientation not in ["front", "back", "left", "right"]: return {}
	if bool(surface.get("massing_wall", false)):
		var tangent_min: float = float(surface.get("tangent_min", 0.0))
		var tangent_max: float = float(surface.get("tangent_max", 0.0))
		var bottom: float = float(surface.get("bottom", 0.0))
		var top: float = float(surface.get("top", 0.0))
		var normal: float = float(surface.get("normal", 0.0))
		if tangent_max <= tangent_min or top <= bottom: return {}
		return {"orientation": orientation, "tangent_min": tangent_min, "tangent_max": tangent_max, "bottom": bottom, "top": top, "normal": normal}
	var tangent_extent: float = dimensions.x if orientation in ["front", "back"] else dimensions.z
	var normal: float = 0.0
	if orientation == "front": normal = -dimensions.z * 0.5
	elif orientation == "back": normal = dimensions.z * 0.5
	elif orientation == "left": normal = -dimensions.x * 0.5
	else: normal = dimensions.x * 0.5
	return {"orientation": orientation, "tangent_min": -tangent_extent * 0.5, "tangent_max": tangent_extent * 0.5, "bottom": 0.0, "top": dimensions.y, "normal": normal}

func _resolve_position(surface: Dictionary, anchor: Dictionary, dimensions: Vector3):
	if not bool(surface.get("massing_wall", false)):
		return super._resolve_position(surface, anchor, dimensions)
	var geometry: Dictionary = _surface_geometry(surface, dimensions)
	if geometry.is_empty(): return Vector3.ZERO
	var orientation: String = str(geometry["orientation"])
	var normal: float = float(geometry["normal"])
	var policy: String = str(anchor.get("policy", "proportional"))
	if policy in ["fixed_local", "surface_local"]:
		var local: Vector3 = _as_vec(anchor.get("local_position", [0, 0, 0]))
		if orientation == "front": local.z = normal - 0.02
		elif orientation == "back": local.z = normal + 0.02
		elif orientation == "left": local.x = normal - 0.02
		else: local.x = normal + 0.02
		return local
	var u: float = clampf(float(anchor.get("u", 0.5)), 0.0, 1.0)
	var v: float = clampf(float(anchor.get("v", 0.5)), 0.0, 1.0)
	var offset: float = maxf(0.0, float(anchor.get("fixed_offset", 1.25)))
	var tangent_min: float = float(geometry["tangent_min"]) + offset
	var tangent_max: float = float(geometry["tangent_max"]) - offset
	if tangent_max < tangent_min:
		var middle: float = (float(geometry["tangent_min"]) + float(geometry["tangent_max"])) * 0.5
		tangent_min = middle
		tangent_max = middle
	var tangent: float = lerpf(tangent_min, tangent_max, u)
	var y: float = lerpf(float(geometry["bottom"]), float(geometry["top"]), v)
	if orientation == "front": return Vector3(tangent, y, normal - 0.02)
	if orientation == "back": return Vector3(tangent, y, normal + 0.02)
	if orientation == "left": return Vector3(normal - 0.02, y, tangent)
	return Vector3(normal + 0.02, y, tangent)

func _surface_fits(building: Dictionary, surface: Dictionary, dimensions: Vector3) -> bool:
	if not bool(surface.get("massing_wall", false)):
		return super._surface_fits(building, surface, dimensions)
	var geometry: Dictionary = _surface_geometry(surface, dimensions)
	if geometry.is_empty(): return false
	return float(geometry["tangent_max"]) - float(geometry["tangent_min"]) >= float(surface.get("min_extent", 0.0))

func _resolved_details(building: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dimensions: Vector3 = _as_vec(building.get("dimensions", [0, 0, 0]))
	for detail_value in building.get("details", []):
		var detail: Dictionary = _copy(detail_value)
		var anchor: Dictionary = detail.get("anchor", {})
		var support: Dictionary = _surface(building, str(anchor.get("surface_id", "")))
		var needs: bool = str(detail.get("state", "")) != "suppressed" and (support.is_empty() or bool(support.get("deleted", false)) or not _surface_fits(building, support, dimensions))
		if not needs and str(detail.get("state", "")) != "suppressed":
			var local: Vector3 = _resolve_position(support, anchor, dimensions)
			var geometry: Dictionary = _surface_geometry(support, dimensions)
			var orientation: String = str(support.get("orientation", "front"))
			var tangent: float = local.x if orientation in ["front", "back"] else local.z
			var footprint: Vector2 = _detail_footprint(detail)
			needs = geometry.is_empty() or tangent - footprint.x < float(geometry.get("tangent_min", 0.0)) or tangent + footprint.x > float(geometry.get("tangent_max", 0.0)) or local.y - footprint.y < float(geometry.get("bottom", 0.0)) or local.y + footprint.y > float(geometry.get("top", dimensions.y))
		var position = null
		if not support.is_empty(): position = _resolve_position(support, anchor, dimensions)
		detail["resolved_position"] = position
		detail["needs_placement"] = needs
		var dormant: bool = str(detail.get("state", "")) == "automatic" and not bool(detail.get("layout_active", true))
		if dormant: detail["needs_placement"] = false
		detail["visible"] = str(detail.get("state", "")) != "suppressed" and not dormant
		detail["show_shutters"] = false
		result.append(detail)

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
			if _details_overlap(detail, other, WINDOW_GAP, true):
				detail["visible"] = false
				detail["layout_blocked"] = true
				break

	for detail_value in result:
		var detail: Dictionary = detail_value
		if not _placed_visible(detail) or str(detail.get("kind", "")) != "window" or str(detail.get("asset_id", "")).contains("round"): continue
		var support: Dictionary = _surface(building, str((detail["anchor"] as Dictionary)["surface_id"]))
		var geometry: Dictionary = _surface_geometry(support, dimensions)
		if geometry.is_empty(): continue
		var local: Vector3 = detail["resolved_position"]
		var orientation: String = str(support.get("orientation", ""))
		var tangent: float = local.x if orientation in ["front", "back"] else local.z
		var fits: bool = tangent - WINDOW_SHUTTER_HALF_WIDTH - WINDOW_CORNER_CLEARANCE >= float(geometry["tangent_min"]) and tangent + WINDOW_SHUTTER_HALF_WIDTH + WINDOW_CORNER_CLEARANCE <= float(geometry["tangent_max"])
		for other_value in result:
			var other: Dictionary = other_value
			if str(other["id"]) == str(detail["id"]) or not _placed_visible(other) or str((other["anchor"] as Dictionary)["surface_id"]) != str((detail["anchor"] as Dictionary)["surface_id"]): continue
			var other_local: Vector3 = other["resolved_position"]
			var other_tangent: float = other_local.x if orientation in ["front", "back"] else other_local.z
			var other_half: float = WINDOW_SHUTTER_HALF_WIDTH if str(other.get("kind", "")) == "window" and not str(other.get("asset_id", "")).contains("round") else _detail_footprint(other).x
			if absf(other_local.y - local.y) < _detail_footprint(detail).y + _detail_footprint(other).y and absf(other_tangent - tangent) < WINDOW_SHUTTER_HALF_WIDTH + other_half + WINDOW_GAP: fits = false
		detail["show_shutters"] = fits
	return result

func _reflow_automatic_windows(building: Dictionary) -> void:
	# Automatic M1 windows belong to the four authored base walls. Generated
	# massing walls are intentionally player-authored until we add a separate
	# procedural upper-storey facade pass.
	var surfaces: Array = building.get("surfaces", [])
	var deleted_states: Dictionary = {}
	for index in surfaces.size():
		var support: Dictionary = surfaces[index]
		if not bool(support.get("massing_wall", false)): continue
		var id: String = str(support.get("id", ""))
		deleted_states[id] = bool(support.get("deleted", false))
		support["deleted"] = true
		surfaces[index] = support
	building["surfaces"] = surfaces
	super._reflow_automatic_windows(building)
	surfaces = building.get("surfaces", [])
	for index in surfaces.size():
		var support: Dictionary = surfaces[index]
		var id: String = str(support.get("id", ""))
		if deleted_states.has(id):
			support["deleted"] = bool(deleted_states[id])
			surfaces[index] = support
	building["surfaces"] = surfaces
