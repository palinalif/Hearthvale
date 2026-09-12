extends SceneTree

const ContactChecks = preload("res://tests/m2_path_grass_contact_checks.gd")

var scene: Node
var checks := 0
var failures := 0
var screenshot_dir := "reports/screenshots/m2-paths"
var captures := 0
const STONE_VERTEX_COUNT := 50 # two centres, paired octagonal rings, eight side quads

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	ContactChecks.source_lock(self)
	ContactChecks.budget_selection(self)
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
		await _finish_scene()
		return
	scene.set_process(false)
	var first_id: int = int(scene.landscape_state.next_id)
	var first: int = int(scene.landscape_state.add_path("packed_earth", 0.75, [[14.0, 14.0], [20.0, 14.0], [22.0, 16.0]]))
	var second: int = int(scene.landscape_state.add_path("cobblestone", 1.5, [[27.0, 12.0], [34.0, 12.0], [36.0, 15.0]]))
	var third: int = int(scene.landscape_state.add_path("stepping_stones", 1.0, [[14.0, 28.0], [20.0, 31.0], [27.0, 29.0]]))
	_check(first == first_id and second == first_id + 1 and third == first_id + 2, "all three styles receive stable path IDs")
	_check(scene.landscape_state.paths.size() == 3 and StateValidate(scene.landscape_state.document()), "three-style render fixture validates")
	# Match normal path confirmation's planting clear; do not alter terrain.
	for path_value in scene.landscape_state.paths:
		scene.landscape_state.clear_records_along_path(path_value.points, float(path_value.width))
	if scene.garden_visual: scene.garden_visual.reset_records(scene.landscape_state.records)
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
	var stone_node: MeshInstance3D = scene.path_visual._style_nodes["stepping_stones"]
	_check_stepping_faces(stone_node.mesh as ArrayMesh, "committed")
	_check_surface_reference(stone_node.mesh as ArrayMesh, "committed")
	ContactChecks.inspect(self, scene, "committed")
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
		captures += 1
		await _capture_stepping_close_views()
	await _check_dig_reseat()
	await ContactChecks.lifecycle(self, scene)
	await _finish_scene()

# Godot fronts are CLOCKWISE: the geometric cross product must oppose the
# supplied outward lighting normal. Normals alone do not control face culling.
func _check_stepping_faces(mesh: ArrayMesh, phase: String) -> void:
	var counts := {"top": 0, "bottom": 0, "side": 0}
	var reversed := {"top": 0, "bottom": 0, "side": 0}
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var material := mesh.surface_get_material(surface) as BaseMaterial3D
		_check(material != null and material.cull_mode == BaseMaterial3D.CULL_BACK, "stone keeps normal back-face culling: " + phase)
		for offset in range(0, indices.size(), 3):
			var a := vertices[indices[offset]]
			var b := vertices[indices[offset + 1]]
			var c := vertices[indices[offset + 2]]
			var normal := normals[indices[offset]]
			var kind := "top" if normal.y > 0.99 else ("bottom" if normal.y < -0.99 else "side")
			counts[kind] = int(counts[kind]) + 1
			if (b - a).cross(c - a).dot(normal) >= -0.00000001:
				reversed[kind] = int(reversed[kind]) + 1
	for kind: String in ["top", "bottom", "side"]:
		_check(int(counts[kind]) > 0 and int(reversed[kind]) == 0, "%s stone %s faces are outward clockwise, not inside-out" % [phase, kind])
	print("STEPPING_FACE_AUDIT " + JSON.stringify({"phase": phase, "triangles": counts, "reversed": reversed}))

func _check_surface_reference(mesh: ArrayMesh, phase: String) -> void:
	var scale_value: float = scene.backend.voxel_scale
	var samples := 0
	var mismatches := 0
	var max_error := 0.0
	var lowest_centre_clearance := INF
	var highest_centre_clearance := -INF
	_check(scene.path_visual.global_transform.is_equal_approx(scene.backend.global_transform), "path and backend share world coordinate frame: " + phase)
	_check(scene.backend.terrain.scale.is_equal_approx(Vector3.ONE * scale_value), "native mesh uses backend voxel scale: " + phase)
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		_check(vertices.size() % STONE_VERTEX_COUNT == 0, "complete octagonal stone records: " + phase)
		for index in vertices.size():
			if normals[index].y < 0.99: continue
			var vertex := vertices[index]
			var scan_y: float = scene.path_visual._surface_height(Vector2(vertex.x, vertex.z))
			# Query the existing sculpt/placement API, not the path's centre helper.
			var hit: Dictionary = scene.backend.sample_surface_plane(Vector3(vertex.x, scan_y + scale_value * 0.5, vertex.z), Vector3.UP, scale_value * 2.0)
			samples += 1
			if not bool(hit.get("valid", false)):
				mismatches += 1
				continue
			var ground: Vector3 = hit["point"]
			var error := absf(scan_y - ground.y)
			max_error = maxf(max_error, error)
			if error > 0.00001: mismatches += 1
			if index % STONE_VERTEX_COUNT == 0:
				lowest_centre_clearance = minf(lowest_centre_clearance, vertex.y - ground.y)
				highest_centre_clearance = maxf(highest_centre_clearance, vertex.y - ground.y)
	_check(samples > 0 and mismatches == 0, "stone height scan agrees with native surface API: " + phase)
	_check(lowest_centre_clearance >= -0.00001 and is_finite(highest_centre_clearance), "stone top centres are not below the native surface: " + phase)
	if phase == "committed":
		_check(highest_centre_clearance <= scale_value + 0.006, "fresh path tops stay within one terrace edge of the native surface")
	print("STEPPING_HEIGHT_AUDIT " + JSON.stringify({"phase": phase, "samples": samples, "mismatches": mismatches, "max_error": max_error, "min_top_clearance": lowest_centre_clearance, "max_top_clearance": highest_centre_clearance, "voxel_scale": scale_value}))

func _first_stone_top() -> Vector3:
	var node: MeshInstance3D = scene.path_visual._style_nodes["stepping_stones"]
	var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return vertices[0]

func _capture_stepping_close_views() -> void:
	if scene.hud: scene.hud.visible = false
	# The SAME runtime path batch and native terrain as the overview. Only the
	# camera changes; no raised fixture, substitute ground, or material override.
	var target := _first_stone_top() + Vector3(1.8, 0.0, 0.9)
	for view: String in ["stepping-close", "stepping-reverse"]:
		var direction := Vector3(2.0, 4.5, 5.5) if view == "stepping-close" else Vector3(-2.0, 4.5, -5.5)
		scene.camera.position = target + direction
		scene.camera.look_at(target, Vector3.UP)
		for _frame in 4: await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		_check(not image.is_empty() and image.get_width() == 1280 and image.get_height() == 720, "actual Mobile close view exists: " + view)
		_check(image.save_png(screenshot_dir.path_join(view + ".png")) == OK, "actual Mobile close view saved: " + view)
		captures += 1

func _check_dig_reseat() -> void:
	var contact_before := ContactChecks.digest(scene.path_visual._contact_data)
	var top := _first_stone_top()
	var point := Vector2(top.x, top.z)
	var ground_before: float = scene.path_visual._surface_height(point)
	var paths_before := JSON.stringify(scene.landscape_state.paths)
	var settings := {"radius": 0.75, "strength": 0.5, "falloff": 0.0, "surface_normal": Vector3.UP}
	var centre := Vector3(top.x, ground_before, top.z)
	var begun: bool = scene.backend.begin_stroke("dig", centre, settings)
	_check(begun, "dig under a real stepping stone begins")
	if not begun: return
	scene.backend.update_stroke(centre, 0.5)
	var live_ground: float = scene.path_visual._surface_height(point)
	_check(live_ground < ground_before, "live dig lowers the queried native surface")
	_check(_first_stone_top().is_equal_approx(top), "live stroke retains stone mesh until commit, explaining temporary exposure")
	_check(ContactChecks.digest(scene.path_visual._contact_data) == contact_before, "live stroke retains committed grass until the existing refresh")
	_check(scene.backend.cancel_stroke(), "dig cancellation restores terrain")
	await process_frame
	_check(_first_stone_top().is_equal_approx(top), "cancel restores original stone top")
	_check(ContactChecks.digest(scene.path_visual._contact_data) == contact_before, "dig cancel restores identical grass contact")
	_check(is_equal_approx(scene.path_visual._surface_height(point), ground_before), "cancel restores native surface height")
	begun = scene.backend.begin_stroke("dig", centre, settings)
	_check(begun, "second dig begins for release/commit regression")
	if not begun: return
	scene.backend.update_stroke(centre, 0.5)
	_check(scene.backend.end_stroke(), "dig release commits through existing terrain API")
	await process_frame
	_check(_first_stone_top().y < top.y, "release rebuilds the path against the lowered surface")
	var node: MeshInstance3D = scene.path_visual._style_nodes["stepping_stones"]
	_check_stepping_faces(node.mesh as ArrayMesh, "after-dig")
	_check_surface_reference(node.mesh as ArrayMesh, "after-dig")
	ContactChecks.inspect(self, scene, "after-dig")
	_check(scene.backend.undo(), "dig can be undone")
	await process_frame
	_check(_first_stone_top().is_equal_approx(top), "undo restores stone height without a saved offset")
	_check(ContactChecks.digest(scene.path_visual._contact_data) == contact_before, "dig undo restores identical grass contact")
	_check(JSON.stringify(scene.landscape_state.paths) == paths_before, "dig/cancel/release/undo leave saved path authority unchanged")

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
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "captures": captures, "capture": screenshot_dir.path_join("all-styles.png") if DisplayServer.get_name() != "headless" else "headless"}))
	quit(1 if failures else 0)
