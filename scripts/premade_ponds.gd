extends RefCounted
class_name PremadePonds
## The starter valley's ponds, expressed as water *regions* (the lake shape
## the water tool authors) so they share the presentation path, materials and
## editability with player-authored water, exactly like the starter river.
## Deterministic and idempotent: fixed outlines on the flat village green,
## added once and matched on every load (old saves get them carved + added;
## current saves already carry them in the landscape document).
const Grid = preload("res://scripts/visual_grid.gd")
const Geometry = preload("res://scripts/water_region_geometry.gd")

## The village green is flat 8.0 m; the water level sits 0.5 m below it so
## the shore reads as a shallow depression, not a hole with raised banks.
const LEVEL := 7.5
## Lake bed depth matches the water tool's excavation plan, so a player
## extending a pond with the tool gets the same profile we author here.
const BED_DEPTH := 0.75

const _POND_MAIN_CENTER := Vector2(54.0, 82.0)
const _POND_SMALL_CENTER := Vector2(36.0, 76.0)

## Water regions to make sure exist in the starter valley: [id, type, level,
## points]. Outlines are hand-authored organic blobs (16 vertices each) with
## two incommensurate radius harmonics, snapped to the visual grid like
## player-drawn polygons.
static func regions() -> Array:
	return [
		_pond(_POND_MAIN_CENTER, 1.75, 0.35, 0.9, 0.25, 2.6),
		_pond(_POND_SMALL_CENTER, 1.15, 0.22, 2.1, 0.18, 4.4),
	]

static func _pond(center: Vector2, base: float, a1: float, p1: float, a2: float, p2: float) -> Dictionary:
	var points: Array = []
	for i in 16:
		var theta: float = i / 16.0 * TAU
		var radius: float = base + a1 * sin(2.0 * theta + p1) + a2 * sin(3.0 * theta + p2)
		var point := (center + Vector2(cos(theta), sin(theta)) * radius).snapped(Vector2(Grid.UNIT, Grid.UNIT))
		points.append([point.x, point.y])
	return {"type": "lake", "level": LEVEL, "points": points}

## Average of the outline, for reporting and tests.
static func center_of(pond: Dictionary) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for raw in pond["points"]:
		var p: Array = raw
		sum += Vector2(float(p[0]), float(p[1]))
		n += 1
	return sum / maxf(1.0, float(n))


## True when an existing landscape region is one of the premade ponds, so
## startup only adds missing ponds and never duplicates them.
static func matches(existing: Dictionary, pond: Dictionary) -> bool:
	if not existing is Dictionary: return false
	if str(existing.get("type", "")) != "lake": return false
	if not is_equal_approx(float(existing.get("level", -1.0)), float(pond["level"])): return false
	var existing_points: Array = existing.get("points", [])
	var pond_points: Array = pond["points"]
	if existing_points.size() != pond_points.size(): return false
	for i in pond_points.size():
		var a: Array = existing_points[i]
		var b: Array = pond_points[i]
		if not is_equal_approx(float(a[0]), float(b[0])) or not is_equal_approx(float(a[1]), float(b[1])):
			return false
	return true


## True when the pond's centre column already sits at (or just below) the lake
## bed: a save that already had the pond carved. Carving is then skipped, so
## startup stays idempotent and the shore ring never ratchets outward.
## `sample` maps a world XZ (meters) to the terrain top in meters (or NAN).
static func already_carved(sample: Callable, pond: Dictionary) -> bool:
	var top: float = float(sample.call(center_of(pond)))
	return is_finite(top) and top <= LEVEL + Grid.UNIT
