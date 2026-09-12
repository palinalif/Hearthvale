extends RefCounted

## Canonical helpers for painted road/path regions.
## Authoring lives on the structural 0.125 m visual grid; rendering may derive
## finer accents later, but saved authority remains a deterministic cell mask.
const Grid = preload("res://scripts/visual_grid.gd")
const DEFAULT_WORLD_SIZE := 48.0
const PROFILE_RING_CAP := 4
const NEIGHBOURS := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

static func cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2.ONE * 0.5) * Grid.UNIT

static func brush_cells(center: Vector2, radius: float, world_size: float = DEFAULT_WORLD_SIZE) -> Array:
	var cell_limit := maxi(1, floori(world_size / Grid.UNIT))
	var safe_radius := maxf(radius, Grid.UNIT * 0.5)
	var lo := Vector2i(
		maxi(0, floori((center.x - safe_radius) / Grid.UNIT)),
		maxi(0, floori((center.y - safe_radius) / Grid.UNIT))
	)
	var hi := Vector2i(
		mini(cell_limit - 1, floori((center.x + safe_radius) / Grid.UNIT)),
		mini(cell_limit - 1, floori((center.y + safe_radius) / Grid.UNIT))
	)
	var result: Array = []
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var cell := Vector2i(x, z)
			if cell_center(cell).distance_to(center) <= safe_radius + 0.000001:
				result.append(cell)
	# A tiny brush at a grid corner can miss every cell centre. Painting must
	# still be continuous, so fall back to the containing structural cell.
	if result.is_empty() and center.x >= 0.0 and center.y >= 0.0 and center.x < world_size and center.y < world_size:
		result.append(Vector2i(
			clampi(floori(center.x / Grid.UNIT), 0, cell_limit - 1),
			clampi(floori(center.y / Grid.UNIT), 0, cell_limit - 1)
		))
	return _sorted(result)

## Rasterize a continuous brush sweep between two world-space X/Z samples.
## Cursor/controller input is frame based, so painting only the endpoints can
## leave holes when the cursor moves several cells in one frame. Sampling at a
## half-cell cadence guarantees overlapping circular stamps without making the
## saved representation depend on frame rate.
static func stroke_cells(from: Vector2, to: Vector2, radius: float, world_size: float = DEFAULT_WORLD_SIZE) -> Array:
	if not from.is_finite() or not to.is_finite(): return []
	var distance := from.distance_to(to)
	var spacing := Grid.UNIT * 0.5
	var steps := maxi(1, ceili(distance / spacing))
	var result: Array = []
	for step in range(steps + 1):
		var amount := float(step) / float(steps)
		result = union_cells(result, brush_cells(from.lerp(to, amount), radius, world_size), world_size)
	return result

static func normalize_cells(values: Array, world_size: float = DEFAULT_WORLD_SIZE) -> Array:
	var cell_limit := maxi(1, floori(world_size / Grid.UNIT))
	var unique := {}
	for value in values:
		var cell := Vector2i(-1, -1)
		if value is Vector2i:
			cell = value
		elif value is Vector2:
			cell = Vector2i(roundi(value.x), roundi(value.y))
		elif value is Array and value.size() >= 2:
			cell = Vector2i(int(value[0]), int(value[1]))
		if cell.x < 0 or cell.y < 0 or cell.x >= cell_limit or cell.y >= cell_limit:
			continue
		unique[cell] = true
	return _sorted(unique.keys())

static func encode_cells(values: Array, world_size: float = DEFAULT_WORLD_SIZE) -> Array:
	var result: Array = []
	for cell: Vector2i in normalize_cells(values, world_size):
		result.append([cell.x, cell.y])
	return result

static func union_cells(existing: Array, painted: Array, world_size: float = DEFAULT_WORLD_SIZE) -> Array:
	var unique := {}
	for cell: Vector2i in normalize_cells(existing, world_size): unique[cell] = true
	for cell: Vector2i in normalize_cells(painted, world_size): unique[cell] = true
	return _sorted(unique.keys())

static func erase_cells(existing: Array, erased: Array, world_size: float = DEFAULT_WORLD_SIZE) -> Array:
	var unique := {}
	for cell: Vector2i in normalize_cells(existing, world_size): unique[cell] = true
	for cell: Vector2i in normalize_cells(erased, world_size): unique.erase(cell)
	return _sorted(unique.keys())

static func distance_field(values: Array, ring_cap: int = PROFILE_RING_CAP) -> Dictionary:
	var remaining := {}
	for cell: Vector2i in normalize_cells(values): remaining[cell] = true
	var result := {}
	var ring := 0
	var safe_cap := maxi(0, ring_cap)
	while not remaining.is_empty() and ring < safe_cap:
		var boundary: Array = []
		for cell: Vector2i in _sorted(remaining.keys()):
			for offset: Vector2i in NEIGHBOURS:
				if not remaining.has(cell + offset):
					boundary.append(cell)
					break
		if boundary.is_empty(): break
		for cell: Vector2i in boundary:
			result[cell] = ring
			remaining.erase(cell)
		ring += 1
	for cell: Vector2i in remaining.keys(): result[cell] = safe_cap
	return result

static func packed_earth_depth_steps(edge_distance: int) -> int:
	# The edge stays level with the lawn. Normal paths sink one voxel through the
	# middle; only broad roads/plazas acquire a two-voxel packed-down interior.
	if edge_distance <= 0: return 0
	if edge_distance >= 3: return 2
	return 1

static func packed_earth_depth_offset(edge_distance: int) -> float:
	return -float(packed_earth_depth_steps(edge_distance)) * Grid.UNIT

static func packed_earth_profile(values: Array) -> Dictionary:
	var field := distance_field(values, PROFILE_RING_CAP)
	var result := {}
	for cell in field:
		result[cell] = packed_earth_depth_steps(int(field[cell]))
	return result

static func _sorted(values: Array) -> Array:
	var result := values.duplicate()
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return result
