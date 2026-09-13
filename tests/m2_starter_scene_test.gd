extends SceneTree
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.starter_hamlet_in_tests = true
	scene.checkpoint_root = "user://m2-starter-integration-%d" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 90000
	while not scene._player_restored and Time.get_ticks_msec() < deadline:
		await process_frame
	check(scene._player_restored, "Native main scene reached ready")
	if scene._player_restored:
		check(scene._starter_seeded, "Fresh scene received starter exactly once")
		check(scene.building_world.get_document()["buildings"].size() == 3, "Fresh scene has three homes")
		check(scene._valley_surround != null, "Scenic surround is present")
		if scene._valley_surround != null: print("STARTER_SURROUND " + JSON.stringify(scene._valley_surround.stats()))
		var before := JSON.stringify(scene.building_world.get_document())
		check(not scene._seed_starter_hamlet(), "Second starter seed refused")
		check(before == JSON.stringify(scene.building_world.get_document()), "Second seed leaves homes unchanged")
		_check_expanded_placement(scene)
		for style in ["well", "chopping_block", "log_stack"]:
			check(style in scene.FURNITURE_STYLE_ORDER, style + " is available in the furniture catalogue")
		for context in ["terrain", "building"]:
			scene.view_context = context
			for corner: Vector3 in [Vector3(0.5,8,0.5), Vector3(63.5,8,0.5), Vector3(0.5,8,63.5), Vector3(63.5,8,63.5)]:
				scene.cursor = corner
				for yaw in range(8):
					scene.camera_yaw = float(yaw) * TAU / 8.0
					scene.camera_distance = 52.0
					scene._update_camera()
					var position: Vector3 = scene.camera.position
					check(position.x >= 0.0 and position.x <= 64.0 and position.z >= 0.0 and position.z <= 64.0, "Camera remains within native extent")
		check(scene._save_all(), "Expanded starter world saves")
		var saved: Dictionary = scene.building_world.get_document()
		check(scene.backend.load_world(), "Expanded starter checkpoint reloads")
		var expected = JSON.parse_string(JSON.stringify(saved["buildings"]))
		check(scene.backend.loaded_building_document["buildings"] == expected, "Reload retains starter building records")
		check(scene.backend.loaded_building_document["landscape"]["composition"].size() == 14, "Reload retains all props and gardens")
		print("STARTER_NATIVE_READY " + JSON.stringify({"world_size":str(scene.backend.world_size()), "homes":3, "save_reload":true}))
	scene._shutting_down = true
	scene.queue_free()
	await process_frame
	await process_frame
	print("STARTER_SCENE_RESULT " + JSON.stringify({"ok":failures.is_empty(), "checks":checks, "failures":failures.size(), "messages":failures}))
	quit(0 if failures.is_empty() else 1)

func _check_expanded_placement(scene: Node) -> void:
	# Exercise live placement, not just the shared constant. Section editing also
	# inherits this bound, so the new meadow must not stop at the old 47.75 line.
	var homes := JSON.stringify(scene.building_world.get_document())
	var landscape := JSON.stringify(scene.landscape_state.document())
	scene.view_context = "building"
	for point: Vector3 in [Vector3(56,10,44), Vector3(24,10,55)]:
		scene.cursor = point
		scene._begin_new_building_placement("woodland_lodge")
		check(scene.building_placement_active, "New home placement begins in expanded land")
		scene.building_placement_target = point
		scene._snap_building_placement_to_ground()
		scene._update_building_preview_transform()
		check(scene.building_placement_valid, "Home can use expanded land at %s: %s" % [point, scene.building_placement_reason])
		for outside: Vector3 in [Vector3(64,10,56), Vector3(56,10,64), Vector3(-0.5,10,56)]:
			scene.building_placement_target = outside
			scene._update_building_preview_transform()
			check(not scene.building_placement_valid and "Outside" in str(scene.building_placement_reason), "House footprint still rejects the actual map edge")
		scene._cancel_building_placement()
	check(homes == JSON.stringify(scene.building_world.get_document()), "Expanded placement cancellation preserves all homes")
	check(landscape == JSON.stringify(scene.landscape_state.document()), "Expanded placement cancellation preserves all planting and props")
