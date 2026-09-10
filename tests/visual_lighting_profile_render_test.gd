extends SceneTree

const Profile = preload("res://scripts/visual_lighting_profile.gd")
const PROFILE_PATHS := [
	"res://resources/visual_profiles/baseline.tres",
	"res://resources/visual_profiles/sky_fill.tres",
	"res://resources/visual_profiles/warm_daylight.tres",
]
const CAPTURE_DIR := "reports/screenshots/m2-hamlet/lighting-profiles"
var scene: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "mobile":
		push_error("This comparison requires the actual Mobile renderer")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://lighting-study-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "disposable gameplay scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building")
	scene.garden_visual.set_wind_enabled(false)
	scene.hud.visible = false
	var sun: DirectionalLight3D
	var world: WorldEnvironment
	for child in scene.get_children():
		if child is DirectionalLight3D: sun = child
		if child is WorldEnvironment: world = child
	check(sun != null and world != null, "comparison uses the gameplay sun and environment")
	if not sun or not world:
		await _finish()
		return
	var original_environment: Environment = world.environment
	var saved_buildings: String = scene.building_world.serialize_document()
	var saved_landscape: Dictionary = scene.landscape_state.document()
	var original_ambient: float = original_environment.ambient_light_energy
	var original_source: int = original_environment.ambient_light_source
	var original_sky: Sky = original_environment.sky
	var original_exposure: float = original_environment.tonemap_exposure
	check(DirAccess.make_dir_recursive_absolute(CAPTURE_DIR) == OK, "capture directory is writable")
	var cameras := [
		{"id": "normal", "yaw": PI * 1.20, "distance": 16.0},
		{"id": "close", "yaw": PI * 1.20, "distance": 7.0},
		{"id": "reverse", "yaw": PI * 0.20, "distance": 16.0},
	]
	for camera_spec in cameras:
		scene.camera_yaw = camera_spec["yaw"]
		scene.camera_pitch = 0.40
		scene.camera_distance = camera_spec["distance"]
		scene._update_camera()
		var camera_transform: Transform3D = scene.camera.global_transform
		for path in PROFILE_PATHS:
			var profile := load(path) as Profile
			check(profile != null, "profile loads: " + path)
			if not profile: continue
			world.environment = original_environment
			check(profile.apply_to(sun, world), "apply profile: " + str(profile.profile_id))
			check(world.environment != original_environment, "profile uses a private Environment")
			check(original_environment.sky == original_sky and original_environment.ambient_light_source == original_source and is_equal_approx(original_environment.ambient_light_energy, original_ambient), "source environment remains unmodified")
			check(is_equal_approx(world.environment.tonemap_exposure, original_exposure), "exposure stays fixed across lighting comparisons")
			check(scene.camera.global_transform.is_equal_approx(camera_transform), "profile application preserves camera framing")
			for frame in 12: await RenderingServer.frame_post_draw
			var image: Image = root.get_texture().get_image()
			check(not image.is_empty() and image.get_size() == Vector2i(1280, 720), "actual Mobile image is present")
			var image_path := "%s/%s-%s.png" % [CAPTURE_DIR, camera_spec["id"], str(profile.profile_id)]
			check(image.save_png(image_path) == OK, "capture saved: " + image_path)
	check(scene.building_world.serialize_document() == saved_buildings, "lighting study leaves authoritative building data unchanged")
	check(scene.landscape_state.document() == saved_landscape, "lighting study leaves planting, paths and composition authority unchanged")
	await _finish()

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("LIGHTING_PROFILE_RENDER " + JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "capture_directory": CAPTURE_DIR, "renderer": RenderingServer.get_current_rendering_method()}))
	quit(1 if failures else 0)
