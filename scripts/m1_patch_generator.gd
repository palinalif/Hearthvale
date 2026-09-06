extends RefCounted
class_name M1PatchGenerator

## Native editable cells share the visible voxel unit. The authored finite
## valley remains 48×32×48 world units; v1 checkpoints migrate without loss.
const PATCH_SIZE := Vector3i(384, 256, 384)
const VOXEL_SCALE := 0.125
const LEGACY_PATCH_SIZE := Vector3i(96, 64, 96)
const LEGACY_VOXEL_SCALE := 0.5
const LEGACY_GENERATOR_ID := "m1_cottage_pad_v1"
const CHANNEL_TYPE := 0
const GENERATOR_ID := "m1_cottage_pad_v2"

static func generate() -> Object:
	var voxels: Object = ClassDB.instantiate("VoxelBuffer")
	voxels.create(PATCH_SIZE.x, PATCH_SIZE.y, PATCH_SIZE.z)
	for x in PATCH_SIZE.x:
		for z in PATCH_SIZE.z:
			var world_x := float(x) * VOXEL_SCALE
			var world_z := float(z) * VOXEL_SCALE
			var height := 8.0 + (world_x - 24.0) / 32.0 + sin(world_z * 0.15) * 0.4
			# Quiet flat cottage pad at world x13..31, z11..25.
			if world_x >= 13.0 and world_x <= 31.0 and world_z >= 11.0 and world_z <= 25.0: height = 8.0
			# Lower meandering east bank.
			if world_x >= 36.0: height = 5.5 + sin(world_z * 0.35 + world_x * 0.08) * 0.6
			var surface := clampi(floori(height / VOXEL_SCALE), 1, PATCH_SIZE.y)
			# Native vertical fills avoid iterating 37.7 million fine cells in
			# GDScript. Only the exposed top cell receives the grass material.
			voxels.fill_area(1, Vector3i(x, 0, z), Vector3i(x + 1, surface - 1, z + 1), CHANNEL_TYPE)
			voxels.set_voxel(2, x, surface - 1, z, CHANNEL_TYPE)
	# Bounded off-centre tunnel and overhang; the roof stays volumetric.
	voxels.fill_area(0, Vector3i(256, 40, 152), Vector3i(312, 64, 208), CHANNEL_TYPE)
	# A shallow east channel leaves a readable water surface above its floor.
	# Keep the authored banks at either edge so it remains a small river strip,
	# not a broad basin or a second terrain system.
	voxels.fill_area(0, Vector3i(312, 32, 80), Vector3i(384, PATCH_SIZE.y, 348), CHANNEL_TYPE)
	return voxels

static func build_library() -> Object:
	var library: Object = ClassDB.instantiate("VoxelBlockyLibrary")
	var empty: Object = ClassDB.instantiate("VoxelBlockyModelEmpty")
	var stone: Object = ClassDB.instantiate("VoxelBlockyModelCube")
	var stone_material := StandardMaterial3D.new()
	stone_material.albedo_color = Color("#ac9677")
	stone_material.vertex_color_use_as_albedo = true
	stone.set_material_override(0, stone_material)
	var grass: Object = ClassDB.instantiate("VoxelBlockyModelCube")
	var grass_material := StandardMaterial3D.new()
	grass_material.albedo_color = Color("#7d9957")
	grass_material.vertex_color_use_as_albedo = true
	grass.set_material_override(0, grass_material)
	library.add_model(empty)
	library.add_model(stone)
	library.add_model(grass)
	library.bake()
	return library
