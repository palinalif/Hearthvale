extends Node3D
class_name M1GardenVisual

const Flora = preload("res://scripts/vegetation_mesh.gd")
const State = preload("res://scripts/landscape_state.gd")
var _groups: Dictionary = {}

func attach_backend(_backend: Node) -> void:
	pass

func refresh_terrain() -> void:
	pass # Saved roots do not relocate or resurrect automatically after edits.

func apply_records(records: Array) -> void:
	# Batch identical authored meshes; each instance is translation-only. This
	# retains every fine cell while avoiding hundreds of per-plant draw calls.
	var batches := {}
	for record: Dictionary in records:
		var kind := str(record["kind"]); var variant := posmod(int(record["seed"]), 3)
		var meshes: Array = Flora.meshes(kind, variant)
		for index in meshes.size():
			var key := "%s_%d_%d" % [kind, variant, index]
			if not batches.has(key): batches[key] = {"mesh": meshes[index], "positions": []}
			batches[key]["positions"].append(State.position_of(record))
	for key in batches:
		var batch: Dictionary = batches[key]
		if not _groups.has(key):
			var node := MultiMeshInstance3D.new(); node.name = "PlantBatch_" + key
			var multi := MultiMesh.new(); multi.transform_format = MultiMesh.TRANSFORM_3D; multi.mesh = batch["mesh"]
			node.multimesh = multi; add_child(node); _groups[key] = node
		var node: MultiMeshInstance3D = _groups[key]
		var multi: MultiMesh = node.multimesh
		var positions: Array = batch["positions"]
		if multi.instance_count != positions.size(): multi.instance_count = positions.size()
		for index in positions.size(): multi.set_instance_transform(index, Transform3D(Basis.IDENTITY, positions[index]))
	for key in _groups:
		if not batches.has(key): _groups[key].multimesh.instance_count = 0

func reset_records(records: Array) -> void:
	apply_records(records)
