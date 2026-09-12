extends RefCounted

## Converts authoritative painted path cells into exact native voxel removals.
## This module does not mutate terrain. It records the original material for
## every proposed removal so the backend can commit the whole path stroke as
## one normal before/after history command.
const Region = preload("res://scripts/m2_painted_path_region.gd")
const Grid = preload("res://scripts/visual_grid.gd")

static func plan_packed_earth(backend: Object, cell_values: Array) -> Dictionary:
	if backend == null or not backend.has_method("voxel_at"):
		return _empty("terrain backend unavailable")
	var scale := float(backend.get("voxel_scale"))
	var patch: Vector3i = backend.get("patch_size")
	if not is_finite(scale) or scale <= 0.0 or patch.x <= 0 or patch.y <= 0 or patch.z <= 0:
		return _empty("invalid terrain grid")
	# Painted authority is on the 0.125 m structural grid. The current M1
	# terrain uses the same voxel pitch; reject a mismatched backend rather than
	# silently digging a different footprint.
	if not is_equal_approx(scale, Grid.UNIT):
		return _empty("path grid and terrain voxel scale differ")
	var cells := Region.normalize_cells(cell_values, float(patch.x) * scale)
	var profile := Region.packed_earth_profile(cells)
	var removals: Array = []
	var min_pos := Vector3i(patch.x, patch.y, patch.z)
	var max_pos := Vector3i.ZERO
	for cell: Vector2i in cells:
		var depth := int(profile.get(cell, 0))
		if depth <= 0: continue
		var world := Region.cell_center(cell)
		var x := clampi(floori(world.x / scale), 0, patch.x - 1)
		var z := clampi(floori(world.y / scale), 0, patch.z - 1)
		var top := _top_solid_y(backend, x, z, patch.y)
		if top < 0: continue
		for offset in depth:
			var y := top - offset
			if y < 0: break
			var position := Vector3i(x, y, z)
			var material := int(backend.voxel_at(position))
			# Never tunnel through an existing void. A path lowers the connected
			# exposed surface only; caves/overhang gaps stay authored terrain.
			if material == 0: break
			removals.append({"position": position, "before": material, "after": 0, "depth": depth})
			min_pos = min_pos.min(position)
			max_pos = max_pos.max(position + Vector3i.ONE)
	return {
		"ok": true,
		"error": "",
		"cells": Region.encode_cells(cells),
		"profile": _encode_profile(profile),
		"removals": removals,
		"changed_count": removals.size(),
		"min": min_pos if not removals.is_empty() else Vector3i.ZERO,
		"max": max_pos if not removals.is_empty() else Vector3i.ZERO,
	}

static func _top_solid_y(backend: Object, x: int, z: int, height: int) -> int:
	for y in range(height - 1, -1, -1):
		if int(backend.voxel_at(Vector3i(x, y, z))) != 0:
			return y
	return -1

static func _encode_profile(profile: Dictionary) -> Array:
	var keys: Array = profile.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	var result: Array = []
	for cell: Vector2i in keys:
		result.append([cell.x, cell.y, int(profile[cell])])
	return result

static func _empty(message: String) -> Dictionary:
	return {"ok": false, "error": message, "cells": [], "profile": [], "removals": [], "changed_count": 0, "min": Vector3i.ZERO, "max": Vector3i.ZERO}
