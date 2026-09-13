extends SceneTree

const EarthChecks = preload("res://tests/m2_packed_earth_checks.gd")
const Region = preload("res://scripts/m2_painted_path_region.gd")
const State = preload("res://scripts/landscape_state.gd")

var scene: Node
var checks := 0
var failures := 0
var screenshot_dir := "reports/screenshots/m2-paths"
var captures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() != "headless":
		if RenderingServer.get_current_rendering_method() != "mobile":
			print("M2_PATH_RENDER_UNAVAILABLE method=" + RenderingServer.get_current_rendering_method())
			quit(2)
			return
		root.size = Vector2i(1280, 720)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(screenshot_dir))
	await _run_scene_checks(DisplayServer.get_name() != "headless")
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
		await _finish_scene()
		return
	scene.set_process(false)
	var first_id := int(scene.landscape_state.next_id)
	var dirt := Region.stroke_cells(Vector2(14.0, 14.0), Vector2(22.0, 16.0), 0.375)
	var stone := Region.stroke_cells(Vector2(27.0, 12.0), Vector2(36.0, 15.0), 0.75)
	var steps := Region.stroke_cells(Vector2(14.0, 28.0), Vector2(27.0, 29.0), 0.50)
	var first: int = scene.landscape_state.paint_path_cells("packed_earth", dirt)
	var second: int = scene.landscape_state.paint_path_cells("cobblestone", stone)
	var third: int = scene.landscape_state.paint_path_cells("stepping_stones", steps)
	_check(first == first_id and second == first_id + 1 and third == first_id + 2, "all three painted materials receive stable region IDs")
	_check(scene.landscape_state.paths.size() == 3 and State.validate(scene.landscape_state.document()), "three-style painted render fixture validates")
	for path_value in scene.landscape_state.paths:
		scene.landscape_state.clear_records_in_path_cells(path_value.cells)
	if scene.garden_visual: scene.garden_visual.reset_records(scene.landscape_state.records)
	scene._refresh_path_visual(true)
	await process_frame
	var stats: Dictionary = scene.path_visual.stats()
	_check(stats.styles.size() == 3, "each painted path style produces a rendered batch")
	_check(stats.draw_calls <= 3 and stats.geometry_cells > 0, "painted geometry is batched by style")
	for style_id in ["packed_earth", "cobblestone", "stepping_stones"]:
		_check(scene.path_visual._style_nodes.has(style_id), "style batch exists: " + style_id)
		var node: MeshInstance3D = scene.path_visual._style_nodes[style_id]
		_check(node.mesh != null and node.mesh.get_surface_count() > 0 and node.mesh.get_surface_count() <= 2, "style uses bounded mesh surfaces: " + style_id)
		_check(_mesh_is_finite_bounded_grounded(node.mesh as ArrayMesh), "style mesh is finite, bounded, and grounded: " + style_id)
	var cobble_polish: Dictionary = stats.get("cobblestone_polish", {})
	_check(int(cobble_polish.get("stones", 0)) > stone.size(), "cobblestone splits painted cells into individual slab stones")
	_check(int(cobble_polish.get("raised_stones", 0)) > 0, "cobblestone includes deterministic height variation")
	var step_polish: Dictionary = stats.get("stepping_stone_polish", {})
	_check(int(step_polish.get("stones", 0)) > 0 and int(step_polish.get("stones", 0)) < steps.size(), "stepping stones remain sparse inside painted authority")
	_check(int(step_polish.get("offset_stones", 0)) == int(step_polish.get("stones", 0)), "stepping stones receive deterministic sub-cell offsets")
	EarthChecks.inspect(self, scene, "committed")
	EarthChecks.width_cases(self, scene)
	if capture:
		await _capture_view("all-styles.png", Vector3(24.0, 8.0, 24.0), 36.0, -1.1, 0.66, "wide painted-path review capture")
		await _capture_view("packed-earth-close.png", Vector3(18.0, 8.0, 15.0), 12.5, -1.18, 0.72, "phone-readable packed-earth close capture")
		await _capture_view("cobblestone-close.png", Vector3(31.5, 8.0, 13.5), 14.5, -1.12, 0.72, "phone-readable cobblestone close capture")
		await _capture_view("stepping-stones-close.png", Vector3(20.5, 8.0, 28.5), 13.5, -1.05, 0.72, "phone-readable stepping-stone close capture")
		await EarthChecks.review(self, scene, screenshot_dir)
	await EarthChecks.lifecycle(self, scene)
	await _finish_scene()

func _capture_view(file_name: String, target: Vector3, distance: float, yaw: float, pitch: float, label: String) -> void:
	scene.cursor = target
	scene.terrain_cursor = target
	scene.camera_yaw = yaw
	scene.camera_pitch = pitch
	scene.camera_distance = distance
	scene._update_camera()
	scene._update_presentation()
	scene._refresh_controller_hud()
	for _i in 4: await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(not image.is_empty() and image.get_width() == 1280 and image.get_height() == 720, label + " exists at 1280x720")
	_check(image.save_png(screenshot_dir.path_join(file_name)) == OK, label + " saved")
	captures += 1

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
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "captures": captures, "capture": screenshot_dir.path_join("all-styles.png") if DisplayServer.get_name() != "headless" else "headless"}))
	quit(1 if failures else 0)
