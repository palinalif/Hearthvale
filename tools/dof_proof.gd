extends SceneTree
## DOF proof (reports/dof-proof/): render the wide hamlet framing with the live
## DOF ON and with it DISABLED, save both 1280x720 PNGs, report changed-pixel
## counts. The far field beyond the hamlet must visibly soften; the village
## band must stay near-identical. Run:
##   DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --max-fps 60 --path . \
##     --renderer mobile --script tools/dof_proof.gd
var scene: Node
const OUT_DIR := "reports/dof-proof"

func _initialize() -> void:
	call_deferred("_run")

func _settle(frames: int) -> void:
	for _i in frames: await RenderingServer.frame_post_draw

func _run() -> void:
	root.size = Vector2i(1280, 720)
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://dof-proof-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline:
		await process_frame
	if not scene._player_restored:
		print("DOF_PROOF scene not ready")
		return
	scene.set_process(false)

	# Identical wide framing as tests/m2_hamlet_composition_render_test.gd.
	scene.cursor = Vector3(25.0, 8.0, 25.0)
	scene.terrain_cursor = scene.cursor
	scene.camera_yaw = -1.04
	scene.camera_pitch = 0.72
	scene.camera_distance = 42.0
	scene._update_camera() # auto-attaches DOF (distance > 30)
	_settle(12)

	# ---- capture 1: DOF DISABLED (attributes detached) ----
	scene.camera.attributes = null
	_settle(10)
	var plain: Image = root.get_texture().get_image()
	print("DOF_PROOF plain %dx%d" % [plain.get_width(), plain.get_height()])

	# ---- capture 2: DOF ON (re-attach the live distance-gated values) ----
	scene._update_camera() # re-applies _update_depth_of_field
	var attributes: CameraAttributesPractical = scene.camera.attributes
	print("DOF_PROOF attributes far_dist=%.1f far_trans=%.1f amount=%.2f near_dist=%.1f" % [
		float(attributes.dof_blur_far_distance), float(attributes.dof_blur_far_transition),
		float(attributes.dof_blur_amount), float(attributes.dof_blur_near_distance)])
	_settle(10)
	var dof: Image = root.get_texture().get_image()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	plain.save_png(OUT_DIR + "/dof-off.png")
	dof.save_png(OUT_DIR + "/dof-on.png")

	# Whole-frame and quadrant changed-pixel counts (quick sanity for the log).
	var w := mini(plain.get_width(), dof.get_width())
	var h := mini(plain.get_height(), dof.get_height())
	var whole := 0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			if plain.get_pixelv(Vector2i(x, y)) != dof.get_pixelv(Vector2i(x, y)):
				whole += 1
	print("DOF_PROOF changed_px(sampled/4)=%d" % whole)
	if whole == 0:
		print("DOF_PROOF WARNING: no visible change — Mobile renderer may drop DOF")
	print("DOF_PROOF saved ", OUT_DIR + "/dof-off.png and dof-on.png")

	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	quit(0)
