extends SceneTree

const SceneScript = preload("res://scripts/m1_scene.gd")
const State = preload("res://scripts/landscape_state.gd")
const GardenVisual = preload("res://scripts/m1_garden_visual.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	var scene = SceneScript.new()
	scene.sculpt_tool = "tree"
	scene.precision_mode = false
	scene.planting_yaw_degrees = 0.0
	scene._rotate_plant_brush(1)
	_check(is_equal_approx(scene.planting_yaw_degrees, 15.0), "tree brush can still nudge randomized facing in 15-degree steps")
	scene.precision_mode = true
	scene._rotate_plant_brush(1)
	_check(is_equal_approx(scene.planting_yaw_degrees, 16.0), "tree brush precision rotation uses one-degree steps")
	scene.sculpt_tool = "foliage"
	scene.precision_mode = false
	scene._rotate_plant_brush(-1)
	_check(is_equal_approx(scene.planting_yaw_degrees, 1.0), "foliage brush uses the same optional rotation nudge")

	var state = State.new()
	_check(state.add("tree", Vector3(12.0, 8.0, 12.0), 1, 16.0), "tree records accept brush yaw")
	_check(state.add("foliage", Vector3(16.0, 8.0, 12.0), 2, 15.0), "foliage records accept brush yaw")
	var tree_record: Dictionary = state.records[0]
	var foliage_record: Dictionary = state.records[1]
	_check(_has_fine_random_facing(tree_record, 16.0), "tree placement combines random 15-degree sub-turn with manual offset")
	_check(_has_fine_random_facing(foliage_record, 15.0), "foliage placement combines random 15-degree sub-turn with manual offset")
	var saved := state.document()
	var restored = State.new()
	_check(State.validate(saved) and restored.restore(saved) and restored.document() == saved, "planting yaw survives validation and restore")

	scene.free()
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures}))
	quit(1 if failures else 0)

func _has_fine_random_facing(record: Dictionary, manual_yaw: float) -> bool:
	var yaw := fposmod(rad_to_deg(GardenVisual.planting_rotation(record).get_euler().y), 360.0)
	var random_component := fposmod(yaw - manual_yaw, 360.0)
	return is_equal_approx(random_component, snappedf(random_component, 15.0))

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)
