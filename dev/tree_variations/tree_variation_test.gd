extends SceneTree

const TreeVariationScript := preload("res://dev/tree_variations/tree_variation.gd")

var checks := 0
var failures := 0
var results: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run_checks")

func _run_checks() -> void:
	var variants := ["compact", "tall", "asymmetric"]
	var generated: Dictionary = {}
	for kind in variants:
		var first: Node3D = TreeVariationScript.build_variant(kind, 1042)
		var second: Node3D = TreeVariationScript.build_variant(kind, 1042)
		get_root().add_child(first)
		_check(first.scale.is_equal_approx(Vector3.ONE), "%s identity root scale" % kind)
		_check(first.get_meta("tree_stats") == second.get_meta("tree_stats"), "%s deterministic stats" % kind)
		_check(first.get_meta("tree_cell_coordinates") == second.get_meta("tree_cell_coordinates"), "%s deterministic coordinates" % kind)
		_check(_check_cubic_grid(first, kind), "%s cubic cells and grid transforms" % kind)
		_check(_check_cube_normals(first), "%s outward cube normals" % kind)
		_check(_check_unique_coordinates(first), "%s unique rendered coordinates" % kind)
		_check(_check_woody_connected(first), "%s connected woody support" % kind)
		var stats: Dictionary = first.get_meta("tree_stats")
		_check(int(stats["draw_groups"]) <= 4, "%s bounded draw groups" % kind)
		_check(int(stats["total_cells"]) <= 1200, "%s bounded cell count" % kind)
		generated[kind] = stats
		results.append({"kind": kind, "stats": stats})
		first.free()
		second.free()
		var rotated_frame := Node3D.new()
		rotated_frame.position = Vector3(2.3, 1.1, -4.0)
		rotated_frame.rotation = Vector3(0.08, 0.42, -0.05)
		get_root().add_child(rotated_frame)
		var framed: Node3D = TreeVariationScript.build_variant(kind, 1042)
		rotated_frame.add_child(framed)
		_check(_check_cubic_grid(framed, "%s translated/rotated" % kind), "%s complete transform check" % kind)
		rotated_frame.free()
		var scaled_frame := Node3D.new()
		scaled_frame.scale = Vector3(1.1, 1.0, 1.0)
		get_root().add_child(scaled_frame)
		var scaled: Node3D = TreeVariationScript.build_variant(kind, 1042)
		scaled_frame.add_child(scaled)
		_check(not _check_cubic_grid(scaled, "%s deliberately scaled" % kind), "%s rejects scaled fixture" % kind)
		scaled_frame.free()
	_check(generated["compact"]["bounds_size_cells"] != generated["tall"]["bounds_size_cells"], "compact and tall bounds differ")
	_check(generated["tall"]["bounds_size_cells"] != generated["asymmetric"]["bounds_size_cells"], "tall and asymmetric bounds differ")
	_check(generated["compact"]["bounds_size_cells"] != generated["asymmetric"]["bounds_size_cells"], "compact and asymmetric bounds differ")
	_check(generated["compact"]["total_cells"] != generated["asymmetric"]["total_cells"], "compact and asymmetric occupancy differs")
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "cell_size": TreeVariationScript.CELL_SIZE, "variants": results}))
	quit(1 if failures else 0)

func _check_cubic_grid(root: Node3D, kind: String) -> bool:
	var cell_size: float = root.get_meta("tree_cell_size")
	var expected_edge := Vector3.ONE * cell_size
	var count := 0
	for child in root.get_children():
		var instance := child as MeshInstance3D
		if instance == null or instance.mesh == null: return false
		if instance.mesh.get_surface_count() == 0: continue
		var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		if vertices.size() % 24 != 0: return false
		for offset in range(0, vertices.size(), 24):
			var local_min := vertices[offset]
			var local_max := vertices[offset]
			for vertex_index in range(offset + 1, offset + 24):
				local_min = Vector3(minf(local_min.x, vertices[vertex_index].x), minf(local_min.y, vertices[vertex_index].y), minf(local_min.z, vertices[vertex_index].z))
				local_max = Vector3(maxf(local_max.x, vertices[vertex_index].x), maxf(local_max.y, vertices[vertex_index].y), maxf(local_max.z, vertices[vertex_index].z))
			var local_edge := local_max - local_min
			var world_edge := local_edge * instance.global_transform.basis.get_scale()
			if not local_edge.is_equal_approx(expected_edge) or not world_edge.is_equal_approx(expected_edge): return false
			count += 1
			var center := (local_min + local_max) * 0.5
			var root_center: Vector3 = root.global_transform.affine_inverse() * (instance.global_transform * center)
			var grid := root_center / cell_size
			if grid.distance_to(Vector3(round(grid.x), round(grid.y), round(grid.z))) > 0.001: return false
	_check(count == int((root.get_meta("tree_stats") as Dictionary)["total_cells"]), "%s metadata count matches transforms" % kind)
	return true

func _check_unique_coordinates(root: Node3D) -> bool:
	var coordinates := {}
	for child in root.get_children():
		var instance := child as MeshInstance3D
		if instance == null or instance.mesh == null or instance.mesh.get_surface_count() == 0: continue
		var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for offset in range(0, vertices.size(), 24):
			var local_min := vertices[offset]
			var local_max := vertices[offset]
			for vertex_index in range(offset + 1, offset + 24):
				local_min = Vector3(minf(local_min.x, vertices[vertex_index].x), minf(local_min.y, vertices[vertex_index].y), minf(local_min.z, vertices[vertex_index].z))
				local_max = Vector3(maxf(local_max.x, vertices[vertex_index].x), maxf(local_max.y, vertices[vertex_index].y), maxf(local_max.z, vertices[vertex_index].z))
			var center := (local_min + local_max) * 0.5
			var root_center: Vector3 = root.global_transform.affine_inverse() * (instance.global_transform * center)
			var cell := Vector3i(roundi(root_center.x / TreeVariationScript.CELL_SIZE), roundi(root_center.y / TreeVariationScript.CELL_SIZE), roundi(root_center.z / TreeVariationScript.CELL_SIZE))
			if coordinates.has(cell): return false
			coordinates[cell] = true
	return true

func _check_cube_normals(root: Node3D) -> bool:
	for child in root.get_children():
		var instance := child as MeshInstance3D
		if instance == null or instance.mesh == null or instance.mesh.get_surface_count() == 0: continue
		var arrays := instance.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for triangle in range(0, indices.size(), 3):
			var a: Vector3 = vertices[indices[triangle]]
			var b: Vector3 = vertices[indices[triangle + 1]]
			var c: Vector3 = vertices[indices[triangle + 2]]
			var face_normal := (b - a).cross(c - a).normalized()
			if face_normal.dot(normals[indices[triangle]].normalized()) < 0.99: return false
	return true

func _check_woody_connected(root: Node3D) -> bool:
	var cells: Array = root.get_meta("tree_woody_cells", [])
	if cells.is_empty(): return false
	var all := {}
	for cell in cells: all[cell] = true
	var seen := {cells[0]: true}
	var queue: Array = [cells[0]]
	while not queue.is_empty():
		var current: Vector3i = queue.pop_front()
		for offset in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
			var next: Vector3i = current + offset
			if all.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen.size() == all.size()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)
