extends SceneTree

const Profile = preload("res://scripts/visual_lighting_profile.gd")
const LOOKS := [
	{"id": "baseline", "profile": "baseline"},
	{"id": "sky_fill", "profile": "sky_fill"},
	{"id": "warm_daylight", "profile": "warm_daylight"},
	{"id": "warm_meadow", "profile": "warm_daylight", "grass": "#82935e"},
]
const CAPTURE_DIR := "reports/screenshots/m2-hamlet/lighting-profiles"
var scene: Node
var checks := 0
var failures := 0
var captures := 0
var receipts: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "mobile":
		push_error("Lighting comparison requires the actual Mobile renderer")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://lighting-study-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored and scene.backend.is_ready(), "disposable current gameplay scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	scene.garden_visual.set_wind_enabled(false)
	scene.edit_pointer = Vector2(12, 12)
	scene._update_detail_hover()
	scene.hud.visible = false
	# Fixed practical camera: no auto exposure or depth-of-field blur.
	scene.camera.attributes = CameraAttributesPractical.new()
	var sun: DirectionalLight3D
	var world: WorldEnvironment
	for child in scene.get_children():
		if child is DirectionalLight3D: sun = child
		if child is WorldEnvironment: world = child
	var library: Object = scene.backend.terrain.mesher.library
	var grass: StandardMaterial3D = library.get_model(2).get_material_override(0)
	check(sun != null and world != null and grass != null, "study uses the gameplay light and native terrain material")
	if not sun or not world or not grass:
		await _finish()
		return
	# M1PatchGenerator.build_library creates these materials per scene, not
	# from imported resources. Only this disposable fixture is recoloured.
	check(grass.resource_path.is_empty(), "ground palette experiment is scene-private")
	var grass_before := grass.albedo_color
	var environment_before: Environment = world.environment
	var sun_before := sun.transform
	var sun_colour_before := sun.light_color
	var sun_energy_before := sun.light_energy
	var environment_snapshot := [environment_before.sky, environment_before.ambient_light_source, environment_before.ambient_light_energy, environment_before.tonemap_exposure]
	check(DirAccess.make_dir_recursive_absolute(CAPTURE_DIR) == OK, "capture directory is writable")
	var cameras := [
		{"id": "normal", "yaw": PI * 1.20, "distance": 16.0},
		{"id": "close", "yaw": PI * 1.20, "distance": 7.0},
		{"id": "reverse", "yaw": PI * 0.20, "distance": 16.0},
		{"id": "edited", "yaw": PI * 1.20, "distance": 16.0},
	]
	for camera_spec in cameras:
		if camera_spec["id"] == "edited":
			# Use the actual new-floor pipeline, not a prettier fixed model.
			scene._begin_next_storey()
			check(scene.portion_valid and scene._commit_portion_placement(), "edited view contains a real editable upper floor")
			scene._presentation_key = ""
			scene._update_presentation()
			scene.garden_visual.set_wind_enabled(false)
			scene.hud.visible = false
		var buildings_before: String = scene.building_world.serialize_document()
		var landscape_before: String = JSON.stringify(scene.landscape_state.document())
		scene.camera_yaw = camera_spec["yaw"]
		scene.camera_pitch = 0.40
		scene.camera_distance = camera_spec["distance"]
		scene._update_camera()
		var camera_transform: Transform3D = scene.camera.global_transform
		var pixel_hashes: Dictionary = {}
		for look in LOOKS:
			var profile := load("res://resources/visual_profiles/%s.tres" % look["profile"]) as Profile
			check(profile != null, "profile loads")
			if not profile: continue
			world.environment = environment_before
			grass.albedo_color = Color(look["grass"]) if look.has("grass") else grass_before
			check(profile.apply_to(sun, world), "apply " + str(look["id"]))
			check(world.environment != environment_before, "private environment used")
			check([environment_before.sky, environment_before.ambient_light_source, environment_before.ambient_light_energy, environment_before.tonemap_exposure] == environment_snapshot, "original environment is untouched")
			check(world.environment.tonemap_exposure == environment_before.tonemap_exposure and world.environment.tonemap_mode == environment_before.tonemap_mode, "exposure and tonemapper are fixed")
			check(scene.camera.global_transform.is_equal_approx(camera_transform), "camera framing is identical across looks")
			for frame in 24: await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			check(not image.is_empty() and image.get_size() == Vector2i(1280, 720), "actual Mobile image exists")
			var path := "%s/%s-%s.png" % [CAPTURE_DIR, camera_spec["id"], look["id"]]
			check(image.save_png(path) == OK, "capture saved")
			var pixel_hash := hash(image.get_data())
			pixel_hashes[look["id"]] = pixel_hash
			receipts.append({"view": camera_spec["id"], "look": look["id"], "path": path, "pixel_hash": pixel_hash, "sun": str(sun.rotation_degrees), "sky_energy": profile.sky_energy, "grass": grass.albedo_color.to_html(), "exposure": world.environment.tonemap_exposure})
			captures += 1
			check(scene.building_world.serialize_document() == buildings_before, "look does not change building records")
			check(JSON.stringify(scene.landscape_state.document()) == landscape_before, "look does not change planting/path records")
		check(pixel_hashes.get("warm_daylight") != pixel_hashes.get("warm_meadow"), "ground colour experiment changes rendered pixels")
	grass.albedo_color = grass_before
	world.environment = environment_before
	sun.transform = sun_before
	sun.light_color = sun_colour_before
	sun.light_energy = sun_energy_before
	check(grass.albedo_color == grass_before and world.environment == environment_before and sun.transform == sun_before, "comparison restores its source look")
	var receipt := FileAccess.open(CAPTURE_DIR + "/manifest.json", FileAccess.WRITE)
	check(receipt != null, "comparison manifest is writable")
	if receipt:
		receipt.store_string(JSON.stringify({"source": OS.get_environment("GITHUB_SHA"), "engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(), "captures": receipts}, "\t"))
		receipt.close()
	await _finish()

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	check(captures == 16, "all four looks have normal/close/reverse/edited captures")
	print("LIGHTING_PROFILE_RENDER " + JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "captures": captures, "capture_directory": CAPTURE_DIR, "renderer": RenderingServer.get_current_rendering_method()}))
	quit(1 if failures else 0)
