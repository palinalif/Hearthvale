extends SceneTree
## DOF proof + tuning for the LIVE camera (step 3, 2026-09-15).
## Renders the exact m2-hamlet review framing (tests/m2_hamlet_composition_render_test.gd:
## cursor 25,8,25 / yaw -1.04 / pitch 0.72 / distance 42) with:
##   * DOF OFF              (camera.attributes = null)
##   * the LIVE attribute values (as driven by the live _update_depth_of_field)
##   * a sweep of alternative dof_blur_amount values
## and reports changed-pixel counts + a per-band breakdown vs the OFF frame, so
## "subtle but felt" can be chosen from evidence instead of taste alone.
## It also measures the static distant-scenery draw-call delta with the node
## visible/hidden. PNGs -> reports/dof-proof/.
##
## Run: DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 900 \
##   /opt/data/tools/godot/Godot_v4.7.2-stable_linux.x86_64 --max-fps 60 \
##   --path . --renderer mobile --script tools/bob_dof_proof.gd

const OUT_DIR := "reports/dof-proof"
const LOG_PATH := OUT_DIR + "/dof-proof.txt"
const AMOUNTS: Array[float] = [0.06, 0.10, 0.14, 0.20]
const BANDS := [["top", 0.0, 0.4], ["middle", 0.4, 0.7], ["bottom", 0.7, 1.0]]

var scene: Node
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

func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	log_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://dof-proof-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline: int = Time.get_ticks_msec() + 120000
	while (not scene._player_restored or not scene.backend or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not scene._player_restored:
		_log("DOF_PROOF scene not ready")
		quit(2)
		return
	scene.set_process(false)
	scene.hud.visible = false
	scene.cursor = Vector3(25.0, 8.0, 25.0)
	scene.terrain_cursor = scene.cursor
	scene.camera_yaw = -1.04
	scene.camera_pitch = 0.72
	scene.camera_distance = 42.0
	scene._update_camera()

	# ---- draw-call delta of the static distant scenery ----
	await _settle(6)
	var with_scenery := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	scene.distant_scenery.visible = false
	await _settle(6)
	var without_scenery := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	scene.distant_scenery.visible = true
	await _settle(6)
	var restored := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_log("DOF_PROOF draw_calls with_distant=%d without_distant=%d (delta=%+d) restored=%d" % [
		with_scenery, without_scenery, with_scenery - without_scenery, restored])
	if scene.distant_scenery.mesh:
		_log("DOF_PROOF distant_mesh surfaces=%d aabb=%s" % [scene.distant_scenery.mesh.get_surface_count(), str(scene.distant_scenery.mesh.get_aabb())])

	# ---- DOF frames ----
	# The live camera always carries CameraAttributesPractical (it is created in
	# _build_world) and the live _update_depth_of_field re-attaches it whenever it
	# is missing, so "DOF off" is expressed by disabling both blur stages — which
	# is exactly the state every close/mid framing runs in.
	scene._update_camera()
	var attributes := scene.camera.attributes as CameraAttributesPractical
	if attributes == null:
		_log("DOF_PROOF no live attributes — aborting")
		quit(2)
		return
	var live_amount := attributes.dof_blur_amount
	attributes.dof_blur_near_enabled = false
	attributes.dof_blur_far_enabled = false
	await _settle(8)
	var off: Image = root.get_texture().get_image()
	off.convert(Image.FORMAT_RGBA8)
	off.save_png(OUT_DIR + "/dof-off.png")

	# Fully detached attribute resource (no DOF pass configured at all): must match
	# the blur-disabled frame, proving the difference below is the DOF itself.
	scene.camera.attributes = null
	await _settle(8)
	var detached: Image = root.get_texture().get_image()
	detached.convert(Image.FORMAT_RGBA8)
	detached.save_png(OUT_DIR + "/dof-detached.png")
	_report("detached_vs_blur_disabled", off, detached)

	scene._update_camera()
	attributes = scene.camera.attributes as CameraAttributesPractical
	await _settle(8)
	var live: Image = root.get_texture().get_image()
	live.convert(Image.FORMAT_RGBA8)
	live.save_png(OUT_DIR + "/dof-live.png")
	_log("DOF_PROOF live amount=%.3f near=%.2f/%.2f far=%.2f/%.2f" % [live_amount,
		attributes.dof_blur_near_distance, attributes.dof_blur_near_transition,
		attributes.dof_blur_far_distance, attributes.dof_blur_far_transition])
	_report("live(amount=%.2f)" % live_amount, off, live)

	for amount in AMOUNTS:
		# _update_camera above may have replaced the attribute resource (the live
		# update re-creates it when it is missing), so re-fetch it each pass.
		attributes = scene.camera.attributes as CameraAttributesPractical
		attributes.dof_blur_amount = amount
		await _settle(8)
		var image: Image = root.get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		image.save_png(OUT_DIR + "/dof-amount-%.2f.png" % amount)
		_report("amount=%.2f" % amount, off, image)

	_log("DOF_PROOF saved to " + OUT_DIR)
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	quit(0)

func _report(label: String, reference: Image, candidate: Image) -> void:
	var w := reference.get_width()
	var h := reference.get_height()
	var ref_data := reference.get_data()
	var cand_data := candidate.get_data()
	var changed := 0
	var worst := 0
	var bands := {}
	for band in BANDS:
		bands[str(band[0])] = 0
	var band_total := {}
	for band in BANDS:
		band_total[str(band[0])] = 0
	for y in h:
		var band_name := "bottom"
		for band in BANDS:
			if float(y) / float(h) >= float(band[1]) and float(y) / float(h) < float(band[2]):
				band_name = str(band[0])
		for x in range(0, w, 2):
			var offset := (y * w + x) * 4
			band_total[band_name] = int(band_total[band_name]) + 1
			var delta: int = maxi(
				absi(int(ref_data[offset]) - int(cand_data[offset])),
				maxi(absi(int(ref_data[offset + 1]) - int(cand_data[offset + 1])), absi(int(ref_data[offset + 2]) - int(cand_data[offset + 2]))))
			if delta > 3:
				changed += 1
				bands[band_name] = int(bands[band_name]) + 1
			worst = maxi(worst, delta)
	_log("DOF_PROOF %s changed(>3)=%d/%d max_channel_delta=%d bands top=%d/%d middle=%d/%d bottom=%d/%d" % [
		label, changed, (w / 2) * h, worst,
		int(bands["top"]), int(band_total["top"]), int(bands["middle"]), int(band_total["middle"]),
		int(bands["bottom"]), int(band_total["bottom"])])