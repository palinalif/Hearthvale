extends SceneTree

var scene: Node
var checks := 0
var failures := 0
var screenshot_dir := "reports/screenshots/m2-paths"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		await _run_scene_checks(false)
	else:
		if RenderingServer.get_current_rendering_method() != "mobile":
			print("M2_PATH_RENDER_UNAVAILABLE method=" + RenderingServer.get_current_rendering_method())
			quit(2)
			return
		root.size = Vector2i(1280, 720)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(screenshot_dir))
		await _run_scene_checks(true)
	_print_result()

func _run_scene_checks(capture: bool) -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-path-render-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene._player_restored and scene.backend != null and scene.backend.is_ready(), "native Mobile path scene ready")
	if not scene._player_restored:
		_finish_scene()
		return
	scene.set_process(false)
	var first_id: int = int(scene.landscape_state.next_id)
	var first: int = int(scene.landscape_state.add_path("packed_earth", 0.75, [[14.0, 14.0], [20.0, 14.0], [22.0, 16.0]]))
	var second: int = int(scene.landscape_state.add_path("cobblestone", 1.5, [[27.0, 12.0], [34.0, 12.0], [36.0, 15.0]]))
	var third: int = int(scene.landscape_state.add_path("stepping_stones", 1.0, [[14.0, 28.0], [20.0, 31.0], [27.0, 29.0]]))
	_check(first == first_id and second == first_id + 1 and third == first_id + 2, "all three styles receive stable path IDs")
	_check(scene.landscape_state.paths.size() == 3 and StateValidate(scene.landscape_state.document()), "three-style render fixture validates")
	scene._refresh_path_visual(true)
	await process_frame
	var stats: Dictionary = scene.path_visual.stats()
	_check(stats.styles.size() == 3, "each path style produces a rendered batch")
	_check(stats.draw_calls <= 3 and stats.geometry_cells > 0, "path geometry is batched by style")
	for style_id in ["packed_earth", "cobblestone", "stepping_stones"]:
		_check(scene.path_visual._style_nodes.has(style_id), "style batch exists: " + style_id)
		var node: MeshInstance3D = scene.path_visual._style_nodes[style_id]
		_check(node.mesh != null and node.mesh.get_surface_count() > 0 and node.mesh.get_surface_count() <= 2, "style uses bounded mesh surfaces: " + style_id)
		_check(_mesh_is_finite_bounded_grounded(node.mesh as ArrayMesh), "style mesh is finite, bounded, and grounded: " + style_id)
	if capture:
		scene.cursor = Vector3(24.0, 8.0, 24.0)
		scene.camera_yaw = -1.1
		scene.camera_pitch = 0.66
		scene.camera_distance = 36.0
		scene._update_camera()
		scene._update_presentation()
		scene._refresh_controller_hud()
		for _i in 4: await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		_check(not image.is_empty() and image.get_width() == 1280 and image.get_height() == 720, "1280x720 Mobile path capture exists")
		_check(image.save_png(screenshot_dir.path_join("all-styles.png")) == OK, "path review capture saved")
	_finish_scene()

func _mesh_is_finite_bounded_grounded(mesh: ArrayMesh) -> bool:
	if mesh == null: return false
	var bounds := mesh.get_aabb()
	if not bounds.position.is_finite() or not bounds.size.is_finite(): return false
	if bounds.position.x < -0.5 or bounds.end.x > 48.5 or bounds.position.z < -0.5 or bounds.end.z > 48.5: return false
	if bounds.position.y < 0.0 or bounds.end.y > 32.0 or bounds.position.y < 4.0: return false
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			if not vertex.is_finite() or vertex.x < -0.5 or vertex.x > 48.5 or vertex.z < -0.5 or vertex.z > 48.5 or vertex.y < 0.0 or vertex.y > 32.0: return false
	return true

func StateValidate(document: Dictionary) -> bool:
	return preload("res://scripts/landscape_state.gd").validate(document)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _finish_scene() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame

func _print_result() -> void:
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "capture": screenshot_dir.path_join("all-styles.png") if DisplayServer.get_name() != "headless" else "headless"}))
	quit(1 if failures else 0)
