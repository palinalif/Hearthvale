extends SceneTree

## Step-5 diagnostic: how much of the hamlet frame IS the distant/blocky backdrop?
##
## Boots the REAL Mobile scene once, rebuilds the three-home hamlet fixture
## (identical to tests/m2_hamlet_composition_render_test.gd), then for each
## requested framing (yaw + pitch + distance) measures, on that exact frame:
##   distant%  = pixels that change when the whole DistantHamlet node is hidden
##               (the terraced outer valley floor + the stacked-box mounds/farms)
##   floor%    = pixels of surface index 4 only (the terraced outer valley floor,
##               4u stepped boxes added in step 4) — measured by repainting that
##               one surface flat magenta with fog off, so the mask is exact
##   bg%       = pixels of world background (sky/void), flat magenta background
## Plus a 64x24 ASCII map of both masks and the first row the backdrop reaches.
##
## Read-only: it writes only PNGs under --out (default reports/screenshots/step5-block/).
##
##   DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 \
##     /opt/data/tools/godot/Godot_v4.7.2-stable_linux.x86_64 \
##     --path . --renderer mobile --script tools/bob_block_scan.gd -- \
##     --suffix=-before --framings=0.62:52:north;0.62:52:east

const World = preload("res://scripts/building_world.gd")

const TARGET := Vector3(25.0, 8.0, 25.0)
const YAW := {
	"north": 0.0, "northeast": -PI / 4.0, "east": -PI / 2.0, "southeast": -3.0 * PI / 4.0,
	"south": PI, "southwest": 3.0 * PI / 4.0, "west": PI / 2.0, "northwest": PI / 4.0,
	# the hamlet-composition render test's own framing (tests/m2_hamlet_composition_render_test.gd)
	"hamlet": -1.04,
}

var scene: Node
var out_dir := "reports/screenshots/step5-block"
var suffix := ""
var framings: Array = ["0.72:42:north", "0.72:42:east"]

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out_dir = argument.trim_prefix("--out=")
		elif argument.begins_with("--suffix="): suffix = argument.trim_prefix("--suffix=")
		elif argument.begins_with("--framings="):
			framings = []
			for entry in argument.trim_prefix("--framings=").split(";"):
				framings.append(str(entry))
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://bob-block-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline: int = Time.get_ticks_msec() + 90000
	while (not scene._player_restored or scene.backend == null or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not scene._player_restored or not scene.backend.is_ready():
		print("BLOCK_SCAN_UNAVAILABLE")
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

	var env: Environment = root.world_3d.environment
	var node: MeshInstance3D = scene.distant_scenery
	var mesh: ArrayMesh = node.mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_material.albedo_color = Color(1.0, 0.0, 1.0)
	print("BLOCK_SCAN viewport=%s surfaces=%d framings=%d" % [str(root.size), mesh.get_surface_count(), framings.size()])

	for entry in framings:
		var parts: PackedStringArray = str(entry).split(":")
		if parts.size() < 3: continue
		var pitch := float(parts[0])
		var distance := float(parts[1])
		var label := str(parts[2])
		var yaw: float = YAW[label] if YAW.has(label) else float(label)
		var tag := "p%03d-d%02d-%s" % [int(round(pitch * 100.0)), int(round(distance)), label]
		scene.camera_distance = distance
		scene.camera_pitch = pitch
		scene.camera_yaw = yaw
		scene._update_camera()
		for _frame in 14: await RenderingServer.frame_post_draw
		var frame: Image = root.get_texture().get_image()
		frame.save_png("%s/%s%s.png" % [out_dir, tag, suffix])
		var attributes = scene.camera.attributes
		scene.camera.attributes = null  # exact masks: no DOF smear in the diff

		# --- distant coverage: the same frame with the whole node hidden ---
		node.visible = false
		for _frame in 8: await RenderingServer.frame_post_draw
		var without: Image = root.get_texture().get_image()
		node.visible = true

		# --- terraced outer floor only: repaint surface 4 flat magenta, fog off ---
		var saved_floor = mesh.surface_get_material(4)
		var fog_was: bool = env.fog_enabled
		env.fog_enabled = false
		mesh.surface_set_material(4, floor_material)
		for _frame in 8: await RenderingServer.frame_post_draw
		var floor_mask: Image = root.get_texture().get_image()
		mesh.surface_set_material(4, saved_floor)
		env.fog_enabled = fog_was

		# --- background (sky/void) share ---
		var saved_colour: Color = env.background_color
		var saved_mode: int = env.background_mode
		env.background_color = Color(1.0, 0.0, 1.0)
		env.background_mode = Environment.BG_COLOR
		for _frame in 8: await RenderingServer.frame_post_draw
		var bg_mask: Image = root.get_texture().get_image()
		env.background_mode = saved_mode
		env.background_color = saved_colour
		scene.camera.attributes = attributes

		_report(tag, yaw, frame, without, floor_mask, bg_mask, pitch, distance)
	print("BLOCK_SCAN_DONE suffix=%s" % suffix)
	scene._shutting_down = true
	scene.queue_free()
	await process_frame
	quit(0)

func _report(tag: String, yaw: float, frame: Image, without: Image, floor_mask: Image, bg_mask: Image, pitch: float, distance: float) -> void:
	var width := frame.get_width()
	var height := frame.get_height()
	var total := width * height
	var distant := 0
	var floor_pixels := 0
	var bg := 0
	var bands := 24
	var band_distant := PackedInt32Array(); band_distant.resize(bands); band_distant.fill(0)
	var band_floor := PackedInt32Array(); band_floor.resize(bands); band_floor.fill(0)
	var band_total := PackedInt32Array(); band_total.resize(bands); band_total.fill(0)
	var first_row := -1
	var map_distant := []
	var map_floor := []
	for y in height:
		var band := mini(bands - 1, y * bands / height)
		var line_distant := ""
		var line_floor := ""
		for x in width:
			var a := frame.get_pixel(x, y)
			var b := without.get_pixel(x, y)
			var changed: bool = absf(a.r - b.r) > 0.012 or absf(a.g - b.g) > 0.012 or absf(a.b - b.b) > 0.012
			var p := floor_mask.get_pixel(x, y)
			var is_floor: bool = p.r > 0.55 and p.b > 0.55 and p.g < 0.45
			var q := bg_mask.get_pixel(x, y)
			var is_bg: bool = q.r > 0.70 and q.b > 0.70 and q.g < 0.60
			band_total[band] += 1
			if changed:
				distant += 1
				band_distant[band] += 1
				if first_row < 0: first_row = y
			if is_floor:
				floor_pixels += 1
				band_floor[band] += 1
			if is_bg: bg += 1
			line_distant += "#" if changed else "."
			line_floor += "F" if is_floor else "."
		if height / 24 > 0 and y % (height / 24) == 0:
			map_distant.append("%02d %s" % [y * 24 / height, _squeeze(line_distant)])
			map_floor.append("%02d %s" % [y * 24 / height, _squeeze(line_floor)])
	print("BLOCK %-22s pitch=%.3f dist=%.1f distant=%7d (%5.2f%%) floor=%7d (%5.2f%%) bg=%6d (%5.2f%%) first_row=%d cam=(%.1f,%.1f,%.1f)" % [
		tag, pitch, distance, distant, 100.0 * float(distant) / float(total), floor_pixels,
		100.0 * float(floor_pixels) / float(total), bg, 100.0 * float(bg) / float(total),
		first_row, scene.camera.global_position.x, scene.camera.global_position.y, scene.camera.global_position.z])
	var profile := "  distant rows:"
	for band in bands:
		profile += " %d:%d%%" % [band, int(round(100.0 * float(band_distant[band]) / float(maxi(1, band_total[band]))))]
	print(profile)
	var floor_profile := "  floor rows:"
	for band in bands:
		floor_profile += " %d:%d%%" % [band, int(round(100.0 * float(band_floor[band]) / float(maxi(1, band_total[band]))))]
	print(floor_profile)
	print("  distant map (# = backdrop pixel):")
	for line in map_distant: print("  " + line)
	print("  terraced-floor map (F = surface-4 box pixel):")
	for line in map_floor: print("  " + line)
	_distance_histogram(frame, floor_mask)

## How far away ARE the blocky pixels? March the engine's own rays for every
## sampled surface-4 (terraced-floor) pixel and report a 10u distance histogram,
## plus the island-vs-outer split — this is what a distance fade has to cover.
func _distance_histogram(frame: Image, floor_mask: Image) -> void:
	var width := frame.get_width()
	var height := frame.get_height()
	var bins := 20
	var floor_bins := PackedInt32Array(); floor_bins.resize(bins); floor_bins.fill(0)
	var island_bins := PackedInt32Array(); island_bins.resize(bins); island_bins.fill(0)
	var samples := 0
	var y := 0
	var luma_sum := 0.0
	var luma_sq_sum := 0.0
	var edge_sum := 0.0
	var edge_count := 0
	var near_edge := 0.0
	var near_count := 0
	var far_edge := 0.0
	var far_count := 0
	var near_luma := 0.0
	var near_luma_sq := 0.0
	var far_luma := 0.0
	var far_luma_sq := 0.0
	while y < height:
		var x := 0
		while x < width:
			var p := floor_mask.get_pixel(x, y)
			if p.r > 0.55 and p.b > 0.55 and p.g < 0.45:
				var hit := _march(scene.camera.project_ray_origin(Vector2(x, y)), scene.camera.project_ray_normal(Vector2(x, y)))
				var bin := mini(bins - 1, int(hit.x / 10.0))
				if hit.y > 0.5: floor_bins[bin] += 1
				else: island_bins[bin] += 1
				samples += 1
				var luma := _luma(frame.get_pixel(x, y))
				luma_sum += luma
				luma_sq_sum += luma * luma
				if x + 1 < width and y + 1 < height:
					# Blockiness proxy: how hard the terrace edges are. Fog should
					# flatten this inside the mask without changing what is drawn.
					var local_edge: float = absf(_luma(frame.get_pixel(x + 1, y)) - luma) + absf(_luma(frame.get_pixel(x, y + 1)) - luma)
					edge_sum += local_edge
					edge_count += 1
					if hit.x < 50.0:
						near_edge += local_edge
						near_count += 1
						near_luma += luma
						near_luma_sq += luma * luma
					else:
						far_edge += local_edge
						far_count += 1
						far_luma += luma
						far_luma_sq += luma * luma
			x += 6
		y += 6
	var mean := luma_sum / float(maxi(1, samples))
	var variance: float = maxf(0.0, luma_sq_sum / float(maxi(1, samples)) - mean * mean)
	print("  floor luma mean=%.3f std=%.3f  edge_energy=%.4f (mean |dLuma| per 2px, lower = hazier/softer)" % [
		mean, sqrt(variance), edge_sum / float(maxi(1, edge_count))])
	print("  floor edge near(<50u)=%.4f (n=%d)  far(>=50u)=%.4f (n=%d)" % [
		near_edge / float(maxi(1, near_count)), near_count, far_edge / float(maxi(1, far_count)), far_count])
	var near_mean := near_luma / float(maxi(1, near_count))
	var far_mean := far_luma / float(maxi(1, far_count))
	print("  floor luma near(<50u) mean=%.3f std=%.3f  far(>=50u) mean=%.3f std=%.3f" % [
		near_mean, sqrt(maxf(0.0, near_luma_sq / float(maxi(1, near_count)) - near_mean * near_mean)),
		far_mean, sqrt(maxf(0.0, far_luma_sq / float(maxi(1, far_count)) - far_mean * far_mean))])
	var line := "  floor-pixel distance histogram (10u bins, camera->surface):"
	for index in bins:
		var total: int = floor_bins[index] + island_bins[index]
		if total > 0: line += " %d0-%d0u:%d" % [index, index + 1, total]
	print(line)
	var usable := 0
	for index in bins:
		if index >= 5: usable += floor_bins[index] + island_bins[index]
	print("  floor-pixel samples=%d  beyond_50u=%d (%.1f%%)" % [samples, usable, 100.0 * float(usable) / float(maxi(1, samples))])

## March one ray: returns (distance, 1.0 = hit the outer valley floor / backdrop
## region, 0.0 = hit the editable island terrain). Same model as bob_rim_capture.
func _march(origin: Vector3, direction: Vector3) -> Vector2:
	var t := 0.5
	while t < 400.0:
		var point := origin + direction * t
		if point.y < 0.0: return Vector2(t, 1.0)
		if point.x > -140.0 and point.x < 188.0 and point.z > -140.0 and point.z < 188.0:
			if point.y <= _probe_surface(point.x, point.z):
				var inside: bool = point.x > 0.0 and point.x < M1PatchGenerator.EXTENT.x and point.z > 0.0 and point.z < M1PatchGenerator.EXTENT.y
				return Vector2(t, 0.0 if inside else 1.0)
		t += 1.0
	return Vector2(400.0, 1.0)

func _probe_surface(x: float, z: float) -> float:
	if x > 0.0 and x < M1PatchGenerator.EXTENT.x and z > 0.0 and z < M1PatchGenerator.EXTENT.y:
		return M1PatchGenerator.terrain_height(x, z)
	return scene._outer_floor_height(x, z)

func _luma(pixel: Color) -> float:
	return 0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b

func _squeeze(line: String) -> String:
	var out := ""
	var columns := 64
	var step := maxi(1, line.length() / columns)
	var i := 0
	while i < line.length():
		var hits := 0
		var count := 0
		var j := i
		while j < mini(i + step, line.length()):
			count += 1
			if line[j] != ".": hits += 1
			j += 1
		out += ("#" if float(hits) / float(maxi(1, count)) > 0.5 else ".")
		i += step
	return out