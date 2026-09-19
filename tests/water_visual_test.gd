extends SceneTree
## Locks the authored-water presentation build (river slice 3): a clipped,
## animated water surface derived from the region records + terrain. Uses a mock
## backend (flat floor + optional bumps) so the build pipeline is testable
## headless without the native voxel module; the native-backed leg is CI-gated by
## the live scene test. Water clips to both the region boundary and the terrain
## (only cells below the level carry a quad).

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
	func is_ready() -> bool: return true
	func revision() -> int: return _rev
	func bump() -> void: _rev += 1
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

func _whole_lake() -> Dictionary:
	return {"id": 1, "type": "lake", "level": 1.5, "points": [[0.0, 0.0], [5.0, 0.0], [5.0, 5.0], [0.0, 5.0]]}

func _corner_lake() -> Dictionary:
	return {"id": 2, "type": "lake", "level": 1.5, "points": [[0.0, 0.0], [2.0, 0.0], [2.0, 2.0], [0.0, 2.0]]}

func _make(backend: Node, regions: Array) -> Node:
	var visual: Node = Visual.new()
	root.add_child(visual)
	visual.attach_backend(backend)
	visual.set_regions(regions)
	return visual

func _verify_build() -> void:
	var mock: Node = MockBackend.new()
	root.add_child(mock)
	var visual := _make(mock, [_whole_lake()])
	var whole: int = visual.surface_quad_count()
	check(whole > 0, "whole-patch lake produces a water surface (quads=%d)" % whole)
	# Flat floor (top 1.0 m) is below the 1.5 m level: every footprint cell is
	# submerged, so the surface must cover the whole region.
	check(whole >= 1500, "submerged floor is fully covered (quads=%d)" % whole)
	visual.queue_free(); mock.queue_free()

func _verify_boundary_clip() -> void:
	var mock: Node = MockBackend.new()
	root.add_child(mock)
	var corner := _make(mock, [_corner_lake()])
	var corner_count: int = corner.surface_quad_count()
	check(corner_count > 0 and corner_count <= 300, "corner lake clips to its boundary (quads=%d)" % corner_count)
	corner.queue_free(); mock.queue_free()

func _verify_terrain_clip() -> void:
	var mock: Node = MockBackend.new()
	root.add_child(mock)
	var visual := _make(mock, [_whole_lake()])
	var before: int = visual.surface_quad_count()
	# Raise a column to 2.0 m (above the 1.5 m level): that cell must dry out.
	mock.bumps[Vector2i(20, 20)] = 8
	mock.bump()
	visual.refresh_terrain()
	var after: int = visual.surface_quad_count()
	check(after == before - 1, "bumping terrain above the level removes one quad (before=%d after=%d)" % [before, after])
	# Lower it back and the quad returns.
	mock.bumps[Vector2i(20, 20)] = 0
	mock.bump()
	visual.refresh_terrain()
	check(visual.surface_quad_count() == before, "lowering terrain restores the quad")
	visual.queue_free(); mock.queue_free()

func _verify_determinism() -> void:
	var mock: Node = MockBackend.new()
	root.add_child(mock)
	var visual := _make(mock, [_whole_lake()])
	var a: int = visual.surface_quad_count()
	visual.refresh_terrain()
	var b: int = visual.surface_quad_count()
	check(a == b and a > 0, "surface build is deterministic (a=%d b=%d)" % [a, b])
	visual.queue_free(); mock.queue_free()

func _verify_stream() -> void:
	var mock: Node = MockBackend.new()
	root.add_child(mock)
	var stream := {"id": 3, "type": "stream", "level": 1.5, "width": 1.0, "flow": [1.0, 0.0], "points": [[0.5, 2.5], [4.5, 2.5]]}
	var visual := _make(mock, [stream])
	var count: int = visual.surface_quad_count()
	check(count > 0, "stream produces a water surface (quads=%d)" % count)
	visual.queue_free(); mock.queue_free()

func _verify_dry() -> void:
	var mock: Node = MockBackend.new()
	root.add_child(mock)
	# Floor top (1.0 m) above the level (0.5 m): nothing is submerged.
	mock.surface = 8
	var dry_lake := {"id": 4, "type": "lake", "level": 0.5, "points": [[0.0, 0.0], [5.0, 0.0], [5.0, 5.0], [0.0, 5.0]]}
	var visual := _make(mock, [dry_lake])
	check(visual.surface_quad_count() == 0, "terrain above the level produces no water")
	visual.queue_free(); mock.queue_free()

func _initialize() -> void:
	_verify_build()
	_verify_boundary_clip()
	_verify_terrain_clip()
	_verify_determinism()
	_verify_stream()
	_verify_dry()
	print("water_visual_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
