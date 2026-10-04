extends SceneTree
## Contract check for the authored path lantern's runtime mesh.
##
## The lantern's glow is driven by the bake receipt, so a re-bake that changes
## the mesh silently breaks the lighting. This asserts the shipped mesh and its
## receipt still agree: the asset is the authored one, it is baked on the
## presentation grid, and every palette the receipt marks emissive has a
## surface named for it.

const M2VoxelEmissive := preload("res://scripts/m2_voxel_emissive.gd")
const M2LanternAssets := preload("res://scripts/m2_lantern_assets.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	var receipt := M2VoxelEmissive.load_receipt(
		M2VoxelEmissive.receipt_path(M2LanternAssets.ASSET))
	_expect(not receipt.is_empty(), "the lantern asset has a bake receipt")
	if receipt.is_empty():
		_finish()
		return

	# The receipt names the source; the baked runtime mesh sits beside it under
	# the canonical MagicaVoxel model directory.
	var asset := str(receipt.get("asset", M2LanternAssets.ASSET))
	var mesh := load("res://assets/models/magicavoxel/%s.res" % asset) as ArrayMesh
	_expect(mesh != null, "the receipt's mesh loads as a mesh")
	if mesh == null:
		_finish()
		return

	# The runtime must present the authored asset, not the legacy procedural
	# lantern: the legacy mesh has 4 surfaces, the authored one has one per
	# palette used.
	_expect(
		mesh.get_surface_count() > 4,
		"the runtime mesh is the authored asset, not the legacy procedural lantern"
	)

	# The lantern is authored on the fine presentation grid, so a re-bake on the
	# structural grid (which halves its size) is caught here.
	var unit := M2VoxelEmissive.voxel_unit(receipt, 0.0)
	_expect(unit > 0.0 and unit <= 0.0625, "the lantern is baked on the presentation grid")

	# The glow lights the surfaces named for the receipt's palettes; a mesh
	# without them has nothing to glow.
	var palettes: Array = receipt.get("emissive_palette_indices", []) as Array
	_expect(not palettes.is_empty(), "the receipt marks at least one palette emissive")
	var missing: Array[int] = []
	for raw in palettes:
		if not _has_palette(mesh, int(raw)):
			missing.append(int(raw))
	_expect(missing.is_empty(), "every emissive palette in the receipt has a matching mesh surface")

	_finish()

func _has_palette(mesh: ArrayMesh, palette_index: int) -> bool:
	for index in mesh.get_surface_count():
		var material := mesh.surface_get_material(index) as StandardMaterial3D
		if material != null and material.resource_name == "palette_%d" % palette_index:
			return true
	return false

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)

func _finish() -> void:
	for failure in _failures:
		print("M2_LANTERN_MESH_CONTRACT_FAIL ", failure)
	print("M2_LANTERN_MESH_CONTRACT ", "PASS" if _failures.is_empty() else "FAIL")
	quit(0 if _failures.is_empty() else 1)
