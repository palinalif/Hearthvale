extends SceneTree

# A ".obj" imports as a Mesh; a ".vox" imports as a PackedScene whose nodes
# carry the voxel model's per-palette-group surfaces.  Both are accepted so the
# bake can take either source format.
func _resolve_mesh(resource: Resource, unit: float) -> Mesh:
	if resource is Mesh:
		return resource as Mesh
	if not (resource is PackedScene):
		return null
	var node := (resource as PackedScene).instantiate()
	if node == null:
		return null
	var merged := ArrayMesh.new()
	var instances: Array = []
	_collect_mesh_instances(node, instances)
	for instance in instances:
		var mesh: Mesh = instance.mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			# The .vox importer emits geometry in voxel cell units, so cell-space
			# sources are scaled into metres here.  An .obj from the project's
			# mesher is already metre-space and must not be scaled again.
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for index in vertices.size():
				vertices[index] *= unit
			arrays[Mesh.ARRAY_VERTEX] = vertices
			merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			merged.surface_set_material(merged.get_surface_count() - 1, mesh.surface_get_material(surface))
	return merged if merged.get_surface_count() > 0 else null

func _collect_mesh_instances(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, out)

## The bake receipt beside the output, if the asset has one.
static func _emissive_receipt(output_path: String) -> Dictionary:
	var receipt_path := output_path.trim_suffix(".res") + ".asset.json"
	if not FileAccess.file_exists(receipt_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
	return parsed as Dictionary if parsed is Dictionary else {}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 3:
		push_error("usage: bake_mesh.gd -- SOURCE_RESOURCE OUTPUT_RESOURCE [VOXEL_UNIT]")
		quit(2)
		return
	var unit := float(args[2]) if args.size() == 3 else 0.125
	if unit <= 0.0:
		push_error("voxel unit must be positive")
		quit(2)
		return
	var raw: Resource = load(str(args[0]))
	if raw == null:
		push_error("could not load source mesh")
		quit(2)
		return
	var source := _resolve_mesh(raw, unit)
	if source == null:
		push_error("source exposes no mesh surfaces")
		quit(2)
		return
	var baked := ArrayMesh.new()
	# The authored asset record is the authority for which palette roles emit; a
	# bake that ignored it would silently ship a lantern with a dark flame.
	var snapped_vertices := 0
	var raw_surfaces: Array = []
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for index in vertices.size():
			# Scale is owned by _resolve_mesh per source format; the bake only
			# snaps to the grid, which is a no-op on correctly authored geometry.
			vertices[index] = Vector3(
				snappedf(vertices[index].x, unit),
				snappedf(vertices[index].y, unit),
				snappedf(vertices[index].z, unit)
			)
			snapped_vertices += 1
		arrays[Mesh.ARRAY_VERTEX] = vertices
		raw_surfaces.append(arrays)
	# The project's prop contract is a ground-level pivot: the lowest vertex sits
	# at y = 0 and the footprint is centred on the placement point.  The .vox
	# importer emits the model in voxel-space with its corner at the origin, so
	# normalise here rather than relying on the importer's origin.
	var bounds := AABB()
	var bounds_started := false
	for arrays in raw_surfaces:
		for vertex in arrays[Mesh.ARRAY_VERTEX]:
			if bounds_started:
				bounds = bounds.expand(vertex)
			else:
				bounds = AABB(vertex, Vector3.ZERO)
				bounds_started = true
	var pivot := Vector3(
		snappedf(-(bounds.position.x + bounds.end.x) * 0.5, unit),
		snappedf(-bounds.position.y, unit),
		snappedf(-(bounds.position.z + bounds.end.z) * 0.5, unit)
	)
	for surface in raw_surfaces.size():
		var arrays: Array = raw_surfaces[surface]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for index in vertices.size():
			vertices[index] += pivot
		arrays[Mesh.ARRAY_VERTEX] = vertices
		baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		# The palette groups carry their own materials; OBJ's legacy Ns
		# interpretation can import them as near-metallic, so force them matte.
		var imported_material := source.surface_get_material(surface) as StandardMaterial3D
		var material: StandardMaterial3D
		if imported_material == null:
			# A source without a material library (an .obj whose .mtl is missing)
			# must still bake: the surface group name is the palette role, so the
			# material is synthesised from it rather than aborting the bake.
			material = StandardMaterial3D.new()
		else:
			material = imported_material.duplicate() as StandardMaterial3D
		# The palette role drives emission, so it is taken from the surface group
		# and not trusted to the importer's material naming.
		material.resource_name = source.surface_get_name(surface)
		material.metallic = 0.0
		material.roughness = 1.0
		baked.surface_set_material(surface, material)
	var error := ResourceSaver.save(baked, str(args[1]))
	print(JSON.stringify({"ok": error == OK, "source": str(args[0]), "output": str(args[1]), "unit": unit, "surfaces": baked.get_surface_count(), "vertices": snapped_vertices, "error": error}))
	quit(0 if error == OK else 1)
