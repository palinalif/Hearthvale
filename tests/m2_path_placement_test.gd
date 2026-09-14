extends SceneTree

const State = preload("res://scripts/landscape_state.gd")
const Excavation = preload("res://scripts/m2_path_terrain_excavation.gd")

var checks := 0
var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-path-placement-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene._player_restored, "native path scene ready")
	if not scene._player_restored:
		_finish()
		return
	scene.set_process(false)
	var fixture_z := -1.0
	for z in [27.0, 29.0, 31.0, 33.0]:
		if scene.landscape_state.add("foliage", Vector3(40.0, 8.0, z), 2):
			fixture_z = z
			break
	_check(fixture_z > 0.0, "paint route has a planting fixture to clear")
	scene.garden_visual.reset_records(scene.landscape_state.records)
	var before: Dictionary = scene.landscape_state.document()
	var history_before: int = scene._history_tags.size()

	await _press(JOY_BUTTON_DPAD_UP)
	_check(scene._build_catalogue_open, "D-pad Up opens the build catalogue")
	scene._build_catalogue_buttons[1].grab_focus()
	await _press(JOY_BUTTON_A)
	_check(scene._roads_catalogue_open and scene._roads_catalogue_buttons.size() == 5, "Roads & Paths opens its path and bridge styles")
	scene._roads_catalogue_buttons[0].grab_focus()
	await _press(JOY_BUTTON_A)
	_check(scene.path_placement_active and scene.path_style_id == "packed_earth" and scene.view_context == "terrain", "style selection enters terrain path painting")
	_check(scene.landscape_state.document() == before, "starting path painting is read-only")
	var initial_width: float = scene.path_width
	await _press(JOY_BUTTON_DPAD_RIGHT)
	_check(scene.path_width > initial_width, "D-pad right increases painted-path brush width")
	await _press(JOY_BUTTON_DPAD_LEFT)
	_check(is_equal_approx(scene.path_width, initial_width), "D-pad left restores painted-path brush width")

	_aim(Vector2(36.0, fixture_z))
	await _button_down(JOY_BUTTON_A)
	_check(scene.path_painting and scene.path_cells.size() > 0, "holding A starts a painted-cell stroke")
	var width_during_stroke: float = scene.path_width
	await _press(JOY_BUTTON_DPAD_RIGHT)
	_check(is_equal_approx(scene.path_width, width_during_stroke), "brush width is locked while a path stroke is live")
	var preview_before := JSON.stringify(scene.landscape_state.document())
	scene._update_path_preview()
	_check(JSON.stringify(scene.landscape_state.document()) == preview_before and scene.path_visual.stats().preview_cells > 0, "live painted preview has geometry without mutating authority")
	_aim(Vector2(44.0, fixture_z))
	_check(scene._sample_path_stroke() and scene.path_cells.size() > 20, "moving while A is held continuously extends the stroke")
	var expected_cut: Dictionary = Excavation.plan_packed_earth_transition(scene.backend, scene.landscape_state.path_cells("packed_earth"), scene.path_cells)
	_check(bool(expected_cut.ok) and int(expected_cut.changed_count) > 0, "packed-earth stroke plans a real terrain cut before commit")
	var cut_position: Vector3i = expected_cut.removals[0].position
	var cut_material: int = int(expected_cut.removals[0].before)
	var terrain_revision_before: int = int(scene.backend.stats().revision)
	await _button_up(JOY_BUTTON_A)
	_check(not scene.path_painting and scene.path_placement_active and scene.landscape_state.paths.size() == 1, "A release commits the stroke and keeps the paint tool active")
	_check(scene.backend.voxel_at(cut_position) == 0 and int(scene.backend.stats().revision) == terrain_revision_before + 1, "packed-earth commit excavates native terrain exactly once")
	_check(scene._history_tags.back() == "path", "terrain cut and painted authority share one path history transaction")
	_check(scene._history_tags.size() == history_before + 1, "one painted stroke records one landscape history entry")
	_check(scene.path_terrain_ownership_count() > 0, "packed-earth excavation records exact terrain ownership")
	var after: Dictionary = scene.landscape_state.document()
	_check(after.paths[0].has("cells") and not after.paths[0].has("points") and not after.paths[0].has("width"), "committed path stores only painted-cell authority")
	_check(scene.landscape_state.records.size() < before.records.size() and not _has_record_at(scene.landscape_state.records, 40.0, fixture_z), "stroke commit clears intersecting planting atomically")

	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(scene.landscape_state.document() == before, "LB undo while painting tool is open restores path and planting together")
	_check(scene.backend.voxel_at(cut_position) == cut_material, "LB undo restores the terrain removed by the same path transaction")
	_check(scene.path_terrain_ownership_count() == 0, "LB undo restores the matching path-terrain ownership state")
	_check(scene.path_placement_active, "undo keeps the path paint tool active")
	_aim(Vector2(36.0, fixture_z))
	await _button_down(JOY_BUTTON_A)
	_aim(Vector2(44.0, fixture_z))
	scene._sample_path_stroke()
	await _button_up(JOY_BUTTON_A)
	after = scene.landscape_state.document()
	var saved := JSON.stringify(after)
	var owned_before_save: int = scene.path_terrain_ownership_count()
	_check(owned_before_save > 0, "repaint owns the excavated terrain before save")
	_check(scene._save_all(), "painted path save succeeds")
	_check(scene._reload_all(), "painted path reload succeeds")
	_check(JSON.stringify(scene.landscape_state.document()) == saved, "save/reload preserves exact painted cells and region ID")
	_check(scene.path_terrain_ownership_count() == owned_before_save, "save/reload preserves packed-earth terrain ownership")
	_check(scene.backend.voxel_at(cut_position) == 0, "reloaded packed-earth ownership still corresponds to the excavated voxel")

	var packed_cells: Array = scene.landscape_state.path_cells("packed_earth")
	scene.path_style_id = "cobblestone"
	scene.path_width = 1.50
	scene._begin_path_placement()
	scene._reset_path_baseline()
	scene.path_painting = true
	scene.path_cells = packed_cells.duplicate()
	_check(scene._commit_path_stroke(), "painting another material over packed earth commits")
	_check(scene.landscape_state.path_cells("packed_earth").is_empty() and not scene.landscape_state.path_cells("cobblestone").is_empty(), "material overwrite transfers painted-cell authority")
	_check(scene.backend.voxel_at(cut_position) == cut_material, "material overwrite restores the terrain previously owned by packed earth")
	_check(scene.path_terrain_ownership_count() == 0, "material overwrite releases restored packed-earth ownership")
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(scene.backend.voxel_at(cut_position) == 0 and scene.path_terrain_ownership_count() == owned_before_save, "undoing overwrite re-excavates packed earth and restores ownership atomically")
	_check(JSON.stringify(scene.landscape_state.document()) == saved, "undoing overwrite restores the saved packed-earth authority")

	var erase_cells: Array = scene.landscape_state.path_cells("packed_earth")
	_check(scene.erase_painted_path_cells(erase_cells), "path erase reconciles packed-earth terrain")
	_check(scene.backend.voxel_at(cut_position) == cut_material and scene.path_terrain_ownership_count() == 0, "path erase restores owned terrain and releases ownership")
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(scene.backend.voxel_at(cut_position) == 0 and scene.path_terrain_ownership_count() == owned_before_save, "undoing path erase restores excavation and ownership")

	var erase_mode_before := JSON.stringify(scene.landscape_state.document())
	var erase_owned_before: int = scene.path_terrain_ownership_count()
	await _press(JOY_BUTTON_X)
	_check(scene.path_erase_mode, "X toggles the active path tool into erase mode")
	scene.path_width = 1.5
	var scale_value: float = float(scene.backend.voxel_scale)
	_aim(Vector2((float(cut_position.x) + 0.5) * scale_value, (float(cut_position.z) + 0.5) * scale_value))
	scene._path_preview_signature = ""
	scene._update_path_preview()
	_check(scene._path_preview_signature.begins_with("erase|") and scene.path_visual.stats().preview_cells > 0, "erase mode owns a distinct preview path")
	_check(is_instance_valid(scene.path_visual._preview_marker), "erase mode keeps an explicit erase marker visible")
	await _button_down(JOY_BUTTON_A)
	await _button_up(JOY_BUTTON_A)
	_check(scene.landscape_state.path_cells("packed_earth").size() < (JSON.parse_string(erase_mode_before).paths[0].cells as Array).size(), "erase stroke removes painted path cells")
	_check(scene.path_terrain_ownership_count() < erase_owned_before, "erase stroke releases packed-earth terrain ownership")
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(JSON.stringify(scene.landscape_state.document()) == erase_mode_before and scene.path_terrain_ownership_count() == erase_owned_before, "undo restores an erase stroke atomically")
	await _press(JOY_BUTTON_X)
	_check(not scene.path_erase_mode, "X toggles the path tool back to paint mode")

	scene._begin_path_placement()
	var cancel_before := JSON.stringify(scene.landscape_state.document())
	var history_after_reload: int = scene._history_tags.size()
	_aim(Vector2(30.0, 35.0))
	await _button_down(JOY_BUTTON_A)
	_aim(Vector2(32.0, 35.0))
	scene._sample_path_stroke()
	await _press(JOY_BUTTON_B)
	_check(scene.path_placement_active and not scene.path_painting and scene.path_cells.is_empty(), "B cancels only the live uncommitted stroke")
	_check(JSON.stringify(scene.landscape_state.document()) == cancel_before and scene._history_tags.size() == history_after_reload, "stroke cancellation changes neither authority nor history")
	await _press(JOY_BUTTON_B)
	_check(not scene.path_placement_active and JSON.stringify(scene.landscape_state.document()) == cancel_before, "B while idle closes path painting without document drift")

	var home: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var home_center: Vector3 = (home["transform"] as Transform3D).origin
	scene._begin_path_placement()
	_aim(Vector2(home_center.x, home_center.z))
	_check(not scene.path_placement_valid and scene.path_placement_reason.contains("interior"), "brush footprint over a home interior is explained and invalid")
	await _button_down(JOY_BUTTON_A)
	_check(not scene.path_painting and scene.path_cells.is_empty(), "invalid home brush cannot begin a stroke")
	await _button_up(JOY_BUTTON_A)
	_check(JSON.stringify(scene.landscape_state.document()) == cancel_before, "invalid home paint cannot commit")
	scene._cancel_path_placement()

	scene._begin_path_placement()
	_aim(Vector2(31.0, 37.0))
	await _button_down(JOY_BUTTON_A)
	var focus_before := JSON.stringify(scene.landscape_state.document())
	scene._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not scene.path_placement_active and JSON.stringify(scene.landscape_state.document()) == focus_before and scene.menu_open, "focus loss discards a live stroke and pauses the world")
	scene._set_menu(false)
	scene._begin_path_placement()
	var disconnect_before := JSON.stringify(scene.landscape_state.document())
	scene._on_joy_connection_changed(0, false)
	_check(not scene.path_placement_active and scene.menu_open and JSON.stringify(scene.landscape_state.document()) == disconnect_before, "controller disconnect cannot commit a stroke accidentally")
	_finish()

func _aim(point: Vector2) -> void:
	scene.cursor = Vector3(point.x, 8.0, point.y)
	scene.terrain_cursor = scene.cursor
	scene._update_brush_preview()
	scene._update_path_validity()

func _has_record_at(records: Array, x: float, z: float) -> bool:
	for record: Dictionary in records:
		var point: Vector3 = State.position_of(record)
		if is_equal_approx(point.x, x) and is_equal_approx(point.z, z): return true
	return false

func _button_down(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func _button_up(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func _press(button: JoyButton) -> void:
	await _button_down(button)
	await _button_up(button)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures}))
	quit(1 if failures else 0)
