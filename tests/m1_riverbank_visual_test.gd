extends SceneTree

const Generator := preload("res://scripts/m1_patch_generator.gd")
const SceneScript := preload("res://scripts/m1_scene.gd")

var checks := 0
var failures := 0

class SavedV2Backend extends Node:
	func is_ready() -> bool: return true
	func voxel_at(cell: Vector3i) -> int:
		if cell.y == 24: return 1
		if cell.y == 39 and not (cell.x >= 312 and cell.z >= 80 and cell.z < 348): return 1
		return 0

func _initialize() -> void:
	var min_center := INF
	var max_center := -INF
	var min_width := INF
	var max_width := -INF
	for z_index in range(0, Generator.PATCH_SIZE.z + 1, 8):
		var z := float(z_index) * Generator.VOXEL_SCALE
		var center := Generator.river_center_x(z)
		var width := Generator.river_half_width(z) * 2.0
		min_center = minf(min_center, center); max_center = maxf(max_center, center)
		min_width = minf(min_width, width); max_width = maxf(max_width, width)
		_check(_on_grid(center) and _on_grid(width), "river bounds remain on the native grid")
		_check(Generator.terrain_height(center, z) < 5.0, "river bed stays below the water surface")
		_check(Generator.terrain_height(center - width * 0.5 - 0.25, z) >= 5.0, "west shoreline stays above water")
		_check(Generator.terrain_height(center + width * 0.5 + 0.25, z) >= 5.0, "east shoreline stays above water")
	_check(max_center - min_center >= 1.5, "river has a readable meander")
	_check(max_width - min_width >= 0.5, "river width varies along its course")
	_check(is_equal_approx(Generator.terrain_height(20.0, 18.0), 8.0), "cottage pad remains unchanged")

	var scene := SceneScript.new()
	root.add_child(scene)
	var mesh: ArrayMesh = scene._build_river_water_mesh()
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_check(vertices.size() == (Generator.PATCH_SIZE.z + 1) * 2, "water strip covers the complete river")
	var grid_aligned := true
	for vertex in vertices:
		grid_aligned = grid_aligned and _on_grid(vertex.x) and _on_grid(vertex.z) and is_zero_approx(vertex.y)
	_check(grid_aligned, "water shoreline vertices follow native terrain steps")
	var clockwise_up := true
	for index in range(0, indices.size(), 3):
		var a := vertices[indices[index]]
		var b := vertices[indices[index + 1]]
		var c := vertices[indices[index + 2]]
		clockwise_up = clockwise_up and (b - a).cross(c - a).dot(normals[indices[index]]) < 0.0
	_check(clockwise_up, "water triangles face upward in Godot's clockwise convention")
	# Existing v2 saves retain their authored straight channel. Rebuilding the
	# surface from authoritative cells must follow that old terrain rather than
	# imposing the new fresh-world bend across it.
	scene.river_water = MeshInstance3D.new()
	scene.backend = SavedV2Backend.new()
	scene.add_child(scene.river_water)
	scene.add_child(scene.backend)
	scene._refresh_river_water_from_terrain()
	var saved_vertices: PackedVector3Array = scene.river_water.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var saved_min := Vector3(INF, INF, INF); var saved_max := Vector3(-INF, -INF, -INF)
	for vertex in saved_vertices:
		saved_min = saved_min.min(vertex); saved_max = saved_max.max(vertex)
	_check(is_equal_approx(saved_min.x, 39.0) and is_equal_approx(saved_max.x, 48.0), "saved v2 water follows its original channel width")
	_check(is_equal_approx(saved_min.z, 10.0) and is_equal_approx(saved_max.z, 43.5), "saved v2 water follows its original channel length")
	scene.queue_free()
	await process_frame
	await process_frame
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "center_span": max_center - min_center, "width_span": max_width - min_width}))
	quit(1 if failures else 0)

func _on_grid(value: float) -> bool:
	return absf(value / Generator.VOXEL_SCALE - roundf(value / Generator.VOXEL_SCALE)) < 0.0002

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)
