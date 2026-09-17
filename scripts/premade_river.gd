extends RefCounted
class_name PremadeRiver
## The starter valley's river, expressed as a water *region* so it shares the
## exact presentation path (M1WaterVisual) with player-authored water. Derived
## deterministically from the terrain generator -- no RNG, no state, and the
## carved bed already exists in the generated terrain (no carve is performed).
## Keeping it a region (not a bespoke mesh) means extending the river or giving
## it a different material later goes through the same system as every other body.
const Generator = preload("res://scripts/m1_patch_generator.gd")
const Bounds = preload("res://scripts/m2_world_bounds.gd")

## Water surface sits just above the generated bed floor (4.375) -- matches the
## previous static mesh at 5.0. Width is generous so the region fully covers the
## channel; the terrain (terrain-top < level) clips it to the actual bed.
const LEVEL := 5.0
const WIDTH := 5.0
const FLOW := [0.0, 1.0]

static func region() -> Dictionary:
	var points: Array = []
	var z := 0.0
	while z <= Bounds.SIZE + 0.000001:
		points.append([Generator.river_center_x(z), z])
		z += 1.0
	return {"type": "stream", "level": LEVEL, "width": WIDTH, "points": points, "flow": FLOW}

## True when an existing water region is this derived river (idempotency check).
static func matches(region: Dictionary, river: Dictionary) -> bool:
	if str(region.get("type", "")) != "stream": return false
	if not is_equal_approx(float(region.get("level", -1.0)), float(river["level"])): return false
	if not is_equal_approx(float(region.get("width", -1.0)), float(river["width"])): return false
	var existing: Array = region.get("points", [])
	var expected: Array = river["points"]
	if existing.size() != expected.size(): return false
	return float(existing[0][0]) == float(expected[0][0]) and float(existing[0][1]) == float(expected[0][1]) \
		and float(existing[-1][0]) == float(expected[-1][0]) and float(existing[-1][1]) == float(expected[-1][1])
