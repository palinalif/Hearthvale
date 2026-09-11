extends SceneTree

const Profile = preload("res://scripts/visual_lighting_profile.gd")
const LOOKS := [
	{"id": "sky_fill", "profile": "sky_fill"},
	{"id": "sky_depth", "profile": "sky_depth"},
	{"id": "sky_soft", "profile": "sky_soft"},
]
const CAPTURE_DIR := ".tools/lighting-polish/captures"
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
	scene.checkpoint_root = "user://lighting-polish-%s" % Time.get_ticks_usec()
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
	scene.camera.attributes = CameraAttributesPractical.new()
	var sun: DirectionalLight3D
	var world: WorldEnvironment
	for child in scene.get_children():
		if child is DirectionalLight3D: sun = child
		if child is WorldEnvironment: world = child
	check(sun != null and world != null and world.environment != null, "study uses gameplay sun and environment")
	if not sun or not world or not world.environment:
		await _finish()
		return
	check(DirAccess.make_dir_recursive_absolute(CAPTURE_DIR) == OK, "capture directory is writable")
	var environment_before: Environment = world.environment
	var source_environment_snapshot := [environment_before.sky, environment_before.ambient_light_source, environment_before.ambient_light_energy, environment_before.tonemap_exposure, environment_before.tonemap_mode, environment_before.background_mode, environment_before.background_color]
	var sun_transform_before := sun.transform
	var sun_colour_before := sun.light_color
	var sun_energy_before := sun.light_energy
	var original: String = scene.building_world.serialize_document()
	var cases := [
		{"id": "cottage-front", "yaw": 1.20, "distance": 9.0, "fixture": "base"},
		{"id": "l-shape", "yaw": 1.15, "distance": 12.0, "fixture": "l_shape"},
		{"id": "t-shape", "yaw": 0.88, "distance": 12.0, "fixture": "t_shape"},
		{"id": "u-courtyard", "yaw": 1.00, "distance": 12.0, "fixture": "u_shape"},
		{"id": "upper-floor", "yaw": 1.20, "distance": 11.0, "fixture": "upper"},
	]
	for spec in cases:
		check(scene.building_world.load_serialized_document(original), "restore clean lighting fixture")
		scene._presentation_key = ""
		scene._update_presentation()
		var fixture := str(spec["fixture"])
		if fixture in ["l_shape", "t_shape", "u_shape"]:
			check(scene._apply_house_shape_preset(fixture), "%s comparison uses house-shape API" % fixture)
		elif fixture == "upper":
			scene._begin_next_storey()
			check(scene.portion_valid and scene._commit_portion_placement(), "upper comparison uses add-floor API")
		scene._presentation_key = ""
		scene._update_presentation()
		scene.garden_visual.set_wind_enabled(false)
		scene.hud.visible = false
		var buildings_before: String = scene.building_world.serialize_document()
		var landscape_before: String = JSON.stringify(scene.landscape_state.document())
		scene.camera_yaw = PI * float(spec["yaw"])
		scene.camera_pitch = 0.43
		scene.camera_distance = float(spec["distance"])
		scene._update_camera()
		var camera_transform: Transform3D = scene.camera.global_transform
		for look in LOOKS:
			world.environment = environment_before
			sun.transform = sun_transform_before
			sun.light_color = sun_colour_before
			sun.light_energy = sun_energy_before
			var profile_id := str(look["profile"])
			var profile := load("res://resources/visual_profiles/%s.tres" % profile_id) as Profile
			check(profile != null, "%s profile loads" % str(look["id"]))
			if not profile: continue
			check(profile.apply_to(sun, world), "apply %s" % str(look["id"]))
			check(world.environment != environment_before and world.environment.sky != null, "candidate owns private sky environment")
			check([environment_before.sky, environment_before.ambient_light_source, environment_before.ambient_light_energy, environment_before.tonemap_exposure, environment_before.tonemap_mode, environment_before.background_mode, environment_before.background_color] == source_environment_snapshot, "source environment remains untouched")
			check(scene.camera.global_transform.is_equal_approx(camera_transform), "camera framing is identical across looks")
			# This is visual evidence, not a byte-perfect renderer determinism gate.
			# Warm a bounded number of frames and capture; animated water/shadows are
			# allowed to evolve naturally between otherwise matched comparisons.
			for frame in 8: await RenderingServer.frame_post_draw
			var image: Image = root.get_texture().get_image()
			check(not image.is_empty() and image.get_size() == Vector2i(1280, 720), "actual Mobile image exists")
			var path := "%s/%s-%s.png" % [CAPTURE_DIR, spec["id"], look["id"]]
			check(image.save_png(path) == OK, "capture saved")
			captures += 1
			receipts.append({"view": spec["id"], "look": look["id"], "path": path, "sun": str(sun.rotation_degrees), "sun_energy": sun.light_energy, "ambient_energy": world.environment.ambient_light_energy, "ambient_source": world.environment.ambient_light_source, "sky_contribution": world.environment.ambient_light_sky_contribution, "exposure": world.environment.tonemap_exposure})
			check(scene.building_world.serialize_document() == buildings_before, "look does not change building records")
			check(JSON.stringify(scene.landscape_state.document()) == landscape_before, "look does not change landscape records")
	world.environment = environment_before
	sun.transform = sun_transform_before
	sun.light_color = sun_colour_before
	sun.light_energy = sun_energy_before
	check(world.environment == environment_before and sun.transform == sun_transform_before and sun.light_color == sun_colour_before and is_equal_approx(sun.light_energy, sun_energy_before), "comparison restores exact source lighting")
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
	check(captures == 15, "sky-fill control/depth/soft looks cover cottage L T U and upper-floor views")
	print("LIGHTING_POLISH_RENDER " + JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "captures": captures, "capture_directory": CAPTURE_DIR, "renderer": RenderingServer.get_current_rendering_method()}))
	quit(1 if failures else 0)
