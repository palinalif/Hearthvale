extends RefCounted
class_name M2HouseMassing

## Townscaper-inspired massing kernel for Hearthvale houses.
## The player authors a few simple rectangular portions; adjacency decides the
## resulting exterior. Internal shared walls disappear and the roof height is a
## distance field over the UNION footprint, so concave corners naturally become
## valleys instead of overlapping independent gables.

const CELL := 0.5
const MIN_PORTION_SIZE := 3.0
const MAX_PORTION_SIZE := 18.0
const MAX_SECTIONS := 10
const JOIN_EPSILON := 0.05

const PRESETS: Array[Dictionary] = [
	{"id": "rectangle", "label": "Rectangle"},
	{"id": "l_shape", "label": "L-shaped"},
	{"id": "t_shape", "label": "T-shaped"},
	{"id": "u_shape", "label": "U-shaped"},
]

static func sections_for(view: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var stored = view.get("massing_sections", [])
	if stored is Array:
		for value in stored:
			if not value is Dictionary: continue
			var normalized := _normalize_section(value as Dictionary)
			if not normalized.is_empty(): result.append(normalized)
	if result.is_empty(): result.append(core_section(view))
	return result

static func core_section(view: Dictionary) -> Dictionary:
	var dimensions: Vector3 = _vec3(view.get("dimensions", Vector3(10, 6, 8)), Vector3(10, 6, 8))
	return {"id": "core", "offset": Vector3.ZERO, "size": dimensions}

static func preset_sections(view: Dictionary, preset_id: String) -> Array[Dictionary]:
	var core := core_section(view)
	var dimensions: Vector3 = core["size"]
	var result: Array[Dictionary] = [core]
	if preset_id == "rectangle": return result
	if preset_id == "l_shape":
		var wing_width: float = _snap(maxf(4.0, dimensions.x * 0.48), 1.0)
		var wing_depth: float = _snap(maxf(4.0, dimensions.z * 0.56), 1.0)
		result.append(_section("l-wing", Vector3(dimensions.x * 0.5 + wing_width * 0.5, 0.0, dimensions.z * 0.20), Vector3(wing_width, dimensions.y, wing_depth)))
	elif preset_id == "t_shape":
		var cross_width: float = _snap(minf(MAX_PORTION_SIZE, maxf(dimensions.x + 4.0, dimensions.x * 1.45)), 1.0)
		var cross_depth: float = _snap(maxf(4.0, dimensions.z * 0.36), 1.0)
		result.append(_section("t-crossbar", Vector3(0.0, 0.0, dimensions.z * 0.5 + cross_depth * 0.5), Vector3(cross_width, dimensions.y, cross_depth)))
	elif preset_id == "u_shape":
		var arm_width: float = _snap(maxf(3.5, dimensions.x * 0.28), 0.5)
		var arm_depth: float = _snap(maxf(5.0, dimensions.z * 0.72), 1.0)
		var arm_x: float = maxf(0.0, dimensions.x * 0.5 - arm_width * 0.5)
		var arm_z: float = -(dimensions.z * 0.5 + arm_depth * 0.5)
		result.append(_section("u-left", Vector3(-arm_x, 0.0, arm_z), Vector3(arm_width, dimensions.y, arm_depth)))
		result.append(_section("u-right", Vector3(arm_x, 0.0, arm_z), Vector3(arm_width, dimensions.y, arm_depth)))
	return result

static func with_portion(view: Dictionary, offset: Vector3, size: Vector3, portion_id: String = "preview") -> Array[Dictionary]:
	var sections := sections_for(view)
	var candidate := _section(portion_id, Vector3(_snap(offset.x, CELL), 0.0, _snap(offset.z, CELL)), Vector3(_snap(size.x, CELL), size.y, _snap(size.z, CELL)))
	if not can_add_portion(sections, candidate): return []
	sections.append(candidate)
	return sections

static func can_add_portion(sections: Array[Dictionary], candidate: Dictionary) -> bool:
	if sections.is_empty() or sections.size() >= MAX_SECTIONS: return false
	var normalized := _normalize_section(candidate)
	if normalized.is_empty(): return false
	var size: Vector3 = normalized["size"]
	if size.x < MIN_PORTION_SIZE or size.z < MIN_PORTION_SIZE or size.x > MAX_PORTION_SIZE or size.z > MAX_PORTION_SIZE: return false
	var candidate_rect := section_rect(normalized)
	var connected := false
	for section in sections:
		var rect := section_rect(section)
		if _contains_rect(rect, candidate_rect): return false
		if _rects_join(rect, candidate_rect): connected = true
	return connected

static func section_rect(section: Dictionary) -> Rect2:
	var offset: Vector3 = _vec3(section.get("offset", Vector3.ZERO), Vector3.ZERO)
	var size: Vector3 = _vec3(section.get("size", Vector3.ZERO), Vector3.ZERO)
	return Rect2(Vector2(offset.x - size.x * 0.5, offset.z - size.z * 0.5), Vector2(size.x, size.z))

static func union_bounds(sections: Array[Dictionary]) -> Rect2:
	if sections.is_empty(): return Rect2()
	var first := section_rect(sections[0])
	var minimum := first.position
	var maximum := first.end
	for index in range(1, sections.size()):
		var rect := section_rect(sections[index])
		minimum = minimum.min(rect.position)
		maximum = maximum.max(rect.end)
	return Rect2(minimum, maximum - minimum)

static func occupancy(view: Dictionary) -> Dictionary:
	var sections := sections_for(view)
	var bounds := union_bounds(sections)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0: return {}
	var x_count := maxi(1, ceili(bounds.size.x / CELL))
	var z_count := maxi(1, ceili(bounds.size.y / CELL))
	var cells: Dictionary = {}
	for x_index in x_count:
		for z_index in z_count:
			var local_x := bounds.position.x + (float(x_index) + 0.5) * CELL
			var local_z := bounds.position.y + (float(z_index) + 0.5) * CELL
			var height := _height_at_sections(sections, local_x, local_z)
			if height > 0.0: cells[Vector2i(x_index, z_index)] = height
	return {"origin": bounds.position, "size": Vector2i(x_count, z_count), "cells": cells, "sections": sections}

static func boundary_faces(view: Dictionary) -> Array[Dictionary]:
	var field := occupancy(view)
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
		var key := key_value as Vector2i
		var center := Vector2(origin.x + (float(key.x) + 0.5) * CELL, origin.y + (float(key.y) + 0.5) * CELL)
		for orientation in directions:
			var direction: Vector2i = directions[orientation]
			if cells.has(key + direction): continue
			var position := Vector3(center.x, 0.0, center.y)
			if orientation == "front": position.z -= CELL * 0.5
			elif orientation == "back": position.z += CELL * 0.5
			elif orientation == "left": position.x -= CELL * 0.5
			else: position.x += CELL * 0.5
			result.append({"cell": key, "orientation": orientation, "position": position, "height": float(cells[key])})
	return result

static func roof_field(view: Dictionary) -> Dictionary:
	var field := occupancy(view)
	if field.is_empty(): return {}
	var cells: Dictionary = field["cells"]
	var distances: Dictionary = {}
	var queue: Array[Vector2i] = []
	var cardinal: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for key_value in cells.keys():
		var key := key_value as Vector2i
		var boundary := false
		for direction in cardinal:
			if not cells.has(key + direction):
				boundary = true
				break
		if boundary:
			distances[key] = 0
			queue.append(key)
	var head := 0
	while head < queue.size():
		var key := queue[head]
		head += 1
		var next_distance := int(distances[key]) + 1
		for direction in cardinal:
			var neighbour := key + direction
			if not cells.has(neighbour) or distances.has(neighbour): continue
			distances[neighbour] = next_distance
			queue.append(neighbour)
	field["distances"] = distances
	return field

static func roof_tiles(view: Dictionary) -> Array[Dictionary]:
	var field := roof_field(view)
	if field.is_empty(): return []
	var cells: Dictionary = field["cells"]
	var distances: Dictionary = field["distances"]
	var origin: Vector2 = field["origin"]
	var profile := str(view.get("roof_profile", "gentle_gable"))
	var pitch := _pitch_for(profile)
	var result: Array[Dictionary] = []
	for key_value in cells.keys():
		var key := key_value as Vector2i
		var distance := int(distances.get(key, 0))
		var center := Vector3(origin.x + (float(key.x) + 0.5) * CELL, float(cells[key]) + 0.12 + (float(distance) + 0.5) * CELL * pitch, origin.y + (float(key.y) + 0.5) * CELL)
		var boundary := distance == 0
		result.append({"cell": key, "center": center, "distance": distance, "edge": boundary, "shade": posmod(key.x * 92821 + key.y * 68917 + distance * 17, 3)})
	return result

static func roof_height_at(view: Dictionary, x: float, z: float) -> float:
	var field := roof_field(view)
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
	var pitch := _pitch_for(str(view.get("roof_profile", "gentle_gable")))
	return float(cells[key]) + 0.12 + (float(int(distances.get(key, 0))) + 0.5) * CELL * pitch

static func shape_name(view: Dictionary) -> String:
	var preset := str(view.get("massing_preset", ""))
	for spec in PRESETS:
		if str(spec["id"]) == preset: return str(spec["label"])
	var sections := sections_for(view)
	return "Rectangle" if sections.size() <= 1 else "Custom (%d portions)" % sections.size()

static func _normalize_section(section: Dictionary) -> Dictionary:
	var size := _vec3(section.get("size", Vector3.ZERO), Vector3.ZERO)
	var offset := _vec3(section.get("offset", Vector3.ZERO), Vector3.ZERO)
	if not size.is_finite() or size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0 or not offset.is_finite(): return {}
	return {"id": str(section.get("id", "section")), "offset": Vector3(offset.x, 0.0, offset.z), "size": size}

static func _section(section_id: String, offset: Vector3, size: Vector3) -> Dictionary:
	return {"id": section_id, "offset": Vector3(_snap(offset.x, CELL), 0.0, _snap(offset.z, CELL)), "size": Vector3(_snap(size.x, CELL), _snap(size.y, CELL), _snap(size.z, CELL))}

static func _height_at_sections(sections: Array[Dictionary], x: float, z: float) -> float:
	var result := 0.0
	var point := Vector2(x, z)
	for section in sections:
		var rect := section_rect(section)
		if point.x >= rect.position.x - JOIN_EPSILON and point.x <= rect.end.x + JOIN_EPSILON and point.y >= rect.position.y - JOIN_EPSILON and point.y <= rect.end.y + JOIN_EPSILON:
			var size: Vector3 = section["size"]
			result = maxf(result, size.y)
	return result

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
