extends SceneTree
## DOF smoke test for the Mobile renderer: renders the hamlet wide
## framing twice — plain vs CameraAttributesPractical DOF — and reports
## changed-pixel count + saves both. A zero diff means the renderer
## silently drops the attributes (would need a different approach).
var scene: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://dof-probe-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline: int = Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline:
		await process_frame
	if not scene._player_restored:
		print("DOF_PROBE scene not ready")
		_quit()
		return

	# Same framing as the hamlet wide test.
	scene.cursor = Vector3(25.0, 8.0, 25.0)
	scene.terrain_cursor = scene.cursor
	scene.camera_yaw = -1.04
	scene.camera_pitch = 0.72
	scene.camera_distance = 42.0
	scene._update_camera()
	for frame in 12:
		await RenderingServer.frame_post_draw
	var plain: Image = root.get_texture().get_image()

	# Godot 4.7 API: near/far blur distances, not focus_distance + aperture.
	# Focus lands on the mid-ground hamlet (focus ~ camera_distance 42).
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_near_enabled = true
	attributes.dof_blur_near_distance = 22.0
	attributes.dof_blur_near_transition = 20.0
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_far_distance = 55.0
	attributes.dof_blur_far_transition = 30.0
	attributes.dof_blur_amount = 0.25
	scene.camera.attributes = attributes
	for frame in 12:
		await RenderingServer.frame_post_draw
	var dof_image: Image = root.get_texture().get_image()

	var changed := 0
	var w := mini(plain.get_width(), dof_image.get_width())
	var h := mini(plain.get_height(), dof_image.get_height())
	for y in h:
		for x in w:
			if plain.get_pixelv(Vector2i(x, y)) != dof_image.get_pixelv(Vector2i(x, y)):
				changed += 1
	print("DOF_PROBE plain=%dx%d dof=%dx%d changed_px=%d" % [
		plain.get_width(), plain.get_height(), dof_image.get_width(), dof_image.get_height(), changed,
	])
	if changed == 0:
		print("DOF_PROBE NO_CHANGE — Mobile renderer ignored the DOF attributes")
	else:
		print("DOF_PROBE DOF_ACTIVE")
	_dir_rec("reports/screenshots/dof-probe")
	plain.save_png("reports/screenshots/dof-probe/plain.png")
	dof_image.save_png("reports/screenshots/dof-probe/dof.png")
	_quit()

func _dir_rec(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))

func _quit() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	quit(0)
