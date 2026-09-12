extends SceneTree

const State = preload("res://scripts/landscape_state.gd")
const Region = preload("res://scripts/m2_painted_path_region.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	var base_document := {"version": 1, "next_id": 2, "records": [{"id": 1, "kind": "foliage", "position": [8.0, 8.0, 8.0], "seed": 4}]}
	var state := State.new()
	_check(State.validate(base_document), "version-1 landscape without paths remains valid")
	_check(state.restore(base_document) and state.paths.is_empty(), "landscape restores with an empty painted path collection")
	var planting_before: Array = state.records.duplicate(true)
	var dirt := Region.brush_cells(Vector2(10.0, 10.0), 0.5)
	var path_id := state.paint_path_cells("packed_earth", dirt)
	_check(path_id == 2, "first painted material consumes the next shared stable landscape ID")
	_check(state.records == planting_before, "painting path authority does not implicitly alter planting records")
	var document := state.document()
	_check(State.validate(document) and document.paths.size() == 1, "painted-cell path document validates")
	_check(document.paths[0].has("cells") and not document.paths[0].has("points") and not document.paths[0].has("width"), "saved path authority contains style plus cells only")
	_check(document.paths[0].cells == Region.encode_cells(dirt), "authoritative cells are sorted and deterministic")
	var restored := State.new()
	_check(restored.restore(document) and JSON.stringify(restored.document()) == JSON.stringify(document), "painted path document round-trips deterministically")
	_check(restored.next_id == 3 and int(restored.paths[0].id) == 2, "path reload preserves next ID and stable material-region ID")

	var more_dirt := Region.brush_cells(Vector2(10.75, 10.0), 0.5)
	var same_id := restored.paint_path_cells("packed_earth", more_dirt)
	_check(same_id == 2 and restored.paths.size() == 1, "repainting the same style merges into its existing region")
	var stone := Region.brush_cells(Vector2(10.0, 10.0), 0.25)
	var stone_id := restored.paint_path_cells("cobblestone", stone)
	_check(stone_id == 3 and restored.paths.size() == 2, "a second material gets one new stable region ID")
	var dirt_lookup := {}
	for cell: Vector2i in restored.path_cells("packed_earth"): dirt_lookup[cell] = true
	var ownership_clean := true
	for cell: Vector2i in restored.path_cells("cobblestone"):
		ownership_clean = ownership_clean and not dirt_lookup.has(cell)
	_check(ownership_clean, "latest paint owns overlapping cells exclusively")
	_check(restored.erase_path_cells(stone), "cell erase removes painted ownership")
	_check(restored.path_cells("cobblestone").is_empty(), "empty material region is removed after erase")

	var invalid_style := _valid_document()
	invalid_style.paths[0].style_id = "gravel"
	_check(not State.validate(invalid_style), "invalid path style is rejected")
	var old_ribbon := {"version": 1, "next_id": 2, "records": [], "paths": [{"id": 1, "style_id": "packed_earth", "width": 0.75, "points": [[10.0, 10.0], [14.0, 10.0]]}]}
	_check(not State.validate(old_ribbon), "old polyline path schema is rejected rather than migrated")
	var duplicate_cell := _valid_document()
	duplicate_cell.paths.append({"id": 2, "style_id": "packed_earth", "cells": [[80, 80]]})
	duplicate_cell.next_id = 3
	_check(not State.validate(duplicate_cell), "one saved region per material is enforced")
	var overlapping := _valid_document()
	overlapping.paths.append({"id": 2, "style_id": "packed_earth", "cells": [[80, 80], [81, 80]]})
	overlapping.next_id = 3
	_check(not State.validate(overlapping), "two materials cannot own the same structural cell")
	var malformed := _valid_document()
	malformed.paths[0].cells = [[80, 80], [79, 80]]
	_check(not State.validate(malformed), "authoritative cell arrays must use canonical sorted order")
	var duplicate_ids := _valid_document()
	duplicate_ids.records = [{"id": 1, "kind": "rock", "position": [4.0, 8.0, 4.0], "seed": 1}]
	duplicate_ids.paths[0].id = 1
	_check(not State.validate(duplicate_ids), "path and planting IDs share a duplicate guard")
	_check(State.validate(document), "planting and painted path records remain jointly valid")
	_print_result()

func _valid_document() -> Dictionary:
	return {"version": 1, "next_id": 2, "records": [], "paths": [{"id": 1, "style_id": "cobblestone", "cells": [[80, 80], [81, 80]]}]}

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _print_result() -> void:
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures}))
	quit(1 if failures else 0)
