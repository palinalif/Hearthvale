extends SceneTree

## Regression test for the lake outline point-placing logic. The first A press used to
## early-return (the "too close to previous" guard fired while the list was still empty),
## so a lake outline could never begin. _lake_outline_action is a pure static and is the
## single source of that decision, so it is called directly on the script here.
const WaterScene = preload("res://scripts/m2_scene_water.gd")

var failures := 0
var checks := 0

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)

func _action(points: Array, point: Vector2) -> String:
	return WaterScene._lake_outline_action(points, point)

func _initialize() -> void:
	var tri := [Vector2(0.0, 0.0), Vector2(2.0, 0.0), Vector2(2.0, 2.0)]
	var pair := [Vector2(0.0, 0.0), Vector2(2.0, 0.0)]

	# THE FIX: the first point must be recorded (an empty list is never "too close").
	_check(_action([], Vector2(1.0, 1.0)) == "add", "first point is added (empty list)")
	_check(_action([Vector2(1.0, 1.0)], Vector2(3.0, 1.0)) == "add", "second far point is added")
	_check(_action([Vector2(1.0, 1.0)], Vector2(1.05, 1.0)) == "ignore", "near-duplicate point is ignored")
	_check(_action(tri, Vector2(0.1, 0.0)) == "close", "near the start with 3+ points closes")
	_check(_action(tri, Vector2(0.0, 3.0)) == "add", "fresh far point extends the outline")
	_check(_action(pair, Vector2(0.1, 0.0)) == "add", "near start with <3 points does not close")

	print("water_lake_outline_test checks=%d failures=%d ok=%s" % [checks, failures, failures == 0])
	quit(1 if failures else 0)
