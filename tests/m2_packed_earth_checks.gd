extends RefCounted

const Grid = preload("res://scripts/visual_grid.gd")
const Region = preload("res://scripts/m2_painted_path_region.gd")
const PathVisual = preload("res://scripts/m2_path_visual.gd")
const ContactChecks = preload("res://tests/m2_path_grass_contact_checks.gd")

static func inspect(checker: SceneTree, scene: Node, phase: String) -> void:
	var document := JSON.stringify(scene.landscape_state.document())
	var visual: Node = scene.path_visual
	var cells: Array = scene.landscape_state.path_cells("packed_earth")
	checker._check(not cells.is_empty(), "packed earth has authoritative painted cells: " + phase)
	checker._check(visual._style_nodes.has("packed_earth"), "painted packed earth produces one style batch: " + phase)
	if not visual._style_nodes.has("packed_earth"): return
	var mesh: Mesh = visual._style_nodes["packed_earth"].mesh
	checker._check(mesh != null and mesh.get_surface_count() <= 2, "packed earth stays within two opaque material surfaces: " + phase)
	checker._check(visual.stats().opaque_surface_draws <= 6, "painted path styles stay inside the existing opaque draw budget: " + phase)
	var grid_aligned := true
	var finite := true
	var top_vertices := 0
	for surface_index in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for index in vertices.size():
			var vertex := vertices[index]
			finite = finite and vertex.is_finite()
			if normals[index].dot(Vector3.UP) > 0.99:
				top_vertices += 1
				grid_aligned = grid_aligned and is_equal_approx(vertex.x, snappedf(vertex.x, Grid.UNIT)) and is_equal_approx(vertex.z, snappedf(vertex.z, Grid.UNIT))
	checker._check(finite and top_vertices > 0, "painted packed-earth mesh is finite and exposes top faces: " + phase)
	checker._check(grid_aligned, "packed-earth top silhouette conforms to the 0.125 m structural voxel grid: " + phase)
	var stats: Dictionary = visual.stats().get("packed_earth", {})
	checker._check(int(stats.get("cells", -1)) == cells.size(), "renderer accounts for every authoritative packed-earth cell: " + phase)
	checker._check(int(stats.get("triangles", 0)) <= cells.size() * 12, "packed-earth cell presentation stays inside box-equivalent geometry budget: " + phase)
	var profile: Dictionary = Region.packed_earth_profile(cells)
	var depths: Dictionary = stats.get("profile_depth_steps", {})
	var expected_depths := {0: 0, 1: 0, 2: 0}
	for cell in profile:
		var step := int(profile[cell])
		expected_depths[step] = int(expected_depths.get(step, 0)) + 1
	checker._check(depths == expected_depths, "packed-earth runtime uses the canonical distance-from-edge U profile: " + phase)
	checker._check(JSON.stringify(scene.landscape_state.document()) == document, "painted rendering never mutates saved path authority: " + phase)
	print("PACKED_EARTH_AUDIT " + JSON.stringify({"phase": phase, "cells": cells.size(), "profile": expected_depths, "opaque_surface_draws": visual.stats().opaque_surface_draws}))

static func width_cases(checker: SceneTree, scene: Node) -> void:
	# Width is now brush area rather than saved ribbon metadata. Exercise narrow,
	# ordinary and plaza-sized masks against the canonical depth field.
	for diameter: float in [0.25, 0.75, 3.0]:
		var cells := Region.brush_cells(Vector2(12.0, 18.0), diameter * 0.5)
		var profile := Region.packed_earth_profile(cells)
		checker._check(not cells.is_empty() and profile.size() == cells.size(), "painted brush diameter produces a complete structural-grid profile: " + str(diameter))
		var max_depth := 0
		for cell in profile: max_depth = maxi(max_depth, int(profile[cell]))
		if diameter <= 0.25:
			checker._check(max_depth == 0, "tiny trail remains at the shoulder profile: " + str(diameter))
		elif diameter < 1.0:
			checker._check(max_depth <= 1, "ordinary footpath never forms a two-voxel basin: " + str(diameter))
		else:
			checker._check(max_depth == 2, "broad painted ground reaches the two-voxel packed centre profile: " + str(diameter))

static func lifecycle(checker: SceneTree, scene: Node) -> void:
	var visual: Node = scene.path_visual
	var paths: Array = scene.landscape_state.paths.duplicate(true)
	var document := JSON.stringify(scene.landscape_state.document())
	if not visual._style_nodes.has("packed_earth"): return
	var original := ContactChecks.mesh_digest(visual._style_nodes["packed_earth"].mesh)
	visual.rebuild(paths, scene.backend)
	checker._check(ContactChecks.mesh_digest(visual._style_nodes["packed_earth"].mesh) == original, "painted packed-earth rebuild is deterministic")
	var reload := PathVisual.new()
	checker.root.add_child(reload)
	reload.rebuild(JSON.parse_string(JSON.stringify(paths)), scene.backend)
	checker._check(ContactChecks.mesh_digest(reload._style_nodes["packed_earth"].mesh) == original, "serialized painted cells reproduce identical packed-earth output")
	reload.queue_free()
	var remaining: Array = []
	for path: Dictionary in paths:
		if str(path["style_id"]) != "packed_earth": remaining.append(path)
	visual.rebuild(remaining, scene.backend)
	await checker.process_frame
	checker._check(not visual._style_nodes.has("packed_earth"), "removing packed-earth authority removes its batch")
	visual.rebuild(paths, scene.backend)
	await checker.process_frame
	checker._check(ContactChecks.mesh_digest(visual._style_nodes["packed_earth"].mesh) == original, "restoring painted authority restores exact packed-earth geometry")
	checker._check(JSON.stringify(scene.landscape_state.document()) == document, "painted rebuild/remove/restore preserves the saved document")

static func review(checker: SceneTree, scene: Node, directory: String) -> void:
	# Screenshot orchestration remains in the caller. The architecture gate here
	# deliberately checks the new authority rather than comparing to ribbon-era
	# geometry fixtures.
	inspect(checker, scene, "review")
