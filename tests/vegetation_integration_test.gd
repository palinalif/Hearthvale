extends SceneTree

const Flora = preload("res://scripts/vegetation_mesh.gd")
const Garden = preload("res://scripts/m1_garden_visual.gd")
const TREE_NAMES := ["orchard", "riverside", "wind"]
const FOLIAGE_NAMES := ["grass", "wildflowers", "leafy"]

var checks := 0
var failures := 0

func _initialize() -> void:
	for kind in ["tree", "foliage"]:
		var names: Array = TREE_NAMES if kind == "tree" else FOLIAGE_NAMES
		for variant in 3:
			var expected := load("res://assets/models/magicavoxel/hearthvale_%s_%s.res" % [kind, names[variant]]) as Mesh
			var actual: Array = Flora.meshes(kind, variant)
			_check(actual.size() == expected.get_surface_count(), "%s variant %d keeps every authored palette surface" % [kind, variant])
			for surface in expected.get_surface_count():
				var source_arrays: Array = expected.surface_get_arrays(surface)
				var part_arrays: Array = actual[surface].surface_get_arrays(0)
				_check(part_arrays[Mesh.ARRAY_VERTEX] == source_arrays[Mesh.ARRAY_VERTEX] and part_arrays[Mesh.ARRAY_INDEX] == source_arrays[Mesh.ARRAY_INDEX], "%s variant %d surface %d uses authored geometry" % [kind, variant, surface])

	var garden := Garden.new()
	root.add_child(garden)
	var records: Array = []
	for variant in 3:
		records.append({"id": variant + 1, "kind": "tree", "seed": variant, "position": [4.0 + variant * 6.0, 8.0, 8.0]})
		records.append({"id": variant + 4, "kind": "foliage", "seed": variant, "position": [4.0 + variant * 2.0, 8.0, 14.0]})
	garden.apply_records(records)
	await process_frame
	var expected_groups := 0
	for kind in ["tree", "foliage"]:
		for variant in 3: expected_groups += Flora.meshes(kind, variant).size()
	_check(garden._groups.size() == expected_groups, "world batches every authored tree and foliage palette surface")
	for key in garden._groups:
		var node: MultiMeshInstance3D = garden._groups[key]
		var kind := str(key).get_slice("_", 0)
		var variant := int(str(key).get_slice("_", 1))
		var surface := int(str(key).get_slice("_", 2))
		var expected: Mesh = Flora.meshes(kind, variant)[surface]
		_check(node.multimesh.mesh == expected and node.multimesh.instance_count == 1, "%s batch renders authored variant %d surface %d" % [kind, variant, surface])
	garden.queue_free()
	await process_frame
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures}))
	quit(1 if failures else 0)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)
