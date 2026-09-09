extends "res://tests/magicavoxel_asset_test.gd"

const FOLIAGE_NAMES := ["grass", "wildflowers", "leafy"]
const PALETTE := {2: Color("#638348"), 3: Color("#486d46"), 4: Color("#87a657"), 5: Color("#df9a8b"), 6: Color("#c7b897")}

func _initialize() -> void:
	for i in 3:
		var name: String = FOLIAGE_NAMES[i]
		var path := "res://assets/models/magicavoxel/hearthvale_foliage_" + name
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
		_check(box.size.x <= 1.125 and box.size.y <= 0.875 and box.size.z <= 1.0, name + " small ground foliage envelope")
		var indices := PackedInt32Array([2, 3, 4, 5, 6] if i == 1 else [2, 3, 4])
		_check(PackedInt32Array(receipt.palette_indices) == indices and mesh.get_surface_count() == indices.size(), name + " palette groups")
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			_check(material != null and material.albedo_color.is_equal_approx(PALETTE[indices[surface]]) and is_zero_approx(material.metallic) and is_equal_approx(material.roughness, 1.0), name + " matte source palette")
		var current_triangles := 0
		for current: Mesh in Flora.meshes("foliage", i):
			for s in current.get_surface_count(): current_triangles += current.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
		candidate_results.append({"name": name, "triangles": triangles, "current_triangles": current_triangles, "bounds": str(box)})
	_finish(0, 0)
