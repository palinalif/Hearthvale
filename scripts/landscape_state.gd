extends RefCounted
class_name LandscapeState

const LIMIT := 320
const TREE_LIMIT := 24
const PATH_STYLE_IDS: Array[String] = ["packed_earth", "cobblestone", "stepping_stones"]
const PATH_LIMIT := 32
const PATH_MIN_POINTS := 2
const PATH_MAX_POINTS := 64
const PATH_MIN_WIDTH := 0.25
const PATH_MAX_WIDTH := 3.0
const PATH_MIN_SEGMENT := 0.125
const PATH_RENDER_CELL_LIMIT := 24000
const EDITABLE_WORLD_SIZE := 48.0
const Grid = preload("res://scripts/visual_grid.gd")
var records: Array = []
var paths: Array = []
var next_id := 1

func document() -> Dictionary:
	return {"version": 1, "next_id": next_id, "records": records.duplicate(true), "paths": paths.duplicate(true)}

static func validate(value: Dictionary) -> bool:
	if not _integer(value.get("version", null)) or int(value["version"]) != 1 or not value.get("records", null) is Array: return false
	if value["records"].size() > LIMIT or not _integer(value.get("next_id", null)) or int(value["next_id"]) < 1: return false
	var path_values = value.get("paths", [])
	if not path_values is Array or path_values.size() > PATH_LIMIT: return false
	var ids := {}
	var trees := 0
	for record in value["records"]:
		if not record is Dictionary: return false
		if not str(record.get("kind", "")) in ["tree", "foliage", "rock"]: return false
		if not _integer(record.get("seed", null)) or not _integer(record.get("id", null)): return false
		var id := int(record.get("id", 0))
		if id < 1 or id >= int(value["next_id"]) or ids.has(id): return false
		ids[id] = true
		var p = record.get("position", null)
		if not p is Array or p.size() != 3: return false
		for number in p:
			if not (number is float or number is int) or not is_finite(float(number)): return false
		if float(p[0]) < 0 or float(p[0]) > 48 or float(p[2]) < 0 or float(p[2]) > 48 or float(p[1]) < 0 or float(p[1]) > 32: return false
		if record["kind"] == "tree": trees += 1
	if trees > TREE_LIMIT: return false
	var rendered_cells := 0
	for path_value in path_values:
		if not _validate_path_record(path_value): return false
		var path: Dictionary = path_value
		var id := int(path["id"])
		if id < 1 or id >= int(value["next_id"]) or ids.has(id): return false
		ids[id] = true
		rendered_cells += _estimated_render_cells(path)
		if rendered_cells > PATH_RENDER_CELL_LIMIT: return false
	return true

func restore(value: Dictionary) -> bool:
	if not validate(value): return false
	records = value["records"].duplicate(true)
	paths = value.get("paths", []).duplicate(true)
	next_id = int(value["next_id"])
	# JSON has no integer/float distinction on reload. Reassert the integer
	# identity fields so deterministic documents keep the same serialization
	# shape as documents created in memory.
	for record_value in records:
		var record: Dictionary = record_value
		record["id"] = int(record["id"])
		record["seed"] = int(record["seed"])
	for path_value in paths:
		var path: Dictionary = path_value
		path["id"] = int(path["id"])
	return true

static func position_of(record: Dictionary) -> Vector3:
	var p: Array = record["position"]
	return Vector3(p[0], p[1], p[2])

func add(kind: String, point: Vector3, seed_value: int) -> bool:
	if not kind in ["tree", "foliage", "rock"] or records.size() >= LIMIT or not point.is_finite() or point.y <= 5.05 or point.y > 32 or point.x < 0 or point.x > 48 or point.z < 0 or point.z > 48: return false
	var trees := 0
	for other in records:
		if other["kind"] == "tree": trees += 1
		var separation := 2.8 if kind == "tree" and other["kind"] == "tree" else (0.5 if kind == "foliage" else 0.8)
		if Vector2(point.x, point.z).distance_to(Vector2(other["position"][0], other["position"][2])) < separation: return false
	if kind == "tree" and trees >= TREE_LIMIT: return false
	records.append({"id": next_id, "kind": kind, "position": [point.x, point.y, point.z], "seed": seed_value})
	next_id += 1
	return true

## Add a composition path and return its shared stable landscape ID. A
## negative result means the candidate failed the same validation used for
## save/reload. Points are accepted as Vector2 values or [x, z] pairs so
## controller code and headless state tests can use the same API.
func add_path(style_id: String, width: float, point_values: Array) -> int:
	var normalized: Array = []
	for point_value in point_values:
		var point := _point_array(point_value)
		if point.is_empty(): return -1
		normalized.append(point)
	var candidate := {"id": next_id, "style_id": style_id, "width": snappedf(width, Grid.UNIT), "points": normalized}
	var proposed := document()
	(proposed["paths"] as Array).append(candidate)
	proposed["next_id"] = next_id + 1
	if not validate(proposed): return -1
	paths.append(candidate)
	next_id += 1
	return int(candidate["id"])

func erase_path(path_id: int) -> bool:
	for index in paths.size():
		if int((paths[index] as Dictionary).get("id", -1)) != path_id: continue
		paths.remove_at(index)
		return true
	return false

## Paths are composition data, so removing a plant here is still reversible by
## the surrounding landscape history entry. Trees use a wider root clearance;
## rocks and foliage are kept clear of the walking surface as well.
func clear_records_along_path(point_values: Array, width: float) -> bool:
	if point_values.size() < PATH_MIN_POINTS: return false
	var kept: Array = []
	var clearance := maxf(width * 0.5, PATH_MIN_WIDTH * 0.5) + 0.25
	var changed := false
	for record_value in records:
		var record: Dictionary = record_value
		var point := position_of(record)
		var radius := clearance + (0.45 if str(record.get("kind", "")) == "tree" else 0.12)
		if _distance_to_polyline_squared(Vector2(point.x, point.z), point_values) <= radius * radius:
			changed = true
		else:
			kept.append(record)
	if changed: records = kept
	return changed

func erase_brush(point: Vector3, radius: float) -> bool:
	var kept: Array = []
	for record in records:
		var p := position_of(record)
		if Vector2(p.x, p.z).distance_to(Vector2(point.x, point.z)) > radius or absf(p.y - point.y) > 3.0: kept.append(record)
	var changed := kept.size() != records.size()
	records = kept
	return changed

func clear_edited_cells(cells: Array, cell_size: float) -> bool:
	# Roots intersect changed native cells, not the enclosing stroke rectangle.
	var lookup := {}
	for point: Vector3 in cells: lookup[Vector3i(floor(point / cell_size))] = true
	var kept: Array = []
	for record in records:
		var p := position_of(record)
		var root_cell := Vector3i(floor(p / cell_size))
		var reach := 2 if record["kind"] == "tree" else 1
		var affected := false
		for x in range(-reach, reach + 1):
			for z in range(-reach, reach + 1):
				for y in range(-1, 2):
					if lookup.has(root_cell + Vector3i(x, y, z)): affected = true
		if not affected: kept.append(record)
	var changed := kept.size() != records.size()
	records = kept
	return changed

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and absf(float(value)) <= 1000000000.0

static func _point_array(value: Variant) -> Array:
	var x: Variant = NAN
	var z: Variant = NAN
	if value is Vector2:
		x = value.x; z = value.y
	elif value is Array and value.size() == 2:
		x = value[0]; z = value[1]
	else:
		return []
	if not (x is int or x is float) or not (z is int or z is float): return []
	if not is_finite(float(x)) or not is_finite(float(z)): return []
	return [snappedf(float(x), Grid.UNIT), snappedf(float(z), Grid.UNIT)]

static func _validate_path_record(value: Variant) -> bool:
	if not value is Dictionary: return false
	var path: Dictionary = value
	if not _integer(path.get("id", null)) or int(path["id"]) < 1: return false
	if not PATH_STYLE_IDS.has(str(path.get("style_id", ""))): return false
	if not (path.get("width", null) is int or path.get("width", null) is float): return false
	var width := float(path["width"])
	if not is_finite(width) or width < PATH_MIN_WIDTH or width > PATH_MAX_WIDTH: return false
	if not is_equal_approx(width, snappedf(width, Grid.UNIT)): return false
	var point_values = path.get("points", null)
	if not point_values is Array or point_values.size() < PATH_MIN_POINTS or point_values.size() > PATH_MAX_POINTS: return false
	var previous := Vector2.ZERO
	for index in point_values.size():
		var point_value = point_values[index]
		if not point_value is Array or point_value.size() != 2: return false
		for coordinate in point_value:
			if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)): return false
		var point := Vector2(float(point_value[0]), float(point_value[1]))
		if point.x < 0.0 or point.x > EDITABLE_WORLD_SIZE or point.y < 0.0 or point.y > EDITABLE_WORLD_SIZE: return false
		if not is_equal_approx(point.x, snappedf(point.x, Grid.UNIT)) or not is_equal_approx(point.y, snappedf(point.y, Grid.UNIT)): return false
		if index > 0 and point.distance_to(previous) < PATH_MIN_SEGMENT - 0.000001: return false
		previous = point
	return true

static func _estimated_render_cells(path: Dictionary) -> int:
	var points: Array = path["points"]
	var width := float(path["width"])
	var samples := 0
	for index in range(1, points.size()):
		var a := Vector2(float(points[index - 1][0]), float(points[index - 1][1]))
		var b := Vector2(float(points[index][0]), float(points[index][1]))
		samples += maxi(1, ceili(a.distance_to(b) / 0.5))
	var width_cells := ceili(width / Grid.UNIT)
	return samples * maxi(1, width_cells) * (3 if str(path["style_id"]) == "stepping_stones" else 2)

static func _distance_to_polyline_squared(point: Vector2, point_values: Array) -> float:
	var best := INF
	for index in range(1, point_values.size()):
		var a_value = point_values[index - 1]
		var b_value = point_values[index]
		var a: Vector2 = a_value if a_value is Vector2 else Vector2(float(a_value[0]), float(a_value[1]))
		var b: Vector2 = b_value if b_value is Vector2 else Vector2(float(b_value[0]), float(b_value[1]))
		var segment: Vector2 = b - a
		var amount := clampf((point - a).dot(segment) / maxf(segment.length_squared(), 0.000001), 0.0, 1.0)
		best = minf(best, point.distance_squared_to(a.lerp(b, amount)))
	return best
