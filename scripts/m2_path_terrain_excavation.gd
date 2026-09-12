extends RefCounted

## Converts authoritative painted path cells into exact native voxel changes.
## The planner never mutates terrain. Packed-earth ownership records preserve the
## original material of every voxel removed by the path system so later profile
## changes can restore only terrain that the path still owns.
const Region = preload("res://scripts/m2_painted_path_region.gd")
const Grid = preload("res://scripts/visual_grid.gd")

static func plan_packed_earth(backend: Object, cell_values: Array) -> Dictionary:
	return plan_packed_earth_transition(backend, [], cell_values, [])

## Reconcile an old packed-earth mask with a new one. Growing/deepening regions
## remove only the additional profile depth; shrinking/overwriting regions put
## back original materials from explicit ownership records. Missing/conflicted
## ownership is never guessed, so player-authored terrain wins over restoration.
static func plan_packed_earth_transition(backend: Object, before_values: Array, after_values: Array, ownership_values: Array = []) -> Dictionary:
	if backend == null or not backend.has_method("voxel_at"):
		return _empty("terrain backend unavailable")
	var scale := float(backend.get("voxel_scale"))
	var patch: Vector3i = backend.get("patch_size")
	if not is_finite(scale) or scale <= 0.0 or patch.x <= 0 or patch.y <= 0 or patch.z <= 0:
		return _empty("invalid terrain grid")
	if not is_equal_approx(scale, Grid.UNIT):
		return _empty("path grid and terrain voxel scale differ")
	var world_size := float(patch.x) * scale
	var before_cells := Region.normalize_cells(before_values, world_size)
	var after_cells := Region.normalize_cells(after_values, world_size)
	var before_profile := Region.packed_earth_profile(before_cells)
	var after_profile := Region.packed_earth_profile(after_cells)
	var ownership := _normalize_ownership(ownership_values, patch)
	var owned_columns := {}
	for owned: Dictionary in ownership:
		var p: Vector3i = owned["position"]
		var cell := Vector2i(p.x, p.z)
		if not owned_columns.has(cell): owned_columns[cell] = []
		(owned_columns[cell] as Array).append(owned)
	for column_value in owned_columns.values():
		(column_value as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["position"] as Vector3i).y < (b["position"] as Vector3i).y)
	var union_cells := Region.union_cells(before_cells, after_cells, world_size)
	var changes: Array = []
	var removals: Array = []
	var restorations: Array = []
	var acquired: Array = []
	var released: Array = []
	var min_pos := Vector3i(patch.x, patch.y, patch.z)
	var max_pos := Vector3i.ZERO
	var conflicts := 0
	for cell: Vector2i in union_cells:
		var before_depth := int(before_profile.get(cell, 0))
		var after_depth := int(after_profile.get(cell, 0))
		var delta := after_depth - before_depth
		if delta == 0: continue
		var column_owned: Array = owned_columns.get(cell, [])
		if delta > 0:
			# If an existing cut no longer has the ownership needed to explain its
			# old depth, terrain was edited independently. Do not dig through it.
			if before_depth > 0 and column_owned.size() < before_depth:
				conflicts += delta
				continue
			var world := Region.cell_center(cell)
			var x := clampi(floori(world.x / scale), 0, patch.x - 1)
			var z := clampi(floori(world.y / scale), 0, patch.z - 1)
			var top := _top_solid_y(backend, x, z, patch.y)
			if top < 0:
				conflicts += delta
				continue
			for offset in delta:
				var y := top - offset
				if y < 0: break
				var position := Vector3i(x, y, z)
				var material := int(backend.voxel_at(position))
				# Never tunnel through a pre-existing void/cave.
				if material == 0:
					conflicts += delta - offset
					break
				var change := {"position": position, "before": material, "after": 0, "depth": after_depth, "delta": delta}
				changes.append(change)
				removals.append(change)
				acquired.append({"position": position, "material": material})
				min_pos = min_pos.min(position)
				max_pos = max_pos.max(position + Vector3i.ONE)
		else:
			var restore_count := -delta
			for index in mini(restore_count, column_owned.size()):
				var owned: Dictionary = column_owned[index]
				var position: Vector3i = owned["position"]
				var material := int(owned["material"])
				released.append(owned)
				var current := int(backend.voxel_at(position))
				if current != 0:
					# The player or another system already owns this voxel now.
					conflicts += 1
					continue
				var change := {"position": position, "before": 0, "after": material, "depth": after_depth, "delta": delta}
				changes.append(change)
				restorations.append(change)
				min_pos = min_pos.min(position)
				max_pos = max_pos.max(position + Vector3i.ONE)
			if column_owned.size() < restore_count: conflicts += restore_count - column_owned.size()
	return {
		"ok": true,
		"error": "",
		"cells": Region.encode_cells(after_cells),
		"profile": _encode_profile(after_profile),
		"changes": changes,
		"removals": removals,
		"restorations": restorations,
		"acquired": acquired,
		"released": released,
		"changed_count": changes.size(),
		"conflict_count": conflicts,
		"min": min_pos if not changes.is_empty() else Vector3i.ZERO,
		"max": max_pos if not changes.is_empty() else Vector3i.ZERO,
	}

static func _normalize_ownership(values: Array, patch: Vector3i) -> Array:
	var result: Array = []
	var seen := {}
	for value in values:
		if not value is Dictionary: continue
		var entry: Dictionary = value
		var raw_position = entry.get("position", null)
		var position := Vector3i(-1, -1, -1)
		if raw_position is Vector3i:
			position = raw_position
		elif raw_position is Array and raw_position.size() == 3:
			if not _integer(raw_position[0]) or not _integer(raw_position[1]) or not _integer(raw_position[2]): continue
			position = Vector3i(int(raw_position[0]), int(raw_position[1]), int(raw_position[2]))
		if position.x < 0 or position.y < 0 or position.z < 0 or position.x >= patch.x or position.y >= patch.y or position.z >= patch.z: continue
		var material = entry.get("material", entry.get("before", 0))
		if not _integer(material) or int(material) <= 0 or int(material) > 65535: continue
		var key := "%d:%d:%d" % [position.x, position.y, position.z]
		if seen.has(key): continue
		seen[key] = true
		result.append({"position": position, "material": int(material)})
	return result

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

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))

static func _empty(message: String) -> Dictionary:
	return {"ok": false, "error": message, "cells": [], "profile": [], "changes": [], "removals": [], "restorations": [], "acquired": [], "released": [], "changed_count": 0, "conflict_count": 0, "min": Vector3i.ZERO, "max": Vector3i.ZERO}
