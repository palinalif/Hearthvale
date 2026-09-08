extends SceneTree

const Grid = preload("res://scripts/visual_grid.gd")
const World = preload("res://scripts/building_world.gd")
const Visual = preload("res://scripts/cottage_visual.gd")
const Flora = preload("res://scripts/vegetation_mesh.gd")
const Garden = preload("res://scripts/m1_garden_visual.gd")
var failures := 0
var checks := 0
var vertices_checked := 0
var instances_checked := 0
var unverified_instances := 0
var scene: Node3D
# Deliberately independent of renderer metadata: only these cottage families
# may use the approved half-cell tier. All other assets retain structural tests.
const DETAIL_PREFIXES := ["Reveal_", "Joinery_", "Shutters_", "ManualShutter_", "FlowerBox_", "BoxFoliage_", "BoxFlowers_", "BoxFlowerAccents_", "Trim_", "Cornice_", "RoofTiles_"]
const DETAIL_NAMES := ["EaveJoinery", "RidgeCourses", "RoofEdgeLip"]

func _initialize() -> void:
	scene = Node3D.new(); root.add_child(scene)
	var world := World.new()
	_check(not world.add_detail("building-1", "flower_box", "wall-front", Vector3(0, 1.5, -7.02), "flower_box_wood").is_empty(), "flower-box fixture exists")
	_check(not world.add_detail("building-1", "shutter", "wall-back", Vector3(0, 3.4, 7.02), "shutter_wood").is_empty(), "manual-shutter fixture exists")
	var rendered := DisplayServer.get_name() != "headless"
	if "--require-rendering" in OS.get_cmdline_user_args():
		_check(rendered and RenderingServer.get_current_rendering_method() == "mobile", "actual Mobile renderer is active")
	for scale_value in [0.25, 0.5, 1.0]:
		for resized in [false, true]:
			var view: Dictionary = world.get_building("building-1")
			if resized:
				world.resize("building-1", Vector3(23, 8, 12))
				view = world.get_building("building-1")
			view["transform"] = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_value), Vector3(3, 8, 4))
			var visual := Visual.new(); scene.add_child(visual)
			_check(visual.apply_building(view, world.get_revision()), "build cottage scale %.2f resize %s" % [scale_value, resized])
			await process_frame
			if rendered: await process_frame
			_inspect_node(visual, visual.global_position, "cottage %.2f resize %s" % [scale_value, resized], rendered)
			visual.free()
			if resized: world.undo()
	var copy_id: String = world.duplicate_building("building-1", Vector3(4, 0, 4))
	_check(not copy_id.is_empty(), "duplicate detail-grid fixture")
	var restored := World.new()
	_check(restored.load_serialized_document(world.serialize_document()), "reload detail-grid fixture")
	var copied_visual := Visual.new(); scene.add_child(copied_visual)
	_check(copied_visual.apply_building(restored.get_building(copy_id), restored.get_revision()), "render reloaded duplicate")
	await process_frame
	if rendered: await process_frame
	_inspect_node(copied_visual, copied_visual.global_position, "reloaded duplicate", rendered)
	copied_visual.free()
	for kind in ["tree", "foliage", "rock"]:
		var signatures: Array[String] = []
		for variant in 3:
			var meshes: Array = Flora.meshes(kind, variant)
			_check(not meshes.is_empty(), "%s variant %d exists" % [kind, variant])
			var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256)
			for mesh: ArrayMesh in meshes:
				_inspect_mesh(mesh, Transform3D.IDENTITY, Vector3.ZERO, "%s variant %d" % [kind, variant])
				context.update((mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array())
			var signature := context.finish().hex_encode()
			signatures.append(signature)
			var repeated: Array = Flora.meshes(kind, variant)
			_check(repeated == meshes, "%s variant %d deterministic cached geometry" % [kind, variant])
		_check(signatures[0] != signatures[1] and signatures[1] != signatures[2], "%s variants change geometry without scaling cells" % kind)
	var garden := Garden.new(); scene.add_child(garden)
	var records: Array = []
	for index in 9:
		records.append({"id": index + 1, "kind": ["tree", "foliage", "rock"][index / 3], "seed": index, "position": [float(index), 8.125, 4.25]})
	garden.apply_records(records)
	await process_frame
	if rendered: await process_frame
	_inspect_node(garden, Vector3.ZERO, "placed garden", rendered)
	garden.free()
	_check(vertices_checked > 1000, "inspect substantial actual geometry")
	if rendered: _check(instances_checked > 100, "inspect actual rendered MultiMesh transforms")
	scene.queue_free(); await process_frame
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "unit": Grid.UNIT, "vertices_checked": vertices_checked, "instances_checked": instances_checked, "unverified_headless_instances": unverified_instances, "renderer": RenderingServer.get_current_rendering_method()}))
	quit(1 if failures else 0)

func _inspect_node(node: Node, origin: Vector3, label: String, rendered: bool) -> void:
	var unit := Grid.UNIT
	if node.get_parent() is Visual:
		var decorative := str(node.name) in DETAIL_NAMES
		for prefix in DETAIL_PREFIXES:
			decorative = decorative or str(node.name).begins_with(prefix)
		_check(node.has_meta("cottage_detail_grid") == decorative, label + "/" + str(node.name) + " declares only permitted detail tier")
		if decorative: unit = Grid.COTTAGE_DETAIL_UNIT
	if node is MultiMeshInstance3D:
		var multi: MultiMesh = node.multimesh
		if not rendered:
			unverified_instances += multi.instance_count
		else:
			var has_fine_step := false
			for i in multi.instance_count:
				var instance: Transform3D = node.global_transform * multi.get_instance_transform(i)
				var size := instance.basis.get_scale().abs()
				has_fine_step = has_fine_step or is_equal_approx(minf(size.x, minf(size.y, size.z)), Grid.COTTAGE_DETAIL_UNIT)
				_check(instance.basis.determinant() > 0.000000001, label + "/" + str(node.name) + " nonzero native instance")
				_inspect_mesh(multi.mesh, instance, origin, label + "/" + str(node.name), unit)
				instances_checked += 1
			if unit == Grid.COTTAGE_DETAIL_UNIT:
				_check(has_fine_step, label + "/" + str(node.name) + " actually contains half-cell detail")
	elif node is MeshInstance3D and node.mesh:
		_inspect_mesh(node.mesh, node.global_transform, origin, label + "/" + str(node.name), unit)
	for child in node.get_children(): _inspect_node(child, origin, label, rendered)

func _inspect_mesh(mesh: Mesh, transform_value: Transform3D, origin: Vector3, label: String, unit := Grid.UNIT) -> void:
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var on_grid := not vertices.is_empty()
		for vertex in vertices:
			var world_point := transform_value * vertex - origin
			for axis in 3:
				on_grid = on_grid and absf(world_point[axis] / unit - roundf(world_point[axis] / unit)) < 0.0002
		vertices_checked += vertices.size()
		_check(on_grid, label + " world vertices share %.4f grid" % unit)
		var valid_faces := true
		for i in range(0, indices.size(), 3):
			var a: Vector3 = transform_value * vertices[indices[i]]
			var b: Vector3 = transform_value * vertices[indices[i + 1]]
			var c: Vector3 = transform_value * vertices[indices[i + 2]]
			var normal := (b - a).cross(c - a).normalized().abs()
			valid_faces = valid_faces and maxf(normal.x, maxf(normal.y, normal.z)) > 0.9999
		_check(valid_faces, label + " faces remain axis-aligned voxel steps")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures <= 30: print("FAIL: " + label)
