extends RefCounted

const Contact = preload("res://scripts/m2_path_grass_contact.gd")
const PathVisual = preload("res://scripts/m2_path_visual.gd")
# LOCKED_FUNCTIONS is filled from the byte-verified 452b0242 renderer below.
const LOCKED_FUNCTIONS := {
	"_append_path": "368bf3ee49b832ea7530073056f8d82294b29131e67cea22b7a6a42a7ec07679",
	"_embedded_center": "5806ec96c10d3799d49c36fbc095897d022505f4129c31ec4aa62a81e1eaaf78",
	"_stepping_stone_half_across": "c40c9b6141af8967bf11cab6cf7a9d495e666f91f691f750475c4c8894e06446",
	"_stepping_stone_center": "08d50ec3df7d4c27d274841f2314dfc606cac2b2749e48dea34605442aa6fe3f",
	"_sample_polyline": "f748d3f58448727c52fd9d7070f7e8e4b9059bcc48f21edf48210ebfa2878668",
	"_surface_height": "f5cfb319b593c2c9e81022cf2aa0f8507f6b6538c8b25ff81b2c7db2205599d5",
	"_point_from_value": "dc4ebd719cb8770032238bbb12c703e2c60eeedbfd064657076e82f85f8d5ac8",
	"_new_builder": "5ec94408a57b06f23cfe08b583624a335d3a2c31977ae6b975378f7000b422d9",
	"_append_box": "89603ec8f31e148189da739754daafbbe95f1bd509337ed7d9d27d06937eb2f1",
	"_append_rounded_stone": "02c191dbdfcc2c7fa4ea1c757ee41b92320a1ea3eccb5ae3587d5f7722b397ef",
	"_mesh_from_builder": "d329ba438ed9755cc929e0318967a2ad507c10986e9a788bca9d5f5855a743b6",
	"_builder_cell_count": "be7dea70c94820e37d7d827cb233d6b7604ac8480b0440683b4e0c198bbdb4d2",
	"_path_material": "e1dcb00f825fc8d76d695d4009259a858d876ceaca86345339b81e3f81448faf",
	"_preview_colours": "1784fd51735c9e517739dde901922be28f88cb217824c8b0b422b7eb07b75aee",
	"_preview_material": "71623a4333e9d775038048a4ef37dd42965779ccccc4663db9603d972dfc1584",
	"_marker_mesh": "f5f5b50c60ab00afba2fcf12d41cd7ccbdb3198873db67be27a23fcb7496b484"
}
const LOCKED_CONSTANTS := "4138db27062d9f7d1b7264ade84989f1ba9936c14bcc29e1bccc4aada6cb2fcd"

static func _function_source(source: String, name: String) -> String:
	var start := source.find("func " + name + "(")
	if start < 0: return ""
	var end := source.find("\nfunc ", start)
	return source.substr(start) if end < 0 else source.substr(start, end - start)

static func source_lock(checker: SceneTree) -> void:
	var source := FileAccess.get_file_as_string("res://scripts/m2_path_visual.gd").replace("\r\n", "\n")
	for name: String in LOCKED_FUNCTIONS:
		var body := _function_source(source, name)
		if name == "_append_path":
			body = body.replace("\t\t\t\tContact.record_primary(builder, path_id, cluster_index, primary_material)\n", "")
		checker._check(body.sha256_text() == str(LOCKED_FUNCTIONS[name]), "452b0242 geometry/source lock: " + name)
	var start := source.find("const Grid =")
	var end := source.find("\nvar backend:", start)
	checker._check(start >= 0 and end > start and source.substr(start, end - start).sha256_text() == LOCKED_CONSTANTS, "452b0242 sizes, colours, epsilon, thickness and cadence constants unchanged")

static func mesh_digest(mesh: Mesh) -> String:
	if mesh == null: return "empty"
	var payload: Array = []
	for surface in mesh.get_surface_count():
		payload.append(mesh.surface_get_arrays(surface))
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		if material != null:
			payload.append([material.albedo_color, material.roughness, material.cull_mode, material.vertex_color_use_as_albedo])
	return var_to_bytes(payload).hex_encode().sha256_text()

static func digest(data: Dictionary) -> String:
	return mesh_digest(data["mesh"]) + var_to_bytes([data["roots"], data["primary_ids"], data["tufts"], data["cells"]]).hex_encode().sha256_text()

static func inspect(checker: SceneTree, scene: Node, phase: String) -> void:
	var visual: Node = scene.path_visual
	var data: Dictionary = visual._contact_data
	var stats: Dictionary = visual.stats()
	var tufts := int(data["tufts"])
	checker._check(tufts > 0 and tufts <= Contact.MAX_TUFTS, "sparse contact exists and obeys global tuft cap: " + phase)
	checker._check(tufts <= floori(float(data["primary_count"]) * 0.35), "at least 65 percent of primary stones remain bare: " + phase)
	checker._check(int(data["cells"]) <= tufts * Contact.MAX_CELLS_PER_TUFT and int(data["triangles"]) <= Contact.MAX_TUFTS * Contact.MAX_CELLS_PER_TUFT * 12, "contact geometry obeys explicit cell/triangle cap: " + phase)
	checker._check(stats.draw_calls <= 3 and stats.opaque_surface_draws <= 7 and stats.grass_contact.draw_calls <= 1, "original path batches plus at most one opaque grass draw: " + phase)
	if data["mesh"] == null: return
	var node: MeshInstance3D = visual._contact_node
	checker._check(node.mesh.get_surface_count() == 1 and node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "single contact surface and no extra shadow draw: " + phase)
	var arrays: Array = node.mesh.surface_get_arrays(0)
	checker._check((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == int(data["cells"]) * 24 and (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() == int(data["cells"]) * 36, "reported grass geometry matches runtime arrays: " + phase)
	var material := node.mesh.surface_get_material(0) as StandardMaterial3D
	checker._check(material != null and material.vertex_color_use_as_albedo and material.vertex_color_is_srgb and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and material.cull_mode == BaseMaterial3D.CULL_BACK, "grass keeps sRGB palette, opaque voxel shading and normal culling: " + phase)
	var builder: Dictionary = visual._new_builder()
	for path: Dictionary in scene.landscape_state.paths:
		if str(path["style_id"]) == "stepping_stones":
			visual._append_path(builder, "stepping_stones", float(path["width"]), path["points"], int(path["id"]))
	var before := var_to_bytes(builder["surfaces"])
	var repeated := Contact.build(visual, builder)
	checker._check(before == var_to_bytes(builder["surfaces"]), "grass generation leaves stone vertices/normals/indices byte-identical: " + phase)
	checker._check(digest(data) == digest(repeated), "deterministic regeneration from unchanged native terrain: " + phase)
	var bins := Contact.footprint_bins(builder)
	var grounded := true
	var clear := true
	var root_heights := {}
	var scale_value := float(scene.backend.voxel_scale)
	for root: Vector3 in data["roots"]:
		var xz := Vector2(root.x, root.z)
		clear = clear and Contact.clears_stones(xz, bins)
		var hit: Dictionary = scene.backend.sample_surface_plane(root + Vector3.UP * scale_value * 0.5, Vector3.UP, scale_value * 2.0)
		grounded = grounded and bool(hit.get("valid", false)) and absf(float((hit.get("point", Vector3.INF) as Vector3).y) - root.y) < 0.00001
		root_heights[Vector2i(floori(root.x / Contact.UNIT), floori(root.z / Contact.UNIT))] = root.y
	checker._check(grounded, "every grass root agrees with its own native terrain surface: " + phase)
	checker._check(clear, "entire grass cell footprints clear every primary/companion/third top: " + phase)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var geometry_ok := true
	for offset in range(0, vertices.size(), 24):
		var low := vertices[offset]
		var high := vertices[offset]
		for index in range(offset, offset + 24):
			low = low.min(vertices[index]); high = high.max(vertices[index])
		var center := (low + high) * 0.5
		var key := Vector2i(floori(center.x / Contact.UNIT), floori(center.z / Contact.UNIT))
		geometry_ok = geometry_ok and low.is_finite() and high.is_finite() and (high - low).is_equal_approx(Vector3.ONE * Contact.UNIT)
		geometry_ok = geometry_ok and root_heights.has(key) and low.y >= float(root_heights.get(key, INF)) - 0.00001 and high.y <= float(root_heights.get(key, -INF)) + Contact.MAX_HEIGHT + 0.00001
	for offset in range(0, indices.size(), 3):
		var a := vertices[indices[offset]]
		var b := vertices[indices[offset + 1]]
		var c := vertices[indices[offset + 2]]
		geometry_ok = geometry_ok and (b - a).cross(c - a).dot(normals[indices[offset]]) < 0.0
	checker._check(geometry_ok, "short cubic grass cells retain outward winding and bounded height: " + phase)
	print("STEPPING_GRASS_AUDIT " + JSON.stringify({"phase": phase, "tufts": tufts, "cells": data["cells"], "vertices": data["vertices"], "triangles": data["triangles"], "additional_draws": data["draw_calls"], "total_opaque_surface_draws": stats.opaque_surface_draws}))

static func budget_selection(checker: SceneTree) -> void:
	# Selection-only stress case. It is not a render fixture or screenshot.
	var candidates: Array = []
	for path_id in range(1, 65):
		for cluster in 64: candidates.append({"path_id": path_id, "cluster": cluster})
	var selected := Contact.selected_primaries(candidates)
	checker._check(selected.size() == Contact.MAX_TUFTS, "large selection saturates but never exceeds 128-tuft global cap")
	candidates.reverse()
	checker._check(selected == Contact.selected_primaries(candidates), "cap selection is independent of input/path enumeration order")
	var per_path := {}
	var ids := {}
	var valid := true
	for item: Dictionary in selected:
		var path_id := int(item["path_id"])
		var cluster := int(item["cluster"])
		per_path[path_id] = int(per_path.get(path_id, 0)) + 1
		valid = valid and int(per_path[path_id]) <= Contact.MAX_PER_PATH and not ids.has(Vector2i(path_id, cluster - 1)) and not ids.has(Vector2i(path_id, cluster + 1))
		ids[Vector2i(path_id, cluster)] = true
	checker._check(valid, "per-path budget and bare adjacent targets survive stress selection")

static func lifecycle(checker: SceneTree, scene: Node) -> void:
	var visual: Node = scene.path_visual
	var document := JSON.stringify(scene.landscape_state.document())
	var paths: Array = scene.landscape_state.paths.duplicate(true)
	var original := digest(visual._contact_data)
	var stone_digest := mesh_digest(visual._style_nodes["stepping_stones"].mesh)
	visual.rebuild(paths)
	visual.rebuild(paths)
	checker._check(digest(visual._contact_data) == original, "repeated rebuild does not shuffle contact")
	var contacts := 0
	for child: Node in visual.get_children():
		if str(child.name) == "PathGrassContact": contacts += 1
	checker._check(contacts == 1, "same-frame rebuild removes previous contact batch immediately")
	visual.show_preview("stepping_stones", 1.0, [[14.0, 28.0], [20.0, 31.0]], true, "")
	visual.hide_preview()
	checker._check(digest(visual._contact_data) == original, "cancelled path preview does not shuffle committed grass")
	var reloaded := PathVisual.new()
	checker.root.add_child(reloaded)
	reloaded.attach_backend(scene.backend)
	var reloaded_paths: Array = JSON.parse_string(JSON.stringify(paths))
	reloaded_paths.reverse()
	reloaded.rebuild(reloaded_paths)
	checker._check(digest(reloaded._contact_data) == original, "fresh renderer and reloaded/reordered saved paths reproduce identical contact")
	reloaded.queue_free()
	visual.rebuild([])
	checker._check(visual._contact_node == null and int(visual._contact_data["tufts"]) == 0 and visual.stats().grass_contact.draw_calls == 0, "removing all paths clears grass geometry and counters")
	await checker.process_frame
	checker._check(visual.get_child_count() == 0, "no stale grass or path nodes survive path removal")
	visual.rebuild(paths)
	await checker.process_frame
	checker._check(digest(visual._contact_data) == original and mesh_digest(visual._style_nodes["stepping_stones"].mesh) == stone_digest, "restoring paths reproduces exact grass and unchanged stones")
	checker._check(JSON.stringify(scene.landscape_state.document()) == document, "contact lifecycle leaves the complete saved landscape unchanged")
