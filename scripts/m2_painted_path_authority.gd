extends RefCounted

## Pure ownership rules for authoritative painted path regions.
## Each style owns at most one saved region record and each structural cell may
## belong to exactly one style. Painting is therefore a deterministic material
## replacement operation rather than a collection of overlapping brush strokes.
const Region = preload("res://scripts/m2_painted_path_region.gd")
const STYLE_IDS: Array[String] = ["packed_earth", "cobblestone", "stepping_stones"]
const MAX_CELLS := 24000

static func paint(path_values: Array, next_id: int, style_id: String, cell_values: Array) -> Dictionary:
	if not STYLE_IDS.has(style_id): return _result(path_values, next_id, false, -1)
	var painted := Region.normalize_cells(cell_values)
	if painted.is_empty(): return _result(path_values, next_id, false, -1)
	var paint_lookup := _lookup(painted)
	var result_paths: Array = []
	var target_cells: Array = []
	var target_id := -1
	var changed := false
	for path_value in path_values:
		if not path_value is Dictionary: continue
		var path: Dictionary = path_value
		var current_style := str(path.get("style_id", ""))
		var current_id := int(path.get("id", -1))
		var cells := Region.normalize_cells(path.get("cells", []))
		if current_style == style_id:
			if target_id < 0: target_id = current_id
			target_cells = Region.union_cells(target_cells, cells)
			continue
		var kept: Array = []
		for cell: Vector2i in cells:
			if paint_lookup.has(cell):
				changed = true
			else:
				kept.append(cell)
		if not kept.is_empty(): result_paths.append({"id": current_id, "style_id": current_style, "cells": Region.encode_cells(kept)})
		elif not cells.is_empty():
			changed = true
	var before_target := target_cells.duplicate()
	target_cells = Region.union_cells(target_cells, painted)
	changed = changed or target_cells != before_target
	if target_id < 0:
		target_id = next_id
		next_id += 1
		changed = true
	result_paths.append({"id": target_id, "style_id": style_id, "cells": Region.encode_cells(target_cells)})
	result_paths.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("id", 0)) < int(b.get("id", 0)))
	if total_cells(result_paths) > MAX_CELLS: return _result(path_values, next_id - (1 if target_id == next_id - 1 else 0), false, -1)
	return _result(result_paths, next_id, changed, target_id)

static func erase(path_values: Array, cell_values: Array) -> Dictionary:
	var erased := Region.normalize_cells(cell_values)
	if erased.is_empty(): return {"paths": path_values.duplicate(true), "changed": false}
	var erase_lookup := _lookup(erased)
	var result_paths: Array = []
	var changed := false
	for path_value in path_values:
		if not path_value is Dictionary: continue
		var path: Dictionary = path_value
		var cells := Region.normalize_cells(path.get("cells", []))
		var kept: Array = []
		for cell: Vector2i in cells:
			if erase_lookup.has(cell): changed = true
			else: kept.append(cell)
		if not kept.is_empty():
			result_paths.append({"id": int(path.get("id", -1)), "style_id": str(path.get("style_id", "")), "cells": Region.encode_cells(kept)})
	result_paths.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("id", 0)) < int(b.get("id", 0)))
	return {"paths": result_paths, "changed": changed}

static func validate(path_values: Array) -> bool:
	if path_values.size() > STYLE_IDS.size(): return false
	var ids := {}
	var styles := {}
	var occupied := {}
	var count := 0
	for path_value in path_values:
		if not path_value is Dictionary: return false
		var path: Dictionary = path_value
		var id_value = path.get("id", null)
		if not (id_value is int or id_value is float) or not is_finite(float(id_value)) or float(id_value) != floorf(float(id_value)): return false
		var id := int(id_value)
		var style_id := str(path.get("style_id", ""))
		if id < 1 or ids.has(id) or not STYLE_IDS.has(style_id) or styles.has(style_id): return false
		ids[id] = true
		styles[style_id] = true
		var raw_cells = path.get("cells", null)
		if not raw_cells is Array or raw_cells.is_empty(): return false
		var cells := Region.normalize_cells(raw_cells)
		if cells.size() != raw_cells.size(): return false
		for index in cells.size():
			var raw = raw_cells[index]
			if not raw is Array or raw.size() != 2: return false
			if int(raw[0]) != cells[index].x or int(raw[1]) != cells[index].y: return false
			if occupied.has(cells[index]): return false
			occupied[cells[index]] = true
		count += cells.size()
		if count > MAX_CELLS: return false
	return true

static func total_cells(path_values: Array) -> int:
	var count := 0
	for path_value in path_values:
		if path_value is Dictionary: count += Region.normalize_cells((path_value as Dictionary).get("cells", [])).size()
	return count

static func cells_for_style(path_values: Array, style_id: String) -> Array:
	for path_value in path_values:
		if path_value is Dictionary and str((path_value as Dictionary).get("style_id", "")) == style_id:
			return Region.normalize_cells((path_value as Dictionary).get("cells", []))
	return []

static func _lookup(values: Array) -> Dictionary:
	var result := {}
	for cell: Vector2i in values: result[cell] = true
	return result

static func _result(paths: Array, next_id: int, changed: bool, path_id: int) -> Dictionary:
	return {"paths": paths.duplicate(true), "next_id": next_id, "changed": changed, "path_id": path_id}
