class_name WaterRegionGeometry
extends RefCounted
## Pure, deterministic geometry over authored water regions. Presentation and
## edit previews both consume this; it owns no state and reads only the region
## record. A lake is a closed boundary polygon; a stream is a centreline with a
## width. Nothing here simulates fluid behaviour.
const Grid = preload("res://scripts/visual_grid.gd")
const PathRegion = preload("res://scripts/m2_painted_path_region.gd")

static func is_lake(region: Dictionary) -> bool:
	return str(region.get("type", "")) == "lake"

static func surface_level(region: Dictionary) -> float:
	var level = region.get("level", 0.0)
	return float(level)

## True when the world XZ point lies inside the authored water body.
static func contains(region: Dictionary, point: Vector2) -> bool:
	if not point.is_finite(): return false
	if is_lake(region):
		return point_in_polygon(_points(region), point)
	return min_distance_to_polyline(_points(region), point) <= stream_radius(region) + 0.000001

static func stream_radius(region: Dictionary) -> float:
	var width = region.get("width", 0.0)
	return float(width) * 0.5

## The region's authored points as Vector2 (lake boundary / stream centreline).
static func points(region: Dictionary) -> PackedVector2Array:
	return _points(region)

## Rasterising a long stream (dozens of stroked segments of ~hundreds of cells
## each) takes seconds on a phone CPU, and the surface/preview paths asked for
## the same footprint repeatedly (resample loop, mesh build, per-frame preview
## fingerprint) — once per call. Memoise per geometry signature so each distinct
## shape is rasterised at most once; callers treat the returned array as
## read-only (it is shared).
static var _footprint_memo: Dictionary = {}
const _FOOTPRINT_MEMO_LIMIT := 10

static func footprint_key(region: Dictionary, world_size: float) -> String:
	return "%s|%.6f|%.6f|%s" % [str(region.get("type", "")), stream_radius(region), world_size, var_to_bytes(_points(region)).hex_encode()]

## Structural-grid cells whose centre lies inside the water body. Used for the
## clipped water surface mesh and shore clipping. Deterministic.
static func footprint_cells(region: Dictionary, world_size: float) -> Array:
	var key := footprint_key(region, world_size)
	if _footprint_memo.has(key):
		return _footprint_memo[key]
	var cells: Array
	if is_lake(region):
		cells = _lake_cells(_points(region), world_size)
	else:
		var points := _points(region)
		if points.size() < 2: cells = []
		else:
			cells = []
			for i in range(1, points.size()):
				cells.append_array(PathRegion.stroke_cells(points[i - 1], points[i], stream_radius(region), world_size))
			# Unioning after every segment repeatedly sorts the growing river.
			# One normalization yields the same bounded, unique, sorted cells.
			cells = PathRegion.normalize_cells(cells, world_size)
	if _footprint_memo.size() >= _FOOTPRINT_MEMO_LIMIT:
		_footprint_memo.clear()
	_footprint_memo[key] = cells
	return cells

## True when the terrain surface Y at a point is below the water level (i.e. the
## point sits under the water body and should show water). Pure.
static func is_submerged(region: Dictionary, point: Vector2, surface_y: float) -> bool:
	return contains(region, point) and surface_y < surface_level(region) - 0.000001

static func flow_direction(region: Dictionary) -> Vector2:
	var flow = region.get("flow", null)
	if flow is Array and flow.size() == 2:
		var direction := Vector2(float(flow[0]), float(flow[1]))
		if direction.length() > 0.000001: return direction.normalized()
	return Vector2(1.0, 0.0)

static func _points(region: Dictionary) -> PackedVector2Array:
	var point_values = region.get("points", [])
	var result := PackedVector2Array()
	if not point_values is Array: return result
	for point_value in point_values:
		if point_value is Array and point_value.size() == 2:
			result.append(Vector2(float(point_value[0]), float(point_value[1])))
	return result

## Even-odd ray cast. Deterministic; no allocation-sensitive order dependence.
static func point_in_polygon(polygon: PackedVector2Array, point: Vector2) -> bool:
	var inside := false
	var n := polygon.size()
	if n < 3: return false
	var j := n - 1
	for i in range(n):
		var a := polygon[i]
		var b := polygon[j]
		if ((a.y > point.y) != (b.y > point.y)) and point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		j = i
	return inside

static func min_distance_to_polyline(polyline: PackedVector2Array, point: Vector2) -> float:
	if polyline.size() < 2: return INF
	var best := INF
	for i in range(1, polyline.size()):
		best = minf(best, point.distance_to(segment_closest_point(polyline[i - 1], polyline[i], point)))
	return best

static func segment_closest_point(a: Vector2, b: Vector2, point: Vector2) -> Vector2:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared < 0.000000001: return a
	var t := ((point - a) .dot(ab) / length_squared)
	return a + ab * clampf(t, 0.0, 1.0)

## Structural cells for a lake: rasterise the polygon bounding box and keep the
## cells whose centre is inside. Bounded and deterministic.
static func _lake_cells(polygon: PackedVector2Array, world_size: float) -> Array:
	if polygon.size() < 3: return []
	var bounds := Rect2()
	for point in polygon: bounds = bounds.expand(point)
	var cell_limit := maxi(1, floori(world_size / Grid.UNIT))
	var result: Array = []
	var x0 := clampi(floori(bounds.position.x / Grid.UNIT), 0, cell_limit)
	var x1 := clampi(ceili(bounds.end.x / Grid.UNIT), 0, cell_limit)
	var z0 := clampi(floori(bounds.position.y / Grid.UNIT), 0, cell_limit)
	var z1 := clampi(ceili(bounds.end.y / Grid.UNIT), 0, cell_limit)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var center := Vector2((x + 0.5) * Grid.UNIT, (z + 0.5) * Grid.UNIT)
			if point_in_polygon(polygon, center):
				result.append(Vector2i(x, z))
	return result
