extends SceneTree

const Authority = preload("res://scripts/m2_painted_path_authority.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	var state := Authority.paint([], 1, "packed_earth", [[10, 10], [11, 10], [12, 10]])
	_check(bool(state.changed), "first paint changes authority")
	_check(int(state.path_id) == 1 and int(state.next_id) == 2, "first style receives one stable landscape ID")
	_check(Authority.validate(state.paths), "first painted region validates")
	_check(Authority.cells_for_style(state.paths, "packed_earth").size() == 3, "first paint owns requested cells")

	var merged := Authority.paint(state.paths, state.next_id, "packed_earth", [[12, 10], [13, 10], [14, 10]])
	_check(int(merged.path_id) == 1 and int(merged.next_id) == 2, "repainting same style keeps its stable ID")
	_check(Authority.cells_for_style(merged.paths, "packed_earth").size() == 5, "same-style strokes merge into one region")
	_check(merged.paths.size() == 1, "same style never creates stroke-fragment records")

	var replaced := Authority.paint(merged.paths, merged.next_id, "cobblestone", [[12, 10], [13, 10]])
	_check(int(replaced.path_id) == 2 and int(replaced.next_id) == 3, "new style receives one new stable ID")
	_check(Authority.cells_for_style(replaced.paths, "packed_earth") == [Vector2i(10, 10), Vector2i(11, 10), Vector2i(14, 10)], "latest material paint removes overlap from previous style")
	_check(Authority.cells_for_style(replaced.paths, "cobblestone") == [Vector2i(12, 10), Vector2i(13, 10)], "latest material owns overlapping cells")
	_check(Authority.validate(replaced.paths), "different materials remain non-overlapping and valid")

	var repainted := Authority.paint(replaced.paths, replaced.next_id, "packed_earth", [[12, 10]])
	_check(Authority.cells_for_style(repainted.paths, "packed_earth").has(Vector2i(12, 10)), "painting old style back reclaims the cell")
	_check(not Authority.cells_for_style(repainted.paths, "cobblestone").has(Vector2i(12, 10)), "reclaimed cell leaves previous material")
	_check(int(repainted.next_id) == 3, "existing styles do not burn IDs while repainting")

	var erased := Authority.erase(repainted.paths, [[10, 10], [12, 10], [13, 10], [14, 10]])
	_check(bool(erased.changed), "erase reports removed painted cells")
	_check(Authority.cells_for_style(erased.paths, "packed_earth") == [Vector2i(11, 10)], "erase removes covered cells across styles")
	_check(Authority.cells_for_style(erased.paths, "cobblestone").is_empty(), "empty style region is removed after erase")
	_check(Authority.validate(erased.paths), "post-erase authority validates")

	var unchanged := Authority.erase(erased.paths, [[99, 99]])
	_check(not bool(unchanged.changed), "erase outside painted area is a no-op")
	_check(JSON.stringify(unchanged.paths) == JSON.stringify(erased.paths), "no-op erase preserves deterministic document shape")

	var invalid_overlap := [
		{"id": 1, "style_id": "packed_earth", "cells": [[1, 1], [2, 1]]},
		{"id": 2, "style_id": "cobblestone", "cells": [[2, 1]]},
	]
	_check(not Authority.validate(invalid_overlap), "saved authority rejects overlapping material ownership")
	var duplicate_style := [
		{"id": 1, "style_id": "packed_earth", "cells": [[1, 1]]},
		{"id": 2, "style_id": "packed_earth", "cells": [[2, 1]]},
	]
	_check(not Authority.validate(duplicate_style), "saved authority rejects fragmented records for one style")
	_check(not Authority.validate([{"id": 1, "style_id": "packed_earth", "cells": [["oops", 1]]}]), "malformed string coordinates are rejected without a cast error")
	_check(not Authority.validate([{"id": 1, "style_id": "packed_earth", "cells": [[1.5, 1]]}]), "fractional saved coordinates are rejected")
	_check(not Authority.validate([{"id": 1, "style_id": "packed_earth", "cells": [[NAN, 1]]}]), "non-finite saved coordinates are rejected")

	var full: Array = []
	for z in 63:
		for x in 384:
			full.append([x, z])
			if full.size() == Authority.MAX_CELLS: break
		if full.size() == Authority.MAX_CELLS: break
	var at_budget := Authority.paint([], 41, "packed_earth", full)
	_check(bool(at_budget.changed) and int(at_budget.next_id) == 42 and Authority.total_cells(at_budget.paths) == Authority.MAX_CELLS, "exact cell budget is accepted")
	var over_budget := Authority.paint(at_budget.paths, at_budget.next_id, "cobblestone", [[383, 383]])
	_check(not bool(over_budget.changed) and int(over_budget.next_id) == 42 and int(over_budget.path_id) == -1, "over-budget new style restores the exact original next_id")
	_check(JSON.stringify(over_budget.paths) == JSON.stringify(at_budget.paths), "over-budget paint leaves authority byte-for-byte unchanged")

	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "paths": erased.paths.size(), "cells": Authority.total_cells(erased.paths)}))
	quit(1 if failures else 0)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)
