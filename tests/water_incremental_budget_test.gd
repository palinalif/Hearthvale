extends SceneTree
const Visual = preload("res://scripts/water_visual.gd")
var checks := 0
var failures := 0

class MockBackend:
	extends Node
	var voxel_scale := 0.125
	var patch_size := Vector3i(80, 32, 80)
	var calls := 0
	var bumps := {}
	func is_ready() -> bool: return true
	func revision() -> int: return 0
	func voxel_at(p: Vector3i) -> int:
		calls += 1
		return 1 if p.y < int(bumps.get(Vector2i(p.x, p.z), 8)) else 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)

func drain(visual: Node) -> void:
	for frame in range(1000):
		visual._process(1.0 / 60.0)
		if visual._pending_cells.is_empty() and visual._dirty_regions.is_empty() and visual._pending_surface_bounds.is_empty(): return
	check(false, "budgeted work eventually finishes")

func _initialize() -> void:
	var backend := MockBackend.new()
	var visual := Visual.new()
	visual.attach_backend(backend)
	var lake := {"id": 1, "type": "lake", "level": 1.5, "points": [[0, 0], [10, 0], [10, 10], [0, 10]]}
	visual.set_regions_incremental([lake])
	visual.set_regions_incremental([lake])
	check(backend.calls == 0, "repeated setters do no synchronous terrain work")
	drain(visual)
	check(visual.surface_quad_count() == 6400, "large lake completes across multiple frame budgets")
	var node: MeshInstance3D = visual._region_nodes[1]
	var arrays := node.mesh.surface_get_arrays(0) # Test-only readback to verify the actual mesh.
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var used := {}
	for index: int in indices: used[index] = true
	check(used.size() == vertices.size(), "every vertex is referenced after multi-frame builds")
	check(indices[indices.size() - 1] == vertices.size() - 1, "later batches use vertex offsets, not quad offsets")
	backend.calls = 0
	var mesh := node.mesh
	visual.set_regions_incremental([lake])
	visual._process(0.016)
	check(backend.calls == 0 and node.mesh == mesh, "unchanged regions keep their uploaded mesh and cached columns")
	backend.bumps[Vector2i(40, 40)] = 16
	var bounds := AABB(Vector3(5, 1, 5), Vector3(0.125, 1, 0.125))
	visual.refresh_surface_from_bounds(bounds)
	visual.refresh_surface_from_bounds(bounds)
	check(backend.calls == 0, "duplicate terrain notifications only queue work")
	drain(visual)
	check(visual.surface_quad_count() == 6399, "localized raise dries exactly one cell")
	check(backend.calls < 1000, "local edit resamples only nearby water columns")
	visual.set_regions_incremental([])
	drain(visual)
	check(visual.surface_quad_count() == 0, "removal clears the uploaded quad count")
	# A pending preview may be cancelled before its columns have been sampled.
	backend.calls = 0
	visual.set_regions_incremental([lake])
	visual.set_regions_incremental([])
	drain(visual)
	check(visual.surface_quad_count() == 0 and backend.calls == 0, "cancelled work cannot resurrect the surface")
	visual.free()
	backend.free()
	print("water_incremental_budget_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
