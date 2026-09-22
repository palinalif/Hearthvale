extends RefCounted
class_name M1PatchGenerator

## Starter valley world generator (M2 v4: 80 m world, closed valley ring).
##
## v4 grows the editable world from 64 m to 80 m (native 512 -> 640 at 0.125 m
## scale). New land beyond the old 0-64 m region:
##   * A closed mountain/forest ring: terrain rises from the v3 boundary edge
##     to a ~13-15 m undulating crest, closing the valley (the presentation
##     ring mesh raises visible peaks above the native height cap).
##   * A village green pad on the highland west of the river for the starter
##     hamlet re-author.
##   * A forest meadow valley east of the river for planting/expansion.
##
## The 0-64 m region is generated with the exact v3 formulas (river centre
## line and ridge heights unchanged), so migrated saves stay seamless at the
## old boundary. Water, bridges and landscape records of migrated worlds are
## untouched; only new ground is generated here.
const Bounds = preload("res://scripts/m2_world_bounds.gd")
const PATCH_SIZE := Bounds.NATIVE_SIZE
const VOXEL_SCALE := 0.125
const LEGACY_PATCH_SIZE := Vector3i(96, 64, 96)
const LEGACY_VOXEL_SCALE := 0.5
const LEGACY_GENERATOR_ID := "m1_cottage_pad_v1"

## The 48 m v2 world (0.5 m cells). Its 4x upsample is the last fallback in
## the migration chain (96 -> 384 -> 640).
const LEGACY_V2_PATCH_SIZE := Vector3i(384, 256, 384)
const LEGACY_V2_GENERATOR_ID := "m1_cottage_pad_v2"
const CHANNEL_TYPE := 0
const GENERATOR_ID := "m2_starter_valley_v4"
const GroundMaterials = preload("res://scripts/terrain_ground_materials.gd")

## Meadow pads (new-world generation only; migrated saves keep their saved
## terrain and records, so pads never affect restores).
##   Village green: flat 8.0 m continuation of the hamlet highland.
##   Forest meadow: 5.65 m valley east of the river; the river-corridor
##   falloff in terrain_height keeps it out of the river bed.
const VILLAGE_GREEN := Rect2(14.0, 28.0, 16.0, 16.0)
const FOREST_MEADOW := Rect2(38.0, 24.0, 8.0, 24.0)

static func river_center_x(world_z: float) -> float:
	return snappedf(40.75 + sin(world_z * 0.19) * 0.9 + sin(world_z * 0.43 + 1.2) * 0.3, VOXEL_SCALE)

static func river_half_width(world_z: float) -> float:
	return snappedf(2.15 + sin(world_z * 0.27 + 0.4) * 0.3, VOXEL_SCALE)

static func terrain_height(world_x: float, world_z: float) -> float:
	var height := _original_height(world_x, world_z)
	# Broad wooded ridges and a generous meadow; no noisy per-cell displacement.
	if world_x > 46.0:
		height = lerpf(height, 10.0 + sin(world_z * 0.10) * 1.25, smoothstep(46.0, 59.0, world_x))
	if world_z > 42.0 and world_x < 35.0:
		height = lerpf(height, 9.5 + sin(world_x * 0.12) * 0.75, smoothstep(42.0, 57.0, world_z))
	for pad: Rect2 in [Rect2(12.5, 26.5, 7.0, 7.0), Rect2(24.5, 31.5, 7.0, 7.0)]:
		var point := Vector2(world_x, world_z)
		var nearest := point.clamp(pad.position, pad.end)
		var blend := 1.0 - smoothstep(0.0, 2.0, point.distance_to(nearest))
		height = lerpf(height, 8.0, blend)
	# --- v4: closed valley ring beyond the old 64 m edge (river corridor
	# keeps the north/south exits open). ---
	height = lerpf(height, _ring_height(world_x, world_z), _ring_weight(world_x, world_z))
	# v4: village green (flat highland extension for the starter hamlet).
	height = lerpf(height, 8.0, _meadow_weight(VILLAGE_GREEN, world_x, world_z, 2.0))
	# v4: forest meadow valley east of the river (never into the river bed).
	height = lerpf(height, 5.65, _meadow_weight(FOREST_MEADOW, world_x, world_z, 2.0) * _river_corridor_falloff(world_x, world_z))
	return height

static func _meadow_weight(rect: Rect2, world_x: float, world_z: float, blend: float) -> float:
	var point := Vector2(world_x, world_z)
	var nearest := point.clamp(rect.position, rect.end)
	return 1.0 - smoothstep(0.0, blend, point.distance_to(nearest))

static func _ring_height(world_x: float, world_z: float) -> float:
	return 13.0 + sin(world_x * 0.055 + world_z * 0.047) * 1.25 + sin(world_x * 0.11 - world_z * 0.08 + 2.0) * 0.7

static func _ring_weight(world_x: float, world_z: float) -> float:
	var depth := maxf(world_x, world_z) - 64.0
	if depth <= 0.0:
		return 0.0
	return smoothstep(0.0, 7.0, depth) * _river_corridor_falloff(world_x, world_z)

static func _river_corridor_falloff(world_x: float, world_z: float) -> float:
	return smoothstep(0.0, 3.0, absf(world_x - river_center_x(world_z)) - river_half_width(world_z))

static func _original_height(world_x: float, world_z: float) -> float:
	var height := 8.0 + (world_x - 24.0) / 32.0 + sin(world_z * 0.15) * 0.4
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

## Deterministic ground painting (stage 3 art pass). Pure function of column
## position (no RNG), so generate() and expand_previous() agree and repeated
## runs produce identical channels. Only the top two surface voxels of each
## column are ever written, so the subsurface stays stone (1) and the old
## 0-64 m region keeps its saved materials on migration.
static func surface_material(world_x: float, world_z: float, height: float) -> int:
	var center := river_center_x(world_z)
	var half := river_half_width(world_z)
	var distance := absf(world_x - center)
	# River bed: sand on the channel floor, gravel on the upper banks.
	if distance <= half:
		return GroundMaterials.SAND if height <= 4.5 else GroundMaterials.GRAVEL
	if distance <= half + 2.5:
		return GroundMaterials.GRAVEL
	# Hamlet highland stays the exact GrassTone grass, with a dirt lane from
	# the well to the bridge landing.
	if world_x >= 13.0 and world_x <= 31.0 and world_z >= 11.0 and world_z <= 25.0:
		return GroundMaterials.GRASS
	if world_z >= 26.5 and world_z <= 28.5 and world_x >= 23.5 and distance > half + 0.5:
		return GroundMaterials.DIRT
	# New ring land (64-80 m): layered forest/mountain variation. The river
	# corridor falloff keeps the two exits green and low.
	var depth := maxf(world_x, world_z) - 64.0
	if depth > 0.0:
		var h := _hash01(world_x, world_z)
		if height >= 12.0:
			return GroundMaterials.ROCK_FACE if h < 0.45 else GroundMaterials.DENSE_GRASS
		if height >= 10.5:
			return GroundMaterials.MOSS if h < 0.35 else GroundMaterials.DENSE_GRASS
		return GroundMaterials.DENSE_GRASS if h < 0.8 else GroundMaterials.GRASS
	# Everything else (meadow pads, lowland, old region): original grass.
	return GroundMaterials.GRASS

static func _hash01(world_x: float, world_z: float) -> float:
	var h := int(world_x * 1000.0) * 374761393 + int(world_z * 1000.0) * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return fmod(absf(float(h)), 1000000.0) / 1000000.0

static func generate() -> Object:
	var voxels: Object = ClassDB.instantiate("VoxelBuffer")
	voxels.create(PATCH_SIZE.x, PATCH_SIZE.y, PATCH_SIZE.z)
	for x in PATCH_SIZE.x:
		for z in PATCH_SIZE.z:
			var height := terrain_height(float(x) * VOXEL_SCALE, float(z) * VOXEL_SCALE)
			var surface := clampi(floori(height / VOXEL_SCALE), 1, PATCH_SIZE.y)
			voxels.fill_area(1, Vector3i(x, 0, z), Vector3i(x + 1, surface - 1, z + 1), CHANNEL_TYPE)
			var material := surface_material(float(x) * VOXEL_SCALE, float(z) * VOXEL_SCALE, height)
			voxels.set_voxel(material, x, surface - 1, z, CHANNEL_TYPE)
			if surface >= 2:
				voxels.set_voxel(material, x, surface - 2, z, CHANNEL_TYPE)
	# The inherited tunnel remains volumetric.
	voxels.fill_area(0, Vector3i(256, 40, 152), Vector3i(312, 64, 208), CHANNEL_TYPE)
	return voxels

static func expand_previous(source: Object, destination: Object = null) -> Object:
	if source == null or source.get_size() != Bounds.PREVIOUS_NATIVE_SIZE: return null
	var result: Object = destination if destination != null else generate()
	if result.get_size() != PATCH_SIZE: return null
	result.set_channel_depth(CHANNEL_TYPE, source.get_channel_depth(CHANNEL_TYPE))
	result.copy_channel_from_area(source, Vector3i.ZERO, Bounds.PREVIOUS_NATIVE_SIZE, Vector3i.ZERO, CHANNEL_TYPE)
	return result

## Copies a saved 384^3 v2 world (48 m, 0.5 m cells) into the 640^3 v4 world
## (0.125 m cells, same 48 m footprint); the new 64-80 m ring and meadows are
## generated fresh around it.
static func expand_legacy_v2(source: Object, destination: Object = null) -> Object:
	if source == null or source.get_size() != LEGACY_V2_PATCH_SIZE: return null
	var result: Object = destination if destination != null else generate()
	if result.get_size() != PATCH_SIZE: return null
	result.set_channel_depth(CHANNEL_TYPE, source.get_channel_depth(CHANNEL_TYPE))
	result.copy_channel_from_area(source, Vector3i.ZERO, LEGACY_V2_PATCH_SIZE, Vector3i.ZERO, CHANNEL_TYPE)
	return result

## Ground material shared by the native grass model. Palette and patch scales
## come from GrassTone (the same model the tuft renderer and the determinism
## tests use), so the GPU field and the CPU model have one source of truth.
static func grass_material() -> ShaderMaterial:
	return GroundMaterials.grass_material(0)

## The full stage-3 material library (10 models, ids 0-9); the caller applies
## the beveled geometry (see TerrainBackend._apply_beveled_blocky_models).
static func build_library() -> Object:
	return GroundMaterials.build_library()
