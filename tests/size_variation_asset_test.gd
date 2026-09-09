extends "res://tests/magicavoxel_asset_test.gd"

const NAMES := ["tree_orchard_compact", "tree_riverside_young", "tree_wind_low", "foliage_mushrooms_flat", "foliage_mushrooms_flat_scatter"]
const ORIGINALS := ["tree_orchard", "tree_riverside", "tree_wind"]
const ORIGINAL_HASHES := ["412375e7cd775aaafad042a5ecd43f54f4de90db64b3fe394db74ddaa0924a6a", "aee75af62a5f8b47bf44d220a65777a3aad43179cbce335ceb975ae7798930e2", "88b53a39027d08175bc905f42e6fb3129b59b43ccecc03b1aea8b7b2c16caaa0"]
const ORIGINAL_BOUNDS := [AABB(Vector3(-2.375, 0, -1.25), Vector3(4.5, 5, 2.625)), AABB(Vector3(-1.375, 0, -1), Vector3(2.5, 6.125, 2)), AABB(Vector3(-2.25, 0, -1.125), Vector3(4.625, 5.125, 2.25))]
const GROUPS := [[1, 2, 3, 4], [1, 2, 3, 4], [1, 2, 3, 4], [6, 12, 13, 14], [6, 12, 13, 14]]
const PALETTE := {1: Color("#765942"), 2: Color("#638348"), 3: Color("#486d46"), 4: Color("#87a657"), 6: Color("#c7b897"), 12: Color("#765942"), 13: Color("#a17359"), 14: Color("#ba906f")}

func _initialize() -> void:
	for i in NAMES.size():
		var name: String = NAMES[i]
		var path := "res://assets/models/magicavoxel/hearthvale_" + name
		var mesh := load(path + ".res") as Mesh
		_check(mesh != null, name + " imports")
		if mesh == null: continue
		var triangles := _inspect(mesh, name)
		var receipt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + ".asset.json"))
		_check(FileAccess.get_sha256("res://assets/source/magicavoxel/" + str(receipt.source)) == receipt.source_sha256, name + " source provenance")
		_check(receipt.tool_commit == "710671d49bdc89e4e3d1ff7c60541c1d0383ac16" and receipt.voxel_unit == UNIT and receipt.voxel_tier == "prop/detail", name + " pinned MCP and prop grid")
		_check(triangles == int(receipt.triangles) and triangles <= (5000 if i < 3 else 500), name + " triangle receipt and budget")
		var box := mesh.get_aabb()
		var occupied: Dictionary = receipt.occupied_bounds
		var dimensions: Array = receipt.declared_dimensions
		var low := Vector3(float(occupied.min[0]) - float(dimensions[0]) / 2.0, float(occupied.min[1]), float(occupied.min[2]) - float(dimensions[2]) / 2.0) * UNIT
		var high := Vector3(float(occupied.max[0]) - float(dimensions[0]) / 2.0, float(occupied.max[1]), float(occupied.max[2]) - float(dimensions[2]) / 2.0) * UNIT
		_check(box.position.is_equal_approx(low) and box.end.is_equal_approx(high) and is_zero_approx(box.position.y), name + " source bounds and centred ground pivot")
		var indices := PackedInt32Array(GROUPS[i])
		_check(PackedInt32Array(receipt.palette_indices) == indices and mesh.get_surface_count() == indices.size(), name + " palette groups")
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			_check(material != null and material.albedo_color.is_equal_approx(PALETTE[indices[surface]]) and is_zero_approx(material.metallic) and is_equal_approx(material.roughness, 1.0), name + " matte source palette")
		if i < 3:
			var original := load("res://assets/models/magicavoxel/hearthvale_" + ORIGINALS[i] + ".res") as Mesh
			_check(original != null, name + " original comparison loads")
			if original != null:
				_check(FileAccess.get_sha256("res://assets/source/magicavoxel/hearthvale_" + ORIGINALS[i] + ".vox") == ORIGINAL_HASHES[i], name + " approved original source remains byte-identical")
				_check(original.get_aabb().is_equal_approx(ORIGINAL_BOUNDS[i]), name + " approved original baked bounds remain unchanged")
				var ratio := box.size / original.get_aabb().size
				_check(ratio.x >= 0.74 and ratio.x <= 0.86 and ratio.y >= 0.74 and ratio.y <= 0.86 and ratio.z >= 0.74 and ratio.z <= 0.86, name + " is a consistent compact size without stretched cells")
		else:
			_check(box.size.y <= 0.5 and box.size.x <= 2.0 and box.size.z <= 1.5, name + " low mushroom envelope")
			_check(_surface_mean_y(mesh, 0) < (_surface_mean_y(mesh, 1) + _surface_mean_y(mesh, 2) + _surface_mean_y(mesh, 3)) / 3.0, name + " mushroom caps remain above their cream stems")
		candidate_results.append({"name": name, "triangles": triangles, "bounds": str(box)})
	_finish(0, 0)
