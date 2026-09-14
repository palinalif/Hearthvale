extends SceneTree
## All authored planter styles through the current controller catalogue and the
## shared placement/history/save implementation. Never opens a player save.
const Assets = preload("res://scripts/m2_planter_assets.gd")
var scene: Node
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	scene = load("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-planter-placement-%d" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene._player_restored, "Native planter test scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	await _press(JOY_BUTTON_DPAD_UP)
	_check(scene._browser_open, "Controller opens the current world catalogue")
	# Move between the three world categories with physical shoulder buttons.
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	_check(scene._build_browser.category == "outdoor", "Controller reaches Outdoor")
	for style: String in Assets.STYLE_IDS:
		_check(_card(style) != null, "Named planter card: " + style)
	scene._close_build_browser()
	for index in Assets.STYLE_IDS.size():
		var style: String = Assets.STYLE_IDS[index]
		var point := Vector2(30.0 + index * 2.0, 34.0)
		var before: Dictionary = scene.landscape_state.document()
		var history_before: int = scene._history_tags.size()
		if not await _choose(style): break
		_aim(point)
		_check(scene.furniture_placement_valid, "Valid free target: " + style)
		var ghost: MeshInstance3D = scene.composition_visual._furniture_preview_node
		_check(ghost != null and ghost.get_meta("authored_asset", "") == Assets.PATHS[style], "Preview uses the selected exported mesh: " + style)
		var yaw := float(scene.furniture_yaw_degrees)
		_check(is_equal_approx(yaw, snappedf(yaw, 15.0)), "Initial gentle rotation: " + style)
		scene._rotate_furniture(1)
		_check(is_equal_approx(scene.furniture_yaw_degrees, fposmod(yaw + 15.0, 360.0)), "15-degree rotation: " + style)
		scene.precision_mode = true
		scene._rotate_furniture(1)
		scene.precision_mode = false
		_check(is_equal_approx(scene.furniture_yaw_degrees, fposmod(yaw + 16.0, 360.0)), "One-degree precision: " + style)
		_check(scene.landscape_state.document() == before, "Preview and rotation are authority-neutral: " + style)
		await _press(JOY_BUTTON_B)
		_check(not scene.furniture_placement_active and scene.landscape_state.document() == before and scene._history_tags.size() == history_before, "Cancel restores exact authority and adds no history: " + style)
		if not await _choose(style): break
		_aim(point)
		scene.precision_mode = true
		scene._rotate_furniture(1)
		scene.precision_mode = false
		var expected_yaw := float(scene.furniture_yaw_degrees)
		var ghost_transform: Transform3D = scene.composition_visual._furniture_preview_node.transform
		var expected_id := int(scene.landscape_state.next_id)
		await _press(JOY_BUTTON_A)
		var record: Dictionary = scene._composition_record(expected_id)
		_check(not scene.furniture_placement_active and not record.is_empty(), "A commits one selected planter: " + style)
		if record.is_empty(): break
		_check(record.style_id == style and record.size == [0.75, 0.75] and is_equal_approx(float(record.yaw_degrees), expected_yaw), "Saved style, footprint and precise yaw: " + style)
		_check(scene._history_tags.size() == history_before + 1, "One undo transaction: " + style)
		var placed := _node(expected_id)
		_check(placed != null and placed.transform.is_equal_approx(ghost_transform), "Preview and committed model agree exactly: " + style)
		var after: Dictionary = scene.landscape_state.document()
		await _press(JOY_BUTTON_LEFT_SHOULDER)
		_check(scene.landscape_state.document() == before, "Undo exact document: " + style)
		await _press(JOY_BUTTON_RIGHT_SHOULDER)
		_check(scene.landscape_state.document() == after and _node(expected_id) != null, "Redo restores identity and authored presentation: " + style)
		# Existing recolour and relocation must neither lose the style nor mutate
		# the shared mesh materials. The material cache itself is asset-tested.
		_aim(point)
		_check(scene._select_detail_near_cursor(), "Placed planter remains selectable: " + style)
		scene._cycle_selected_detail_colour()
		var coloured: Dictionary = scene._composition_record(expected_id)
		_check(not str(coloured.get("colour_id", "")).is_empty(), "Existing recolour operation: " + style)
		var move_before: Dictionary = scene.landscape_state.document()
		var move_history: int = scene._history_tags.size()
		scene._select_detail_near_cursor()
		scene._begin_selected_detail_move()
		_aim(point + Vector2(0.0, 1.5))
		_check(scene.furniture_placement_active and scene._detail_edit_id == expected_id, "Move keeps stable identity: " + style)
		_check(scene.composition_visual._furniture_preview_node.mesh == Assets.mesh_for(style, str(coloured.colour_id), true, true), "Move ghost retains the saved colour: " + style)
		await _press(JOY_BUTTON_B)
		_check(scene.landscape_state.document() == move_before and scene._history_tags.size() == move_history, "Move cancellation is exact: " + style)
		_aim(point)
		scene._select_detail_near_cursor()
		scene._begin_selected_detail_move()
		_aim(point + Vector2(0.0, 1.5))
		scene.precision_mode = true
		scene._rotate_furniture(-1)
		scene.precision_mode = false
		await _press(JOY_BUTTON_A)
		var moved: Dictionary = scene._composition_record(expected_id)
		_check(moved.style_id == style and moved.colour_id == coloured.colour_id and moved.position == [point.x, point.y + 1.5] and int(scene.landscape_state.next_id) == int(move_before.next_id), "Relocation preserves identity, style, tint and next ID: " + style)
		_check(scene._history_tags.size() == move_history + 1, "Relocation is one transaction: " + style)
	var saved := JSON.stringify(scene.landscape_state.document())
	_check(scene._save_all() and scene._reload_all(), "All three planters save and reload through normal checkpoint code")
	_check(JSON.stringify(scene.landscape_state.document()) == saved, "Reload preserves the exact planter document")
	_check(scene.composition_visual.stats().furniture_count == 3, "Reload rebuilds all three authored models")
	if await _choose("barrel_planter_light"):
		var home: Dictionary = scene.building_world.get_building(scene.selected_building_id)
		var home_point: Vector3 = (home.transform as Transform3D).origin
		_aim(Vector2(home_point.x, home_point.z))
		_check(not scene.furniture_placement_valid and scene.furniture_placement_reason.contains("home"), "Home overlap is explained")
		await _press(JOY_BUTTON_A)
		_check(scene.furniture_placement_active and JSON.stringify(scene.landscape_state.document()) == saved, "Invalid overlap cannot commit")
		_aim(Vector2(0.125, 34.0))
		_check(not scene.furniture_placement_valid, "Rotated footprint cannot cross world bounds")
		await _press(JOY_BUTTON_B)
	_check(JSON.stringify(scene.landscape_state.document()) == saved, "Invalid-target cancellation leaves save unchanged")
	await _finish()

func _choose(style: String) -> bool:
	scene._open_build_browser("outdoor", true)
	for i in 4: await process_frame
	var card := _card(style)
	_check(card != null, "Current browser card remains reachable: " + style)
	if card == null: return false
	card.grab_focus()
	await _press(JOY_BUTTON_A)
	var selected: bool = scene.furniture_placement_active and scene.furniture_style_id == style
	_check(selected, "Controller chooses exact planter style: " + style)
	return selected

func _card(style: String) -> Button:
	for card: Button in scene._build_browser.cards:
		if str(card.get_meta("item")["id"]) == style: return card
	return null

func _node(id: int) -> MeshInstance3D:
	for node: MeshInstance3D in scene.composition_visual._furniture_nodes:
		if int(node.get_meta("composition_id")) == id: return node
	return null

func _aim(point: Vector2) -> void:
	scene.cursor = Vector3(point.x, 8.0, point.y)
	scene.terrain_cursor = scene.cursor
	scene._update_brush_preview()
	scene._update_furniture_validity()
	scene._update_furniture_preview()

func _press(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		for i in 4: await process_frame

func _finish() -> void:
	if is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("PLANTER_PLACEMENT_CHECK " + JSON.stringify({"ok": failures.is_empty(), "checks": checks, "failures": failures.size(), "messages": failures}))
	quit(0 if failures.is_empty() else 1)
