extends RefCounted
## Pure, deterministic excavator for an authored water region — the native voxel
## changes the river/lake tool applies when committing. Lowers each bed cell's
## terrain top to the region's bed level and each bank cell's top to the water
## level (a smooth shore). It never mutates terrain and never tunnels through a
## pre-existing void/cave. The same region + terrain always yields the same plan.
const Grid = preload("res://scripts/visual_grid.gd")
const Plan = preload("res://scripts/water_carve_plan.gd")

static func plan_bed(backend: Object, region: Dictionary, world_size: float) -> Dictionary:
	if backend == null or not backend.has_method("voxel_at"):
		return _empty("terrain backend unavailable")
	var scale := float(backend.get("voxel_scale"))
	var patch: Vector3i = backend.get("patch_size")
	if not is_finite(scale) or scale <= 0.0 or patch.x <= 0 or patch.y <= 0 or patch.z <= 0:
		return _empty("invalid terrain grid")
	if not is_equal_approx(scale, Grid.UNIT):
		return _empty("water grid and terrain voxel scale differ")
	var plan: Dictionary = Plan.plan(region, _sampler(backend, scale, patch), world_size)
	var bed_level := float(plan["bed_level"])
	var level := float(plan["level"])
	var changes: Array = []
	for entry: Array in plan["bed"]:
		var cell: Vector2i = entry[0]
		changes.append_array(_carve_column(backend, cell, _target_top_y(bed_level, scale), patch.y))
	for bank: Vector2i in plan["banks"]:
		changes.append_array(_carve_column(backend, bank, _target_top_y(level, scale), patch.y))
	return {"ok": true, "changes": changes, "changed_count": changes.size()}

static func _carve_column(backend: Object, cell: Vector2i, target_top: int, height: int) -> Array:
	var result: Array = []
	if target_top < 0: return result
	var top := _top_solid_y(backend, cell.x, cell.y, height)
	if top < 0: return result
	for y in range(top, target_top, -1):
		var position := Vector3i(cell.x, y, cell.y)
		var material := int(backend.voxel_at(position))
		if material == 0: break
		result.append({"position": position, "before": material, "after": 0})
	return result

static func _sampler(backend: Object, scale: float, patch: Vector3i) -> Callable:
	return func(p: Vector2) -> float:
		var x := clampi(floori(p.x / scale), 0, patch.x - 1)
		var z := clampi(floori(p.y / scale), 0, patch.z - 1)
		for y in range(patch.y - 1, -1, -1):
			if int(backend.voxel_at(Vector3i(x, y, z))) != 0:
				return float(y + 1) * scale
		return NAN

## Largest solid voxel Y whose top face is at or below world_y (i.e. (y+1)*scale <= world_y).
static func _target_top_y(world_y: float, scale: float) -> int:
	return floori(world_y / scale) - 1

static func _top_solid_y(backend: Object, x: int, z: int, height: int) -> int:
	for y in range(height - 1, -1, -1):
		if int(backend.voxel_at(Vector3i(x, y, z))) != 0:
			return y
	return -1

static func _empty(message: String) -> Dictionary:
	return {"ok": false, "error": message, "changes": [], "changed_count": 0}
