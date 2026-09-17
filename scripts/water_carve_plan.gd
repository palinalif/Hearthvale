class_name WaterCarvePlan
extends RefCounted
## Pure, deterministic carve plan for an authored water region — the "what the
## river/lake tool would carve" preview. Given a terrain-top sampler (world Y of
## the column top, NAN when the column is empty) it returns which cells to lower
## to the bed level and which shore (bank) cells to smooth. No terrain writes,
## no state, no RNG: the same region + terrain always yields the same plan.
const Grid = preload("res://scripts/visual_grid.gd")
const Geometry = preload("res://scripts/water_region_geometry.gd")
const STREAM_BED_DEPTH := 0.4
const LAKE_BED_DEPTH := 0.75

static func bed_depth(region: Dictionary) -> float:
	return LAKE_BED_DEPTH if Geometry.is_lake(region) else STREAM_BED_DEPTH

## plan(region, sample: Callable(Vector2)->float, world_size) -> Dictionary with
## "level", "bed_level", "bed" (Array of [Vector2i, float]), "banks" (Array of
## Vector2i) and "cells" (footprint cell count).
static func plan(region: Dictionary, sample: Callable, world_size: float) -> Dictionary:
	var level := Geometry.surface_level(region)
	var bed_level := level - bed_depth(region)
	var bed: Array = []
	var cells := Geometry.footprint_cells(region, world_size)
	var inside := {}
	for cell: Vector2i in cells:
		inside[cell] = true
		var center := _cell_center(cell)
		var top: float = sample.call(center)
		if not is_nan(top) and top > bed_level + 0.000001:
			bed.append([cell, bed_level])
	var banks := {}
	for cell: Vector2i in cells:
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor := cell + offset
			if inside.has(neighbor) or neighbor.x < 0 or neighbor.y < 0:
				continue
			var ntop: float = sample.call(_cell_center(neighbor))
			if not is_nan(ntop) and ntop > level + 0.000001:
				banks[neighbor] = true
	var bank_list: Array = []
	for cell: Vector2i in banks:
		bank_list.append(cell)
	bank_list.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a.y * 1000 + a.x) < (b.y * 1000 + b.x))
	return {"level": level, "bed_level": bed_level, "bed": bed, "banks": bank_list, "cells": cells.size()}

static func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * Grid.UNIT, (cell.y + 0.5) * Grid.UNIT)
