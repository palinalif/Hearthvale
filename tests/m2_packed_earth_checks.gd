extends RefCounted

const Earth = preload("res://scripts/m2_packed_earth.gd")
const PathVisual = preload("res://scripts/m2_path_visual.gd")
const ContactChecks = preload("res://tests/m2_path_grass_contact_checks.gd")
const State = preload("res://scripts/landscape_state.gd")
const BASELINE := "e8560f30e2466854ab359459463659e0c9cd5b9e"
const BASELINE_FILE := "res://tests/fixtures/m2_path_visual_e8560f30.txt"
const BASELINE_SHA256 := "1ff5bcb9841fc25d6a2566ecdb43a974afc66d2d75f6428df48792e38ee03713"
const PACKED_BASELINE := "3ff78a2fd6de8cdbed1e274e047525ebe9e96584"
const PACKED_BASELINE_FILE := "res://tests/fixtures/m2_packed_earth_3ff78a2f.txt"
const PACKED_BASELINE_SHA256 := "436ec62adf9a80bdcf27bd93319750e440e46f5e92e888376503250fe4b60495"

static func _baseline(checker: SceneTree, scene: Node) -> Node3D:
	var source := FileAccess.get_file_as_string(BASELINE_FILE).replace("\r\n", "\n")
	checker._check(source.sha256_text() == BASELINE_SHA256, "before renderer is the exact e8560f30 source, not a reconstructed substitute")
	var script := GDScript.new()
	script.source_code = source.replace("class_name M2PathVisual\n", "")
	checker._check(script.reload() == OK, "exact baseline renderer compiles without a duplicate global class")
	var visual: Node3D = script.new()
	visual.visible = false
	scene.add_child(visual)
	visual.rebuild(scene.landscape_state.paths, scene.backend)
	return visual

static func _packed_baseline(checker: SceneTree) -> GDScript:
	var source := FileAccess.get_file_as_string(PACKED_BASELINE_FILE).replace("\r\n", "\n")
	checker._check(source.sha256_text() == PACKED_BASELINE_SHA256, "packed-earth before helper is the exact 3ff78a2f source")
	var script := GDScript.new()
	script.source_code = source
	checker._check(script.reload() == OK, "exact 3ff78a2f packed-earth helper compiles")
	return script

static func _packed_result(visual: Node, helper: GDScript, paths: Array, decorate: bool = true) -> Dictionary:
	var builder: Dictionary = visual._new_builder()
	var packed: Array = []
	for path: Dictionary in paths:
		if str(path["style_id"]) == "packed_earth": packed.append(path)
	packed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	for path: Dictionary in packed:
		helper.call("append_path", visual, builder, float(path["width"]), path["points"], int(path["id"]), decorate)
	return {"mesh": helper.call("mesh_from_builder", builder), "stats": helper.call("stats", builder), "builder": builder}

static func _distance(point: Vector2, points: Array) -> float:
	var result := INF
	for index in range(1, points.size()):
		var a := Vector2(float(points[index - 1][0]), float(points[index - 1][1]))
		var b := Vector2(float(points[index][0]), float(points[index][1]))
		result = minf(result, point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)))
	return result

static func inspect(checker: SceneTree, scene: Node, phase: String) -> void:
	var document := JSON.stringify(scene.landscape_state.document())
	var visual: Node = scene.path_visual
	var builder: Dictionary = visual._new_builder()
	var estimated_cells := 0
	var packed: Array = []
	for path: Dictionary in scene.landscape_state.paths:
		if str(path["style_id"]) == "packed_earth": packed.append(path)
	packed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	for path: Dictionary in packed:
		Earth.append_path(visual, builder, float(path["width"]), path["points"], int(path["id"]))
		estimated_cells += State._estimated_render_cells(path)
	var expected := Earth.mesh_from_builder(builder)
	var actual: Mesh = visual._style_nodes["packed_earth"].mesh
	checker._check(ContactChecks.mesh_digest(actual) == ContactChecks.mesh_digest(expected), "packed earth deterministically reproduces runtime geometry: " + phase)
	var stats := Earth.stats(builder)
	checker._check(int(stats["triangles"]) <= estimated_cells * 12, "soil plus contact stays inside the existing box-equivalent geometry budget: " + phase)
	checker._check(actual.get_surface_count() <= 2 and visual.stats().opaque_surface_draws <= 7, "packed-earth refinement adds zero opaque draw calls: " + phase)
	checker._check(int(stats["tufts"]) <= Earth.MAX_TUFTS and int(stats["tufts"]) <= packed.size() * Earth.MAX_PER_PATH and int(stats["grass_cells"]) <= Earth.MAX_CELLS_PER_TUFT * int(stats["tufts"]), "packed grass obeys explicit global/per-path/cell bounds: " + phase)
	checker._check(visual._style_nodes["packed_earth"].cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "dirt skin and short contact add no shadow pass: " + phase)
	var arrays: Array = actual.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var opaque_colours := colours.size() == vertices.size()
	for colour: Color in colours:
		opaque_colours = opaque_colours and is_finite(colour.r) and is_finite(colour.g) and is_finite(colour.b) and is_equal_approx(colour.a, 1.0)
	checker._check(opaque_colours, "soil/grass edge transition uses finite fully opaque vertex colours, not a terrain mask: " + phase)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var finite := true
	var extent_ok := true
	var winding := true
	var terrain_ok := true
	var terrain_heights := {}
	for vertex: Vector3 in vertices:
		finite = finite and vertex.is_finite()
		var inside := false
		for path: Dictionary in packed:
			inside = inside or _distance(Vector2(vertex.x, vertex.z), path["points"]) <= float(path["width"]) * 0.5 + 0.00003
		extent_ok = extent_ok and inside
	for index in range(0, indices.size(), 3):
		var a := vertices[indices[index]]
		var b := vertices[indices[index + 1]]
		var c := vertices[indices[index + 2]]
		winding = winding and (b - a).cross(c - a).dot(normals[indices[index]]) < -0.0000000001
		var centre := (a + b + c) / 3.0
		var scale_value := float(scene.backend.voxel_scale)
		var hit: Dictionary = scene.backend.sample_surface_plane(centre + Vector3.UP * scale_value * 0.5, Vector3.UP, scale_value * 2.0)
		var ground: Vector3 = hit.get("point", Vector3.INF)
		terrain_ok = terrain_ok and bool(hit.get("valid", false)) and absf(centre.y - ground.y - Earth.TOP_EPSILON) < 0.00003
		terrain_heights[snappedf(centre.y, 0.001)] = true
	checker._check(finite and extent_ok, "finite soil never expands beyond the saved half-width: " + phase)
	checker._check(winding, "every packed-earth top has outward clockwise winding: " + phase)
	checker._check(terrain_ok, "every soil triangle lies 0.004 above its own native terrain, not a slab-height workaround: " + phase)
	var roots_ok := true
	for root: Vector3 in builder["earth"]["roots"]:
		roots_ok = roots_ok and is_equal_approx(root.y, float(visual._surface_height(Vector2(root.x, root.z))))
		for path: Dictionary in packed:
			roots_ok = roots_ok and _distance(Vector2(root.x, root.z), path["points"]) >= float(path["width"]) * 0.30
	checker._check(roots_ok, "grass roots follow native terrain and leave the centre clear: " + phase)
	checker._check(JSON.stringify(scene.landscape_state.document()) == document, "packed-earth generation changes no path/save authority: " + phase)
	print("PACKED_EARTH_AUDIT " + JSON.stringify({"phase": phase, "baseline": PACKED_BASELINE, "geometry": stats, "height_levels": terrain_heights.size(), "opaque_surface_draws": visual.stats().opaque_surface_draws}))

static func width_cases(checker: SceneTree, scene: Node) -> void:
	for width: float in [0.25, 0.75, 3.0]:
		var builder: Dictionary = scene.path_visual._new_builder()
		var values: Array = [[7.0, 17.0], [11.0, 17.0], [14.0, 19.0]]
		Earth.append_path(scene.path_visual, builder, width, values, 719)
		var mesh := Earth.mesh_from_builder(builder)
		var stat := Earth.stats(builder)
		checker._check(mesh != null and int(stat["triangles"]) <= State._estimated_render_cells({"style_id": "packed_earth", "width": width, "points": values}) * 12, "width/bend/native-terrace case obeys unchanged geometry budget: " + str(width))
		var bounded := true
		var continuous := true
		var min_extent := INF
		var max_extent := -INF
		var asymmetric := false
		var centre_min := INF
		var centre_max := -INF
		var patch_hits := 0
		for distance_index in 400:
			var distance := float(distance_index) / 40.0
			var left := Earth.extent(width, distance, 719, -1)
			var right := Earth.extent(width, distance, 719, 1)
			asymmetric = asymmetric or absf(left - right) > width * 0.003
			for side: int in [-1, 1]:
				var edge_extent := Earth.extent(width, distance, 719, side)
				min_extent = minf(min_extent, edge_extent)
				max_extent = maxf(max_extent, edge_extent)
				bounded = bounded and edge_extent >= width * 0.415 - 0.000001 and edge_extent <= width * 0.5
				continuous = continuous and absf(edge_extent - Earth.extent(width, distance + 0.025, 719, side)) < 0.003
			var wear := Earth._interior_wear(719, distance, 0.0, width)
			centre_min = minf(centre_min, wear.x)
			centre_max = maxf(centre_max, wear.x)
			if wear.y > 0.35: patch_hits += 1
		checker._check(bounded and continuous, "coherent edges stay inside the saved footprint and preserve at least 83 percent width without sample jumps: " + str(width))
		checker._check(min_extent <= width * 0.445 and max_extent >= width * 0.485 and max_extent - min_extent >= width * 0.055 and asymmetric, "edge wear contains both near-full tongues and materially visible bounded incursions: " + str(width))
		checker._check(centre_min < 0.05 and centre_max > 0.80 and patch_hits > 0 and patch_hits < 180, "internal centre wear breaks up and directional patches stay sparse: " + str(width))

static func lifecycle(checker: SceneTree, scene: Node) -> void:
	var visual: Node = scene.path_visual
	var paths: Array = scene.landscape_state.paths.duplicate(true)
	var document := JSON.stringify(scene.landscape_state.document())
	var original := ContactChecks.mesh_digest(visual._style_nodes["packed_earth"].mesh)
	visual.rebuild(paths)
	visual.rebuild(paths)
	checker._check(ContactChecks.mesh_digest(visual._style_nodes["packed_earth"].mesh) == original, "rebuild does not reshuffle packed soil or grass")
	var reload := PathVisual.new()
	checker.root.add_child(reload)
	var restored: Array = JSON.parse_string(JSON.stringify(paths))
	restored.reverse()
	reload.rebuild(restored, scene.backend)
	checker._check(ContactChecks.mesh_digest(reload._style_nodes["packed_earth"].mesh) == original, "reloaded/reordered path records reproduce identical packed-earth output")
	reload.queue_free()
	var remaining: Array = []
	for path: Dictionary in paths:
		if str(path["style_id"]) != "packed_earth": remaining.append(path)
	visual.rebuild(remaining)
	await checker.process_frame
	checker._check(not visual._style_nodes.has("packed_earth") and not visual.stats().has("packed_earth"), "removing dirt clears both soil/contact geometry and statistics")
	visual.rebuild(paths)
	await checker.process_frame
	checker._check(ContactChecks.mesh_digest(visual._style_nodes["packed_earth"].mesh) == original, "restoring paths restores exact dirt and edge contact")
	visual.show_preview("packed_earth", 0.75, [[14.0, 14.0], [20.0, 14.0]], true, "")
	visual.hide_preview()
	checker._check(ContactChecks.mesh_digest(visual._style_nodes["packed_earth"].mesh) == original, "preview cancellation does not change committed packed earth")
	var centre := Vector3(17.0, float(visual._surface_height(Vector2(17.0, 14.0))), 14.0)
	var settings := {"radius": 0.75, "strength": 0.5, "falloff": 0.0, "surface_normal": Vector3.UP}
	checker._check(scene.backend.begin_stroke("dig", centre, settings), "native dig begins beneath dirt")
	scene.backend.update_stroke(centre, 0.5)
	checker._check(ContactChecks.mesh_digest(visual._style_nodes["packed_earth"].mesh) == original, "live terrain stroke retains committed dirt until normal refresh")
	checker._check(scene.backend.cancel_stroke(), "dirt dig can be cancelled")
	await checker.process_frame
	checker._check(ContactChecks.mesh_digest(visual._style_nodes["packed_earth"].mesh) == original, "dig cancel reproduces exact packed-earth geometry")
	checker._check(scene.backend.begin_stroke("dig", centre, settings), "second dirt dig begins")
	scene.backend.update_stroke(centre, 0.5)
	checker._check(scene.backend.end_stroke(), "dirt dig release commits")
	await checker.process_frame
	checker._check(ContactChecks.mesh_digest(visual._style_nodes["packed_earth"].mesh) != original, "terrain commit refreshes dirt without saved decoration")
	inspect(checker, scene, "after-dirt-dig")
	checker._check(scene.backend.undo(), "dirt terrain edit can be undone")
	await checker.process_frame
	checker._check(ContactChecks.mesh_digest(visual._style_nodes["packed_earth"].mesh) == original, "terrain undo restores identical packed earth")
	checker._check(JSON.stringify(scene.landscape_state.document()) == document, "dirt rebuild/remove/reload/dig/cancel/undo preserve the full saved document")

static func review(checker: SceneTree, scene: Node, directory: String) -> void:
	var candidate: Node3D = scene.path_visual
	var locked := _baseline(checker, scene)
	var packed_before := _packed_baseline(checker)
	var saved: Dictionary = scene.landscape_state.document().duplicate(true)
	for style: String in ["stepping_stones", "cobblestone"]:
		checker._check(ContactChecks.mesh_digest(locked._style_nodes[style].mesh) == ContactChecks.mesh_digest(candidate._style_nodes[style].mesh), "runtime " + style + " output is byte-identical to locked pre-dirt baseline")
	checker._check(ContactChecks.digest(locked._contact_data) == ContactChecks.digest(candidate._contact_data), "accepted stepping-stone grass output is byte-identical to locked baseline")
	var before_result := _packed_result(candidate, packed_before, scene.landscape_state.paths)
	print("PACKED_EARTH_BEFORE_COST " + JSON.stringify({"baseline": PACKED_BASELINE, "geometry": before_result["stats"], "opaque_surface_draws": candidate.stats().opaque_surface_draws}))
	var before_dir := directory.path_join("before")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(before_dir))
	var packed_node: MeshInstance3D = candidate._style_nodes["packed_earth"]
	var candidate_mesh: ArrayMesh = packed_node.mesh
	for variant in 2:
		packed_node.mesh = before_result["mesh"] if variant == 0 else candidate_mesh
		await _views(checker, scene, before_dir if variant == 0 else directory)
	packed_node.mesh = candidate_mesh

	# An additional normal saved path crosses unmodified native terraces. It is
	# created once, then both dirt helpers consume EXACTLY the same records.
	var id: int = scene.landscape_state.add_path("packed_earth", 0.75, [[7.0, 17.0], [11.0, 17.0], [14.0, 19.0]])
	checker._check(id > 0, "terrace review uses a valid native path record")
	for path: Dictionary in scene.landscape_state.paths:
		scene.landscape_state.clear_records_along_path(path["points"], float(path["width"]))
	scene.garden_visual.reset_records(scene.landscape_state.records)
	candidate.rebuild(scene.landscape_state.paths)
	var reference := JSON.stringify(scene.landscape_state.document())
	packed_node = candidate._style_nodes["packed_earth"]
	candidate_mesh = packed_node.mesh
	before_result = _packed_result(candidate, packed_before, scene.landscape_state.paths)
	for variant in 2:
		packed_node.mesh = before_result["mesh"] if variant == 0 else candidate_mesh
		var target_dir := before_dir if variant == 0 else directory
		var target := Vector3(10.5, float(candidate._surface_height(Vector2(10.5, 17.5))), 17.5)
		scene.camera.position = target + Vector3(1.5, 5.7, 7.5)
		scene.camera.look_at(target, Vector3.UP)
		await _capture(checker, scene, target_dir.path_join("packed-earth-terrace.png"))
		checker._check(JSON.stringify(scene.landscape_state.document()) == reference, "before/after terrace captures leave terrain/path authority matched")
	packed_node.mesh = candidate_mesh
	inspect(checker, scene, "terrace-review")
	scene.landscape_state.restore(saved)
	scene.garden_visual.reset_records(scene.landscape_state.records)
	scene.path_visual = candidate
	candidate.visible = true
	locked.visible = false
	locked.queue_free()
	candidate.rebuild(scene.landscape_state.paths)

static func _views(checker: SceneTree, scene: Node, directory: String) -> void:
	if scene.hud: scene.hud.visible = true
	scene.cursor = Vector3(24.0, 8.0, 24.0)
	scene.camera_yaw = -1.1
	scene.camera_pitch = 0.66
	scene.camera_distance = 36.0
	scene._update_camera()
	scene._update_presentation()
	scene._refresh_controller_hud()
	await _capture(checker, scene, directory.path_join("all-styles.png"))
	if scene.hud: scene.hud.visible = false
	var old_dir: String = checker.screenshot_dir
	checker.screenshot_dir = directory
	await checker._capture_stepping_close_views()
	checker.screenshot_dir = old_dir
	var target := Vector3(18.5, float(scene.path_visual._surface_height(Vector2(18.5, 14.5))), 14.5)
	for view: String in ["packed-earth-close", "packed-earth-reverse"]:
		var direction := Vector3(-4.0, 5.6, 4.8) if view == "packed-earth-close" else Vector3(4.0, 5.6, -4.8)
		scene.camera.position = target + direction
		scene.camera.look_at(target, Vector3.UP)
		await _capture(checker, scene, directory.path_join(view + ".png"))

static func _capture(checker: SceneTree, scene: Node, path: String) -> void:
	for frame in 4: await RenderingServer.frame_post_draw
	var image: Image = checker.root.get_texture().get_image()
	checker._check(RenderingServer.get_current_rendering_method() == "mobile" and image.get_size() == Vector2i(1280, 720), "native actual-Mobile paired capture exists: " + path)
	checker._check(image.save_png(path) == OK, "paired capture saved: " + path)
	checker.captures += 1
