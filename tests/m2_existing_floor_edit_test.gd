extends SceneTree

const Massing = preload("res://scripts/m2_house_massing.gd")
const World = preload("res://scripts/m2_building_world.gd")
var scene: Node
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-floor-edit-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "native floor-edit scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	var building_id: String = scene.selected_building_id
	check(scene._edit_floors_button.disabled, "single-storey house does not offer nonexistent floors")
	scene._begin_next_storey()
	check(scene.portion_valid and scene._commit_portion_placement(), "existing add route creates floor 2")
	await _refresh()
	var original: Dictionary = scene.building_world.get_building(building_id)
	var floors: Array[Dictionary] = Massing.sections_on_level(Massing.sections_for(original), 1)
	check(floors.size() == 1 and not scene._edit_floors_button.disabled, "placed upper floor enables Edit floors")
	if floors.size() != 1:
		await _finish()
		return
	var floor_id: String = floors[0]["id"]
	var window_ids: Array[String] = []
	for detail in original.get("details", []):
		if bool(detail.get("massing_auto", false)) and bool(detail.get("visible", false)) and not bool(detail.get("needs_placement", true)):
			window_ids.append(str(detail["id"]))
	check(window_ids.size() >= 2, "upstairs windows available for preservation checks")
	if window_ids.size() < 2:
		await _finish()
		return
	check(scene._commit_detail_style(window_ids[0], "window_arch_casement", "berry"), "lock upstairs window style and colour")
	check(scene.building_world.suppress_detail(building_id, window_ids[1]), "suppress another upstairs window")
	await _refresh()
	var before: Dictionary = scene.building_world.get_document()
	var saved: String = scene.building_world.serialize_document()
	var cursor_before: Vector3 = scene.cursor
	var revision: int = scene.building_world.get_revision()
	await _open_picker()
	check(scene._floor_edit_picker_open and scene._floor_edit_picker.visible, "Home options action opens floor chooser")
	check(not scene._building_panel.visible and scene.tools_open, "chooser has exclusive menu state")
	check(scene._floor_edit_buttons[0].text == "Floor 2", "chooser names the storey without technical IDs")
	check(is_instance_valid(scene._floor_edit_highlight), "focused floor has an in-world highlight")
	check(scene._floor_edit_picker.get_global_rect().end.y < scene._prompt_bar.get_global_rect().position.y, "chooser stays above controller prompts")
	_press("m1_cycle_right")
	check(scene.building_world.serialize_document() == saved and scene.cursor == cursor_before, "browsing cannot change the world")
	_press("m1_cancel")
	await _settle()
	check(not scene._floor_edit_picker_open and scene._building_panel.visible and root.gui_get_focus_owner() == scene._edit_floors_button, "Back restores the home action and focus")

	await _open_editor()
	check(scene.portion_placement_active and scene._editing_portion_id == floor_id, "controller reopens the existing upper portion")
	check(scene.portion_valid and scene.portion_size == floors[0]["size"], "preview starts at the placed dimensions")
	check(not is_instance_valid(scene._floor_edit_highlight), "selection highlight removed before edit preview")
	var original_size: Vector3 = scene.portion_size
	_press("m1_cycle_right")
	_press("m1_height_up")
	check(scene.portion_size.x > original_size.x and scene.portion_size.z > original_size.z and scene.portion_valid, "D-pad grows width and depth of the placed floor")
	var preview: Dictionary = scene._preview_massing_view(scene.building_world.get_building(building_id))
	check(Massing.sections_for(preview).size() == Massing.sections_for(original).size(), "preview replaces rather than appends a floor")
	check(scene.building_world.serialize_document() == saved, "resizing preview does not mutate authority")
	_press("m1_cancel")
	await _refresh()
	check(not scene.portion_placement_active and scene.building_world.serialize_document() == saved, "Cancel restores the exact placed floor")

	await _open_editor()
	_press("m1_cycle_right")
	var intended: Vector3 = scene.portion_size
	_press("m1_accept")
	await _refresh()
	var edited: Dictionary = scene.building_world.get_building(building_id)
	check(not scene.portion_placement_active and scene.building_world.get_revision() == revision + 1, "Apply is one edit, then leaves preview")
	var edited_floor: Dictionary = _section(edited, floor_id)
	check(not edited_floor.is_empty() and edited_floor.get("size") == intended, "same floor ID receives the intended dimensions")
	check(edited["dimensions"] == original["dimensions"] and _section(edited, "core") == _section(original, "core"), "lower/core floor does not resize")
	check(Massing.sections_for(edited).size() == Massing.sections_for(original).size(), "commit does not duplicate the upper floor")
	var edited_window: Dictionary = _detail(edited, window_ids[0])
	check(str(edited_window.get("asset_id", "")) == "window_arch_casement" and edited_window.get("override", {}).get("color_id", "") == "berry", "floor regeneration preserves authored window style and colour")
	check(str(_detail(edited, window_ids[1]).get("state", "")) == "suppressed", "floor regeneration preserves suppression")
	var after: Dictionary = scene.building_world.get_document()
	check(scene.building_world.undo(), "floor resize undo")
	await _refresh()
	check(scene.building_world.get_document()["buildings"] == before["buildings"], "one undo restores all house records")
	check(scene.building_world.redo(), "floor resize redo")
	await _refresh()
	check(scene.building_world.get_document()["buildings"] == after["buildings"], "redo restores the edited house records")
	var restored := World.new()
	check(restored.load_serialized_document(scene.building_world.serialize_document()), "resized floor reloads")
	check(restored.get_building(building_id)["massing_sections"] == edited["massing_sections"] and _detail(restored.get_building(building_id), window_ids[0]).get("override", {}) == edited_window.get("override", {}), "reload retains floor size and decor overrides")

	await _open_editor()
	var unchanged: String = scene.building_world.serialize_document()
	check(not scene._commit_portion_placement() and scene.building_world.serialize_document() == unchanged, "unchanged Apply is a no-op")
	scene._begin_existing_portion_edit(floor_id)
	var old_offset: Vector3 = scene.portion_offset
	scene.camera_yaw = 0.0
	Input.action_press("m1_move_right", 0.2)
	for frame in 30: scene._read_camera_and_cursor(1.0 / 60.0)
	Input.action_release("m1_move_right")
	check(scene.portion_offset.x > old_offset.x, "small stick deltas accumulate before snapping")
	check(scene.building_world.serialize_document() == unchanged, "moving preview remains read-only")
	scene._cancel_current_edit("focus lost")
	check(not scene.portion_placement_active and scene._editing_portion_id.is_empty() and scene.building_world.serialize_document() == unchanged, "focus-loss path cancels without writing")

	scene._begin_existing_portion_edit(floor_id)
	_press("m1_cycle_right")
	check(scene.building_world.set_material(building_id, "chalk_white"), "concurrent edit fixture")
	var concurrent: String = scene.building_world.serialize_document()
	check(not scene._commit_portion_placement() and scene.portion_reason.contains("changed"), "stale preview cannot overwrite a newer edit")
	check(scene.building_world.serialize_document() == concurrent, "rejected stale edit leaves new data intact")
	scene._cancel_portion_placement()

	scene._begin_next_storey()
	check(scene.portion_valid and scene._commit_portion_placement(), "add a third floor using the inherited flow")
	await _refresh()
	var stacked: Dictionary = scene.building_world.get_building(building_id)
	scene._begin_existing_portion_edit(floor_id)
	scene.portion_offset.x += 3.0
	scene._update_portion_preview()
	check(not scene.portion_valid and scene.portion_reason.contains("support"), "editing a middle floor cannot strand a higher floor")
	check(not scene._commit_portion_placement(), "unsupported replacement cannot commit")
	scene._cancel_portion_placement()
	check(scene.building_world.get_building(building_id) == stacked, "unsupported edit and cancel preserve the stack")
	await _finish()

func _open_picker() -> void:
	scene._open_building_panel()
	scene._edit_floors_button.grab_focus()
	await _settle()
	_press("m1_accept")
	await _settle()

func _open_editor() -> void:
	await _open_picker()
	_press("m1_accept")
	await _settle()

func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	scene._input(event)

func _settle() -> void:
	for frame in 3: await process_frame

func _refresh() -> void:
	scene._presentation_key = ""
	scene._update_presentation()
	await _settle()

func _section(view: Dictionary, id: String) -> Dictionary:
	for section in Massing.sections_for(view):
		if str(section["id"]) == id: return section
	return {}

func _detail(view: Dictionary, id: String) -> Dictionary:
	for detail in view.get("details", []):
		if str(detail.get("id", "")) == id: return detail
	return {}

func _finish() -> void:
	Input.action_release("m1_move_right")
	if is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m2_existing_floor_edit_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
