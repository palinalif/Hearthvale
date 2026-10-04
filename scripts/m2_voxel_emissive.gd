extends RefCounted
class_name M2VoxelEmissive
## Reader for the contract the canonical MagicaVoxel bake records beside each mesh.
##
## `tools/magicavoxel/bake_mesh.gd` emits one surface per palette group and
## records which of those surfaces are authored to emit
## (`emissive_palette_indices`) together with the energy it used
## (`emissive_energy`). Runtime glow reads that receipt instead of hardcoding
## palette numbers, so re-authoring a `.vox` cannot silently move a glowing
## surface out from under the code that lights it.

const RECEIPT_DIR := "res://assets/models/magicavoxel"

static func receipt_path(asset_name: String) -> String:
	return "%s/%s.asset.json" % [RECEIPT_DIR, asset_name]

static func load_receipt(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

## Surface indices whose material is one of the receipt's palette numbers.
##
## The canonical bake keeps one surface per palette and names each material
## `palette_N`, so matching by name survives a re-bake that changes surface
## ordering, and a palette that emits no geometry is simply skipped.
static func emissive_surfaces(receipt: Dictionary, mesh: Mesh) -> Array[int]:
	var found: Array[int] = []
	var array := mesh as ArrayMesh
	if array == null:
		return found
	var wanted := {}
	for raw in (receipt.get("emissive_palette_indices", []) as Array):
		wanted["palette_%d" % int(raw)] = true
	for index in array.get_surface_count():
		var material := array.surface_get_material(index) as StandardMaterial3D
		if material != null and wanted.has(material.resource_name):
			found.append(index)
	return found

static func emissive_energy(receipt: Dictionary, fallback: float) -> float:
	return float(receipt.get("emissive_energy", fallback))

## Voxel edge length the mesh was baked at, used to scale legacy anchors.
static func voxel_unit(receipt: Dictionary, fallback: float) -> float:
	return float(receipt.get("voxel_unit", fallback))

## Local-space centre of the given surfaces, used to seat a light inside the
## authored emitter volume. Returns `fallback` when there is nothing to measure.
static func centroid(mesh: ArrayMesh, surface_indices: Array[int], fallback: Vector3) -> Vector3:
	if mesh == null or surface_indices.is_empty(): return fallback
	var sum := Vector3.ZERO
	var count := 0
	for index in surface_indices:
		if index < 0 or index >= mesh.get_surface_count(): continue
		var vertices: PackedVector3Array = mesh.surface_get_arrays(index)[ArrayMesh.ARRAY_VERTEX]
		for vertex in vertices:
			sum += vertex
			count += 1
	return sum / float(count) if count > 0 else fallback
