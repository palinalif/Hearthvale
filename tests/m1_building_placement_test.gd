extends SceneTree

var failures := 0
var checks := 0
var scene: Node

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.checkpoint_root = "user://m1-building-placement-test-%s" % Time.get_ticks_usec()
	scene.test_mode = true
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 30000
	while (scene.backend == null or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline: await process_frame
	check(scene.backend != null and scene.backend.is_ready(), "native backend ready")
	if scene.backend == null or not scene.backend.is_ready(): await _finish(); return
	await process_frame
	await _press(JOY_BUTTON_BACK)
	check(scene.view_context == "building", "building context selected")
	var before: Dictionary = scene.building_world.get_document()
	var source: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var source_transform: Transform3D = source["transform"]
	scene._tool_choice("Duplicate cottage")
	check(scene.building_placement_active, "duplicate enters building placement mode")
	check(scene.building_world.get_document() == before, "ghost duplicate does not mutate recipe")
	check(scene.building_placement_ghost != null and scene.building_placement_ghost.visible, "cottage ghost is visible")
	var initial_target: Vector3 = scene.building_placement_target
	await _hold_axis(JOY_AXIS_LEFT_X, 1.0, 20)
	check(scene.building_placement_target != initial_target, "left stick moves duplicate freely")
	check(scene.building_world.get_document() == before, "moving ghost remains read-only")
	await _press(JOY_BUTTON_B)
	check(not scene.building_placement_active, "B cancels duplicate placement")
	check(scene.building_world.get_document() == before, "cancel leaves building document unchanged")

	scene._tool_choice("Duplicate cottage")
	await _hold_axis(JOY_AXIS_LEFT_X, -1.0, 20)
	var target: Vector3 = scene.building_placement_target
	await _press(JOY_BUTTON_A)
	check(not scene.building_placement_active, "A commits duplicate placement")
	var after: Dictionary = scene.building_world.get_document()
	check(after != before, "commit mutates recipe once")
	var buildings: Array[Dictionary] = scene.building_world.get_buildings()
	check(buildings.size() == 2, "commit creates exactly one cottage")
	check(scene.selected_building_id != "building-1", "new cottage becomes selected")
	var placed: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var placed_transform: Transform3D = placed["transform"]
	check(placed_transform.origin.is_equal_approx(target), "committed cottage matches ghost position")
	check(placed_transform.basis.is_equal_approx(source_transform.basis), "duplicate preserves miniature scale and rotation")
	check(absf(placed_transform.origin.y - target.y) < 0.001, "duplicate keeps terrain-grounded height")
	await _finish()

func _press(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new(); event.button_index = button; event.pressed = true
	Input.parse_input_event(event); Input.flush_buffered_events(); await process_frame
	var release := InputEventJoypadButton.new(); release.button_index = button; release.pressed = false
	Input.parse_input_event(release); Input.flush_buffered_events(); await process_frame

func _hold_axis(axis: JoyAxis, value: float, frames: int) -> void:
	var event := InputEventJoypadMotion.new(); event.axis = axis; event.axis_value = value
	Input.parse_input_event(event); Input.flush_buffered_events()
	for _i in frames: await process_frame
	var release := InputEventJoypadMotion.new(); release.axis = axis; release.axis_value = 0.0
	Input.parse_input_event(release); Input.flush_buffered_events(); await process_frame

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene.queue_free(); await process_frame; await process_frame
	print("m1_building_placement_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
