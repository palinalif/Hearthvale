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

static func river_center_x(world_z: float) -> float:
	return snappedf(40.75 + sin(world_z * 0.19) * 0.9 + sin(world_z * 0.43 + 1.2) * 0.3, VOXEL_SCALE)

static func river_half_width(world_z: float) -> float:
	return snappedf(2.15 + sin(world_z * 0.27 + 0.4) * 0.3, VOXEL_SCALE)

static func terrain_height(world_x: float, world_z: float) -> float:
	var height := 8.0 + (world_x - 24.0) / 32.0 + sin(world_z * 0.15) * 0.4
	# Quiet flat cottage pad at world x13..31, z11..25.
	if world_x >= 13.0 and world_x <= 31.0 and world_z >= 11.0 and world_z <= 25.0:
		height = 8.0
	var low_bank := 5.65 + sin(world_z * 0.31 + world_x * 0.07) * 0.3
	if world_x > 31.0:
		height = lerpf(height, low_bank, smoothstep(31.0, 36.5, world_x))
	var distance := absf(world_x - river_center_x(world_z))
	var half_width := river_half_width(world_z)
	if distance <= half_width:
		return 4.375 + snappedf(sin(world_z * 0.29) * 0.125, VOXEL_SCALE)
	if distance <= half_width + 2.5:
		var bank_blend := smoothstep(0.0, 1.0, (distance - half_width) / 2.5)
		return lerpf(5.125, height, bank_blend)
	return height

static func generate() -> Object:
	var voxels: Object = ClassDB.instantiate("VoxelBuffer")
	voxels.create(PATCH_SIZE.x, PATCH_SIZE.y, PATCH_SIZE.z)
	for x in PATCH_SIZE.x:
		for z in PATCH_SIZE.z:
			var world_x := float(x) * VOXEL_SCALE
			var world_z := float(z) * VOXEL_SCALE
			var height := terrain_height(world_x, world_z)
			var surface := clampi(floori(height / VOXEL_SCALE), 1, PATCH_SIZE.y)
			# Native vertical fills avoid iterating 37.7 million fine cells in
			# GDScript. Only the exposed top cell receives the grass material.
			voxels.fill_area(1, Vector3i(x, 0, z), Vector3i(x + 1, surface - 1, z + 1), CHANNEL_TYPE)
			voxels.set_voxel(2, x, surface - 1, z, CHANNEL_TYPE)
	# Bounded off-centre tunnel and overhang; the roof stays volumetric.
	voxels.fill_area(0, Vector3i(256, 40, 152), Vector3i(312, 64, 208), CHANNEL_TYPE)
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
