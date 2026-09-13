extends SceneTree
## Source, baked-mesh, legacy-save and preview parity. No player save is opened.
const Assets = preload("res://scripts/m2_planter_assets.gd")
const Visual = preload("res://scripts/m2_hamlet_visual.gd")
const State = preload("res://scripts/landscape_state.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var output: Array = []
	var result := OS.execute("python", [ProjectSettings.globalize_path("res://tests/m2_planter_source_test.py")], output, true)
	for text in output: print(text)
	_check(result == 0, "Editable source, provenance, barrel and deterministic export tests")
	output.clear()
	result = OS.execute("python", [ProjectSettings.globalize_path("res://tests/magicavoxel_converter_test.py")], output, true)
	for text in output: print(text)
	_check(result == 0, "Exact exposed-cell coverage for all prior vegetation and three planters")
	for style: String in Assets.STYLE_IDS:
		var mesh := Assets.mesh_for(style)
		_check(mesh != null, "Baked mesh exists: " + style)
		if mesh == null: continue
		_check(Assets.DEFINITIONS[style].size == Vector2(0.75, 0.75), "Original physical footprint: " + style)
		var bounds := mesh.get_aabb()
		_check(is_zero_approx(bounds.position.y) and bounds.end.y <= 0.875, "Base pivot and miniature height: " + style)
		_check(bounds.position.x >= -0.3751 and bounds.end.x <= 0.3751 and bounds.position.z >= -0.3751 and bounds.end.z <= 0.3751, "Mesh remains within footprint: " + style)
		var triangles := 0
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			triangles += indices.size() / 3
			for point in points:
				_check(point.distance_to(point.snapped(Vector3.ONE * Assets.UNIT)) < 0.00002, "Cubic 0.0625 baked grid")
			for i in range(0, indices.size(), 3):
				var cross := (points[indices[i + 1]] - points[indices[i]]).cross(points[indices[i + 2]] - points[indices[i]])
				_check(cross.length_squared() > 0.00000001 and cross.dot(normals[indices[i]]) < 0.0, "Nondegenerate outward Godot winding")
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			_check(material != null and is_zero_approx(material.metallic) and is_equal_approx(material.roughness, 1.0), "Matte canonical materials")
		_check(triangles <= 1000, "Bounded triangle cost: " + style)
		_check(mesh == Assets.mesh_for(style), "Canonical mesh is cached")
		for colour: String in ["", "natural", "sage", "blue", "berry", "cream"]:
			var tinted := Assets.mesh_for(style, colour)
			for valid: bool in [true, false]:
				var ghost := Assets.mesh_for(style, colour, true, valid)
				_check(ghost == Assets.mesh_for(style, colour, true, valid), "Preview variant cache is bounded")
				_check(ghost.get_aabb().is_equal_approx(mesh.get_aabb()), "Ghost and asset share bounds")
				for surface in mesh.get_surface_count():
					_check(ghost.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] == mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX], "Preview has identical geometry")
					var base := mesh.surface_get_material(surface) as StandardMaterial3D
					var placed := tinted.surface_get_material(surface) as StandardMaterial3D
					var preview := ghost.surface_get_material(surface) as StandardMaterial3D
					_check(base.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and is_equal_approx(base.albedo_color.a, 1.0), "Tint/ghost never mutates canonical opacity")
					_check(placed.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and preview.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "Opaque placed and translucent preview materials")
	var state := State.new()
	var legacy := {"version": 1, "next_id": 8, "records": [], "paths": [], "bridges": [], "composition": [{"id": 7, "kind": "furniture", "style_id": "barrel_planter", "position": [30.0, 34.0], "size": [0.75, 0.75], "yaw_quarters": 3, "colour_id": "sage"}]}
	_check(state.restore(legacy) and state.document() == legacy, "Existing quarter-turn planter saves restore without schema or identity changes")
	var visual := Visual.new()
	root.add_child(visual)
	visual.rebuild_furniture(state.composition)
	_check(visual._furniture_nodes.size() == 1, "Legacy planter gets authored presentation")
	var node: MeshInstance3D = visual._furniture_nodes[0]
	_check(int(node.get_meta("composition_id")) == 7 and node.get_meta("authored_asset") == Assets.PATHS["barrel_planter"], "Stable identity maps to actual exported asset")
	_check(node.basis.is_equal_approx(Basis(Vector3.UP, 3 * PI / 2)), "Legacy orientation preserved")
	visual.show_furniture_preview("barrel_planter", Vector2(30, 34), Assets.FOOTPRINT, 270.0, true, "sage")
	_check(visual._furniture_preview_node.transform.is_equal_approx(node.transform), "Preview and legacy placement have matching transform")
	_check(state.document() == legacy, "All presentation work is save-authority neutral")
	visual.hide_furniture_preview()
	visual.queue_free()
	await process_frame
	print("PLANTER_ASSET_CHECK " + JSON.stringify({"ok": failures.is_empty(), "checks": checks, "failures": failures.size(), "messages": failures}))
	quit(0 if failures.is_empty() else 1)
