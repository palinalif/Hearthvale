extends SceneTree
## Authored street-prop sources, export reproducibility, baked grid, footprints
## and preview parity for the five catalogue props. No player save is opened.
const Assets = preload("res://scripts/m2_table_assets.gd")

const EXPECTED := {
	"clothesline": {"size": Vector2(2.5, 0.5), "height": 0.75, "voxels": 310},
	"potted_trio": {"size": Vector2(1.0, 0.75), "height": 0.625, "voxels": 224},
	"market_crate": {"size": Vector2(0.625, 0.625), "height": 0.75, "voxels": 310},
	"bird_feeder": {"size": Vector2(0.875, 0.875), "height": 0.9375, "voxels": 229},
	"mailbox": {"size": Vector2(0.75, 0.5), "height": 1.0, "voxels": 180},
	"topiary_pair": {"size": Vector2(0.875, 0.5), "height": 0.75, "voxels": 363},
	"beehive": {"size": Vector2(0.4375, 0.5625), "height": 0.875, "voxels": 174},
	"wheelbarrow": {"size": Vector2(1.0, 0.375), "height": 0.5, "voxels": 148},
	"flower_arch": {"size": Vector2(0.8125, 0.125), "height": 0.75, "voxels": 122},
	"garden_gnome": {"size": Vector2(0.375, 0.375), "height": 0.875, "voxels": 182},
	"garden_gnome_small": {"size": Vector2(0.375, 0.375), "height": 0.5, "voxels": 102},
	"garden_gnome_tall": {"size": Vector2(0.375, 0.375), "height": 1.0, "voxels": 190},
}
const NAMES := {
	"clothesline": "hearthvale_clothesline",
	"potted_trio": "hearthvale_potted_trio",
	"market_crate": "hearthvale_market_crate",
	"bird_feeder": "hearthvale_bird_feeder",
	"mailbox": "hearthvale_mailbox",
	"topiary_pair": "hearthvale_topiary_pair",
	"beehive": "hearthvale_beehive",
	"wheelbarrow": "hearthvale_wheelbarrow",
	"flower_arch": "hearthvale_flower_arch",
	"garden_gnome": "hearthvale_garden_gnome",
	"garden_gnome_small": "hearthvale_garden_gnome_small",
	"garden_gnome_tall": "hearthvale_garden_gnome_tall",
}

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
	for style_id in EXPECTED:
		var name: String = NAMES[style_id]
		var receipt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/magicavoxel/%s.asset.json" % [name]))
		_check(receipt != null, "%s: converter receipt exists" % [style_id])
		if receipt == null:
			_finish()
			return
		var source := "res://assets/source/magicavoxel/%s.vox" % [name]
		_check(FileAccess.get_sha256(source) == str(receipt.source_sha256), "%s: provenance matches source bytes" % [style_id])
		_check(float(receipt.voxel_unit) == Assets.UNIT and str(receipt.voxel_tier) == "prop/detail", "%s: pinned prop-grid receipt" % [style_id])
		_check(receipt.tool_commit == "710671d49bdc89e4e3d1ff7c60541c1d0383ac16", "%s: pinned MCP tool receipt" % [style_id])

		var temp := "user://street_prop_reexport.obj"
		var output: Array = []
		var result := OS.execute("python3", [ProjectSettings.globalize_path("res://tools/magicavoxel/vox_to_obj.py"), "--unit", "0.0625", "--greedy", ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(temp)], output, true)
		_check(result == 0, "%s: converter re-export succeeds" % [style_id])
		var canonical_lines := FileAccess.get_file_as_string("res://assets/models/magicavoxel/%s.obj" % [name]).split("\n", false)
		var reexported_lines := FileAccess.get_file_as_string(temp).split("\n", false)
		var same := reexported_lines.size() == canonical_lines.size()
		for line_index in reexported_lines.size():
			if str(reexported_lines[line_index]).begins_with("mtllib "): continue
			same = same and str(reexported_lines[line_index]) == str(canonical_lines[line_index])
		_check(same, "%s: re-exported OBJ is identical apart from the mtllib reference" % [style_id])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))

		var mesh := Assets.mesh_for(style_id)
		_check(mesh != null, "%s: baked mesh exists" % [style_id])
		if mesh == null:
			_finish()
			return
		var bounds := mesh.get_aabb()
		_check(is_zero_approx(bounds.position.y), "%s: ground pivot" % [style_id])
		_check(bounds.size.y <= float(EXPECTED[style_id]["height"]) + 0.0001, "%s: miniature height" % [style_id])
		var size: Vector2 = EXPECTED[style_id]["size"]
		_check(bounds.size.x <= size.x + 0.0001 and bounds.size.z <= size.y + 0.0001, "%s: mesh stays within the saved placement footprint" % [style_id])
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for point in points:
				_check(point.distance_to(point.snapped(Vector3.ONE * Assets.UNIT)) < 0.00002, "%s: cubic 0.0625 baked grid" % [style_id])
			for i in range(0, indices.size(), 3):
				var cross := (points[indices[i + 1]] - points[indices[i]]).cross(points[indices[i + 2]] - points[indices[i]])
				_check(cross.length_squared() > 0.00000001 and cross.dot(normals[indices[i]]) < 0.0, "%s: nondegenerate outward Godot winding" % [style_id])
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			_check(material != null and is_zero_approx(material.metallic) and is_equal_approx(material.roughness, 1.0), "%s: matte canonical materials" % [style_id])
		_check(int(receipt.voxel_count) == int(EXPECTED[style_id]["voxels"]), "%s: voxel-count receipt" % [style_id])
		_check(int(receipt.voxel_count) == int(Assets.VOXEL_COUNTS[style_id]), "%s: voxel count registered in the assets module" % [style_id])
		_check(mesh == Assets.mesh_for(style_id), "%s: canonical mesh is cached" % [style_id])
		for valid: bool in [true, false]:
			var ghost := Assets.mesh_for(style_id, "", true, valid)
			_check(ghost.get_aabb().is_equal_approx(bounds), "%s: ghost and asset share bounds" % [style_id])
			for surface in mesh.get_surface_count():
				_check(ghost.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] == mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX], "%s: preview has identical geometry" % [style_id])
				var base := mesh.surface_get_material(surface) as StandardMaterial3D
				var preview := ghost.surface_get_material(surface) as StandardMaterial3D
				_check(base.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and is_equal_approx(base.albedo_color.a, 1.0), "%s: ghost never mutates canonical opacity" % [style_id])
				_check(preview.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and not is_equal_approx(preview.albedo_color.a, 1.0), "%s: translucent preview materials" % [style_id])
	_finish()

func _finish() -> void:
	print("street_prop_asset_test checks=%d failures=%d" % [checks, failures.size()])
	for message in failures: print("FAIL: " + message)
	quit(1 if failures.is_empty() else 0)
