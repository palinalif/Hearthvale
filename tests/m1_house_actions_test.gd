extends "res://tests/m1_resize_handles_test.gd"
## Real controller input through the exported scene, including the new
## surface -> House route to the preserved whole-house operations.

func aim_shell() -> bool:
	var view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var t: Transform3D = view["transform"]
	var d: Vector3 = view["dimensions"]
	scene.camera_yaw = PI
	scene.camera_pitch = 0.2
	scene.camera_distance = 10.0
	scene._update_camera()
	for x in [0.0, -0.35, 0.35]:
		for y in [0.90, 0.70, 0.15]:
			scene.edit_pointer = scene.camera.unproject_position(t * Vector3(d.x * x, d.y * y, -d.z * 0.5))
			scene._update_detail_hover()
			if scene.hovered_detail_id.is_empty() and scene._pointer_over_selected_shell():
				scene._refresh_controller_hud()
				return true
	return false


func choose_whole_house() -> void:
	check(scene._part_menu_open, "bare surface opens contextual actions first")
	for step in scene._part_buttons.size():
		var focus := root.gui_get_focus_owner() as Button
		if focus and str(focus.get_meta("part_action", "")) == "house":
			await press(JOY_BUTTON_A)
			return
		await press(JOY_BUTTON_DPAD_RIGHT)
	check(false, "House action is controller reachable")

func _run() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://house-actions-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "native scene ready")
	if not scene._player_restored: _finish(); return
	scene.set_process(false)
	scene._set_view_context("building")
	scene._update_resize_handles()
	check(not scene._resize_overlay.visible and scene._handle_candidates().is_empty(), "handles are absent during ordinary cottage editing")
	check(aim_shell(), "bare wall is targetable")
	var before: String = scene.building_world.serialize_document()
	await press(JOY_BUTTON_A)
	await choose_whole_house()
	check(scene._house_actions_open and scene.tools_open and not scene.resize_active and not scene.detail_move_active, "House action opens only Move/Resize chooser")
	check(scene._house_actions_panel.visible and not scene._building_panel.visible, "no competing legacy panel")
	check(scene._house_action_buttons.size() == 2 and root.gui_get_focus_owner() == scene._house_action_buttons[0], "two choices with initial Move focus")
	var id: String = scene.selected_building_id
	await press(JOY_BUTTON_DPAD_RIGHT)
	await press(JOY_BUTTON_LEFT_SHOULDER)
	check(scene.selected_building_id == id and scene.building_world.serialize_document() == before, "picker blocks cottage switching and world undo")
	await press(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner() == scene._house_action_buttons[1], "D-pad selects Resize")
	await press(JOY_BUTTON_A)
	check(scene._resize_selecting and not scene._house_actions_open and scene._resize_overlay.visible and not scene.resize_active, "Resize reveals handles without grabbing one")
	await press(JOY_BUTTON_B)
	check(not scene._resize_selecting and scene.view_context == "building" and not scene._resize_overlay.visible, "B dismisses handles, not cottage editing")
	check(aim_shell(), "shell available after finishing resize")
	await press(JOY_BUTTON_A)
	await press(JOY_BUTTON_B)
	check(not scene.tools_open and scene.view_context == "building", "B closes chooser one level")

	# Details never pass through the whole-house picker.
	var original: Dictionary = scene.building_world.get_building(id)
	var transform_value: Transform3D = original["transform"]
	var window: Dictionary = {}
	for detail in original["details"]:
		if str(detail["kind"]) != "window" or not bool(detail.get("visible", false)): continue
		scene.edit_pointer = scene.camera.unproject_position(transform_value * (detail["resolved_position"] as Vector3))
		scene._update_detail_hover()
		if scene.hovered_detail_id == str(detail["id"]):
			window = detail
			break
	check(not window.is_empty(), "visible window fixture found")
	await press(JOY_BUTTON_A)
	check(scene.detail_move_active and not scene._house_actions_open, "window A still directly moves the window")
	await press(JOY_BUTTON_B)

	# Existing cottage identity and authored choices must travel, not duplicate.
	var other_id: String = scene.building_world.duplicate_building(id, Vector3(8, 0, 8))
	var other: Dictionary = scene.building_world.get_building(other_id)
	scene._update_presentation()
	before = scene.building_world.serialize_document()
	var count: int = scene.building_world.get_buildings().size()
	var history: int = scene._history_tags.size()
	check(aim_shell(), "shell selected before Move")
	var camera_before: Transform3D = scene.camera.global_transform
	await press(JOY_BUTTON_A)
	await choose_whole_house()
	await press(JOY_BUTTON_A)
	check(scene._moving_house and scene.building_placement_active, "A chooses Move house")
	check(scene.building_placement_target.is_equal_approx(transform_value.origin), "move begins at original location, not duplicate offset")
	check(not scene.cottage_visuals[id].visible and scene.building_placement_ghost.visible, "one ghost replaces original renderer during move")
	drag(Vector2.RIGHT, 60)
	check(scene.building_placement_target.distance_to(transform_value.origin) > 0.25, "stick translates the complete house")
	check(scene.building_world.serialize_document() == before and scene._history_tags.size() == history, "moving preview is pure")
	var camera_target: Vector3 = scene.building_placement_target + Vector3(0, 2, 0)
	check((-scene.camera.global_basis.z).dot((camera_target - scene.camera.global_position).normalized()) > 0.99, "camera follows free relocation")
	await press(JOY_BUTTON_B)
	check(not scene._moving_house and scene.view_context == "building" and scene.cottage_visuals[id].visible, "cancel restores original renderer and building mode")
	check(scene.building_world.serialize_document() == before and scene._history_tags.size() == history, "cancel creates no committed edit")
	check(scene.camera.global_transform.is_equal_approx(camera_before), "cancel restores source orbit")
	check(aim_shell(), "shell available after move cancel")
	await press(JOY_BUTTON_A)
	await choose_whole_house()
	await press(JOY_BUTTON_A)
	drag(Vector2.RIGHT, 60)
	var destination: Vector3 = scene.building_placement_target
	await press(JOY_BUTTON_A)
	var moved: Dictionary = scene.building_world.get_building(id)
	check(scene.building_world.get_buildings().size() == count and scene.selected_building_id == id, "confirm keeps house count and stable selected ID")
	check((moved["transform"] as Transform3D).origin.is_equal_approx(destination), "existing house moved to preview destination")
	check(moved["details"] == original["details"] and moved["dimensions"] == original["dimensions"] and moved["material_id"] == original["material_id"], "all details, dimensions and materials retained")
	check(scene.building_world.get_building(other_id) == other, "other cottage unchanged")
	check(scene._history_tags.size() == history + 1, "one move is one undo entry")
	await press(JOY_BUTTON_LEFT_SHOULDER)
	check(scene.building_world.get_building(id) == original, "undo restores entire original cottage")
	await press(JOY_BUTTON_RIGHT_SHOULDER)
	check(scene.building_world.get_building(id) == moved, "redo restores relocation")
	var restored = preload("res://scripts/cottage_resize_world.gd").new()
	var save_text: String = scene.building_world.serialize_document()
	var saved: Dictionary = JSON.parse_string(save_text)
	check(restored.load_serialized_document(save_text), "same-schema save can be loaded")
	var loaded: Dictionary = restored.get_building(id)
	# Preserve exact saved records; normalize JSON number types on BOTH sides
	# when comparing a live view with a reloaded view. No fields are excluded.
	check(JSON.stringify(restored.get_document()["buildings"]) == JSON.stringify(saved["buildings"]), "reload preserves every saved cottage record exactly")
	check(JSON.parse_string(JSON.stringify(loaded)) == JSON.parse_string(JSON.stringify(moved)), "complete moved view survives save/reload with JSON number types")
	check((loaded["transform"] as Transform3D).is_equal_approx(moved["transform"]) and loaded["dimensions"] == moved["dimensions"], "reloaded transform and dimensions match moved house")
	for i in loaded["details"].size():
		var actual: Dictionary = loaded["details"][i]
		var expected: Dictionary = moved["details"][i]
		check(actual["id"] == expected["id"] and (actual["resolved_position"] as Vector3).is_equal_approx(expected["resolved_position"]), "reloaded detail keeps identity and local position")
	print("HOUSE_LAYOUT_NUMBER_TYPES live=" + JSON.stringify(moved["automatic_layout"]) + " loaded=" + JSON.stringify(loaded["automatic_layout"]))
	var rev: int = scene.building_world.get_revision()
	check(not scene.building_world.move_building(id, Vector3.INF, rev), "nonfinite relocation rejected")
	check(not scene.building_world.move_building(id, destination + Vector3.ONE, rev - 1), "stale relocation rejected")
	history = scene._history_tags.size()
	scene._begin_house_move()
	await press(JOY_BUTTON_A)
	check(scene._history_tags.size() == history, "confirm without moving creates no undo entry")
	scene._begin_house_move()
	await press(JOY_BUTTON_START)
	check(scene.menu_open and not scene._moving_house and scene.cottage_visuals[id].visible, "Pause restores a moving house")
	await press(JOY_BUTTON_B)
	scene._begin_house_move()
	scene.building_world.set_material(id, "rose_lime")
	scene._read_camera_and_cursor(1.0 / 60.0)
	check(not scene._moving_house and scene.building_world.get_building(id)["material_id"] == "rose_lime", "stale move cancels without reverting newer changes")
	# Explicit duplication remains distinct and still makes a new house.
	scene._begin_building_placement()
	check(not scene._moving_house, "Duplicate does not enter Move operation")
	await press(JOY_BUTTON_A)
	check(scene.building_world.get_buildings().size() == count + 1, "Duplicate still creates a new cottage")
	_finish()

func _finish() -> void:
	stick(Vector2.ZERO)
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m1_house_actions_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
