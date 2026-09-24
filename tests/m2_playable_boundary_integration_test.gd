extends SceneTree
## Controller focus cannot enter the waterfall or the surrounding mountains.
## Construct without entering the tree to avoid opening or changing saves.
const Boundary = preload("res://scripts/m2_playable_boundary.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node = load("res://scenes/m1.tscn").instantiate()
	scene._setup_input_map()
	scene.view_context = "terrain"
	scene.cursor = Vector3(82, 8, 140)
	scene.terrain_cursor = scene.cursor
	scene._read_camera_and_cursor(0.0)
	_check(Boundary.is_inside(scene.cursor), "terrain cursor cannot reach waterfall")
	_check((scene.terrain_cursor as Vector3).is_equal_approx(scene.cursor), "terrain focus follows bounded cursor")
	_check(is_equal_approx((scene.cursor as Vector3).y, 8.0), "terrain height is preserved")
	for point: Vector3 in [Vector3(0, 8, 80), Vector3(160, 8, 80), Vector3(80, 8, 0), Vector3(80, 8, 160)]:
		scene.cursor = point
		scene._read_camera_and_cursor(0.0)
		_check(Boundary.is_inside(scene.cursor), "mountain-side terrain focus is bounded")
	scene.cursor = Vector3(80, 8, 131.9)
	scene.terrain_cursor = scene.cursor
	Input.action_press("m1_move_down")
	scene._read_camera_and_cursor(1.0)
	Input.action_release("m1_move_down")
	_check(Boundary.is_inside(scene.cursor), "held controller movement stops before the waterfall")
	scene.building_placement_target = Vector3(80, 8, 140)
	# Parent placement preview requires a live building world; its clamp seam
	# runs before sampling ground/preview, and can be checked independently.
	scene._clamp_building_placement()
	_check(Boundary.is_inside(scene.building_placement_target), "building placement target is bounded before preview")
	scene.view_context = "building"
	scene.cursor = Vector3(16, 8, 80)
	scene._read_camera_and_cursor(0.0)
	_check((scene.cursor as Vector3).is_equal_approx(Vector3(16, 8, 80)), "existing building edit focus is not relocated")
	scene.free()
	print(JSON.stringify({"ok": failures == 0, "failures": failures, "checks": checks, "playable_boundary_integration": true}))
	quit(1 if failures else 0)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	print("FAIL: " + label)
