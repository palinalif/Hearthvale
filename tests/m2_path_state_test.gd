extends SceneTree

const State = preload("res://scripts/landscape_state.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	var old_document := {"version": 1, "next_id": 2, "records": [{"id": 1, "kind": "foliage", "position": [8.0, 8.0, 8.0], "seed": 4}]}
	var old_state := State.new()
	_check(State.validate(old_document), "version-1 landscape without paths remains valid")
	_check(old_state.restore(old_document) and old_state.paths.is_empty(), "old landscape restores with an empty path collection")
	var planting_before: Array = old_state.records.duplicate(true)
	var path_id := old_state.add_path("packed_earth", 0.75, [[10.01, 10.01], Vector2(14.0, 10.0)])
	_check(path_id == 2, "path consumes the next shared stable landscape ID")
	_check(old_state.records == planting_before, "adding a path does not alter existing planting records")
	var document: Dictionary = old_state.document()
	_check(State.validate(document) and document.paths.size() == 1, "valid path document validates")
	_check(document.paths[0].points == [[10.0, 10.0], [14.0, 10.0]], "authoritative X/Z coordinates snap to the 0.125 grid")
	var restored := State.new()
	_check(restored.restore(document) and JSON.stringify(restored.document()) == JSON.stringify(document), "path document round-trips deterministically")
	_check(restored.next_id == 3 and int(restored.paths[0].id) == 2, "path reload preserves next ID and path ID")

	var invalid_style := _valid_document()
	invalid_style.paths[0].style_id = "gravel"
	_check(not State.validate(invalid_style), "invalid path style is rejected")
	var invalid_coordinate := _valid_document()
	invalid_coordinate.paths[0].points[1] = [48.125, 12.0]
	_check(not State.validate(invalid_coordinate), "out-of-bounds path coordinate is rejected")
	var off_grid := _valid_document()
	off_grid.paths[0].points[1] = [12.01, 12.0]
	_check(not State.validate(off_grid), "off-grid authoritative path coordinate is rejected")
	var invalid_width := _valid_document()
	invalid_width.paths[0].width = 0.125
	_check(not State.validate(invalid_width), "width below the bounded minimum is rejected")
	var duplicate_ids := _valid_document()
	duplicate_ids.records = [{"id": 1, "kind": "rock", "position": [4.0, 8.0, 4.0], "seed": 1}]
	duplicate_ids.paths[0].id = 1
	_check(not State.validate(duplicate_ids), "path and planting IDs share a duplicate guard")
	var too_few := _valid_document()
	too_few.paths[0].points = [[10.0, 10.0]]
	_check(not State.validate(too_few), "path with fewer than two points is rejected")
	var too_many := _valid_document()
	too_many.paths[0].points = []
	for index in 65: too_many.paths[0].points.append([float(index) * 0.5, 10.0])
	_check(not State.validate(too_many), "path with more than 64 points is rejected")
	var too_many_paths := _valid_document()
	too_many_paths.paths = []
	for index in 33: too_many_paths.paths.append({"id": index + 1, "style_id": "packed_earth", "width": 0.75, "points": [[1.0, 1.0], [1.125, 1.0]]})
	too_many_paths.next_id = 35
	_check(not State.validate(too_many_paths), "more than 32 paths is rejected")
	var render_limited := {"version": 1, "next_id": 8, "records": [], "paths": []}
	for index in 7:
		render_limited.paths.append({"id": index + 1, "style_id": "cobblestone", "width": 3.0, "points": [[0.0, float(index)], [48.0, float(index)]]})
	_check(not State.validate(render_limited), "global rendered-cell limit is enforced")
	_check(State.validate(document), "planting and path records remain jointly valid after all checks")
	_print_result()

func _valid_document() -> Dictionary:
	return {"version": 1, "next_id": 2, "records": [], "paths": [{"id": 1, "style_id": "cobblestone", "width": 1.5, "points": [[10.0, 10.0], [14.0, 10.0]]}]}

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _print_result() -> void:
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures}))
	quit(1 if failures else 0)
