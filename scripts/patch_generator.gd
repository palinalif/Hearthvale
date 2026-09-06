extends RefCounted
class_name PatchGenerator

const PATCH_SIZE := Vector3i(48, 32, 48)
const CHANNEL_TYPE := 0
const GENERATOR_ID := "m0_terrace_tunnel_v1"

static func generate() -> Object:
	var voxels: Object = ClassDB.instantiate("VoxelBuffer")
	voxels.create(PATCH_SIZE.x, PATCH_SIZE.y, PATCH_SIZE.z)
	for x in PATCH_SIZE.x:
		for z in PATCH_SIZE.z:
			var terrace := 10 + ((int(x / 8) + int(z / 8)) % 4)
			for y in terrace:
				voxels.set_voxel(1 if y < terrace - 1 else 2, x, y, z, CHANNEL_TYPE)
	# A clear tunnel with an intact roof through the centre of the patch.
	for x in range(0, PATCH_SIZE.x):
		for y in range(3, 7):
			for z in range(19, 29):
				voxels.set_voxel(0, x, y, z, CHANNEL_TYPE)
	# A distinct shallow basin for the M0 water material experiment. Its floor
	# stays solid and it is separated from the tunnel by an intact ridge.
	for x in range(34, 47):
		for y in range(3, PATCH_SIZE.y):
			for z in range(4, 15):
				voxels.set_voxel(0, x, y, z, CHANNEL_TYPE)
	return voxels

static func build_library() -> Object:
	var library: Object = ClassDB.instantiate("VoxelBlockyLibrary")
	var empty: Object = ClassDB.instantiate("VoxelBlockyModelEmpty")
	var stone: Object = ClassDB.instantiate("VoxelBlockyModelCube")
	var stone_material := StandardMaterial3D.new()
	stone_material.albedo_color = Color(0.52, 0.42, 0.30)
	stone_material.vertex_color_use_as_albedo = true
	stone.set_material_override(0, stone_material)
	var grass: Object = ClassDB.instantiate("VoxelBlockyModelCube")
	var grass_material := StandardMaterial3D.new()
	grass_material.albedo_color = Color(0.32, 0.62, 0.22)
	grass_material.vertex_color_use_as_albedo = true
	grass.set_material_override(0, grass_material)
	library.add_model(empty)
	library.add_model(stone)
	library.add_model(grass)
	library.bake()
	return library
