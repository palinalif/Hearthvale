extends RefCounted
class_name M2HouseMassing

## Townscaper-inspired massing kernel for Hearthvale houses.
## Players author simple rectangular portions horizontally and vertically;
## adjacency decides the resulting exterior. Old records without a level remain
## ground-floor portions, while upper portions are supported by the floor below.

const CELL := 0.5
const MIN_PORTION_SIZE := 3.0
const MAX_PORTION_SIZE := 18.0
const MAX_SECTIONS := 16
const MAX_FLOORS := 4
const JOIN_EPSILON := 0.05

const PRESETS: Array[Dictionary] = [
	{"id": "rectangle", "label": "Rectangle"},
	{"id": "l_shape", "label": "L-shaped"},
	{"id": "t_shape", "label": "T-shaped"},
	{"id": "u_shape", "label": "U-shaped"},
]

static func sections_for(view: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var stored: Variant = view.get("massing_sections", [])
	if stored is Array:
		for value in stored:
			if not value is Dictionary: continue
			var normalized: Dictionary = _normalize_section(value as Dictionary)
			if not normalized.is_empty(): result.append(normalized)
	if result.is_empty(): result.append(core_section(view))
	return result

static func core_section(view: Dictionary) -> Dictionary:
	var dimensions: Vector3 = _vec3(view.get("dimensions", Vector3(10, 6, 8)), Vector3(10, 6, 8))
	return {"id": "core", "level": 0, "offset": Vector3.ZERO, "size": dimensions}

static func storey_height(view: Dictionary) -> float:
	return maxf(CELL, _vec3(view.get("dimensions", Vector3(10, 6, 8)), Vector3(10, 6, 8)).y)

static func section_level(section: Dictionary) -> int:
	return maxi(0, int(section.get("level", 0)))

static func section_bottom(section: Dictionary) -> float:
	return float(section_level(section)) * float((section.get("size", Vector3.ZERO) as Vector3).y)

static func section_top(section: Dictionary) -> float:
	var size: Vector3 = section.get("size", Vector3.ZERO)
	return section_bottom(section) + size.y

static func sections_on_level(sections: Array[Dictionary], level: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for section in sections:
		if section_level(section) == level: result.append(section)
	return result

static func max_level(sections: Array[Dictionary]) -> int:
	var result := 0
	for section in sections: result = maxi(result, section_level(section))
	return result

static func floor_count(view: Dictionary) -> int:
	return max_level(sections_for(view)) + 1

static func preset_sections(view: Dictionary, preset_id: String) -> Array[Dictionary]:
	var core: Dictionary = core_section(view)
	var dimensions: Vector3 = core["size"]
	var result: Array[Dictionary] = [core]
	if preset_id == "rectangle": return result
	if preset_id == "l_shape":
		var wing_width: float = _snap(maxf(4.0, dimensions.x * 0.48), 1.0)
		var wing_depth: float = _snap(maxf(4.0, dimensions.z * 0.56), 1.0)
		result.append(_section("l-wing", Vector3(dimensions.x * 0.5 + wing_width * 0.5, 0.0, dimensions.z * 0.20), Vector3(wing_width, dimensions.y, wing_depth), 0))
	elif preset_id == "t_shape":
		var cross_width: float = _snap(minf(MAX_PORTION_SIZE, maxf(dimensions.x + 4.0, dimensions.x * 1.45)), 1.0)
		var cross_depth: float = _snap(maxf(4.0, dimensions.z * 0.36), 1.0)
		result.append(_section("t-crossbar", Vector3(0.0, 0.0, dimensions.z * 0.5 + cross_depth * 0.5), Vector3(cross_width, dimensions.y, cross_depth), 0))
	elif preset_id == "u_shape":
		var arm_width: float = _snap(maxf(3.5, dimensions.x * 0.28), 0.5)
		var arm_depth: float = _snap(maxf(5.0, dimensions.z * 0.72), 1.0)
		var arm_x: float = maxf(0.0, dimensions.x * 0.5 - arm_width * 0.5)
		var arm_z: float = -(dimensions.z * 0.5 + arm_depth * 0.5)
		result.append(_section("u-left", Vector3(-arm_x, 0.0, arm_z), Vector3(arm_width, dimensions.y, arm_depth), 0))
		result.append(_section("u-right", Vector3(arm_x, 0.0, arm_z), Vector3(arm_width, dimensions.y, arm_depth), 0))
	return result

static func upper_preset_sections(view: Dictionary, preset_id: String, level: int) -> Array[Dictionary]:
	if level <= 0 or level >= MAX_FLOORS: return []
	var base: Array[Dictionary] = preset_sections(view, preset_id)
	var result: Array[Dictionary] = []
	for section in base:
		var copy: Dictionary = section.duplicate(true)
		copy["id"] = "floor-%d-%s" % [level + 1, str(copy.get("id", "section"))]
		copy["level"] = level
		var size: Vector3 = copy["size"]
		var offset: Vector3 = copy["offset"]
		offset.y = float(level) * size.y
		copy["offset"] = offset
		result.append(copy)
	return result

static func with_portion(view: Dictionary, offset: Vector3, size: Vector3, portion_id: String = "preview", level: int = 0) -> Array[Dictionary]:
	var sections: Array[Dictionary] = sections_for(view)
	var candidate: Dictionary = _section(portion_id, Vector3(_snap(offset.x, CELL), 0.0, _snap(offset.z, CELL)), Vector3(_snap(size.x, CELL), size.y, _snap(size.z, CELL)), level)
	if not can_add_portion(sections, candidate): return []
	sections.append(candidate)
	return sections

static func can_add_portion(sections: Array[Dictionary], candidate: Dictionary) -> bool:
	if sections.is_empty() or sections.size() >= MAX_SECTIONS: return false
	var normalized: Dictionary = _normalize_section(candidate)
	if normalized.is_empty(): return false
	var level: int = section_level(normalized)
	if level < 0 or level >= MAX_FLOORS: return false
	var size: Vector3 = normalized["size"]
	if size.x < MIN_PORTION_SIZE or size.z < MIN_PORTION_SIZE or size.x > MAX_PORTION_SIZE or size.z > MAX_PORTION_SIZE: return false
	var candidate_rect: Rect2 = section_rect(normalized)
	var same_level: Array[Dictionary] = sections_on_level(sections, level)
	var connected := same_level.is_empty()
	for section in same_level:
		var rect: Rect2 = section_rect(section)
		if _contains_rect(rect, candidate_rect): return false
		if _rects_join(rect, candidate_rect): connected = true
	if level == 0:
		return connected and not same_level.is_empty()
	return _is_supported_by_level(sections, candidate_rect, level - 1)

static func section_rect(section: Dictionary) -> Rect2:
	var offset: Vector3 = _vec3(section.get("offset", Vector3.ZERO), Vector3.ZERO)
	var size: Vector3 = _vec3(section.get("size", Vector3.ZERO), Vector3.ZERO)
	return Rect2(Vector2(offset.x - size.x * 0.5, offset.z - size.z * 0.5), Vector2(size.x, size.z))

static func union_bounds(sections: Array[Dictionary]) -> Rect2:
	if sections.is_empty(): return Rect2()
	var first: Rect2 = section_rect(sections[0])
	var minimum: Vector2 = first.position
	var maximum: Vector2 = first.end
	for index in range(1, sections.size()):
		var rect: Rect2 = section_rect(sections[index])
		minimum = minimum.min(rect.position)
		maximum = maximum.max(rect.end)
	return Rect2(minimum, maximum - minimum)

static func level_bounds(sections: Array[Dictionary], level: int) -> Rect2:
	return union_bounds(sections_on_level(sections, level))

static func occupancy(view: Dictionary) -> Dictionary:
	var sections: Array[Dictionary] = sections_for(view)
	var bounds: Rect2 = union_bounds(sections)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0: return {}
	var x_count := maxi(1, ceili(bounds.size.x / CELL))
	var z_count := maxi(1, ceili(bounds.size.y / CELL))
	var cells: Dictionary = {}
	for x_index in x_count:
		for z_index in z_count:
			var local_x := bounds.position.x + (float(x_index) + 0.5) * CELL
			var local_z := bounds.position.y + (float(z_index) + 0.5) * CELL
			var height: float = _height_at_sections(sections, local_x, local_z)
			if height > 0.0: cells[Vector2i(x_index, z_index)] = height
	return {"origin": bounds.position, "size": Vector2i(x_count, z_count), "cells": cells, "sections": sections}

static func boundary_faces(view: Dictionary) -> Array[Dictionary]:
	var field: Dictionary = occupancy(view)
	if field.is_empty(): return []
	var cells: Dictionary = field["cells"]
	var origin: Vector2 = field["origin"]
	var result: Array[Dictionary] = []
	var directions := {
		"front": Vector2i(0, -1),
		"back": Vector2i(0, 1),
		"left": Vector2i(-1, 0),
		"right": Vector2i(1, 0),
	}
	for key_value in cells.keys():
		var key: Vector2i = key_value as Vector2i
		var center := Vector2(origin.x + (float(key.x) + 0.5) * CELL, origin.y + (float(key.y) + 0.5) * CELL)
		var top: float = float(cells[key])
		for orientation in directions:
			var direction: Vector2i = directions[orientation]
			var neighbour_top: float = float(cells.get(key + direction, 0.0))
			if neighbour_top >= top - JOIN_EPSILON: continue
			var position := Vector3(center.x, 0.0, center.y)
			if orientation == "front": position.z -= CELL * 0.5
			elif orientation == "back": position.z += CELL * 0.5
			elif orientation == "left": position.x -= CELL * 0.5
			else: position.x += CELL * 0.5
			var bottom: float = maxf(0.60, neighbour_top)
			result.append({"cell": key, "orientation": orientation, "position": position, "bottom": bottom, "height": top})
	return result

static func roof_field(view: Dictionary) -> Dictionary:
	var field: Dictionary = occupancy(view)
	if field.is_empty(): return {}
	var cells: Dictionary = field["cells"]
	var distances: Dictionary = {}
	var queue: Array[Vector2i] = []
	var cardinal: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for key_value in cells.keys():
		var key: Vector2i = key_value as Vector2i
		var height: float = float(cells[key])
		var boundary := false
		for direction in cardinal:
			var neighbour := key + direction
			if not cells.has(neighbour) or absf(float(cells[neighbour]) - height) > JOIN_EPSILON:
				boundary = true
				break
		if boundary:
			distances[key] = 0
			queue.append(key)
	var head := 0
	while head < queue.size():
		var key: Vector2i = queue[head]
		head += 1
		var next_distance := int(distances[key]) + 1
		var height: float = float(cells[key])
		for direction in cardinal:
			var neighbour: Vector2i = key + direction
			if not cells.has(neighbour) or distances.has(neighbour): continue
			if absf(float(cells[neighbour]) - height) > JOIN_EPSILON: continue
			distances[neighbour] = next_distance
			queue.append(neighbour)
	field["distances"] = distances
	return field

static func roof_tiles(view: Dictionary) -> Array[Dictionary]:
	var field: Dictionary = roof_field(view)
	if field.is_empty(): return []
	var cells: Dictionary = field["cells"]
	var distances: Dictionary = field["distances"]
	var origin: Vector2 = field["origin"]
	var profile := str(view.get("roof_profile", "gentle_gable"))
	var pitch: float = _pitch_for(profile)
	var result: Array[Dictionary] = []
	for key_value in cells.keys():
		var key: Vector2i = key_value as Vector2i
		var distance := int(distances.get(key, 0))
		var base_height: float = float(cells[key])
		var center := Vector3(origin.x + (float(key.x) + 0.5) * CELL, base_height + 0.12 + (float(distance) + 0.5) * CELL * pitch, origin.y + (float(key.y) + 0.5) * CELL)
		var boundary := distance == 0
		result.append({"cell": key, "center": center, "distance": distance, "base_height": base_height, "edge": boundary, "shade": posmod(key.x * 92821 + key.y * 68917 + distance * 17, 3)})
	return result

static func roof_height_at(view: Dictionary, x: float, z: float) -> float:
	var field: Dictionary = roof_field(view)
	if field.is_empty(): return _vec3(view.get("dimensions", Vector3(10, 6, 8)), Vector3(10, 6, 8)).y
	var origin: Vector2 = field["origin"]
	var cells: Dictionary = field["cells"]
	var distances: Dictionary = field["distances"]
	var key := Vector2i(floori((x - origin.x) / CELL), floori((z - origin.y) / CELL))
	if not cells.has(key):
		var best_distance := INF
		var best_key := Vector2i.ZERO
		for key_value in cells.keys():
			var candidate := key_value as Vector2i
			var center := Vector2(origin.x + (float(candidate.x) + 0.5) * CELL, origin.y + (float(candidate.y) + 0.5) * CELL)
			var distance_sq := center.distance_squared_to(Vector2(x, z))
			if distance_sq < best_distance:
				best_distance = distance_sq
				best_key = candidate
		key = best_key
	var pitch: float = _pitch_for(str(view.get("roof_profile", "gentle_gable")))
	return float(cells[key]) + 0.12 + (float(int(distances.get(key, 0))) + 0.5) * CELL * pitch

static func shape_name(view: Dictionary) -> String:
	var preset := str(view.get("massing_preset", ""))
	var floors: int = floor_count(view)
	for spec in PRESETS:
		if str(spec["id"]) == preset:
			var label := str(spec["label"])
			return "%s • %d floors" % [label, floors] if floors > 1 else label
	var sections: Array[Dictionary] = sections_for(view)
	if sections.size() <= 1: return "Rectangle"
	return "Custom (%d portions%s)" % [sections.size(), " • %d floors" % floors if floors > 1 else ""]

static func _normalize_section(section: Dictionary) -> Dictionary:
	var size: Vector3 = _vec3(section.get("size", Vector3.ZERO), Vector3.ZERO)
	var offset: Vector3 = _vec3(section.get("offset", Vector3.ZERO), Vector3.ZERO)
	if not size.is_finite() or size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0 or not offset.is_finite(): return {}
	var level: int = maxi(0, int(section.get("level", 0)))
	if not section.has("level") and absf(offset.y) > JOIN_EPSILON:
		level = maxi(0, roundi(offset.y / maxf(CELL, size.y)))
	if level >= MAX_FLOORS: return {}
	offset = Vector3(_snap(offset.x, CELL), float(level) * size.y, _snap(offset.z, CELL))
	return {"id": str(section.get("id", "section")), "level": level, "offset": offset, "size": Vector3(_snap(size.x, CELL), _snap(size.y, CELL), _snap(size.z, CELL))}

static func _section(section_id: String, offset: Vector3, size: Vector3, level: int = 0) -> Dictionary:
	var normalized_level := clampi(level, 0, MAX_FLOORS - 1)
	return {"id": section_id, "level": normalized_level, "offset": Vector3(_snap(offset.x, CELL), float(normalized_level) * _snap(size.y, CELL), _snap(offset.z, CELL)), "size": Vector3(_snap(size.x, CELL), _snap(size.y, CELL), _snap(size.z, CELL))}

static func _height_at_sections(sections: Array[Dictionary], x: float, z: float) -> float:
	var result := 0.0
	var point := Vector2(x, z)
	for section in sections:
		var rect: Rect2 = section_rect(section)
		if point.x >= rect.position.x - JOIN_EPSILON and point.x <= rect.end.x + JOIN_EPSILON and point.y >= rect.position.y - JOIN_EPSILON and point.y <= rect.end.y + JOIN_EPSILON:
			result = maxf(result, section_top(section))
	return result

static func _is_supported_by_level(sections: Array[Dictionary], candidate_rect: Rect2, support_level: int) -> bool:
	var supports: Array[Dictionary] = sections_on_level(sections, support_level)
	if supports.is_empty(): return false
	var x_count := maxi(1, ceili(candidate_rect.size.x / CELL))
	var z_count := maxi(1, ceili(candidate_rect.size.y / CELL))
	for x_index in x_count:
		for z_index in z_count:
			var point := Vector2(candidate_rect.position.x + (float(x_index) + 0.5) * candidate_rect.size.x / float(x_count), candidate_rect.position.y + (float(z_index) + 0.5) * candidate_rect.size.y / float(z_count))
			var supported := false
			for section in supports:
				var rect := section_rect(section)
				if point.x >= rect.position.x - JOIN_EPSILON and point.x <= rect.end.x + JOIN_EPSILON and point.y >= rect.position.y - JOIN_EPSILON and point.y <= rect.end.y + JOIN_EPSILON:
					supported = true
					break
			if not supported: return false
	return true

static func _rects_join(a: Rect2, b: Rect2) -> bool:
	var x_overlap := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	var z_overlap := minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
	if x_overlap > JOIN_EPSILON and z_overlap > JOIN_EPSILON: return true
	var touch_x := absf(a.end.x - b.position.x) <= JOIN_EPSILON or absf(b.end.x - a.position.x) <= JOIN_EPSILON
	var touch_z := absf(a.end.y - b.position.y) <= JOIN_EPSILON or absf(b.end.y - a.position.y) <= JOIN_EPSILON
	return (touch_x and z_overlap > JOIN_EPSILON) or (touch_z and x_overlap > JOIN_EPSILON)

static func _contains_rect(outer: Rect2, inner: Rect2) -> bool:
	return inner.position.x >= outer.position.x - JOIN_EPSILON and inner.position.y >= outer.position.y - JOIN_EPSILON and inner.end.x <= outer.end.x + JOIN_EPSILON and inner.end.y <= outer.end.y + JOIN_EPSILON

static func _pitch_for(profile: String) -> float:
	if profile == "swept_gable": return 0.42
	if profile == "steep_gable": return 0.88
	if profile == "shed": return 0.32
	if profile == "gambrel": return 0.72
	if profile == "saltbox": return 0.62
	return 0.58

static func _snap(value: float, step: float) -> float:
	return snappedf(value, step)

static func _vec3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3: return value as Vector3
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback
