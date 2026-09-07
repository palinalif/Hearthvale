extends SceneTree

const Placement = preload("res://scripts/wall_attachment_placement.gd")
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
	scene.checkpoint_root = "user://m1-placement-test-%s" % Time.get_ticks_usec()
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
	scene.selected_surface_id = "wall-back"
	scene._tool_choice("Add flower box")
	check(scene.detail_move_active and scene.placement_kind == "flower_box", "flower box enters placement mode")
	check(scene.building_world.get_document() == before, "ghost placement does not mutate recipe")
	check(scene.detail_move_surface_id == "wall-back", "explicit support selection is honored")
	check(scene.detail_move_position.z > 7.0, "back-wall ghost stays on back face")
	check(scene.placement_ghost != null and scene.placement_ghost.visible and scene.placement_ghost.get_child_count() > 0, "flower box ghost is visible")
	var ghost_piece: MeshInstance3D = scene.placement_ghost.get_child(0)
	var ghost_material := ghost_piece.material_override as StandardMaterial3D
	check(ghost_material != null and ghost_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and ghost_material.albedo_color.a < 1.0, "ghost is visibly translucent")
	var start := scene.detail_move_position
	await _axis(JOY_AXIS_LEFT_X, 1.0)
	check(scene.detail_move_position != start and scene.detail_move_position.z > 7.0, "left stick moves freely while remaining wall locked")
	var old_surface := scene.detail_move_surface_id
	await _press(JOY_BUTTON_DPAD_RIGHT)
	check(scene.detail_move_surface_id != old_surface, "dpad cycles wall during placement")
	var support := Placement.surface(scene.building_world.get_building(scene.selected_building_id), scene.detail_move_surface_id)
	var orientation := str(support.get("orientation", ""))
	var p: Vector3 = scene.detail_move_position
	check((orientation == "front" and p.z < -7.0) or (orientation == "back" and p.z > 7.0) or (orientation == "left" and p.x < -9.0) or (orientation == "right" and p.x > 9.0), "cycled ghost moves to correct wall side")
	await _press(JOY_BUTTON_B)
	check(not scene.detail_move_active and scene.placement_kind.is_empty(), "B cancels placement mode")
	check(scene.building_world.get_document() == before, "cancel leaves recipe unchanged")
	check(not scene.placement_ghost.visible, "cancel hides ghost")

	scene.selected_surface_id = "wall-back"
	scene._tool_choice("Add flower box")
	var placed_position := scene.detail_move_position
	await _press(JOY_BUTTON_A)
	check(not scene.detail_move_active and scene.placement_kind.is_empty(), "A commits placement")
	var after: Dictionary = scene.building_world.get_document()
	check(after != before, "commit mutates recipe once")
	var building: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var placed: Dictionary = {}
	for detail_value in building.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("id", "")) == scene.selected_detail_id: placed = detail; break
	check(not placed.is_empty() and str(placed.get("kind", "")) == "flower_box", "committed detail is flower box")
	check(str(placed.get("anchor", {}).get("surface_id", "")) == "wall-back", "committed flower box keeps chosen support")
	check(placed.get("resolved_position", null) is Vector3 and (placed["resolved_position"] as Vector3).is_equal_approx(placed_position), "commit matches ghost position")
	check((placed["resolved_position"] as Vector3).z > 7.0, "committed box remains on correct wall side")
	await _finish()

func _press(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new(); event.button_index = button; event.pressed = true
	Input.parse_input_event(event); Input.flush_buffered_events(); await process_frame
	var release := InputEventJoypadButton.new(); release.button_index = button; release.pressed = false
	Input.parse_input_event(release); Input.flush_buffered_events(); await process_frame

func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new(); event.axis = axis; event.axis_value = value
	Input.parse_input_event(event); Input.flush_buffered_events(); await process_frame
	var release := InputEventJoypadMotion.new(); release.axis = axis; release.axis_value = 0.0
	Input.parse_input_event(release); Input.flush_buffered_events(); await process_frame

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene.queue_free(); await process_frame; await process_frame
	print("m1_attachment_placement_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
