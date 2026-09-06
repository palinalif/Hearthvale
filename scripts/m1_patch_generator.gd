extends RefCounted
class_name M1PatchGenerator

## M1 doubles index resolution while keeping the authored world 48×32×48.
const PATCH_SIZE := Vector3i(96, 64, 96)
const VOXEL_SCALE := 0.5
const CHANNEL_TYPE := 0
const GENERATOR_ID := "m1_cottage_pad_v1"

static func generate() -> Object:
	var voxels: Object = ClassDB.instantiate("VoxelBuffer")
	voxels.create(PATCH_SIZE.x, PATCH_SIZE.y, PATCH_SIZE.z)
	for x in PATCH_SIZE.x:
		for z in PATCH_SIZE.z:
			var world_x := float(x) * VOXEL_SCALE
			var world_z := float(z) * VOXEL_SCALE
			var surface := 16 + floori((float(x) - 48.0) / 32.0 + sin(float(z) * 0.075) * 0.8)
			# Quiet flat cottage pad at world x13..31, z11..25.
			if world_x >= 13.0 and world_x <= 31.0 and world_z >= 11.0 and world_z <= 25.0: surface = 16
			# Lower meandering east bank.
			if world_x >= 36.0: surface = 11 + floori(sin(world_z * 0.35 + world_x * 0.08) * 1.2)
			for y in surface:
				voxels.set_voxel(1 if y < surface - 1 else 2, x, y, z, CHANNEL_TYPE)
	# Bounded off-centre tunnel and overhang; the roof stays volumetric.
	for x in range(64, 78):
		for z in range(38, 52):
			for y in range(10, 16): voxels.set_voxel(0, x, y, z, CHANNEL_TYPE)
	# A shallow east channel leaves a readable water surface above its floor.
	# Keep two native-cell banks at either edge so it remains a small river strip,
	# not a broad basin or a second terrain system.
	for x in range(78, 96):
		for z in range(20, 87):
			for y in range(8, PATCH_SIZE.y): voxels.set_voxel(0, x, y, z, CHANNEL_TYPE)
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
