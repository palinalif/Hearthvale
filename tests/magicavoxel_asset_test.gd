extends SceneTree

const Flora := preload("res://scripts/vegetation_mesh.gd")
const UNIT := 0.125
const CANDIDATE_PATH := "res://assets/models/magicavoxel/hearthvale_tree_pilot_broad.res"
const EXPECTED_PALETTE := [Color("#765942"), Color("#638348"), Color("#486d46"), Color("#87a657")]

var checks := 0
var failures := 0

func _initialize() -> void:
	var candidate: Mesh = load(CANDIDATE_PATH)
	_check(candidate != null, "converted MagicaVoxel candidate imports as a Mesh")
	if candidate == null:
		_finish(0, 0)
		return
	var candidate_triangles := _inspect(candidate, "candidate")
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
	if rendered:
		await _render_comparison(candidate)
	_finish(candidate_triangles, current_triangles)

func _inspect(mesh: Mesh, label: String) -> int:
	var triangles := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var aligned := not vertices.is_empty()
		var worst_error := 0.0
		var worst_vertex := Vector3.ZERO
		for vertex in vertices:
			for axis in 3:
				var error := absf(vertex[axis] / UNIT - roundf(vertex[axis] / UNIT))
				if error > worst_error: worst_error = error; worst_vertex = vertex
				aligned = aligned and error < 0.0002
		if not aligned: print("GRID DIAGNOSTIC %s surface=%d vertex=%s error=%.7f" % [label, surface, str(worst_vertex), worst_error])
		_check(aligned, label + " vertices use the 0.125 grid")
		var axis_aligned := true
		for index in range(0, indices.size(), 3):
			var normal := (vertices[indices[index + 1]] - vertices[indices[index]]).cross(vertices[indices[index + 2]] - vertices[indices[index]]).normalized().abs()
			axis_aligned = axis_aligned and maxf(normal.x, maxf(normal.y, normal.z)) > 0.9999
		_check(axis_aligned, label + " remains cubic after import")
		triangles += indices.size() / 3
	return triangles

func _render_comparison(candidate: Mesh) -> void:
	var scene := Node3D.new(); root.add_child(scene)
	var ground := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(12, 8); ground.mesh = plane
	var ground_material := StandardMaterial3D.new(); ground_material.albedo_color = Color("#91aa68"); ground.material_override = ground_material; scene.add_child(ground)
	for mesh: Mesh in Flora.meshes("tree", 0):
		var part := MeshInstance3D.new(); part.mesh = mesh; part.position.x = -2.5; scene.add_child(part)
	var authored := MeshInstance3D.new(); authored.mesh = candidate; authored.position.x = 2.5; scene.add_child(authored)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, -30, 0); sun.shadow_enabled = true; scene.add_child(sun)
	var environment_node := WorldEnvironment.new(); var environment := Environment.new(); environment.background_mode = Environment.BG_COLOR; environment.background_color = Color("#c3d2c5"); environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color = Color("#c2d5e0"); environment.ambient_light_energy = 0.55; environment_node.environment = environment; scene.add_child(environment_node)
	var camera := Camera3D.new(); camera.position = Vector3(9, 6.5, 12); camera.look_at_from_position(camera.position, Vector3(0, 2.5, 0)); camera.current = true; scene.add_child(camera)
	for unused in 20: await process_frame
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with("--capture="):
			var path := str(argument).trim_prefix("--capture=")
			_check(root.get_viewport().get_texture().get_image().save_png(path) == OK, "comparison capture saved")
	scene.queue_free(); await process_frame

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: " + label)

func _finish(candidate_triangles: int, current_triangles: int) -> void:
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "candidate_triangles": candidate_triangles, "current_triangles": current_triangles, "renderer": RenderingServer.get_current_rendering_method()}))
	quit(1 if failures else 0)
