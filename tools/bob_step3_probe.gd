extends SceneTree
## Step-3 measurement probe (Bob, 2026-09-15).
## Run (background, log to file):
##   DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 1800 \
##     /opt/data/tools/godot/Godot_v4.7.2-stable_linux.x86_64 --max-fps 60 \
##     --path . --renderer mobile --script tools/bob_step3_probe.gd
##
## Prints (a) world geometry facts (patch size, voxel scale, terrain surface
## height, island extent) and (b) a PITCH SWEEP of the hamlet review framing
## with the backdrop repainted MAGENTA so "empty void in frame" is measurable:
## for every pitch it reports how many top-band pixels are still backdrop.
## PNGs land in reports/screenshots/step3-probe/ for eyeballing.

const OUT_DIR := "reports/screenshots/step3-probe"
const LOG_PATH := OUT_DIR + "/probe.txt"
const PITCHES: Array[float] = [0.72, 0.85, 0.95, 1.05, 1.15, 1.25, 1.40]
const BAND_ROWS := 40
const SETTLE_FRAMES := 4
const WIDTH := 640
const HEIGHT := 360

var scene: Node
var sky_material: ProceduralSkyMaterial
var log_file: FileAccess

func _initialize() -> void:
	call_deferred("_run")

func _log(line: String) -> void:
	print(line)
	if log_file:
		log_file.store_line(line)
		log_file.flush()

func _settle(frames: int) -> void:
	for _i in frames:
		await RenderingServer.frame_post_draw

func _is_backdrop_raw(r: int, g: int, b: int) -> bool:
	var rf := r / 255.0
	var gf := g / 255.0
	var bf := b / 255.0
	return rf > 0.35 and bf > 0.35 and gf < minf(rf, bf) - 0.15

func _run() -> void:
	root.size = Vector2i(WIDTH, HEIGHT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	log_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://step3-probe-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline: int = Time.get_ticks_msec() + 120000
	while (not scene._player_restored or not scene.backend or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not scene._player_restored:
		_log("PROBE scene not ready")
		quit(2)
		return
	scene.set_process(false)
	_log("PROBE scene ready")

	# ---- world geometry facts ----
	var backend: Node = scene.backend
	var terrain: Node = backend.terrain
	_log("PROBE world_size=%s patch_size=%s voxel_scale=%.4f" % [str(backend.world_size()), str(backend.patch_size), float(backend.voxel_scale)])
	_log("PROBE terrain_scale=%s terrain_bounds=%s" % [str(terrain.scale), str(terrain.bounds)])
	for column in [Vector2i(24, 24), Vector2i(12, 32), Vector2i(40, 24), Vector2i(2, 2), Vector2i(46, 46), Vector2i(0, 0)]:
		var top_cell := _top_cell(backend, column.x, column.y)
		_log("PROBE surface x=%d z=%d top_cell_y=%d world_y=%.3f" % [column.x, column.y, top_cell, (float(top_cell) + 0.5) * float(backend.voxel_scale)])

	# ---- pitch sweep with a magenta backdrop ----
	var world: WorldEnvironment = _find_environment(scene)
	var environment: Environment = world.environment
	sky_material = environment.sky.sky_material as ProceduralSkyMaterial
	var saved := {
		"ambient_source": environment.ambient_light_source,
		"ambient_color": environment.ambient_light_color,
		"ambient_energy": environment.ambient_light_energy,
		"top": sky_material.sky_top_color,
		"horizon": sky_material.sky_horizon_color,
		"ground_horizon": sky_material.ground_horizon_color,
		"ground_bottom": sky_material.ground_bottom_color,
		"top_energy": sky_material.sky_energy_multiplier,
		"ground_energy": sky_material.ground_energy_multiplier,
		"fog_sky": environment.fog_sky_affect,
	}
	sky_material.sky_top_color = Color(1, 0, 1)
	sky_material.sky_horizon_color = Color(1, 0, 1)
	sky_material.ground_horizon_color = Color(1, 0, 1)
	sky_material.ground_bottom_color = Color(1, 0, 1)
	sky_material.sky_energy_multiplier = 1.0
	sky_material.ground_energy_multiplier = 1.0
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.88, 0.86, 0.82)
	environment.ambient_light_energy = 1.0
	environment.fog_sky_affect = 0.0

	scene.cursor = Vector3(25.0, 8.0, 25.0)
	scene.terrain_cursor = scene.cursor
	scene.camera_yaw = -1.04
	scene.camera_distance = 42.0
	for pitch in PITCHES:
		scene.camera_pitch = pitch
		scene._update_camera()
		await _settle(SETTLE_FRAMES)
		var image: Image = root.get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		var w := image.get_width()
		var h := image.get_height()
		var data := image.get_data()
		var band_total := 0
		var band_backdrop := 0
		var whole_backdrop := 0
		var first_clean_row := h
		# Sample every 2nd pixel on both axes (1/4 of the frame) so the GDScript
		# loop stays cheap; ratios are unaffected by the uniform sampling.
		for y in range(0, h, 2):
			var row_backdrop := 0
			var row_samples := 0
			for x in range(0, w, 2):
				var offset := (y * w + x) * 4
				row_samples += 1
				if _is_backdrop_raw(data[offset], data[offset + 1], data[offset + 2]):
					whole_backdrop += 1
					row_backdrop += 1
			if y < BAND_ROWS:
				band_total += row_samples
				band_backdrop += row_backdrop
			if row_backdrop == 0 and first_clean_row == h:
				first_clean_row = y
		_log("PROBE pitch=%.2f backdrop=%.1f%% top%d=%.1f%% first_clean_row=%d/%d" % [
			pitch, 100.0 * float(whole_backdrop) / float((w / 2) * (h / 2)),
			BAND_ROWS, 100.0 * float(band_backdrop) / float(maxi(band_total, 1)), first_clean_row, h])
		image.save_png("%s/pitch-%.2f.png" % [OUT_DIR, pitch])

	# ---- restore ----
	environment.ambient_light_source = int(saved["ambient_source"])
	environment.ambient_light_color = saved["ambient_color"]
	environment.ambient_light_energy = float(saved["ambient_energy"])
	sky_material.sky_top_color = saved["top"]
	sky_material.sky_horizon_color = saved["horizon"]
	sky_material.ground_horizon_color = saved["ground_horizon"]
	sky_material.ground_bottom_color = saved["ground_bottom"]
	sky_material.sky_energy_multiplier = float(saved["top_energy"])
	sky_material.ground_energy_multiplier = float(saved["ground_energy"])
	environment.fog_sky_affect = float(saved["fog_sky"])
	_log("PROBE done")
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	quit(0)

func _top_cell(backend: Node, cell_x: int, cell_z: int) -> int:
	var limit: int = int(backend.patch_size.y) - 1
	var y := limit
	while y > 0:
		if backend.voxel_at(Vector3i(cell_x, y, cell_z)) != 0:
			return y
		y -= 1
	return -1

func _find_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node
	for child in node.get_children():
		var found := _find_environment(child)
		if found:
			return found
	return null