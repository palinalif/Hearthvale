extends SceneTree

## Step-4 diagnostic: from-hamlet rim captures + an objective "void" measurement.
##
## Boots the REAL Mobile scene, rebuilds the three-home hamlet fixture (same as
## tests/m2_hamlet_composition_render_test.gd) and captures the live hamlet
## review camera looking toward each boundary direction. For every direction it
## also renders a second frame with the world background forced to flat magenta:
## because the pitch clamp keeps the sky out of frame (step-3 skycheck = 0 sky
## pixels at 0.72), any strongly-magenta pixel is a hole in the world — the
## drop-off/void Pali reported. Read-only: it mutates nothing on disk but the
## PNGs under reports/screenshots/step4-rim/.
##
##   DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --path . --renderer mobile \
##       --script tools/bob_rim_capture.gd -- --suffix=-before
##
## Writes  <out>/<dir><suffix>.png  and  <out>/<dir><suffix>-void.png.

const World = preload("res://scripts/building_world.gd")
const Generator = preload("res://scripts/m1_patch_generator.gd")

const OUT_DIR := "reports/screenshots/step4-rim"
const TARGET := Vector3(25.0, 8.0, 25.0)

var scene: Node
var suffix := ""
var pitch := 0.72
var distance := 42.0
var view_context_name := "terrain"

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--suffix="): suffix = argument.trim_prefix("--suffix=")
		elif argument.begins_with("--pitch="): pitch = float(argument.trim_prefix("--pitch="))
		elif argument.begins_with("--distance="): distance = float(argument.trim_prefix("--distance="))
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://bob-rim-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline: int = Time.get_ticks_msec() + 90000
	while (not scene._player_restored or scene.backend == null or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not scene._player_restored or not scene.backend.is_ready():
		print("RIM_PROBE_UNAVAILABLE")
		quit(2)
		return
	scene.set_process(false)

	# Three-home hamlet fixture (identical placement to the composition test).
	var lodge_basis: Basis = Basis(Vector3.UP, deg_to_rad(-10.0)).scaled(Vector3.ONE * World.MINIATURE_SCALE)
	scene.building_world.create_home_at("woodland_lodge", Transform3D(lodge_basis, Vector3(12.0, 8.0, 32.0)), scene.building_world.get_revision())
	var gable_basis: Basis = Basis(Vector3.UP, deg_to_rad(12.0)).scaled(Vector3.ONE * World.MINIATURE_SCALE)
	scene.building_world.create_home_at("village_gable", Transform3D(gable_basis, Vector3(31.0, 8.0, 31.0)), scene.building_world.get_revision())
	if scene.has_method("_sync_cottage_visuals"): scene._sync_cottage_visuals()

	if scene.hud: scene.hud.visible = false
	scene.cursor = TARGET
	scene.terrain_cursor = scene.cursor
	scene.camera_distance = distance
	scene.camera_pitch = pitch

	_print_boundary_profile()

	var env: Environment = root.world_3d.environment
	var directions := [
		["north", 0.0], ["northeast", -PI / 4.0], ["east", -PI / 2.0], ["southeast", -3.0 * PI / 4.0],
		["south", PI], ["southwest", 3.0 * PI / 4.0], ["west", PI / 2.0], ["northwest", PI / 4.0],
	]
	for entry in directions:
		var name: String = entry[0]
		var yaw: float = entry[1]
		scene.camera_yaw = yaw
		scene._update_camera()
		for _frame in 14: await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		image.save_png("%s/%s%s.png" % [OUT_DIR, name, suffix])
		var position: Vector3 = scene.camera.global_position
		# --- void mask: same frame, flat magenta background, nothing else changed ---
		var saved_colour: Color = env.background_color
		env.background_color = Color(1.0, 0.0, 1.0)
		env.background_mode = Environment.BG_COLOR
		for _frame in 8: await RenderingServer.frame_post_draw
		var mask: Image = root.get_texture().get_image()
		mask.save_png("%s/%s%s-void.png" % [OUT_DIR, name, suffix])
		env.background_mode = Environment.BG_SKY
		env.background_color = saved_colour
		var void_pixels := _count_magenta(mask)
		var void_lower := _count_magenta_band(mask, 2.0 / 3.0, 1.0)
		print("RIM_DIR name=%s yaw=%.3f cam=(%.1f,%.1f,%.1f) void_px=%d (%.2f%%) void_lower_third=%d" % [
			name, yaw, position.x, position.y, position.z, void_pixels,
			100.0 * float(void_pixels) / float(mask.get_width() * mask.get_height()), void_lower])
	scene._shutting_down = true
	scene.queue_free()
	await process_frame
	print("RIM_PROBE_DONE suffix=%s pitch=%.2f distance=%.1f" % [suffix, pitch, distance])
	quit(0)

func _print_boundary_profile() -> void:
	# Distance from the hamlet review target to each boundary, and the authored
	# terrain height along each boundary, reported as one line (the diagnosis).
	var unit: float = Generator.VOXEL_SCALE
	var extent := Vector3(Generator.PATCH_SIZE) * unit
	print("RIM_BOUNDARY world_extent=(%.1f, %.1f) patch=%s voxel=%.3f hamlet_target=(%.1f,%.1f,%.1f)" % [
		extent.x, extent.z, str(Generator.PATCH_SIZE), unit, TARGET.x, TARGET.y, TARGET.z])
	print("RIM_DISTANCES to_x0=%.1f to_xmax=%.1f to_z0=%.1f to_zmax=%.1f" % [
		TARGET.x - 0.0, extent.x - TARGET.x, TARGET.z - 0.0, extent.z - TARGET.z])
	for label in ["west_x0", "east_xmax", "north_z0", "south_zmax"]:
		var low := 999.0
		var high := -999.0
		for step in 96:
			var t := float(step) / 95.0
			var h := 0.0
			if label == "west_x0": h = Generator.terrain_height(0.05, 0.05 + t * (extent.z - 0.1))
			elif label == "east_xmax": h = Generator.terrain_height(extent.x - 0.05, 0.05 + t * (extent.z - 0.1))
			elif label == "north_z0": h = Generator.terrain_height(0.05 + t * (extent.x - 0.1), 0.05)
			else: h = Generator.terrain_height(0.05 + t * (extent.x - 0.1), extent.z - 0.05)
			low = minf(low, h)
			high = maxf(high, h)
		print("RIM_EDGE %s rim_height_min=%.2f rim_height_max=%.2f above_hamlet_floor_min=%.2f above_hamlet_floor_max=%.2f" % [
			label, low, high, low - 8.0, high - 8.0])

func _count_magenta(image: Image) -> int:
	var total := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.80 and pixel.g < 0.20 and pixel.b > 0.80: total += 1
	return total

func _count_magenta_band(image: Image, from_fraction: float, to_fraction: float) -> int:
	var y0 := int(float(image.get_height()) * from_fraction)
	var y1 := int(float(image.get_height()) * to_fraction)
	var total := 0
	for y in range(y0, y1):
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.80 and pixel.g < 0.20 and pixel.b > 0.80: total += 1
	return total
