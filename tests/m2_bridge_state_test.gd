extends SceneTree

const State = preload("res://scripts/landscape_state.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	var legacy := {"version": 1, "next_id": 2, "records": [{"id": 1, "kind": "foliage", "position": [8.0, 8.0, 8.0], "seed": 4}], "paths": []}
	_check(State.validate(legacy), "legacy landscape without bridges remains valid")
	var state := State.new()
	_check(state.restore(legacy) and state.bridges.is_empty(), "legacy landscape restores with empty bridge collection")
	var bridge_id := state.add_bridge("timber", 1.0, [Vector2(10.01, 10.01), [14.0, 10.0]])
	_check(bridge_id == 2, "bridge consumes the next shared stable landscape ID")
	var document := state.document()
	_check(State.validate(document) and document.bridges.size() == 1, "valid bridge document validates")
	_check(document.bridges[0].points == [[10.0, 10.0], [14.0, 10.0]], "bridge endpoints snap to the structural grid")
	var restored := State.new()
	_check(restored.restore(document) and JSON.stringify(restored.document()) == JSON.stringify(document), "bridge document round-trips deterministically")
	_check(int(restored.bridges[0].id) == 2 and restored.next_id == 3, "bridge reload preserves identity and next ID")

	var bad_style := document.duplicate(true)
	bad_style.bridges[0].style_id = "steel"
	_check(not State.validate(bad_style), "unsupported bridge style is rejected")
	var short_span := document.duplicate(true)
	short_span.bridges[0].points[1] = [10.5, 10.0]
	_check(not State.validate(short_span), "bridge span below minimum is rejected")
	var long_span := document.duplicate(true)
	long_span.bridges[0].points[1] = [22.0, 10.0]
	_check(not State.validate(long_span), "bridge span above maximum is rejected")
	var off_grid := document.duplicate(true)
	off_grid.bridges[0].points[1] = [14.01, 10.0]
	_check(not State.validate(off_grid), "off-grid bridge endpoint is rejected")
	var duplicate_id := document.duplicate(true)
	duplicate_id.bridges[0].id = 1
	_check(not State.validate(duplicate_id), "bridge IDs share the landscape duplicate guard")
	var bad_width := document.duplicate(true)
	bad_width.bridges[0].width = 2.5
	_check(not State.validate(bad_width), "bridge width outside bounded range is rejected")
	var too_many := {"version": 1, "next_id": 18, "records": [], "paths": [], "bridges": []}
	for index in 17:
		too_many.bridges.append({"id": index + 1, "style_id": "timber", "width": 1.0, "points": [[2.0, float(index) * 2.0], [4.0, float(index) * 2.0]]})
	_check(not State.validate(too_many), "bridge count limit is enforced")
	_check(state.erase_bridge(bridge_id) and state.bridges.is_empty(), "bridge can be erased by stable ID")
	_print_result()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _print_result() -> void:
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures}))
	quit(1 if failures else 0)
