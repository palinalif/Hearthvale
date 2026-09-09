extends SceneTree

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
	var source: Mesh = load(str(args[0]))
	if source == null:
		push_error("could not load source mesh")
		quit(2)
		return
	var baked := ArrayMesh.new()
	var snapped_vertices := 0
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for index in vertices.size():
			vertices[index] = Vector3(snappedf(vertices[index].x, unit), snappedf(vertices[index].y, unit), snappedf(vertices[index].z, unit))
			snapped_vertices += 1
		arrays[Mesh.ARRAY_VERTEX] = vertices
		baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		# OBJ's legacy Ns interpretation can import near-metallic materials.
		# These palette groups describe matte bark and foliage.
		var imported_material := source.surface_get_material(surface) as StandardMaterial3D
		if imported_material == null:
			push_error("palette surface requires a StandardMaterial3D")
			quit(2)
			return
		var material := imported_material.duplicate() as StandardMaterial3D
		material.metallic = 0.0
		material.roughness = 1.0
		baked.surface_set_material(surface, material)
	var error := ResourceSaver.save(baked, str(args[1]))
	print(JSON.stringify({"ok": error == OK, "source": str(args[0]), "output": str(args[1]), "unit": unit, "surfaces": baked.get_surface_count(), "vertices": snapped_vertices, "error": error}))
	quit(0 if error == OK else 1)
