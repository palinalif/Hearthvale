extends SceneTree

func _receipt(source_path: String) -> Dictionary:
	# vox_to_obj.py writes "<asset>.asset.json" beside the OBJ it emits.
	var path := source_path.get_base_dir().path_join(source_path.get_file().get_basename() + ".asset.json")
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _emissive_settings(receipt: Dictionary) -> Dictionary:
	return {
		"indices": receipt.get("emissive_palette_indices", []),
		"energy": float(receipt.get("emissive_energy", 1.5)),
	}


func _palette_index(receipt: Dictionary, surface: int) -> int:
	# The converter emits one OBJ material group per used palette index in
	# ascending order, so surface N maps to receipt.palette_indices[N].
	var indices: Array = receipt.get("palette_indices", [])
	return int(indices[surface]) if surface < indices.size() else -1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 3:
		push_error("usage: bake_mesh.gd -- SOURCE_RESOURCE OUTPUT_RESOURCE [VOXEL_UNIT]")
		quit(2)
		return
	var unit := float(args[2]) if args.size() == 3 else 0.125
	if not unit in [0.125, 0.0625]:
		push_error("voxel unit must be 0.125 or 0.0625")
		quit(2)
		return
	# Godot's MagicaVoxel importer yields a PackedScene wrapping a
	# MeshInstance3D, not a Mesh, so accept either shape.  A scene with several
	# mesh instances is combined in traversal order.
	var source: Mesh = _load_source_mesh(str(args[0]))
	if source == null:
		push_error("could not load source mesh")
		quit(2)
		return
	var baked := ArrayMesh.new()
	# The .asset.json receipt beside the source OBJ may nominate palette indices
	# that are light sources (lantern glass, flame). Those surfaces bake with
	# emission so an authored prop glows by itself, without a runtime shader hack.
	var receipt := _receipt(args[0])
	var emissive := _emissive_settings(receipt)
	# Canonicalize in two passes: snap every vertex to the presentation grid
	# first, then drop the whole model so its lowest point sits at y = 0.  A
	# prop authored with empty space under it (a maypole pole, a hanging sign)
	# would otherwise float where the runtime expects a ground pivot.
	var snapped_vertices := 0
	var lowest := INF
	var surfaces: Array = []
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for index in vertices.size():
			vertices[index] = Vector3(snappedf(vertices[index].x, unit), snappedf(vertices[index].y, unit), snappedf(vertices[index].z, unit))
			lowest = minf(lowest, vertices[index].y)
			snapped_vertices += 1
		arrays[Mesh.ARRAY_VERTEX] = vertices
		surfaces.append(arrays)
	var ground_offset := 0.0 if lowest == INF else lowest
	for surface_index in surfaces.size():
		var surface_arrays: Array = surfaces[surface_index]
		var shifted: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
		for vertex_index in shifted.size():
			shifted[vertex_index] = shifted[vertex_index] - Vector3(0.0, ground_offset, 0.0)
		surface_arrays[Mesh.ARRAY_VERTEX] = shifted
		baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
		# OBJ's legacy Ns interpretation can import near-metallic materials.
		# These palette groups describe matte bark and foliage.
		var imported_material := source.surface_get_material(surface_index) as StandardMaterial3D
		if imported_material == null:
			push_error("palette surface requires a StandardMaterial3D")
			quit(2)
			return
		var material := imported_material.duplicate() as StandardMaterial3D
		material.metallic = 0.0
		material.roughness = 1.0
		var palette_index := _palette_index(receipt, surface_index)
		if emissive["indices"].has(palette_index):
			material.emission_enabled = true
			material.emission = material.albedo_color
			material.emission_energy_multiplier = emissive["energy"]
		baked.surface_set_material(surface_index, material)
	var error := ResourceSaver.save(baked, str(args[1]))
	print(JSON.stringify({"ok": error == OK, "source": str(args[0]), "output": str(args[1]), "unit": unit, "surfaces": baked.get_surface_count(), "vertices": snapped_vertices, "ground_offset": ground_offset, "error": error}))
	quit(0 if error == OK else 1)


# Resolve a bake source to a Mesh.  `.vox` files import as a PackedScene whose
# MeshInstance3D children carry the geometry, so a plain `load()` never yields
# a Mesh; combine every mesh instance under the source, in traversal order.
func _load_source_mesh(path: String) -> Mesh:
	var resource: Resource = load(path)
	if resource == null:
		return null
	if resource is Mesh:
		return resource as Mesh
	if not resource is PackedScene:
		push_error("source resource is neither a Mesh nor a PackedScene")
		return null
	var scene_root: Node = (resource as PackedScene).instantiate()
	if scene_root == null:
		return null
	var combined := ArrayMesh.new()
	var instances: Array[MeshInstance3D] = []
	_collect_mesh_instances(scene_root, instances)
	for instance: MeshInstance3D in instances:
		var mesh: Mesh = instance.mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(surface))
			var material: Material = instance.material_override
			if material == null:
				material = mesh.surface_get_material(surface)
			combined.surface_set_material(combined.get_surface_count() - 1, material)
	scene_root.queue_free()
	return combined if combined.get_surface_count() > 0 else null


func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_mesh_instances(child, out)
