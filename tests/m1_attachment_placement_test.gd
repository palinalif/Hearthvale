extends SceneTree

const Placement = preload("res://scripts/wall_attachment_placement.gd")
const World = preload("res://scripts/building_world.gd")
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
	# The revised default is the wall visible to the camera, not a stale support.
	# Keep all back-face, cancel, commit and explicit wall-switch assertions.
	scene.camera_yaw = 0.0
	scene.camera_pitch = 0.35
	scene._update_camera()
	var before: Dictionary = scene.building_world.get_document()
	scene.selected_surface_id = "wall-back"
	scene._tool_choice("Add flower box")
	check(scene.detail_move_active and scene.placement_kind == "flower_box", "flower box enters placement mode")
	check(scene.building_world.get_document() == before, "ghost placement does not mutate recipe")
	check(scene.detail_move_surface_id == "wall-back", "camera-facing back wall selected")
	check(scene.detail_move_position.z > 7.0, "back-wall ghost stays on back face")
	check(scene.placement_ghost != null and scene.placement_ghost.visible and scene.placement_ghost.get_child_count() > 0, "flower box ghost is visible")
	var ghost_piece: MeshInstance3D = scene.placement_ghost.get_child(0)
	var ghost_material := ghost_piece.material_override as StandardMaterial3D
	check(ghost_material != null and ghost_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and ghost_material.albedo_color.a < 1.0, "ghost is visibly translucent")
	var start: Vector3 = scene.detail_move_position
	await _axis(JOY_AXIS_LEFT_X, 1.0)
	check(scene.detail_move_position != start and scene.detail_move_position.z > 7.0, "held left stick escapes soft snap while remaining wall locked")
	var old_surface: String = scene.detail_move_surface_id
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
	var placed_position: Vector3 = scene.detail_move_position
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

	# Structural attachments use the same preview-only wall placement, then
	# become independent manual recipe records with real shell openings.
	scene.selected_detail_id = ""
	scene.selected_surface_id = ""
	var structural_before: Dictionary = scene.building_world.get_document()
	scene._begin_new_attachment("window")
	check(scene.detail_move_active and scene.placement_kind == "window" and scene.placement_asset_id == "window_wood", "Add window enters wall-locked placement with the home default family")
	check(scene.building_world.get_document() == structural_before, "window ghost does not mutate authority")
	await _press(JOY_BUTTON_A)
	var manual_window_id: String = scene.selected_detail_id
	var manual_window: Dictionary = scene._selected_detail_record()
	check(not manual_window_id.is_empty() and manual_window["kind"] == "window" and manual_window["state"] == "manual", "placed window persists as an independent manual opening")

	scene._begin_new_attachment("door")
	check(scene.detail_move_active and scene.placement_kind == "door" and scene.placement_asset_id == "door_timber", "Add door enters wall-locked placement with the home default family")
	var door_support := Placement.surface(scene.building_world.get_building(scene.selected_building_id), scene.detail_move_surface_id)
	var door_orientation := str(door_support.get("orientation", "front"))
	var door_candidate: Vector3 = scene.detail_move_position
	if door_orientation in ["front", "back"]: door_candidate.x += 4.5
	else: door_candidate.z += 4.5
	var door_clamped := Placement.clamp_to_wall(scene.building_world.get_building(scene.selected_building_id), scene.detail_move_surface_id, door_candidate, Placement.footprint("door", "door_timber"))
	check(not door_clamped.is_empty(), "additional door has a valid clear wall candidate")
	if not door_clamped.is_empty():
		scene.detail_move_position = door_clamped["position"]
		scene._detail_free_position = scene.detail_move_position
	await _press(JOY_BUTTON_A)
	var manual_door: Dictionary = scene._selected_detail_record()
	check(not manual_door.is_empty() and manual_door["kind"] == "door" and manual_door["state"] == "manual", "placed door persists as an independent manual opening")
	check(scene.building_world.get_document() != structural_before, "structural placements commit authoritative recipe changes")
	var manual_door_id := str(manual_door.get("id", ""))
	check(scene.building_world.undo() and scene.building_world.get_building(scene.selected_building_id)["details"].all(func(detail): return str(detail["id"]) != manual_door_id), "one undo removes only the newly placed door")
	check(scene.building_world.redo() and scene.building_world.get_building(scene.selected_building_id)["details"].any(func(detail): return str(detail["id"]) == manual_door_id), "redo restores the placed door")
	var restored := World.new()
	check(restored.load_serialized_document(scene.building_world.serialize_document()), "world with extra structural openings reloads")
	var restored_details: Array = restored.get_building(scene.selected_building_id)["details"]
	check(restored_details.any(func(detail): return str(detail["id"]) == manual_window_id) and restored_details.any(func(detail): return str(detail["id"]) == manual_door_id), "added window and door identities survive reload")
	await _finish()

func _press(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new(); event.button_index = button; event.pressed = true
	Input.parse_input_event(event); Input.flush_buffered_events(); await process_frame
	var release := InputEventJoypadButton.new(); release.button_index = button; release.pressed = false
	Input.parse_input_event(release); Input.flush_buffered_events(); await process_frame

func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new(); event.axis = axis; event.axis_value = value
	Input.parse_input_event(event); Input.flush_buffered_events()
	var until := Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < until: await process_frame
	var release := InputEventJoypadMotion.new(); release.axis = axis; release.axis_value = 0.0
	Input.parse_input_event(release); Input.flush_buffered_events(); await process_frame

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene.queue_free(); await process_frame; await process_frame
	print("m1_attachment_placement_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
