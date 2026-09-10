extends SceneTree

const World = preload("res://scripts/building_world.gd")
const State = preload("res://scripts/landscape_state.gd")

var scene: Node
var checks := 0
var failures := 0
const SCREENSHOT_DIR := "reports/screenshots/m2-hamlet"
const SCREENSHOT_PATH := SCREENSHOT_DIR + "/full-hamlet.png"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "mobile":
		print("M2_HAMLET_RENDER_UNAVAILABLE")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCREENSHOT_DIR))
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-hamlet-render-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene._player_restored and scene.backend != null and scene.backend.is_ready(), "native Mobile hamlet scene ready")
	if not scene._player_restored:
		_finish()
		return
	scene.set_process(false)

	# Build an intentional three-home cluster around one shared lane. The default
	# riverside cottage stays at 22,18; lodge and tall gable make the skyline and
	# footprint rhythm visibly different instead of reading as copied houses.
	var lodge_basis := Basis(Vector3.UP, deg_to_rad(-10.0)).scaled(Vector3.ONE * World.MINIATURE_SCALE)
	var lodge_id: String = scene.building_world.create_home_at("woodland_lodge", Transform3D(lodge_basis, Vector3(12.0, 8.0, 32.0)), scene.building_world.get_revision())
	var gable_basis := Basis(Vector3.UP, deg_to_rad(12.0)).scaled(Vector3.ONE * World.MINIATURE_SCALE)
	var gable_id: String = scene.building_world.create_home_at("village_gable", Transform3D(gable_basis, Vector3(31.0, 8.0, 31.0)), scene.building_world.get_revision())
	_check(not lodge_id.is_empty() and not gable_id.is_empty() and scene.building_world.get_buildings().size() == 3, "composition fixture contains three distinct saved homes")
	if scene.has_method("_sync_cottage_visuals"): scene._sync_cottage_visuals()

	# One irregular village lane ties all homes to the river crossing. Shorter
	# branches terminate near front gardens rather than slicing through houses.
	var main_path := scene.landscape_state.add_path("packed_earth", 1.0, [[8.0, 25.0], [14.0, 24.0], [21.0, 25.0], [29.0, 27.0], [35.0, 25.5], [38.5, 24.5]])
	var cottage_path := scene.landscape_state.add_path("stepping_stones", 0.75, [[21.0, 25.0], [21.5, 22.5], [22.0, 20.5]])
	var lodge_path := scene.landscape_state.add_path("packed_earth", 0.75, [[14.0, 24.0], [13.0, 27.0], [12.0, 29.5]])
	var gable_path := scene.landscape_state.add_path("cobblestone", 0.875, [[29.0, 27.0], [30.0, 28.5]])
	_check(main_path > 0 and cottage_path > 0 and lodge_path > 0 and gable_path > 0, "hamlet lane and home branches receive saved path IDs")
	for path_value in scene.landscape_state.paths:
		var path: Dictionary = path_value
		scene.landscape_state.clear_records_along_path(path.points, float(path.width))

	# The existing authored river runs around x=40.75. A timber bridge from the
	# low west bank to the far bank makes the road network terminate somewhere
	# meaningful rather than simply fading at the edge of the composition.
	var bridge_id := scene.landscape_state.add_bridge("timber", 1.0, [[38.5, 24.5], [43.5, 24.5]])
	_check(bridge_id > 0, "saved timber bridge crosses the authored river")
	scene.landscape_state.clear_records_along_path([[38.5, 24.5], [43.5, 24.5]], 1.25)

	# Private garden pockets make the homes feel inhabited before M3 introduces
	# actual inhabitants. Fences frame space without enclosing every centimetre.
	var garden_ids := [
		scene.landscape_state.add_composition("garden", "cottage_flowers", Vector2(17.0, 17.0), Vector2(3.0, 2.0), 1),
		scene.landscape_state.add_composition("garden", "kitchen_rows", Vector2(12.0, 36.0), Vector2(3.5, 2.5), 0),
		scene.landscape_state.add_composition("garden", "herb_garden", Vector2(35.0, 31.0), Vector2(2.25, 2.25), 1),
	]
	var fence_ids := [
		scene.landscape_state.add_composition("fence", "rustic_fence", Vector2(17.0, 15.75), Vector2(3.0, 0.25), 0),
		scene.landscape_state.add_composition("fence", "rustic_fence", Vector2(15.5, 17.0), Vector2(3.0, 0.25), 1),
		scene.landscape_state.add_composition("fence", "rustic_gate", Vector2(18.5, 17.0), Vector2(1.5, 0.375), 1),
		scene.landscape_state.add_composition("fence", "rustic_fence", Vector2(12.0, 37.375), Vector2(3.0, 0.25), 0),
	]
	_check(garden_ids.all(func(id): return int(id) > 0) and fence_ids.all(func(id): return int(id) > 0), "gardens fences and gate all become stable composition records")

	# Furniture sits at useful social/navigation points: bench and planter at the
	# central junction, signpost at the split, lantern near the bridge approach.
	var furniture_ids := [
		scene.landscape_state.add_composition("furniture", "bench", Vector2(23.5, 26.25), Vector2(1.5, 0.625), 0),
		scene.landscape_state.add_composition("furniture", "barrel_planter", Vector2(19.0, 25.75), Vector2(0.75, 0.75), 0),
		scene.landscape_state.add_composition("furniture", "signpost", Vector2(28.0, 26.0), Vector2(0.625, 0.625), 1),
		scene.landscape_state.add_composition("furniture", "lantern", Vector2(36.5, 25.5), Vector2(0.5, 0.5), 0),
	]
	_check(furniture_ids.all(func(id): return int(id) > 0), "all four street-furniture families are present in the composed hamlet")
	for object_value in scene.landscape_state.composition:
		var object: Dictionary = object_value
		scene.landscape_state.clear_records_in_footprint(object.position, object.size, int(object.yaw_quarters), 0.08)
	if scene.garden_visual: scene.garden_visual.reset_records(scene.landscape_state.records)

	_check(State.validate(scene.landscape_state.document()), "full hamlet composition remains valid saved landscape authority")
	scene._refresh_path_visual(true)
	scene._refresh_bridge_visual(true)
	scene._refresh_detail_visual(true)
	scene._update_presentation()
	await process_frame
	await process_frame
	var path_stats: Dictionary = scene.path_visual.stats()
	var composition_stats: Dictionary = scene.composition_visual.stats()
	_check(path_stats.geometry_cells > 0 and path_stats.styles.size() == 3, "full composition renders all three road languages")
	_check(int(composition_stats.get("bridge_count", 0)) == 1 and int(composition_stats.get("garden_count", 0)) == 3, "full composition renders bridge and all garden types")
	_check(int(composition_stats.get("fence_count", 0)) == 4 and int(composition_stats.get("furniture_count", 0)) == 4, "full composition renders fences gate and all furniture types")

	# Clean review framing: keep this as a real live-scene capture, simply hide the
	# editing HUD so the composition itself can be judged at normal miniature scale.
	if scene.hud: scene.hud.visible = false
	scene.cursor = Vector3(25.0, 8.0, 25.0)
	scene.terrain_cursor = scene.cursor
	scene.camera_yaw = -1.04
	scene.camera_pitch = 0.72
	scene.camera_distance = 42.0
	scene._update_camera()
	for _frame in 12: await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(not image.is_empty() and image.get_width() == 1280 and image.get_height() == 720, "1280x720 Mobile hamlet review capture exists")
	_check(image.save_png(SCREENSHOT_PATH) == OK, "full hamlet review capture saved")
	print("M2_HAMLET_RENDER_RESULT " + JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "renderer": RenderingServer.get_current_rendering_method(), "capture": SCREENSHOT_PATH, "buildings": scene.building_world.get_buildings().size(), "paths": scene.landscape_state.paths.size(), "composition": scene.landscape_state.composition.size()}))
	_finish()

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
	quit(1 if failures else 0)
