extends SceneTree

var checks := 0
var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-furniture-placement-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene._player_restored, "native street-furniture scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	var before: Dictionary = scene.landscape_state.document()
	var history_before: int = scene._history_tags.size()

	await _press(JOY_BUTTON_DPAD_UP)
	_check(scene._browser_open and scene._build_browser.category == "homes", "D-pad Up opens the world build browser")
	if not scene._browser_open:
		await _finish()
		return
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	_check(scene._build_browser.category == "outdoor", "world build browser reaches Outdoor")
	if scene._build_browser.category != "outdoor":
		await _finish()
		return
	var bench_card := _browser_card("bench")
	var lantern_card := _browser_card("lantern")
	var signpost_card := _browser_card("signpost")
	var barrel_card := _browser_card("barrel_planter")
	_check(bench_card != null and lantern_card != null and signpost_card != null and barrel_card != null, "Outdoor browser exposes all four street-furniture choices")
	if bench_card == null:
		await _finish()
		return
	if lantern_card != null and signpost_card != null and barrel_card != null:
		var bench_item: Dictionary = bench_card.get_meta("item", {})
		var lantern_item: Dictionary = lantern_card.get_meta("item", {})
		var signpost_item: Dictionary = signpost_card.get_meta("item", {})
		var barrel_item: Dictionary = barrel_card.get_meta("item", {})
		_check(str(bench_item.get("name", "")).begins_with("Village bench") and str(lantern_item.get("name", "")).begins_with("Path lantern") and str(signpost_item.get("name", "")).begins_with("Wooden signpost") and str(barrel_item.get("name", "")).begins_with("Barrel planter"), "all four street-furniture choices are visually named")

	bench_card.grab_focus()
	await _press(JOY_BUTTON_A)
	_check(scene.furniture_placement_active and scene.furniture_style_id == "bench" and scene.view_context == "terrain", "bench selection enters world placement")
	var random_yaw := float(scene.furniture_yaw_degrees)
	_check(is_equal_approx(random_yaw, snappedf(random_yaw, 15.0)), "furniture starts on a randomized 15-degree facing")
	_aim(Vector2(36.0, 34.0))
	var preview_node := scene.composition_visual.get_node_or_null("FurniturePreview") as MeshInstance3D
	_check(scene.furniture_placement_valid and preview_node != null and preview_node.mesh != null, "bench gets a valid live placement preview with real geometry")
	scene._rotate_furniture(1)
	_check(is_equal_approx(scene.furniture_yaw_degrees, fposmod(random_yaw + 15.0, 360.0)) and scene.landscape_state.document() == before, "furniture keeps gentle manual nudging from its randomized facing")
	scene.precision_mode = true
	scene._rotate_furniture(1)
	var committed_yaw := fposmod(random_yaw + 16.0, 360.0)
	_check(is_equal_approx(scene.furniture_yaw_degrees, committed_yaw) and scene.landscape_state.document() == before, "precision mode gives furniture one-degree adjustment")
	scene.precision_mode = false
	await _press(JOY_BUTTON_A)
	var bench_committed: bool = not scene.furniture_placement_active and scene.landscape_state.composition.size() == 1
	_check(bench_committed, "A commits the bench")
	if not bench_committed:
		await _finish()
		return
	var bench: Dictionary = scene.landscape_state.composition[0]
	_check(bench.kind == "furniture" and bench.style_id == "bench" and is_equal_approx(float(bench.yaw_degrees), committed_yaw), "bench saves randomized precise orientation")
	_check(scene._history_tags.size() == history_before + 1, "bench placement is one landscape undo transaction")
	_check(scene.composition_visual.stats().furniture_count == 1 and scene.composition_visual.stats().furniture_geometry_cells > 0, "bench builds fine disposable presentation")

	var styles := [
		["lantern", Vector2(0.5, 0.5), Vector2(34.0, 34.0)],
		["signpost", Vector2(0.625, 0.625), Vector2(32.0, 34.0)],
		["barrel_planter", Vector2(0.75, 0.75), Vector2(30.0, 34.0)],
	]
	for entry in styles:
		scene.furniture_style_id = entry[0]
		scene.furniture_size = entry[1]
		scene.furniture_yaw_quarters = 0
		scene._begin_furniture_placement()
		_check(is_equal_approx(scene.furniture_yaw_degrees, snappedf(scene.furniture_yaw_degrees, 15.0)), "%s gets a randomized fine-step facing" % entry[0])
		_aim(entry[2])
		_check(scene.furniture_placement_valid, "%s has a valid placement target" % entry[0])
		_check(scene._commit_furniture(), "%s commits through the shared placement transaction" % entry[0])
	_check(scene.landscape_state.composition.size() == 4 and scene.composition_visual.stats().furniture_count == 4, "all four furniture styles coexist in saved authority and presentation")
	var after: Dictionary = scene.landscape_state.document()
	var saved := JSON.stringify(after)
	_check(scene._save_all() and scene._reload_all(), "street-furniture save and reload succeeds")
	_check(JSON.stringify(scene.landscape_state.document()) == saved and scene.composition_visual.stats().furniture_count == 4, "reload preserves and rebuilds all furniture records")

	var cancel_before := JSON.stringify(scene.landscape_state.document())
	scene.furniture_style_id = "bench"
	scene.furniture_size = Vector2(1.5, 0.625)
	scene._begin_furniture_placement()
	_aim(Vector2(28.0, 34.0))
	await _press(JOY_BUTTON_B)
	_check(not scene.furniture_placement_active and JSON.stringify(scene.landscape_state.document()) == cancel_before, "B cancels furniture preview without authority drift")

	var home: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var home_center: Vector3 = (home["transform"] as Transform3D).origin
	scene._begin_furniture_placement()
	_aim(Vector2(home_center.x, home_center.z))
	_check(not scene.furniture_placement_valid and scene.furniture_placement_reason.contains("home"), "street furniture cannot be placed inside a home")
	await _press(JOY_BUTTON_A)
	_check(scene.furniture_placement_active and scene.landscape_state.composition.size() == 4, "invalid home-overlap furniture cannot commit")
	scene._cancel_furniture_placement()

	# The street-scale 2x flower arch anchors at 6.875m: still placeable because
	# COMPOSITION_MAX_SIZE grew past the original 6.0 small-prop cap.
	scene.furniture_style_id = "flower_arch"
	scene.furniture_size = Vector2(6.875, 3.0)
	scene.furniture_yaw_quarters = 0
	scene._begin_furniture_placement()
	_aim(Vector2(40.0, 20.0))
	_check(scene.furniture_placement_valid, "street-scale flower arch has a valid placement target")
	_check(scene._commit_furniture(), "street-scale flower arch commits")
	scene.furniture_size = Vector2(8.0, 3.0)
	scene._begin_furniture_placement()
	_aim(Vector2(40.0, 24.0))
	_check(not scene.furniture_placement_valid and scene.furniture_placement_reason.contains("detail limit"), "furniture beyond the 7.5m cap is still rejected")
	scene._cancel_furniture_placement()
	await _finish()

func _browser_card(item_id: String) -> Button:
	if not scene._build_browser:
		return null
	for card in scene._build_browser.cards:
		var item: Dictionary = card.get_meta("item", {})
		if str(item.get("id", "")) == item_id:
			return card
	return null

func _aim(point: Vector2) -> void:
	scene.cursor = Vector3(point.x, 8.0, point.y)
	scene.terrain_cursor = scene.cursor
	scene._update_brush_preview()
	scene._update_furniture_validity()
	scene._update_furniture_preview()

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
