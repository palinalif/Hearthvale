extends SceneTree

const State = preload("res://scripts/landscape_state.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	var legacy := {"version": 1, "next_id": 2, "records": [{"id": 1, "kind": "foliage", "position": [8.0, 8.0, 8.0], "seed": 4}], "paths": [], "bridges": []}
	_check(State.validate(legacy), "legacy landscape without hamlet details remains valid")
	var state := State.new()
	_check(state.restore(legacy) and state.composition.is_empty(), "legacy landscape restores with empty composition collection")
	var garden_id := state.add_composition("garden", "cottage_flowers", Vector2(12.01, 12.01), Vector2(3.0, 2.0), 1)
	_check(garden_id == 2, "garden consumes the next shared stable landscape ID")
	var fence_id := state.add_composition("fence", "rustic_fence", Vector2(18.0, 12.0), Vector2(3.0, 0.25), 0)
	_check(fence_id == 3, "fence shares the landscape identity sequence")
	var furniture_id := state.add_composition("furniture", "bench", Vector2(22.0, 12.0), Vector2(1.5, 0.625), 2)
	_check(furniture_id == 4, "street furniture shares the landscape identity sequence")
	var document: Dictionary = state.document()
	_check(State.validate(document) and document.composition.size() == 3, "valid hamlet detail document validates")
	_check(document.composition[0].position == [12.0, 12.0] and document.composition[0].yaw_quarters == 1, "detail position snaps and rotation is saved")
	var restored := State.new()
	_check(restored.restore(document) and JSON.stringify(restored.document()) == JSON.stringify(document), "hamlet detail document round-trips deterministically")

	var bad_kind := document.duplicate(true)
	bad_kind.composition[0].kind = "statue"
	_check(not State.validate(bad_kind), "unsupported detail kind is rejected")
	var bad_style := document.duplicate(true)
	bad_style.composition[0].style_id = "formal_roses"
	_check(not State.validate(bad_style), "unsupported style for a detail kind is rejected")
	var bad_yaw := document.duplicate(true)
	bad_yaw.composition[0].yaw_quarters = 4
	_check(not State.validate(bad_yaw), "rotation outside four quarter turns is rejected")
	var off_grid := document.duplicate(true)
	off_grid.composition[0].position = [12.01, 12.0]
	_check(not State.validate(off_grid), "off-grid detail position is rejected")
	var outside := document.duplicate(true)
	outside.composition[0].position = [0.5, 12.0]
	outside.composition[0].size = [3.0, 2.0]
	_check(not State.validate(outside), "detail footprint outside editable world is rejected")
	var too_large := document.duplicate(true)
	too_large.composition[0].size = [6.125, 2.0]
	_check(not State.validate(too_large), "oversized detail footprint is rejected")
	var duplicate_id := document.duplicate(true)
	duplicate_id.composition[0].id = 1
	_check(not State.validate(duplicate_id), "hamlet detail IDs share the global landscape duplicate guard")
	_check(state.erase_composition(furniture_id) and state.composition.size() == 2, "hamlet detail erases by stable ID")
	_print_result()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _print_result() -> void:
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures}))
	quit(1 if failures else 0)
