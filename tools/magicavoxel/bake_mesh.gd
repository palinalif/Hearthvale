extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("usage: bake_mesh.gd -- SOURCE_RESOURCE OUTPUT_RESOURCE")
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
			vertices[index] = Vector3(snappedf(vertices[index].x, 0.125), snappedf(vertices[index].y, 0.125), snappedf(vertices[index].z, 0.125))
			snapped_vertices += 1
		arrays[Mesh.ARRAY_VERTEX] = vertices
		baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		baked.surface_set_material(surface, source.surface_get_material(surface))
	var error := ResourceSaver.save(baked, str(args[1]))
	print(JSON.stringify({"ok": error == OK, "source": str(args[0]), "output": str(args[1]), "surfaces": baked.get_surface_count(), "vertices": snapped_vertices, "error": error}))
	quit(0 if error == OK else 1)
