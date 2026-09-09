extends "res://tests/magicavoxel_asset_test.gd"

const ASSET_NAMES := ["foliage_reeds", "foliage_fern", "foliage_mushrooms"]
const GROUPS := [[2,3,4,12], [2,3,4], [6,12,13,14]]
const PALETTE := {2: Color("#638348"), 3: Color("#486d46"), 4: Color("#87a657"), 6: Color("#c7b897"), 12: Color("#765942"), 13: Color("#a17359"), 14: Color("#ba906f")}
const ENVELOPES := [Vector3(1.25,1.75,1.0), Vector3(1.375,0.75,1.25), Vector3(1.0,0.75,1.0)]

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
		_check(box.size.x <= ENVELOPES[i].x and box.size.y <= ENVELOPES[i].y and box.size.z <= ENVELOPES[i].z, name + " small ground foliage envelope")
		var indices := PackedInt32Array(GROUPS[i])
		_check(PackedInt32Array(receipt.palette_indices) == indices and mesh.get_surface_count() == indices.size(), name + " palette groups")
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			_check(material != null and material.albedo_color.is_equal_approx(PALETTE[indices[surface]]) and is_zero_approx(material.metallic) and is_equal_approx(material.roughness, 1.0), name + " matte source palette")
		if name == "foliage_mushrooms":
			_check(_surface_mean_y(mesh, 0) < (_surface_mean_y(mesh, 1) + _surface_mean_y(mesh, 2) + _surface_mean_y(mesh, 3)) / 3.0, "mushroom caps remain above their cream stems")
		var current_triangles := 0
		for current: Mesh in Flora.meshes("rock" if i >= 3 else "foliage", i % 3):
			for s in current.get_surface_count(): current_triangles += current.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
		candidate_results.append({"name": name, "triangles": triangles, "current_triangles": current_triangles, "bounds": str(box)})
	_finish(0, 0)
