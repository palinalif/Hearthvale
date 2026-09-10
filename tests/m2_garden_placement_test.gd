extends SceneTree

const State = preload("res://scripts/landscape_state.gd")

var checks := 0
var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-garden-placement-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene._player_restored, "native garden scene ready")
	if not scene._player_restored:
		_finish()
		return
	scene.set_process(false)

	var fixture := Vector3.ZERO
	for point in [Vector3(40, 8, 40), Vector3(42, 8, 40), Vector3(38, 8, 40), Vector3(40, 8, 36)]:
		if scene.landscape_state.add("foliage", point, 9):
			fixture = point
			break
	_check(fixture != Vector3.ZERO, "garden fixture has planting to clear")
	scene.garden_visual.reset_records(scene.landscape_state.records)
	var before: Dictionary = scene.landscape_state.document()
	var history_before: int = scene._history_tags.size()

	await _press(JOY_BUTTON_DPAD_UP)
	_check(scene._build_catalogue_open and scene._build_catalogue_buttons.size() == 4, "build catalogue includes Hamlet details")
	scene._build_catalogue_buttons[3].grab_focus()
	await _press(JOY_BUTTON_A)
	_check(scene._hamlet_catalogue_open and scene._hamlet_catalogue_buttons.size() == 9, "Hamlet details opens the complete composition catalogue")
	_check(scene._hamlet_catalogue_buttons[0].text.begins_with("Cottage flower garden") and scene._hamlet_catalogue_buttons[2].text.begins_with("Herb garden"), "garden choices are visually named")
	scene._hamlet_catalogue_buttons[0].grab_focus()
	await _press(JOY_BUTTON_A)
	_check(scene.garden_placement_active and scene.garden_style_id == "cottage_flowers" and scene.view_context == "terrain", "garden selection enters world placement")
	_check(scene.landscape_state.document() == before, "starting garden placement is preview-only")

	_aim(Vector2(fixture.x, fixture.z))
	_check(scene.garden_placement_valid and scene.composition_visual.stats().preview_cells > 0, "valid garden target renders a preview")
	scene._rotate_garden(1)
	_check(scene.garden_yaw_quarters == 1 and scene.landscape_state.document() == before, "garden rotation changes preview without touching authority")
	await _press(JOY_BUTTON_A)
	_check(not scene.garden_placement_active and scene.landscape_state.composition.size() == 1, "A commits a garden")
	var garden: Dictionary = scene.landscape_state.composition[0]
	_check(garden.kind == "garden" and garden.style_id == "cottage_flowers" and int(garden.yaw_quarters) == 1, "garden commit preserves style and orientation")
	_check(scene._history_tags.size() == history_before + 1, "garden commit is one landscape history entry")
	_check(not _has_record_at(scene.landscape_state.records, fixture.x, fixture.z), "garden commit clears planting inside its footprint atomically")
	_check(scene.composition_visual.stats().garden_count == 1 and scene.composition_visual.stats().garden_geometry_cells > 0, "committed garden rebuilds disposable presentation")
	var after: Dictionary = scene.landscape_state.document()

	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(scene.landscape_state.document() == before, "undo removes garden and restores cleared planting")
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	_check(scene.landscape_state.document() == after, "redo restores garden and planting removal")
	var saved := JSON.stringify(scene.landscape_state.document())
	_check(scene._save_all(), "garden save succeeds")
	_check(scene._reload_all(), "garden reload succeeds")
	_check(JSON.stringify(scene.landscape_state.document()) == saved, "save/reload preserves exact garden authority")
	_check(scene.composition_visual.stats().garden_count == 1, "garden presentation rebuilds after reload")

	var cancel_before := JSON.stringify(scene.landscape_state.document())
	var history_after_reload: int = scene._history_tags.size()
	scene.garden_style_id = "herb_garden"
	scene.garden_size = Vector2(2.25, 2.25)
	scene._begin_garden_placement()
	_aim(Vector2(34.0, 38.0))
	await _press(JOY_BUTTON_B)
	_check(not scene.garden_placement_active and JSON.stringify(scene.landscape_state.document()) == cancel_before, "B cancels garden preview without authority drift")
	_check(scene._history_tags.size() == history_after_reload, "cancelled garden adds no history entry")

	var home: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var home_center: Vector3 = (home["transform"] as Transform3D).origin
	scene.garden_style_id = "kitchen_rows"
	scene.garden_size = Vector2(3.5, 2.5)
	scene._begin_garden_placement()
	_aim(Vector2(home_center.x, home_center.z))
	_check(not scene.garden_placement_valid and scene.garden_placement_reason.contains("home"), "garden overlap with a home is rejected with an explanation")
	await _press(JOY_BUTTON_A)
	_check(scene.garden_placement_active and scene.landscape_state.composition.size() == 1, "invalid garden cannot commit")
	scene._cancel_garden_placement()
	_finish()

func _aim(point: Vector2) -> void:
	scene.cursor = Vector3(point.x, 8.0, point.y)
	scene.terrain_cursor = scene.cursor
	scene._update_brush_preview()
	scene._update_garden_validity()
	scene._update_garden_preview()

func _has_record_at(records: Array, x: float, z: float) -> bool:
	for record: Dictionary in records:
		var point := State.position_of(record)
		if is_equal_approx(point.x, x) and is_equal_approx(point.z, z): return true
	return false

func _press(button: JoyButton) -> void:
	var down := InputEventJoypadButton.new()
	down.button_index = button
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await process_frame
	var up := InputEventJoypadButton.new()
	up.button_index = button
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await process_frame

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
