extends SceneTree
## Authored gathering-table source, export reproducibility, baked grid, save
## compatibility and preview parity. No player save is opened.
const Assets = preload("res://scripts/m2_table_assets.gd")
const Visual = preload("res://scripts/m2_hamlet_visual.gd")
const State = preload("res://scripts/landscape_state.gd")
const EXPECTED_PALETTE := [Color("#c9a878"), Color("#7d5b43"), Color("#594337")]

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
	var receipt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/magicavoxel/hearthvale_table_gathering.asset.json"))
	_check(receipt != null, "Converter receipt exists")
	var source := "res://assets/source/magicavoxel/hearthvale_table_gathering.vox"
	_check(FileAccess.get_sha256(source) == str(receipt.source_sha256), "Provenance matches source bytes")
	_check(float(receipt.voxel_unit) == Assets.UNIT and str(receipt.voxel_tier) == "prop/detail", "Pinned prop-grid receipt")
	_check(receipt.tool_commit == "710671d49bdc89e4e3d1ff7c60541c1d0383ac16", "Pinned MCP tool receipt")

	# Re-export reproducibility: the canonical source must produce the committed OBJ.
	var temp := "user://table_gathering_reexport.obj"
	var output: Array = []
	var result := OS.execute("python3", [ProjectSettings.globalize_path("res://tools/magicavoxel/vox_to_obj.py"), "--unit", "0.0625", "--greedy", ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(temp)], output, true)
	for text in output: print(text)
	_check(result == 0, "Converter re-export succeeds")
	var canonical_obj := FileAccess.get_file_as_string("res://assets/models/magicavoxel/hearthvale_table_gathering.obj")
	var reexported := FileAccess.get_file_as_string(temp)
	var reexported_lines := reexported.split("\n", false)
	var canonical_lines := canonical_obj.split("\n", false)
	var same := reexported_lines.size() == canonical_lines.size()
	for line_index in reexported_lines.size():
		if str(reexported_lines[line_index]).begins_with("mtllib "): continue
		same = same and str(reexported_lines[line_index]) == str(canonical_lines[line_index])
	_check(same, "Re-exported OBJ is identical apart from the mtllib reference")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))

	var mesh := Assets.mesh_for("village_table")
	_check(mesh != null, "Baked mesh exists")
	if mesh == null:
		_finish()
		return
	var bounds := mesh.get_aabb()
	_check(is_zero_approx(bounds.position.y) and bounds.size.y <= 0.5625, "Ground pivot and miniature height")
	_check(bounds.size.x <= 1.25 and bounds.size.z <= 1.875, "Mesh stays within the saved placement footprint")
	_check(mesh.get_surface_count() == 3, "Three authored palette groups")
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for point in points:
			_check(point.distance_to(point.snapped(Vector3.ONE * Assets.UNIT)) < 0.00002, "Cubic 0.0625 baked grid")
		for i in range(0, indices.size(), 3):
			var cross := (points[indices[i + 1]] - points[indices[i]]).cross(points[indices[i + 2]] - points[indices[i]])
			_check(cross.length_squared() > 0.00000001 and cross.dot(normals[indices[i]]) < 0.0, "Nondegenerate outward Godot winding")
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		_check(material != null and material.albedo_color.is_equal_approx(EXPECTED_PALETTE[surface]), "Palette group %d keeps its authored color" % [surface + 1])
		_check(material != null and is_zero_approx(material.metallic) and is_equal_approx(material.roughness, 1.0), "Matte canonical materials")
	_check(int(receipt.triangles) == 280, "Triangle receipt matches the greedy export")
	_check(int(receipt.voxel_count) == int(Assets.VOXEL_COUNTS["village_table"]), "Voxel-count receipt")
	_check(mesh == Assets.mesh_for("village_table"), "Canonical mesh is cached")
	for valid: bool in [true, false]:
		var ghost := Assets.mesh_for("village_table", "", true, valid)
		_check(ghost == Assets.mesh_for("village_table", "", true, valid), "Preview variant cache is bounded")
		_check(ghost.get_aabb().is_equal_approx(mesh.get_aabb()), "Ghost and asset share bounds")
		for surface in mesh.get_surface_count():
			_check(ghost.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] == mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX], "Preview has identical geometry")
			var base := mesh.surface_get_material(surface) as StandardMaterial3D
			var preview := ghost.surface_get_material(surface) as StandardMaterial3D
			_check(base.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and is_equal_approx(base.albedo_color.a, 1.0), "Ghost never mutates canonical opacity")
			_check(preview.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "Translucent preview materials")

	# A save written while the table was procedural restores with the authored
	# presentation and no record changes.
	var state := State.new()
	var legacy := {"version": 1, "next_id": 4, "records": [], "paths": [], "bridges": [], "composition": [{"id": 3, "kind": "furniture", "style_id": "village_table", "position": [31.0, 33.5], "size": [1.25, 1.875], "yaw_quarters": 2}]}
	_check(state.restore(legacy) and state.document() == legacy, "Existing village-table saves restore without schema or identity changes")
	var visual := Visual.new()
	root.add_child(visual)
	visual.rebuild_furniture(state.composition)
	_check(visual._furniture_nodes.size() == 1, "Legacy table record renders")
	var node: MeshInstance3D = visual._furniture_nodes[0]
	_check(node.get_meta("authored_asset") == Assets.PATHS["village_table"], "Legacy record receives the authored asset")
	visual.show_furniture_preview("village_table", Vector2(40, 40), Vector2(1.25, 1.875), 90.0, true)
	_check(visual._furniture_preview_node != null and visual._furniture_preview_node.get_meta("authored_asset") == Assets.PATHS["village_table"], "Placement preview uses the authored asset")
	_finish()

func _finish() -> void:
	print("m2_table_asset_test: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if failures.size() else 0)
