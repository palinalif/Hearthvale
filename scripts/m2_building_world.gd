extends "res://scripts/cottage_resize_world.gd"
class_name M2BuildingWorld

## Keep the inherited move/rotate and resize-handle edit contract.
## M2 keeps the M1 document schema, but generated massing walls can describe a
## bounded facade run instead of implicitly spanning the original rectangle.
## Legacy surface geometry retains BuildingWorld behaviour.

# Vector3 stores clamped positions at lower precision than scalar bounds.
# Ignore only rounding dust, not actual overhang (0.00001 local units).
const ATTACHMENT_EDGE_EPSILON := 0.00001
const JoinedPlacement = preload("res://scripts/wall_attachment_placement.gd")
var _overlap_orientations: Dictionary = {}

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
	_overlap_orientations = {}
	for wall in building.get("surfaces", []): _overlap_orientations[str(wall.get("id", ""))] = str(wall.get("orientation", ""))
	var result: Array[Dictionary] = []
	var dimensions: Vector3 = _as_vec(building.get("dimensions", [0, 0, 0]))
	for detail_value in building.get("details", []):
		var detail: Dictionary = _copy(detail_value)
		var anchor: Dictionary = detail.get("anchor", {})
		var support: Dictionary = _surface(building, str(anchor.get("surface_id", "")))
		var inside_covered_wall := false
		var needs: bool = str(detail.get("state", "")) != "suppressed" and (support.is_empty() or bool(support.get("deleted", false)) or not _surface_fits(building, support, dimensions))
		if not needs and str(detail.get("state", "")) != "suppressed":
			var local: Vector3 = _resolve_position(support, anchor, dimensions)
			var geometry: Dictionary = _surface_geometry(support, dimensions)
			var orientation: String = str(support.get("orientation", "front"))
			var tangent: float = local.x if orientation in ["front", "back"] else local.z
			var footprint: Vector2 = _detail_footprint(detail)
			needs = (
				geometry.is_empty()
				or tangent - footprint.x < float(geometry.get("tangent_min", 0.0)) - ATTACHMENT_EDGE_EPSILON
				or tangent + footprint.x > float(geometry.get("tangent_max", 0.0)) + ATTACHMENT_EDGE_EPSILON
				or local.y - footprint.y < float(geometry.get("bottom", 0.0)) - ATTACHMENT_EDGE_EPSILON
				or local.y + footprint.y > float(geometry.get("top", dimensions.y)) + ATTACHMENT_EDGE_EPSILON
			)
		if not needs and support.has("exposed_wall_runs") and str(detail.get("state", "")) != "suppressed":
			var position_view := {"dimensions": dimensions, "surfaces": [support]}
			var local: Vector3 = _resolve_position(support, anchor, dimensions)
			var allowed := JoinedPlacement.clamp_to_wall(position_view, str(support["id"]), local, _detail_footprint(detail))
			inside_covered_wall = allowed.is_empty() or not (allowed["position"] as Vector3).is_equal_approx(local)
			needs = inside_covered_wall
		var position = null
		if not support.is_empty(): position = _resolve_position(support, anchor, dimensions)
		detail["resolved_position"] = position
		detail["needs_placement"] = needs
		var dormant: bool = str(detail.get("state", "")) == "automatic" and (not bool(detail.get("layout_active", true)) or inside_covered_wall)
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
	# Let the original layout own only the four authored base walls, then run a
	# second stable slot pass over generated upper-storey facade runs.
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
	_reflow_upper_storey_windows(building)

func _reflow_upper_storey_windows(building: Dictionary) -> void:
	var surfaces: Array = building.get("surfaces", [])
	var details: Array = building.get("details", [])
	var default_asset: String = _upper_window_asset(building)
	var remaining_capacity: int = maxi(0, MAX_DETAILS - details.size())
	for surface_value in surfaces:
		if not surface_value is Dictionary: continue
		var support: Dictionary = surface_value
		if not bool(support.get("massing_wall", false)) or int(support.get("massing_level", 0)) <= 0: continue
		var surface_id: String = str(support.get("id", ""))
		if surface_id.is_empty(): continue
		var count: int = _upper_window_count(support)
		if bool(support.get("deleted", false)): count = 0
		var slots: Dictionary = {}
		for detail_value in details:
			if not detail_value is Dictionary: continue
			var detail: Dictionary = detail_value
			if not bool(detail.get("generated", false)) or not bool(detail.get("massing_auto", false)) or str(detail.get("kind", "")) != "window": continue
			var default_value: Variant = detail.get("default", {})
			var default_anchor: Dictionary = {}
			if default_value is Dictionary: default_anchor = (default_value as Dictionary).get("anchor", {})
			if default_anchor.is_empty(): default_anchor = detail.get("anchor", {})
			if str(default_anchor.get("surface_id", "")) != surface_id: continue
			var slot: int = int(detail.get("layout_slot", slots.size()))
			detail["layout_slot"] = slot
			slots[slot] = detail
		for slot in count:
			if slots.has(slot): continue
			if remaining_capacity <= 0: break
			var detail_id: String = "%s-auto-%s-%d" % [str(building.get("id", "building")), surface_id, slot]
			var detail: Dictionary = _window(detail_id, surface_id, 0.5, 0.48)
			detail["asset_id"] = default_asset
			detail["massing_auto"] = true
			detail["layout_slot"] = slot
			var default_record: Dictionary = detail.get("default", {})
			default_record["asset_id"] = default_asset
			detail["default"] = default_record
			details.append(detail)
			slots[slot] = detail
			remaining_capacity -= 1
		for slot_value in slots.keys():
			var slot: int = int(slot_value)
			var detail: Dictionary = slots[slot]
			detail["layout_active"] = slot < count
			if str(detail.get("state", "")) != "automatic" or slot >= count: continue
			var u: float = (float(slot) + 0.5) / float(maxi(1, count))
			var anchor := {"surface_id": surface_id, "policy": "proportional", "u": u, "v": 0.48, "fixed_offset": 1.25}
			detail["anchor"] = anchor
			var default_record: Dictionary = detail.get("default", {})
			default_record["id"] = str(detail.get("id", ""))
			default_record["asset_id"] = str(detail.get("asset_id", default_asset))
			default_record["u"] = u
			default_record["v"] = 0.48
			default_record["anchor"] = anchor.duplicate(true)
			detail["default"] = default_record
	building["details"] = details

func _upper_window_count(surface: Dictionary) -> int:
	var span: float = float(surface.get("tangent_max", 0.0)) - float(surface.get("tangent_min", 0.0))
	var height: float = float(surface.get("top", 0.0)) - float(surface.get("bottom", 0.0))
	var minimum_span: float = (WINDOW_HALF_WIDTH + WINDOW_CORNER_CLEARANCE) * 2.0
	if span < minimum_span or height < 4.2: return 0
	return maxi(1, floori((span - WINDOW_CORNER_CLEARANCE * 2.0) / WINDOW_TARGET_SPACING))

func _upper_window_asset(building: Dictionary) -> String:
	var style_id: String = str(building.get("style_id", "riverside_cottage"))
	if style_id == "woodland_lodge": return "window_lodge"
	if style_id == "village_gable": return "window_tudor"
	return "window_wood"

func _details_overlap(left: Dictionary, right: Dictionary, gap: float, reserve_suppression: bool = false) -> bool:
	if str(left.get("anchor", {}).get("surface_id", "")) == str(right.get("anchor", {}).get("surface_id", "")):
		return super._details_overlap(left, right, gap, reserve_suppression)
	var orientation := str(_overlap_orientations.get(str(left.get("anchor", {}).get("surface_id", "")), ""))
	if orientation.is_empty() or orientation != str(_overlap_orientations.get(str(right.get("anchor", {}).get("surface_id", "")), "")): return false
	var reserved := reserve_suppression and str(right.get("state", "")) == "suppressed" and str(right.get("kind", "")) == "window" and right.get("resolved_position") is Vector3
	if not _placed_visible(left) or not (_placed_visible(right) or reserved): return false
	var a: Vector3 = left["resolved_position"]
	var b: Vector3 = right["resolved_position"]
	var normal_axis := 2 if orientation in ["front", "back"] else 0
	if absf(a[normal_axis] - b[normal_axis]) > 0.001: return false
	var tangent_axis := 0 if normal_axis == 2 else 2
	var a_half := _detail_footprint(left)
	var b_half := _detail_footprint(right)
	return absf(a[tangent_axis] - b[tangent_axis]) < a_half.x + b_half.x + gap and absf(a.y - b.y) < a_half.y + b_half.y
