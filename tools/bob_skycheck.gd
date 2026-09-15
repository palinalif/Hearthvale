extends SceneTree
## Sky-band check for the step-3 camera clamp.
## Repaints the procedural sky in two unmistakable probes — UPPER hemisphere
## (sky_top/sky_horizon) MAGENTA, LOWER hemisphere (ground_*) CYAN — then renders
## the hamlet review framing at several pitches and counts how many in-frame
## pixels are actual SKY. This is the decisive test of Pali's ask ("camera cannot
## tilt up far enough to show the sky band"): at the live floor 0.55 the magenta
## count must be exactly 0, while the old floor 0.08 must frame a large sky band.
##
## Run: DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 900 \
##   /opt/data/tools/godot/Godot_v4.7.2-stable_linux.x86_64 --max-fps 60 \
##   --path . --renderer mobile --script tools/bob_skycheck.gd

const OUT_DIR := "reports/screenshots/step3-skycheck"
const LOG_PATH := OUT_DIR + "/skycheck.txt"
## geometry: sky enters the frame's top edge at fov/2 = 26 deg = 0.4538 rad
const PITCHES: Array[float] = [0.72, 0.62, 0.4538, 0.30, 0.08]

var scene: Node
var log_file: FileAccess

func _initialize() -> void:
	call_deferred("_run")

func _log(line: String) -> void:
	print(line)
	if log_file:
		log_file.store_line(line)
		log_file.flush()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	log_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://skycheck-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline: int = Time.get_ticks_msec() + 120000
	while (not scene._player_restored or not scene.backend or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not scene._player_restored:
		_log("SKYCHECK scene not ready")
		quit(2)
		return
	scene.set_process(false)
	if scene.hud: scene.hud.visible = false
	var world: WorldEnvironment = _find_environment(scene)
	var environment: Environment = world.environment
	var sky_material := environment.sky.sky_material as ProceduralSkyMaterial
	sky_material.sky_top_color = Color(1, 0, 1)
	sky_material.sky_horizon_color = Color(1, 0, 1)
	sky_material.ground_horizon_color = Color(0, 1, 1)
	sky_material.ground_bottom_color = Color(0, 1, 1)
	sky_material.sky_energy_multiplier = 1.0
	sky_material.ground_energy_multiplier = 1.0
	environment.fog_sky_affect = 0.0
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.88, 0.86, 0.82)
	environment.ambient_light_energy = 1.0

	scene.cursor = Vector3(25.0, 8.0, 25.0)
	scene.terrain_cursor = scene.cursor
	scene.camera_yaw = -1.04
	scene.camera_distance = 42.0
	for pitch in PITCHES:
		scene.camera_pitch = pitch
		scene._update_camera()
		for _i in 6:
			await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		var w := image.get_width()
		var h := image.get_height()
		var data := image.get_data()
		var sky_pixels := 0
		var void_pixels := 0
		var top_sky := 0
		var top_void := 0
		var top_total := 0
		var first_sky_row := h
		for y in h:
			var row_sky := 0
			for x in range(0, w, 2):
				var offset := (y * w + x) * 4
				var r := int(data[offset])
				var g := int(data[offset + 1])
				var b := int(data[offset + 2])
				if y < 90: top_total += 1
				if r > 120 and b > 120 and g < r - 60 and g < b - 60:
					sky_pixels += 1
					row_sky += 1
					if y < 90: top_sky += 1
				elif g > 120 and b > 120 and r < g - 60 and r < b - 60:
					void_pixels += 1
					if y < 90: top_void += 1
			if row_sky > 0 and first_sky_row == h:
				first_sky_row = y
		_log("SKYCHECK pitch=%.4f sky_px=%d (%.2f%%) void_px=%d (%.2f%%) top90_sky=%d top90_void=%d/%d first_sky_row=%d" % [
			pitch, sky_pixels, 100.0 * float(sky_pixels) / float((w / 2) * h),
			void_pixels, 100.0 * float(void_pixels) / float((w / 2) * h),
			top_sky, top_void, top_total, first_sky_row])
		image.save_png("%s/pitch-%.4f.png" % [OUT_DIR, pitch])
	_log("SKYCHECK done")
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	quit(0)

func _find_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node
	for child in node.get_children():
		var found := _find_environment(child)
		if found:
			return found
	return null