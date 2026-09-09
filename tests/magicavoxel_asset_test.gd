extends SceneTree

const Flora := preload("res://scripts/vegetation_mesh.gd")
const UNIT := 0.0625
const TERRAIN_UNIT := 0.125
const CANDIDATE_PATH := "res://assets/models/magicavoxel/hearthvale_tree_pilot_broad.res"
const EXPECTED_PALETTE := [Color("#765942"), Color("#638348"), Color("#486d46"), Color("#87a657")]

var checks := 0
var failures := 0
var candidate_results: Array = []

func _initialize() -> void:
	var candidate: Mesh = load(CANDIDATE_PATH)
	_check(candidate != null, "converted MagicaVoxel candidate imports as a Mesh")
	if candidate == null:
		_finish(0, 0)
		return
	var candidate_triangles := _inspect(candidate, "candidate", TERRAIN_UNIT)
	var current_triangles := 0
	for mesh: Mesh in Flora.meshes("tree", 0): current_triangles += _inspect(mesh, "current tree")
	var bounds := candidate.get_aabb()
	_check(bounds.size.y <= 6.0 and bounds.size.x <= 4.0 and bounds.size.z <= 4.0, "candidate stays within the M1 tree silhouette budget")
	_check(bounds.position.y >= -0.001 and bounds.position.y <= 0.001, "candidate pivot sits on the ground")
	_check(candidate.get_surface_count() == 4, "candidate preserves the four authored palette groups")
	for surface in mini(candidate.get_surface_count(), EXPECTED_PALETTE.size()):
		var material := candidate.surface_get_material(surface) as StandardMaterial3D
		_check(material != null and material.albedo_color.is_equal_approx(EXPECTED_PALETTE[surface]), "candidate palette group %d preserves its authored color" % [surface + 1])
	_check(candidate_triangles <= 8000, "candidate remains below the pilot triangle ceiling")

	var rendered := DisplayServer.get_name() != "headless"
	if "--require-rendering" in OS.get_cmdline_user_args():
		_check(rendered and RenderingServer.get_current_rendering_method() == "mobile", "actual Mobile renderer is active")
	for variant in 3:
		var names := ["orchard", "riverside", "wind"]
		var name: String = names[variant]
		var path := "res://assets/models/magicavoxel/hearthvale_tree_" + name
		var authored := load(path + ".res") as Mesh
		_check(authored != null, name + " baked mesh exists")
		if authored == null: continue
		var triangles := _inspect(authored, name)
		var receipt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + ".asset.json"))
		var source := "res://assets/source/magicavoxel/" + str(receipt.source)
		_check(FileAccess.get_sha256(source) == receipt.source_sha256, name + " provenance matches source bytes")
		_check(receipt.tool_commit == "710671d49bdc89e4e3d1ff7c60541c1d0383ac16" and receipt.voxel_unit == UNIT and receipt.voxel_tier == "prop/detail", name + " pinned tool and prop-grid receipt")
		_check(triangles == int(receipt.triangles) and triangles <= 8000, name + " triangle receipt and budget")
		var box := authored.get_aabb()
		var declared: Array = receipt.declared_dimensions
		var occupied: Dictionary = receipt.occupied_bounds
		var expected_min := Vector3(float(occupied.min[0]) - float(declared[0]) / 2, float(occupied.min[1]), float(occupied.min[2]) - float(declared[2]) / 2) * UNIT
		var expected_max := Vector3(float(occupied.max[0]) - float(declared[0]) / 2, float(occupied.max[1]), float(occupied.max[2]) - float(declared[2]) / 2) * UNIT
		_check(box.position.is_equal_approx(expected_min) and box.end.is_equal_approx(expected_max), name + " declared horizontal centre pivot and occupied bounds")
		_check(absf(box.position.y) < 0.0001, name + " ground pivot")
		var current_box := AABB()
		var current_count := 0
		for mesh: Mesh in Flora.meshes("tree", variant):
			current_box = current_box.merge(mesh.get_aabb())
			current_count += _inspect(mesh, name + " procedural reference")
		var ratio := box.size / current_box.size
		_check(ratio.x >= 0.75 and ratio.x <= 1.2 and ratio.y >= 0.85 and ratio.y <= 1.15 and ratio.z >= 0.75 and ratio.z <= 1.2, name + " dimensions match corresponding procedural tree")
		_check(authored.get_surface_count() == 4 and PackedInt32Array(receipt.palette_indices) == PackedInt32Array([1, 2, 3, 4]), name + " four palette groups")
		for surface in authored.get_surface_count():
			var material := authored.surface_get_material(surface) as StandardMaterial3D
			_check(material != null and material.albedo_color.is_equal_approx(EXPECTED_PALETTE[surface]), name + " palette color preserved")
			_check(material != null and is_zero_approx(material.metallic) and is_equal_approx(material.roughness, 1.0), name + " matte foliage/bark shading")
		candidate_results.append({"name": name, "triangles": triangles, "procedural_triangles": current_count, "bounds": str(box)})
		if rendered: await _render_comparison(authored, variant, name)
	_finish(candidate_triangles, current_triangles)

func _inspect(mesh: Mesh, label: String, unit: float = UNIT) -> int:
	var triangles := 0
	var smallest_axis_edge := INF
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var aligned := not vertices.is_empty()
		var worst_error := 0.0
		var worst_vertex := Vector3.ZERO
		for vertex in vertices:
			for axis in 3:
				var error := absf(vertex[axis] / unit - roundf(vertex[axis] / unit))
				if error > worst_error: worst_error = error; worst_vertex = vertex
				aligned = aligned and error < 0.0002
		if not aligned: print("GRID DIAGNOSTIC %s surface=%d vertex=%s error=%.7f" % [label, surface, str(worst_vertex), worst_error])
		_check(aligned, label + " vertices use the %.4f grid" % unit)
		var axis_aligned := true
		for index in range(0, indices.size(), 3):
			var triangle: Array[Vector3] = [vertices[indices[index]], vertices[indices[index + 1]], vertices[indices[index + 2]]]
			var normal: Vector3 = (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).normalized().abs()
			axis_aligned = axis_aligned and maxf(normal.x, maxf(normal.y, normal.z)) > 0.9999
			for edge: Vector3 in [triangle[1] - triangle[0], triangle[2] - triangle[1], triangle[0] - triangle[2]]:
				var changed_axes := int(not is_zero_approx(edge.x)) + int(not is_zero_approx(edge.y)) + int(not is_zero_approx(edge.z))
				if changed_axes == 1: smallest_axis_edge = minf(smallest_axis_edge, edge.length())
		_check(axis_aligned, label + " remains cubic after import")
		triangles += indices.size() / 3
	_check(is_equal_approx(smallest_axis_edge, unit), label + " exposes the selected voxel edge")
	return triangles

func _surface_mean_y(mesh: Mesh, surface: int) -> float:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	var total := 0.0
	for vertex in vertices: total += vertex.y
	return total / float(vertices.size())

func _render_comparison(candidate: Mesh, variant: int = 0, name: String = "pilot") -> void:
	var scene := Node3D.new(); root.add_child(scene)
	var ground := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(12, 8); ground.mesh = plane
	var ground_material := StandardMaterial3D.new(); ground_material.albedo_color = Color("#91aa68"); ground.material_override = ground_material; scene.add_child(ground)
	for mesh: Mesh in Flora.meshes("tree", variant):
		var part := MeshInstance3D.new(); part.mesh = mesh; part.position.x = -2.5; scene.add_child(part)
	var authored := MeshInstance3D.new(); authored.mesh = candidate; authored.position.x = 2.5; scene.add_child(authored)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, -30, 0); sun.shadow_enabled = true; scene.add_child(sun)
	var environment_node := WorldEnvironment.new(); var environment := Environment.new(); environment.background_mode = Environment.BG_COLOR; environment.background_color = Color("#c3d2c5"); environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color = Color("#c2d5e0"); environment.ambient_light_energy = 0.55; environment_node.environment = environment; scene.add_child(environment_node)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 12.5; camera.position = Vector3(3.5, 6.5, 15); camera.look_at_from_position(camera.position, Vector3(0, 2.5, 0)); camera.current = true; scene.add_child(camera)
	if "--normal-distance" in OS.get_cmdline_user_args(): camera.size = 20.0
	if "--reverse" in OS.get_cmdline_user_args():
		camera.look_at_from_position(Vector3(-3.5, 6.5, -15), Vector3(0, 2.5, 0))
	var overlay := CanvasLayer.new(); scene.add_child(overlay)
	var title := Label.new(); title.text = "HEARTHVALE / " + name.to_upper() + " / REVIEW ONLY"; title.position = Vector2(30, 20); title.add_theme_font_size_override("font_size", 26); title.modulate = Color("#26392f"); overlay.add_child(title)
	var labels := Label.new(); labels.text = "CURRENT PROCEDURAL                                      MCP CANDIDATE"; labels.position = Vector2(210, 645); labels.add_theme_font_size_override("font_size", 23); labels.modulate = Color("#26392f"); overlay.add_child(labels)
	if "--reverse" in OS.get_cmdline_user_args(): labels.text = "MCP CANDIDATE                                      CURRENT PROCEDURAL"
	for unused in 20: await process_frame
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with("--capture="):
			var path := str(argument).trim_prefix("--capture=").get_basename() + "-" + name + ".png"
			_check(root.get_viewport().get_texture().get_image().save_png(path) == OK, "comparison capture saved")
	scene.queue_free(); await process_frame

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: " + label)

func _finish(candidate_triangles: int, current_triangles: int) -> void:
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "candidate_triangles": candidate_triangles, "current_triangles": current_triangles, "candidates": candidate_results, "renderer": RenderingServer.get_current_rendering_method()}))
	quit(1 if failures else 0)
