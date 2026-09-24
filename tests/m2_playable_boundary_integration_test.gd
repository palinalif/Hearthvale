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
	# A broad sculpt brush is rejected before the backend opens a transaction.
	scene.brush_radius = 4.0
	scene._terrain_target_valid = true
	scene._terrain_target_point = Vector3(80, 8, 130)
	scene._begin_stroke()
	_check(not scene.stroke_active, "sculpt footprint beyond rim cannot start")
	scene.stroke_active = true
	scene.stroke_aim_offset = Vector3.ZERO
	scene.cursor = Vector3(80, 8, 131)
	scene._read_camera_and_cursor(0.0)
	_check(Boundary.is_circle_footprint_inside(scene.cursor + scene.stroke_aim_offset, scene.brush_radius), "held sculpt brush slides at inner rim")
	scene.stroke_active = false
	scene._paint_plant_sample()
	_check(scene.landscape_state.records.is_empty(), "planting footprint beyond rim cannot change landscape")
	# Validate actual placement through the inherited validity chain, without
	# entering the tree or creating a gameplay save.
	scene.building_world = scene._create_building_world()
	scene.building_placement_active = true
	scene.building_placement_operation = "new"
	scene.building_placement_design_id = "riverside_cottage"
	scene.building_placement_revision = scene.building_world.get_revision()
	var scale: float = preload("res://scripts/building_world.gd").MINIATURE_SCALE
	for x: float in [80.0, 130.0]:
		scene.building_placement_target = Vector3(x, 8, 80)
		scene.building_placement_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale), scene.building_placement_target)
		scene._update_building_placement_validity()
		_check(scene.building_placement_valid == (x == 80.0), "home footprint validity matches valley rim at x=%.0f" % x)
	scene.building_placement_active = false
	scene.path_placement_active = true
	scene.path_width = 4.0
	scene._path_terrain_revision = scene._terrain_revision()
	scene._path_building_revision = scene.building_world.get_revision()
	scene._path_before_serialized = JSON.stringify(scene.landscape_state.document())
	scene._terrain_target_point = Vector3(80, 8, 80)
	scene._update_path_validity()
	_check(scene.path_placement_valid, "path brush remains available inside the valley")
	scene.path_painting = true
	scene._path_last_sample = Vector2(80, 80)
	scene._terrain_target_point = Vector3(80, 8, 131)
	_check(not scene._sample_path_stroke() and scene.path_cells.is_empty(), "held path brush cannot sweep outside the rim")
	scene.path_placement_active = false
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
