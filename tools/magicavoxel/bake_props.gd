extends SceneTree
# Batch-bake every authored prop source in the starter-hamlet catalogue.
#
# One process for the whole catalogue: launching a Godot instance per prop made
# the CI bake step take longer than its own timeout. Each source is snapped to
# the 0.125 structural grid and written beside its tracked siblings.
#
#   godot --headless --path . --script res://tools/magicavoxel/bake_props.gd

const SOURCE_DIR := "res://assets/source/magicavoxel"
const MODEL_DIR := "res://assets/models/magicavoxel"
const UNIT := 0.125


func _init() -> void:
	var dir := DirAccess.open(SOURCE_DIR)
	if dir == null:
		push_error("cannot open %s" % SOURCE_DIR)
		quit(2)
		return
	var names: Array = dir.get_files()
	names.sort()
	var baked := 0
	var failures: Array[String] = []
	for file: String in names:
		if not file.ends_with(".vox"):
			continue
		var base: String = file.trim_suffix(".vox")
		if not base.begins_with("hearthvale_prop_") and base != "hearthvale_bench":
			continue
		# The .vox importer hands back a VoxelModel, not a Mesh.
		var model: Object = load("%s/%s.vox" % [SOURCE_DIR, base])
		if model == null:
			failures.append("%s: source did not load" % base)
			continue
		var source: Mesh = model.get_mesh() as Mesh
		if source == null:
			failures.append("%s: source produced no mesh" % base)
			continue
		var result := _bake(source, "%s/%s.obj" % [MODEL_DIR, base])
		if result != OK:
			failures.append("%s: bake returned %d" % [base, result])
			continue
		baked += 1
	print(JSON.stringify({"ok": failures.is_empty(), "baked": baked, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _bake(source: Mesh, output: String) -> int:
	var baked := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for index in vertices.size():
			vertices[index] = Vector3(
				snappedf(vertices[index].x, UNIT),
				snappedf(vertices[index].y, UNIT),
				snappedf(vertices[index].z, UNIT))
		arrays[Mesh.ARRAY_VERTEX] = vertices
		baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := source.surface_get_material(surface) as StandardMaterial3D
		if material == null:
			push_error("palette surface requires a StandardMaterial3D")
			return FAILED
		var copy := material.duplicate() as StandardMaterial3D
		copy.metallic = 0.0
		copy.roughness = 0.85
		baked.surface_set_material(surface, copy)
	return ResourceSaver.save(baked, output)
