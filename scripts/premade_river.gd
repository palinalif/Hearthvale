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
## A region stored by an older world size (shorter point list, same river) is
## still recognised as the starter river so it can be extended in place rather
## than duplicated.
static func matches(region: Dictionary, river: Dictionary) -> bool:
	if str(region.get("type", "")) != "stream": return false
	if not is_equal_approx(float(region.get("level", -1.0)), float(river["level"])): return false
	if not is_equal_approx(float(region.get("width", -1.0)), float(river["width"])): return false
	var existing: Array = region.get("points", [])
	if existing.size() < 2: return false
	var river_flow: Array = river["flow"] if river["flow"] is Array else []
	var region_flow: Array = region.get("flow", []) if region.has("flow") and region.get("flow") is Array else []
	if river_flow.size() != region_flow.size(): return false
	for i in river_flow.size():
		if not is_equal_approx(float(river_flow[i]), float(region_flow[i])): return false
	var expected: Array = river["points"]
	if existing.size() == expected.size():
		for i in existing.size():
			if not is_equal_approx(float(existing[i][0]), float(expected[i][0])): return false
			if not is_equal_approx(float(existing[i][1]), float(expected[i][1])): return false
		return true
	return is_starter_river(region)

## True when a stored stream region follows the starter river centerline from
## its mouth for at least the old 64 m world (idempotency across world sizes).
static func is_starter_river(region: Dictionary) -> bool:
	if str(region.get("type", "")) != "stream": return false
	if not is_equal_approx(float(region.get("level", -1.0)), LEVEL): return false
	if not is_equal_approx(float(region.get("width", -1.0)), WIDTH): return false
	var existing: Array = region.get("points", [])
	if existing.size() < 2: return false
	for point: Array in existing:
		var z := float(point[1])
		if z < 0.0 or z > Bounds.SIZE: return false
		if absf(float(point[0]) - Generator.river_center_x(z)) > 0.1875: return false
	return true
