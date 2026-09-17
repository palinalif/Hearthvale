extends SceneTree
## Verifies the region-water surface localizes its per-edit resample to the
## dirty bounds (like the river and waterfalls) instead of rescanning every
## column: a local edit updates only the affected quad, a far edit (no bumped
## cell) leaves the surface unchanged, and a local restore puts the quad back.

const Visual = preload("res://scripts/water_visual.gd")

var checks := 0
var failures := 0

class MockBackend:
	extends Node
	var voxel_scale := 0.125
	var patch_size := Vector3i(40, 16, 40)
	var surface := 8
	var bumps := {}
	var _rev := 0
	var last_edit_bounds := AABB()
	func is_ready() -> bool: return true
	func revision() -> int: return _rev
	func bump() -> void: _rev += 1
	func get_last_edit_bounds() -> AABB: return last_edit_bounds
	func _col_surface(x: int, z: int) -> int:
		return surface + int(bumps.get(Vector2i(x, z), 0))
	func voxel_at(p: Vector3i) -> int:
		if p.x < 0 or p.z < 0 or p.x >= patch_size.x or p.z >= patch_size.z: return 0
		return 1 if p.y < _col_surface(p.x, p.z) else 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _initialize() -> void:
	var mock: Node = MockBackend.new()
	root.add_child(mock)
	var visual: Node = Visual.new()
	root.add_child(visual)
	visual.attach_backend(mock)
	# A small lake near the origin so the far test has dry ground to work on.
	var lake := {"id": 1, "type": "lake", "level": 1.5, "points": [[0.0, 0.0], [1.5, 0.0], [1.5, 1.5], [0.0, 1.5]]}
	visual.set_regions([lake])
	var whole: int = visual.surface_quad_count()
	check(whole > 0, "initial surface built (quads=%d)" % whole)

	# Local edit: raise one in-water column (voxel 8,8 -> world 1.0) above the
	# 1.5 m level; the bounded resample must dry just that quad.
	mock.bumps[Vector2i(8, 8)] = 8
	mock.bump()
	mock.last_edit_bounds = AABB(Vector3(1.0, 0.0, 1.0), Vector3(0.125, 1.0, 0.125))
	visual.refresh_surface_from_bounds(mock.last_edit_bounds)
	visual._do_surface_rebuild()  # simulate the deferred end-of-frame flush
	var after_local: int = visual.surface_quad_count()
	check(after_local == whole - 1, "localized edit dried one quad (before=%d after=%d)" % [whole, after_local])

	# Far edit (no bumped cell): the bounded resample touches no changed cell,
	# so the surface count is unchanged.
	mock.last_edit_bounds = AABB(Vector3(4.5, 0.0, 4.5), Vector3(0.125, 1.0, 0.125))
	visual.refresh_surface_from_bounds(mock.last_edit_bounds)
	visual._do_surface_rebuild()
	check(visual.surface_quad_count() == after_local, "far edit leaves the surface unchanged (quads=%d)" % visual.surface_quad_count())

	# Local restore: lower the column; the quad returns.
	mock.bumps[Vector2i(8, 8)] = 0
	mock.bump()
	mock.last_edit_bounds = AABB(Vector3(1.0, 0.0, 1.0), Vector3(0.125, 1.0, 0.125))
	visual.refresh_surface_from_bounds(mock.last_edit_bounds)
	visual._do_surface_rebuild()
	check(visual.surface_quad_count() == whole, "localized restore returns the quad (quads=%d)" % visual.surface_quad_count())

	visual.queue_free()
	mock.queue_free()
	print("water_surface_local_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
