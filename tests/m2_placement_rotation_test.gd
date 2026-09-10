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
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-placement-rotation-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "native scene ready")
	if not scene._player_restored: await _finish(); return
	scene.set_process(false)
	scene._set_view_context("building")

	var source_id: String = scene.selected_building_id
	var source: Dictionary = scene.building_world.get_building(source_id)
	var before: String = scene.building_world.serialize_document()
	scene._begin_building_placement()
	check(scene.building_placement_active and scene.building_placement_operation == "duplicate", "place-home preview starts without authority mutation")
	check(scene.building_placement_valid and scene.building_placement_reason == "Valid placement", "default preview starts valid")
	var coarse_before: Basis = scene.building_placement_transform.basis
	await _press(JOY_BUTTON_DPAD_RIGHT)
	check(not scene.building_placement_transform.basis.is_equal_approx(coarse_before), "D-pad rotates the complete preview")
	check(scene.building_placement_ghost.transform.is_equal_approx(scene.building_placement_transform), "ghost transform agrees with candidate transform")
	var coarse_yaw: float = scene.building_placement_transform.basis.get_euler().y
	await _press(JOY_BUTTON_LEFT_STICK)
	await _press(JOY_BUTTON_DPAD_RIGHT)
	var fine_delta := absf(scene.building_placement_transform.basis.get_euler().y - coarse_yaw)
	check(is_equal_approx(fine_delta, deg_to_rad(1.0)), "precision rotation uses a one-degree step")
	await _press(JOY_BUTTON_DPAD_UP)
	check(not scene.building_rotation_snap, "rotation snapping can be disabled")

	scene.building_placement_target = (source["transform"] as Transform3D).origin
	scene._update_building_preview_transform()
	check(not scene.building_placement_valid and scene.building_placement_reason.begins_with("Overlaps"), "hard overlap names its reason")
	check(not scene._commit_building_placement() and scene.building_placement_active, "overlap cannot commit")
	check(scene.building_world.serialize_document() == before, "invalid confirmation does not mutate authority")
	scene.building_placement_target.x = 0.0
	scene._update_building_preview_transform()
	check(not scene.building_placement_valid and scene.building_placement_reason == "Outside editable world", "world bounds name their reason")

	scene.building_placement_target = (source["transform"] as Transform3D).origin + Vector3(8, 0, 8)
	scene._update_building_preview_transform()
	check(scene.building_placement_valid, "clear rotated candidate becomes valid")
	var placed_transform: Transform3D = scene.building_placement_transform
	check(scene._commit_building_placement(), "valid rotated home commits")
	var duplicate_id: String = scene.selected_building_id
	var duplicate: Dictionary = scene.building_world.get_building(duplicate_id)
	check(duplicate_id != source_id and (duplicate["transform"] as Transform3D).is_equal_approx(placed_transform), "duplicate receives a fresh identity and exact preview transform")
	check(str(duplicate["details"][0]["id"]) != str(source["details"][0]["id"]), "duplicate deep-copies attachment identities")
	check(scene.building_world.undo() and scene.building_world.get_buildings().size() == 1, "duplicate is one undo transaction")
	check(scene.building_world.redo() and scene.building_world.get_buildings().size() == 2, "duplicate redo restores the rotated home")

	scene.selected_building_id = source_id
	source = scene.building_world.get_building(source_id)
	var source_details: Array = source["details"].duplicate(true)
	scene._begin_house_move()
	check(scene.building_placement_operation == "move" and scene.building_placement_valid, "existing home enters valid move/rotate preview")
	await _press(JOY_BUTTON_DPAD_LEFT)
	var moved_transform: Transform3D = scene.building_placement_transform
	check(scene._commit_building_placement(), "rotation-only existing-home edit commits")
	var moved: Dictionary = scene.building_world.get_building(source_id)
	check((moved["transform"] as Transform3D).is_equal_approx(moved_transform), "existing home matches rotation preview")
	check(moved["details"] == source_details, "existing-home rotation retains attachment records")
	var serialized: String = scene.building_world.serialize_document()
	var restored = preload("res://scripts/cottage_resize_world.gd").new()
	check(restored.load_serialized_document(serialized), "rotated homes reload from the saved document")
	check((restored.get_building(source_id)["transform"] as Transform3D).is_equal_approx(moved_transform), "saved yaw survives reload")

	var stable_before: String = scene.building_world.serialize_document()
	scene._begin_house_move()
	scene.building_world.set_material(source_id, "rose_lime")
	scene._update_building_placement_validity()
	check(not scene.building_placement_valid and scene.building_placement_reason.begins_with("Home changed"), "stale preview explains why confirmation is blocked")
	check(not scene._commit_building_placement(), "stale transform cannot overwrite the newer recipe")
	check(scene.building_world.serialize_document() != stable_before and scene.building_world.get_building(source_id)["material_id"] == "rose_lime", "stale rejection preserves the newer edit")
	scene._cancel_building_placement()

	await _finish()

func _press(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	var release := InputEventJoypadButton.new()
	release.button_index = button
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await process_frame

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m2_placement_rotation_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
