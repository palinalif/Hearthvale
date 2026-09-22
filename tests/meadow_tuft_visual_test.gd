extends SceneTree

## Locks the meadow tuft presentation build (living-grass, part 2 integration):
## deterministic mesh build from a terrain revision, native-column validation,
## exclusion handling and the batched single-draw-call budget. Uses a mock
## backend (flat grass) so the build pipeline is testable headless without the
## native voxel module; native-backed legs are CI-gated by the live scene test.

const Garden = preload("res://scripts/m1_garden_visual.gd")
const Tone = preload("res://scripts/grass_tone.gd")

var checks := 0
var failures := 0

class MockBackend:
	extends Node
	var voxel_scale := 0.125
	var patch_size := Vector3i(512, 256, 512)
	var surface := 8
	var _rev := 0
	var reads := 0
	var edit_bounds := AABB()
	var removed: Dictionary = {}
	func is_ready() -> bool: return true
	func revision() -> int: return _rev
	func bump() -> void: _rev += 1
	func get_last_edit_bounds() -> AABB: return edit_bounds
	func voxel_at(p: Vector3i) -> int:
		reads += 1
		if removed.has(Vector2i(p.x, p.z)): return 0
		if p.x < 0 or p.z < 0 or p.x >= patch_size.x or p.z >= patch_size.z: return 0
		if p.y == surface: return 2
		if p.y < surface: return 1
		return 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _vertex_count(node: MeshInstance3D) -> int:
	if node == null or node.mesh == null: return 0
	var mesh: ArrayMesh = node.mesh
	if mesh.get_surface_count() == 0: return 0
	var surface_arrays: Array = mesh.surface_get_arrays(0)
	var surface_vertices: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
	return surface_vertices.size()

func _initialize() -> void:
	_verify_build()
	_verify_determinism()
	_verify_exclusions()
	_verify_validation()
	_verify_local_terrain_refresh()
	print("meadow_tuft_visual_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _verify_local_terrain_refresh() -> void:
	var pair := _make_garden()
	var garden: Node = pair[0]
	var mock: Node = pair[1]
	var full_reads: int = mock.reads
	var original: PackedVector3Array = garden._tuft_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var tuft: Dictionary = garden._tuft_plan[0]
	var point: Vector2 = (Vector2(tuft["cell"]) + Vector2.ONE * 0.5) * Garden.MEADOW_UNIT
	var cell := Vector2i(floori(point.x / mock.voxel_scale), floori(point.y / mock.voxel_scale))
	mock.removed[cell] = true
	mock.edit_bounds = AABB(Vector3(cell.x * mock.voxel_scale, 0, cell.y * mock.voxel_scale), Vector3(mock.voxel_scale, 32, mock.voxel_scale))
	mock.bump()
	mock.reads = 0
	garden.refresh_terrain()
	var local_reads: int = mock.reads
	var edited: PackedVector3Array = garden._tuft_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(edited.size() < original.size(), "local excavation removes tufts over its missing ground")
	check(local_reads > 0 and local_reads < full_reads / 10, "local terrain edit reads only affected tuft columns")
	var fresh: Node = Garden.new()
	root.add_child(fresh)
	fresh.attach_backend(mock)
	check(edited == fresh._tuft_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "local refresh matches a full fresh mesh exactly")
	mock.removed.clear()
	mock.bump()
	garden.refresh_terrain()
	check(original == garden._tuft_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "undo restores the exact tuft geometry")
	mock.removed[cell] = true
	mock.edit_bounds = AABB()
	mock.bump()
	garden.refresh_terrain()
	check(edited == garden._tuft_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "unknown edit bounds safely refresh all columns")
	print("MEADOW_LOCAL " + JSON.stringify({"full_reads": full_reads, "local_reads": local_reads}))
	garden.queue_free(); fresh.queue_free(); mock.queue_free()

func _make_garden() -> Array:
	var garden: Node = Garden.new()
	root.add_child(garden)
	var mock: Node = MockBackend.new()
	root.add_child(mock)
	garden.attach_backend(mock)
	return [garden, mock]

func _verify_build() -> void:
	var pair := _make_garden()
	var garden: Node = pair[0]
	var node: MeshInstance3D = garden.get("_tuft_node")
	check(node != null, "a tuft mesh node is created on attach")
	if node == null:
		garden.queue_free(); (pair[1] as Node).queue_free(); return
	var verts := _vertex_count(node)
	check(verts > 0, "the tuft mesh has geometry (verts=%d)" % verts)
	# Every tuft cell is one box (24 verts); cell count must divide cleanly.
	check(verts % 24 == 0, "geometry is whole tuft boxes (verts=%d)" % verts)
	var colors: PackedColorArray = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var family_ok := colors.size() > 0
	for i in colors.size():
		if not Tone.in_green_family(colors[i]): family_ok = false
	check(family_ok, "every tuft vertex colour is inside the meadow green family")
	garden.queue_free(); (pair[1] as Node).queue_free()
	print("MEADOW_BUILD " + JSON.stringify({"vertices": verts, "cells": verts / 24}))

func _verify_determinism() -> void:
	var pair := _make_garden()
	var garden: Node = pair[0]
	var mock: Node = pair[1]
	var first := _vertex_count(garden.get("_tuft_node"))
	mock.bump()
	garden.refresh_terrain()
	var second := _vertex_count(garden.get("_tuft_node"))
	check(first > 0 and first == second, "rebuilt mesh is byte-for-byte the same size after a terrain revision (%d == %d)" % [first, second])
	# The dedupe key must not rebuild when nothing changed.
	var before: Node = garden.get("_tuft_node")
	garden.refresh_terrain()
	check(before == garden.get("_tuft_node"), "no-op refresh does not rebuild the mesh")
	garden.queue_free(); mock.queue_free()
	print("MEADOW_DETERMINISM " + JSON.stringify({"first": first, "second": second}))

func _verify_exclusions() -> void:
	var pair := _make_garden()
	var garden: Node = pair[0]
	var open := _vertex_count(garden.get("_tuft_node"))
	var center := Rect2(24.0, 24.0, 16.0, 16.0)
	garden.set_meadow_exclusions([center])
	var excluded := _vertex_count(garden.get("_tuft_node"))
	check(excluded < open, "a building exclusion removes tufts (%d -> %d)" % [open, excluded])
	garden.set_meadow_exclusions([])
	var restored := _vertex_count(garden.get("_tuft_node"))
	check(restored == open, "clearing the exclusion restores the full scatter (%d)" % restored)
	garden.queue_free(); (pair[1] as Node).queue_free()
	print("MEADOW_EXCLUDE " + JSON.stringify({"open": open, "excluded": excluded, "restored": restored}))

func _verify_validation() -> void:
	var pair := _make_garden()
	var garden: Node = pair[0]
	var mock: Node = pair[1]
	var node: MeshInstance3D = garden.get("_tuft_node")
	var surface_world := float(mock.surface + 1) * 0.125
	var verts: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var sits_on_grass := false
	var above_surface := true
	for i in verts.size():
		var v: Vector3 = verts[i]
		if v.y < surface_world - 0.001:
			above_surface = false
		if absf(v.y - surface_world) < 0.2:
			sits_on_grass = true
	check(above_surface, "no tuft geometry sinks below the grass surface")
	check(sits_on_grass, "tuft bases sit on the grass surface")
	# A non-grass (stone) surface must reject tufts: raise the surface type.
	mock.surface = 8
	var stone: Node = StoneBackend.new()
	root.add_child(stone)
	garden.attach_backend(stone)
	var stone_verts := _vertex_count(garden.get("_tuft_node"))
	check(stone_verts == 0, "a stone (non-grass) surface scatters no tufts (verts=%d)" % stone_verts)
	garden.queue_free(); mock.queue_free(); stone.queue_free()
	print("MEADOW_VALIDATE " + JSON.stringify({"surface_world": surface_world, "sits_on_grass": sits_on_grass, "stone_verts": stone_verts}))

class StoneBackend:
	extends Node
	var voxel_scale := 0.125
	var patch_size := Vector3i(512, 256, 512)
	func is_ready() -> bool: return true
	func revision() -> int: return 1
	func voxel_at(p: Vector3i) -> int:
		if p.x < 0 or p.z < 0 or p.x >= patch_size.x or p.z >= patch_size.z: return 0
		if p.y == 8: return 3
		if p.y < 8: return 1
		return 0
