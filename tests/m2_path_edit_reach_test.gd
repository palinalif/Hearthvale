extends SceneTree

## M2PathVisual.edit-reach checks (fast, no scene): the predicate the scene
## uses to skip the full path re-mesh must agree exactly with the height-cache
## invalidation margin, stay conservative on unknown edit bounds, and be
## cheap enough to run on every terrain change.

const Visual = preload("res://scripts/m2_path_visual.gd")
const Grid = preload("res://scripts/visual_grid.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

## World AABB covering the inclusive structural-cell range (min_x..max_x,
## min_z..max_z) at the shared 0.125 grid.
func _bounds(min_x: int, min_z: int, max_x: int, max_z: int) -> AABB:
	return AABB(
		Vector3(min_x * Grid.UNIT, 0.0, min_z * Grid.UNIT),
		Vector3((max_x - min_x + 1) * Grid.UNIT, Grid.UNIT, (max_z - min_z + 1) * Grid.UNIT)
	)

func _run() -> void:
	var visual: Node = Visual.new()
	root.add_child(visual)

	var paths: Array = [
		{"style_id": "packed_earth", "cells": [Vector2i(112, 112), Vector2i(113, 112)]},
		{"style_id": "cobblestone", "cells": [Vector2i(200, 200)]},
		{"style_id": "stepping_stones", "cells": []},
	]

	# An edit on a path cell always touches.
	_check(visual.last_terrain_edit_touches_paths(paths, _bounds(112, 112, 112, 112)), "edit on a packed-earth cell touches the path")
	_check(visual.last_terrain_edit_touches_paths(paths, _bounds(200, 200, 200, 200)), "edit on a cobblestone cell touches the path")
	# An edit within the 2-cell margin (one free cell between) touches;
	# three cells away (two free cells) does not.
	_check(visual.last_terrain_edit_touches_paths(paths, _bounds(115, 112, 115, 112)), "edit two cells past the last packed-earth cell touches the path")
	_check(not visual.last_terrain_edit_touches_paths(paths, _bounds(116, 112, 116, 112)), "edit three cells past the path stays clear of it")
	_check(visual.last_terrain_edit_touches_paths(paths, _bounds(109, 112, 109, 112)), "edit two cells before the path touches the path")
	_check(not visual.last_terrain_edit_touches_paths(paths, _bounds(108, 112, 108, 112)), "edit three cells before the path stays clear of it")
	# A multi-cell edit counts from its bounding box, not only its nearest cell.
	_check(visual.last_terrain_edit_touches_paths(paths, _bounds(110, 112, 116, 112)), "wide edit overlapping the path touches the path")
	_check(not visual.last_terrain_edit_touches_paths(paths, _bounds(150, 150, 154, 154)), "edit far from every path cell stays clear")
	# Unknown edit extent stays conservative; no painted paths means nothing to
	# rebuild regardless.
	_check(visual.last_terrain_edit_touches_paths(paths, AABB()), "unknown edit extent stays conservative (touch)")
	_check(not visual.last_terrain_edit_touches_paths([], _bounds(112, 112, 112, 112)), "no painted paths means no touch even on the edit")

	# The same margin must drive the height-cache invalidation: a cell the
	# predicate says the edit reaches is exactly the cell whose cached height
	# is dropped, and nothing further.
	visual.set_preview_terrain_revision(1)
	visual._preview_surface_heights[Vector2i(112, 112)] = 5.0
	visual._preview_surface_heights[Vector2i(300, 300)] = 5.0
	visual.set_authoritative_terrain_change(2, _bounds(113, 112, 113, 112))
	_check(not visual._preview_surface_heights.has(Vector2i(112, 112)), "edit two cells away invalidates the neighbouring path cell height")
	_check(visual._preview_surface_heights.has(Vector2i(300, 300)), "heights far from the edit stay cached")
	_check(visual.last_terrain_edit_touches_paths(paths, _bounds(113, 112, 113, 112)), "invalidated cell and edit-reach agree for the same bounds")
	visual.set_authoritative_terrain_change(3, AABB())
	_check(visual._preview_surface_heights.is_empty(), "unknown edit extent clears the whole height cache")

	visual.queue_free()
	_print_result()

func _print_result() -> void:
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures}))
	quit(1 if failures else 0)
