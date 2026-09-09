extends "res://tests/magicavoxel_asset_test.gd"

const ASSET_NAMES := ["foliage_seedgrass", "foliage_cream", "foliage_mauve", "rock_slab", "rock_split", "rock_moss"]
const GROUPS := [[2,3,4,6], [2,3,4,6,7], [2,3,4,8,9], [6,10,11], [6,10,11], [2,3,6,10,11]]
const PALETTE := {2: Color("#638348"), 3: Color("#486d46"), 4: Color("#87a657"), 5: Color("#df9a8b"), 6: Color("#c7b897"), 7: Color("#dbd4b2"), 8: Color("#9f8b9d"), 9: Color("#bba5b5"), 10: Color("#a49c8b"), 11: Color("#b8ae98")}

func _initialize() -> void:
	for i in ASSET_NAMES.size():
		var name: String = ASSET_NAMES[i]
		var path := "res://assets/models/magicavoxel/hearthvale_" + name
		var mesh := load(path + ".res") as Mesh
		_check(mesh != null, name + " imports")
		if mesh == null: continue
		var triangles := _inspect(mesh, name)
		var receipt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + ".asset.json"))
		_check(FileAccess.get_sha256("res://assets/source/magicavoxel/" + str(receipt.source)) == receipt.source_sha256, name + " source provenance")
		_check(receipt.tool_commit == "710671d49bdc89e4e3d1ff7c60541c1d0383ac16" and receipt.voxel_unit == UNIT and receipt.voxel_tier == "prop/detail", name + " pinned MCP and prop grid")
		_check(triangles == int(receipt.triangles) and triangles <= 500, name + " triangle receipt and budget")
		var box := mesh.get_aabb()
		var occupied: Dictionary = receipt.occupied_bounds
		var dimensions: Array = receipt.declared_dimensions
		var low := Vector3(float(occupied.min[0]) - float(dimensions[0]) / 2.0, float(occupied.min[1]), float(occupied.min[2]) - float(dimensions[2]) / 2.0) * UNIT
		var high := Vector3(float(occupied.max[0]) - float(dimensions[0]) / 2.0, float(occupied.max[1]), float(occupied.max[2]) - float(dimensions[2]) / 2.0) * UNIT
		_check(box.position.is_equal_approx(low) and box.end.is_equal_approx(high) and is_zero_approx(box.position.y), name + " source bounds and centred ground pivot")
		_check(box.size.x <= (1.5 if i >= 3 else 1.125) and box.size.y <= 1.0 and box.size.z <= 1.0, name + " small ground foliage envelope")
		var indices := PackedInt32Array(GROUPS[i])
		_check(PackedInt32Array(receipt.palette_indices) == indices and mesh.get_surface_count() == indices.size(), name + " palette groups")
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			_check(material != null and material.albedo_color.is_equal_approx(PALETTE[indices[surface]]) and is_zero_approx(material.metallic) and is_equal_approx(material.roughness, 1.0), name + " matte source palette")
		var current_triangles := 0
		for current: Mesh in Flora.meshes("rock" if i >= 3 else "foliage", i % 3):
			for s in current.get_surface_count(): current_triangles += current.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
		candidate_results.append({"name": name, "triangles": triangles, "current_triangles": current_triangles, "bounds": str(box)})
	_finish(0, 0)
