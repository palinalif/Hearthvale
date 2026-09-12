extends RefCounted
class_name LandscapeState

const LIMIT := 320
const TREE_LIMIT := 24
const PATH_STYLE_IDS: Array[String] = ["packed_earth", "cobblestone", "stepping_stones"]
# Transitional caller-only limits while the scene tool is cut from point routes
# to hold-to-paint strokes. Saved path documents never use width or points.
const PATH_MIN_POINTS := 2
const PATH_MAX_POINTS := 64
const PATH_MIN_WIDTH := 0.25
const PATH_MAX_WIDTH := 3.0
const PATH_MIN_SEGMENT := 0.125
const PATH_RENDER_CELL_LIMIT := 24000
const BRIDGE_STYLE_IDS: Array[String] = ["timber", "stone"]
const BRIDGE_LIMIT := 16
const BRIDGE_MIN_WIDTH := 0.75
const BRIDGE_MAX_WIDTH := 2.0
const BRIDGE_MIN_SPAN := 1.0
const BRIDGE_MAX_SPAN := 10.0
const BRIDGE_RENDER_CELL_LIMIT := 8000
const COMPOSITION_STYLE_IDS := {
	"garden": ["cottage_flowers", "kitchen_rows", "herb_garden"],
	"fence": ["rustic_fence", "rustic_gate"],
	"furniture": ["bench", "lantern", "signpost", "barrel_planter"],
}
const COMPOSITION_LIMIT := 96
const COMPOSITION_MIN_SIZE := 0.125
const COMPOSITION_MAX_SIZE := 6.0
const COMPOSITION_RENDER_CELL_LIMIT := 24000
const EDITABLE_WORLD_SIZE := 48.0
const Grid = preload("res://scripts/visual_grid.gd")
const PathRegion = preload("res://scripts/m2_painted_path_region.gd")
const PathAuthority = preload("res://scripts/m2_painted_path_authority.gd")

var records: Array = []
var paths: Array = []
var bridges: Array = []
var composition: Array = []
var next_id := 1

func document() -> Dictionary:
	return {"version": 1, "next_id": next_id, "records": records.duplicate(true), "paths": paths.duplicate(true), "bridges": bridges.duplicate(true), "composition": composition.duplicate(true)}

static func validate(value: Dictionary) -> bool:
	if not _integer(value.get("version", null)) or int(value["version"]) != 1 or not value.get("records", null) is Array: return false
	if value["records"].size() > LIMIT or not _integer(value.get("next_id", null)) or int(value["next_id"]) < 1: return false
	var path_values = value.get("paths", [])
	if not path_values is Array or not PathAuthority.validate(path_values): return false
	if PathAuthority.total_cells(path_values) > PATH_RENDER_CELL_LIMIT: return false
	var bridge_values = value.get("bridges", [])
	if not bridge_values is Array or bridge_values.size() > BRIDGE_LIMIT: return false
	var composition_values = value.get("composition", [])
	if not composition_values is Array or composition_values.size() > COMPOSITION_LIMIT: return false
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
	for path_value in path_values:
		var path: Dictionary = path_value
		var id := int(path["id"])
		if id < 1 or id >= int(value["next_id"]) or ids.has(id): return false
		ids[id] = true
	var bridge_cells := 0
	for bridge_value in bridge_values:
		if not _validate_bridge_record(bridge_value): return false
		var bridge: Dictionary = bridge_value
		var id := int(bridge["id"])
		if id < 1 or id >= int(value["next_id"]) or ids.has(id): return false
		ids[id] = true
		bridge_cells += _estimated_bridge_render_cells(bridge)
		if bridge_cells > BRIDGE_RENDER_CELL_LIMIT: return false
	var composition_cells := 0
	for object_value in composition_values:
		if not _validate_composition_record(object_value): return false
		var object: Dictionary = object_value
		var id := int(object["id"])
		if id < 1 or id >= int(value["next_id"]) or ids.has(id): return false
		ids[id] = true
		composition_cells += _estimated_composition_render_cells(object)
		if composition_cells > COMPOSITION_RENDER_CELL_LIMIT: return false
	return true

func restore(value: Dictionary) -> bool:
	if not validate(value): return false
	records = value["records"].duplicate(true)
	paths = value.get("paths", []).duplicate(true)
	bridges = value.get("bridges", []).duplicate(true)
	composition = value.get("composition", []).duplicate(true)
	next_id = int(value["next_id"])
	for record_value in records:
		var record: Dictionary = record_value
		record["id"] = int(record["id"])
		record["seed"] = int(record["seed"])
	for path_value in paths:
		var path: Dictionary = path_value
		path["id"] = int(path["id"])
		for cell_value in path["cells"]:
			cell_value[0] = int(cell_value[0])
			cell_value[1] = int(cell_value[1])
	for bridge_value in bridges:
		var bridge: Dictionary = bridge_value
		bridge["id"] = int(bridge["id"])
	for object_value in composition:
		var object: Dictionary = object_value
		object["id"] = int(object["id"])
		object["yaw_quarters"] = int(object["yaw_quarters"])
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

## Temporary caller bridge during the interaction rewrite. Point routes are
## rasterized immediately and never enter the saved document schema.
func add_path(style_id: String, width: float, point_values: Array) -> int:
	if not PATH_STYLE_IDS.has(style_id) or point_values.size() < PATH_MIN_POINTS or point_values.size() > PATH_MAX_POINTS: return -1
	var safe_width := snappedf(clampf(width, PATH_MIN_WIDTH, PATH_MAX_WIDTH), Grid.UNIT)
	var points: Array[Vector2] = []
	for value in point_values:
		var point := _point_array(value)
		if point.is_empty(): return -1
		var parsed := Vector2(float(point[0]), float(point[1]))
		if parsed.x < 0.0 or parsed.x > EDITABLE_WORLD_SIZE or parsed.y < 0.0 or parsed.y > EDITABLE_WORLD_SIZE: return -1
		points.append(parsed)
	var cells: Array = []
	for index in range(1, points.size()):
		if points[index - 1].distance_to(points[index]) < PATH_MIN_SEGMENT - 0.000001: return -1
		cells = PathRegion.union_cells(cells, PathRegion.stroke_cells(points[index - 1], points[index], safe_width * 0.5, EDITABLE_WORLD_SIZE), EDITABLE_WORLD_SIZE)
	return paint_path_cells(style_id, cells)

## Same temporary bridge for planting clearance. The authoritative operation is
## still cell-based, so removing this adapter later does not change save data.
func clear_records_along_path(point_values: Array, width: float) -> bool:
	if point_values.size() < PATH_MIN_POINTS: return false
	var safe_width := snappedf(clampf(width, PATH_MIN_WIDTH, PATH_MAX_WIDTH), Grid.UNIT)
	var points: Array[Vector2] = []
	for value in point_values:
		var point := _point_array(value)
		if point.is_empty(): return false
		points.append(Vector2(float(point[0]), float(point[1])))
	var cells: Array = []
	for index in range(1, points.size()):
		cells = PathRegion.union_cells(cells, PathRegion.stroke_cells(points[index - 1], points[index], safe_width * 0.5, EDITABLE_WORLD_SIZE), EDITABLE_WORLD_SIZE)
	return clear_records_in_path_cells(cells)

## Paint authoritative structural-grid cells. Repainting the same material
## merges into its region; painting another material transfers ownership.
func paint_path_cells(style_id: String, cell_values: Array) -> int:
	var result := PathAuthority.paint(paths, next_id, style_id, cell_values)
	if not bool(result.get("changed", false)): return int(result.get("path_id", -1))
	var proposed := document()
	proposed["paths"] = result["paths"]
	proposed["next_id"] = int(result["next_id"])
	if not validate(proposed): return -1
	paths = (result["paths"] as Array).duplicate(true)
	next_id = int(result["next_id"])
	return int(result["path_id"])

func erase_path_cells(cell_values: Array) -> bool:
	var result := PathAuthority.erase(paths, cell_values)
	if not bool(result.get("changed", false)): return false
	var proposed := document()
	proposed["paths"] = result["paths"]
	if not validate(proposed): return false
	paths = (result["paths"] as Array).duplicate(true)
	return true

func path_cells(style_id: String) -> Array:
	return PathAuthority.cells_for_style(paths, style_id)

func erase_path(path_id: int) -> bool:
	for index in paths.size():
		if int((paths[index] as Dictionary).get("id", -1)) != path_id: continue
		paths.remove_at(index)
		return true
	return false

## Painted path cells clear planting from the occupied ground plus a small root
## margin. This remains part of the surrounding landscape undo transaction.
func clear_records_in_path_cells(cell_values: Array, margin_cells: int = 2) -> bool:
	var painted := PathRegion.normalize_cells(cell_values)
	if painted.is_empty(): return false
	var occupied := {}
	for cell: Vector2i in painted: occupied[cell] = true
	var kept: Array = []
	var changed := false
	for record_value in records:
		var record: Dictionary = record_value
		var point := position_of(record)
		var root := Vector2i(floori(point.x / Grid.UNIT), floori(point.z / Grid.UNIT))
		var reach := maxi(0, margin_cells) + (3 if str(record.get("kind", "")) == "tree" else 1)
		var affected := false
		for z in range(-reach, reach + 1):
			for x in range(-reach, reach + 1):
				if occupied.has(root + Vector2i(x, z)):
					affected = true
					break
			if affected: break
		if affected: changed = true
		else: kept.append(record)
	if changed: records = kept
	return changed

## Simple bridges remain separate composition authority instead of being baked
## into terrain or path meshes.
func add_bridge(style_id: String, width: float, point_values: Array) -> int:
	if point_values.size() != 2: return -1
	var normalized: Array = []
	for point_value in point_values:
		var point := _point_array(point_value)
		if point.is_empty(): return -1
		normalized.append(point)
	var candidate := {"id": next_id, "style_id": style_id, "width": snappedf(width, Grid.UNIT), "points": normalized}
	var proposed := document()
	(proposed["bridges"] as Array).append(candidate)
	proposed["next_id"] = next_id + 1
	if not validate(proposed): return -1
	bridges.append(candidate)
	next_id += 1
	return int(candidate["id"])

func erase_bridge(bridge_id: int) -> bool:
	for index in bridges.size():
		if int((bridges[index] as Dictionary).get("id", -1)) != bridge_id: continue
		bridges.remove_at(index)
		return true
	return false

func add_composition(kind: String, style_id: String, point_value: Variant, size_value: Variant, yaw_quarters: int) -> int:
	var point := _point_array(point_value)
	var size := _size_array(size_value)
	if point.is_empty() or size.is_empty(): return -1
	var candidate := {"id": next_id, "kind": kind, "style_id": style_id, "position": point, "size": size, "yaw_quarters": posmod(yaw_quarters, 4)}
	var proposed := document()
	(proposed["composition"] as Array).append(candidate)
	proposed["next_id"] = next_id + 1
	if not validate(proposed): return -1
	composition.append(candidate)
	next_id += 1
	return int(candidate["id"])

func erase_composition(object_id: int) -> bool:
	for index in composition.size():
		if int((composition[index] as Dictionary).get("id", -1)) != object_id: continue
		composition.remove_at(index)
		return true
	return false

func clear_records_in_footprint(point_value: Variant, size_value: Variant, yaw_quarters: int, margin: float = 0.0) -> bool:
	var point_array := _point_array(point_value)
	var size_array := _size_array(size_value)
	if point_array.is_empty() or size_array.is_empty(): return false
	var center := Vector2(float(point_array[0]), float(point_array[1]))
	var size := Vector2(float(size_array[0]), float(size_array[1]))
	var angle := -float(posmod(yaw_quarters, 4)) * PI * 0.5
	var cosine := cos(angle)
	var sine := sin(angle)
	var kept: Array = []
	var changed := false
	for record_value in records:
		var record: Dictionary = record_value
		var world := position_of(record)
		var delta := Vector2(world.x, world.z) - center
		var local := Vector2(delta.x * cosine - delta.y * sine, delta.x * sine + delta.y * cosine)
		var extra := margin + (0.35 if str(record.get("kind", "")) == "tree" else 0.08)
		if absf(local.x) <= size.x * 0.5 + extra and absf(local.y) <= size.y * 0.5 + extra:
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

static func _size_array(value: Variant) -> Array:
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

static func _validate_bridge_record(value: Variant) -> bool:
	if not value is Dictionary: return false
	var bridge: Dictionary = value
	if not _integer(bridge.get("id", null)) or int(bridge["id"]) < 1: return false
	if not BRIDGE_STYLE_IDS.has(str(bridge.get("style_id", ""))): return false
	if not (bridge.get("width", null) is int or bridge.get("width", null) is float): return false
	var width := float(bridge["width"])
	if not is_finite(width) or width < BRIDGE_MIN_WIDTH or width > BRIDGE_MAX_WIDTH: return false
	if not is_equal_approx(width, snappedf(width, Grid.UNIT)): return false
	var point_values = bridge.get("points", null)
	if not point_values is Array or point_values.size() != 2: return false
	var parsed: Array[Vector2] = []
	for point_value in point_values:
		if not point_value is Array or point_value.size() != 2: return false
		for coordinate in point_value:
			if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)): return false
		var point := Vector2(float(point_value[0]), float(point_value[1]))
		if point.x < 0.0 or point.x > EDITABLE_WORLD_SIZE or point.y < 0.0 or point.y > EDITABLE_WORLD_SIZE: return false
		if not is_equal_approx(point.x, snappedf(point.x, Grid.UNIT)) or not is_equal_approx(point.y, snappedf(point.y, Grid.UNIT)): return false
		parsed.append(point)
	var span := parsed[0].distance_to(parsed[1])
	return span >= BRIDGE_MIN_SPAN - 0.000001 and span <= BRIDGE_MAX_SPAN + 0.000001

static func _validate_composition_record(value: Variant) -> bool:
	if not value is Dictionary: return false
	var object: Dictionary = value
	if not _integer(object.get("id", null)) or int(object["id"]) < 1: return false
	var kind := str(object.get("kind", ""))
	if not COMPOSITION_STYLE_IDS.has(kind): return false
	if not (COMPOSITION_STYLE_IDS[kind] as Array).has(str(object.get("style_id", ""))): return false
	if not _integer(object.get("yaw_quarters", null)): return false
	var yaw := int(object["yaw_quarters"])
	if yaw < 0 or yaw > 3: return false
	var position = object.get("position", null)
	var size = object.get("size", null)
	if not position is Array or position.size() != 2 or not size is Array or size.size() != 2: return false
	for coordinate in position:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)): return false
	for extent in size:
		if not (extent is int or extent is float) or not is_finite(float(extent)): return false
	var center := Vector2(float(position[0]), float(position[1]))
	var dimensions := Vector2(float(size[0]), float(size[1]))
	if dimensions.x < COMPOSITION_MIN_SIZE or dimensions.y < COMPOSITION_MIN_SIZE or dimensions.x > COMPOSITION_MAX_SIZE or dimensions.y > COMPOSITION_MAX_SIZE: return false
	if not is_equal_approx(center.x, snappedf(center.x, Grid.UNIT)) or not is_equal_approx(center.y, snappedf(center.y, Grid.UNIT)): return false
	if not is_equal_approx(dimensions.x, snappedf(dimensions.x, Grid.UNIT)) or not is_equal_approx(dimensions.y, snappedf(dimensions.y, Grid.UNIT)): return false
	var rotated := Vector2(dimensions.y, dimensions.x) if yaw % 2 == 1 else dimensions
	var half := rotated * 0.5
	return center.x - half.x >= 0.0 and center.x + half.x <= EDITABLE_WORLD_SIZE and center.y - half.y >= 0.0 and center.y + half.y <= EDITABLE_WORLD_SIZE

static func _estimated_bridge_render_cells(bridge: Dictionary) -> int:
	var points: Array = bridge["points"]
	var a := Vector2(float(points[0][0]), float(points[0][1]))
	var b := Vector2(float(points[1][0]), float(points[1][1]))
	var span_samples := maxi(1, ceili(a.distance_to(b) / 0.25))
	var width_cells := maxi(1, ceili(float(bridge["width"]) / Grid.UNIT))
	return span_samples * width_cells + span_samples * 4 + 16

static func _estimated_composition_render_cells(object: Dictionary) -> int:
	var size: Array = object["size"]
	var area := float(size[0]) * float(size[1])
	var base := 24 if str(object["kind"]) == "furniture" else (48 if str(object["kind"]) == "fence" else 72)
	return base + ceili(area * 24.0)
