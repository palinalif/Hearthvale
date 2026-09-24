extends RefCounted
class_name M1PatchGenerator

## Native 160 m starter valley. New worlds have a rounded basin with raised
## foothills on all sides and a reservoir shelf feeding the northern waterfall.
## Saved voxel buffers remain authoritative; this changes fresh generation only.
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
const GENERATOR_ID := "m2_starter_valley_v7"
const GroundMaterials = preload("res://scripts/terrain_ground_materials.gd")

## Meadow pads (new-world generation only; migrated saves keep their saved
## terrain and records, so pads never affect restores). Doubled v4 pads.
##   Village green: flat 8.0 m continuation of the hamlet highland.
##   Forest meadow: 5.65 m valley east of the river; the river-corridor
##   falloff in terrain_height keeps it out of the river bed.
const VILLAGE_GREEN := Rect2(28.0, 56.0, 32.0, 32.0)
const FOREST_MEADOW := Rect2(76.0, 48.0, 16.0, 48.0)
const VALLEY_CENTER := Vector2(80.0, 80.0)
const FOOTHILL_RADIUS := 58.0
const MOUNTAIN_RADIUS := 80.0
const SOURCE_CENTER := Vector2(82.0, 143.5)
const SOURCE_LEVEL := 23.0
const SOURCE_LIP_Z := 140.0
## v6: the spill's razor-thin 0.5 m step becomes a natural rock cliff (lip
## overhang -> steep mid-face with two ledges -> gentle talus foot) and the
## river bed below the spill deepens into a plunge pool that the river drains.
const CLIFF_FOOT_Z := 135.5
const POOL_CENTER := Vector2(82.0, 136.0)
const POOL_RADIUS := Vector2(5.0, 3.25)
const POOL_FLOOR := 2.25

static func previous_river_center_x(world_z: float) -> float:
	# Saved starter streams before the lower valley gained broader bends.
	return snappedf(81.5 + sin(world_z * 0.095) * 1.8 + sin(world_z * 0.215 + 1.2) * 0.6, VOXEL_SCALE)

static func river_center_x(world_z: float) -> float:
	# Broader, asymmetric bends downstream; fade to the original channel at
	# the village and waterfall so both authored crossings remain anchored.
	var bend := smoothstep(5.0, 19.0, world_z) * (1.0 - smoothstep(105.0, 125.0, world_z))
	return snappedf(previous_river_center_x(world_z) + bend * (2.1 * sin(world_z * 0.058 + 0.8) + 0.8 * sin(world_z * 0.14)), VOXEL_SCALE)

static func river_half_width(world_z: float) -> float:
	# Keep the bed inside the 6 m starter-water footprint, leaving a dry
	# bank on each side instead of a broad exposed shallow shelf.
	return snappedf(2.6 + sin(world_z * 0.135 + 0.4) * 0.35, VOXEL_SCALE)

static func terrain_height(world_x: float, world_z: float) -> float:
	var height := _original_height(world_x, world_z)
	# Broad wooded ridges and a generous meadow; no noisy per-cell displacement.
	# (v5: all v4 zones doubled, wavelengths halved, heights unchanged.)
	if world_x > 92.0:
		height = lerpf(height, 10.0 + sin(world_z * 0.05) * 1.25, smoothstep(92.0, 118.0, world_x))
	if world_z > 84.0 and world_x < 70.0:
		height = lerpf(height, 9.5 + sin(world_x * 0.06) * 0.75, smoothstep(84.0, 114.0, world_z))
	for pad: Rect2 in [Rect2(25.0, 53.0, 14.0, 14.0), Rect2(49.0, 63.0, 14.0, 14.0)]:
		var point := Vector2(world_x, world_z)
		var nearest := point.clamp(pad.position, pad.end)
		var blend := 1.0 - smoothstep(0.0, 4.0, point.distance_to(nearest))
		height = lerpf(height, 8.0, blend)
	# --- v5: closed valley ring beyond the old 128 m edge (river corridor
	# keeps the north/south exits open). ---
	height = lerpf(height, _ring_height(world_x, world_z), _ring_weight(world_x, world_z))
	# The waterfall begins in a mountain notch, not atop an isolated flat
	# platform. Two broad native ridges rise behind and beside its reservoir;
	# the river corridor and the spill shelf are left to their owners below.
	var backing_rise := _waterfall_backing_rise(world_x, world_z)
	if backing_rise > 0.0:
		height = minf(height + backing_rise, 31.75)
	height = lerpf(height, 8.0, _meadow_weight(Rect2(26.0, 22.0, 36.0, 28.0), world_x, world_z, 4.0))
	# v5: village green (flat highland extension for the starter hamlet).
	height = lerpf(height, 8.0, _meadow_weight(VILLAGE_GREEN, world_x, world_z, 4.0))
	# v5: forest meadow valley east of the river (never into the river bed).
	height = lerpf(height, 5.65, _meadow_weight(FOREST_MEADOW, world_x, world_z, 4.0) * _river_corridor_falloff(world_x, world_z))
	# Carve only the inlet feeding the lip. Outside its tapered banks the
	# native mountain ring (and west headwall) remains untouched; the
	# graded bed joins the native banks instead of spanning them with a bench.
	var inlet := _waterfall_inlet_weight(world_x, world_z)
	if inlet > 0.0:
		height = lerpf(height, _waterfall_inlet_floor(world_z), inlet)
	# Recess the pond behind the spill, grading its dry banks into the hills.
	# Keep the bed submerged without changing the structural lip or drop.
	var from_center := Vector2(world_x, world_z) - SOURCE_CENTER
	var pond_radius := Vector2(5.9, 6.0)
	var pond_distance := Vector2(from_center.x / pond_radius.x, from_center.y / pond_radius.y).length()
	var pond := 1.0 - smoothstep(1.0, 1.4, pond_distance)
	height = lerpf(height, SOURCE_LEVEL - 0.75, pond)
	# Unequal grassy headlands frame the pond outside the wet footprint.
	var dry_shore := smoothstep(5.5, 8.0, from_center.length())
	var west := Vector2((world_x - 69.0) / 14.0, (world_z - 145.0) / 10.0).length()
	var east := Vector2((world_x - 95.0) / 14.0, (world_z - 144.0) / 9.0).length()
	var headland := maxf(1.0 - smoothstep(0.2, 1.0, west), 1.0 - smoothstep(0.2, 1.0, east)) * dry_shore
	height = maxf(height, lerpf(height, 26.0, headland))
	if world_z < SOURCE_LIP_Z and absf(world_x - river_center_x(world_z)) <= river_half_width(world_z):
		height = 4.375 + snappedf(sin(world_z * 0.145) * 0.125, VOXEL_SCALE)
	# v6: rock face below the reservoir lip and a plunge pool in the river
	# bed, so the cascade reads reservoir -> cliff -> sheet -> pool. Both are
	# deterministic (no RNG); the pool carves through the talus foot into the
	# river bed. All heights land on the 0.125 m grid.
	var cliff := _cliff_face_weight(world_x, world_z)
	if cliff > 0.0:
		height = lerpf(height, _cliff_face_height(world_x, world_z), cliff)
	var pool := _plunge_pool_weight(world_x, world_z)
	if pool > 0.0:
		height = lerpf(height, POOL_FLOOR, pool)
	return height

## A single slanting west headwall joins the rear mountain ring to the
## reservoir shoulder. The eastern shoulder relies on the native ring rather
## than mirroring another isolated bump across the lake.
static func _waterfall_backing_rise(world_x: float, world_z: float) -> float:
	var a := Vector2(64.0, 159.0)
	var b := Vector2(75.0, 145.0)
	var p := Vector2(world_x, world_z)
	var along := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	var distance := p.distance_to(a.lerp(b, along))
	var flank := 1.0 - smoothstep(4.0, 14.0, distance)
	return 6.5 * flank * (1.0 - 0.45 * along)

## A narrow, tapering creek inlet within the existing mountain ring.
## The full-width cut ends just behind the lake; further upstream only a
## small thalweg remains, with native hills on both sides. The southward
## fade leaves the separate structural cliff and river corridor intact.
static func _waterfall_inlet_weight(world_x: float, world_z: float) -> float:
	var rear := maxf(0.0, world_z - 146.0)
	var center_x := SOURCE_CENTER.x - 0.18 * rear
	var taper := smoothstep(146.0, 158.0, world_z)
	var half_width := lerpf(11.5, 3.5, taper)
	var inner := lerpf(5.5, 2.0, taper)
	var lateral := 1.0 - smoothstep(inner, half_width, absf(world_x - center_x))
	var front := smoothstep(138.75, 140.0, world_z)
	var rear_fade := 1.0 - smoothstep(151.0, 159.0, world_z)
	return lateral * front * rear_fade

## Gently rising creek bed; the tight lake apron below overrides this at
## the shore, while the tapered banks blend back to the native hills.
static func _waterfall_inlet_floor(world_z: float) -> float:
	var rear := maxf(0.0, world_z - SOURCE_LIP_Z)
	return 22.25 + 1.25 * smoothstep(140.0, 142.0, world_z) + 0.16 * rear + 0.008 * rear * rear

## Support the full waterfall curtain across the inner 7 m, then grade
## into the native mountain without the former wide projecting wings.
static func _cliff_face_weight(world_x: float, world_z: float) -> float:
	if world_z >= SOURCE_LIP_Z or world_z < CLIFF_FOOT_Z:
		return 0.0
	var side := world_x - SOURCE_CENTER.x
	return 1.0 - smoothstep(7.0, 10.5 if side > 0.0 else 11.5, absf(side))

## The cliff's top edge: an asymmetric depth stagger (east 2.25 m uphill,
## west 1.75 m downhill) plus a broad 0.75 m wave, so the lip line sweeps as
## a diagonal across the face instead of a straight transverse cliff. The
## stagger only shifts where the profile is evaluated; the 22.25 lip, 17.5 m
## head, and toe values are preserved. Broad rock ribs break the mid-face.
## Deterministic; generate() quantises the surface to 0.125 m.
static func _cliff_face_height(world_x: float, world_z: float) -> float:
	var side := world_x - SOURCE_CENTER.x
	var distance := absf(side)
	# The stagger is only active around the upper-wall band; it tapers
	# out into the toe (keeps the 4.5 m toe exact) and above it into the
	# lip (keeps the 22.25 m lip exact).
	var stagger := smoothstep(4.0, 11.0, distance) * (1.0 if side > 0.0 else -0.75)
	stagger += 0.5 * sin(side * 0.55 + 2.0) * smoothstep(3.5, 9.0, distance)
	stagger *= smoothstep(136.75, 137.5, world_z)
	# Fade the stagger out before the pinned lip; otherwise its shifted
	# profile makes a narrow rock spike higher than the spill edge.
	stagger *= 1.0 - smoothstep(139.0, SOURCE_LIP_Z, world_z)
	var face_z := world_z - stagger
	var middle := smoothstep(135.5, 136.75, world_z) * (1.0 - smoothstep(138.25, SOURCE_LIP_Z, world_z))
	var rib := 0.5 * sin(side * 0.85) + 0.25 * sin(side * 1.7 + 0.4)
	return _cliff_profile(face_z, side) + rib * middle

## The drop from the 22.25 lip overhang to the 4.5 pool toe. The centre
## (under the sheet) falls steeply just below the lip, keeping rock behind
## the falling water rather than projecting a talus wedge into the sheet;
## the flanks follow the same wall and ease into the pool,
## so the silhouette is one vertical drop from the shelf with no flat cap
## or projecting bench south of the lip. The flank's exponent and a small
## ripple undulate in x (zero at both pinned ends), so the rock reads
## uneven without any horizontal mass in front of the cascade.
static func _cliff_profile(world_z: float, side: float) -> float:
	if world_z >= SOURCE_LIP_Z:
		return 22.25                                        # spill edge, no dry cap
	if world_z < 136.5:
		return lerpf(4.75, 4.5, smoothstep(136.5, CLIFF_FOOT_Z, world_z))
	var up := smoothstep(SOURCE_LIP_Z, 136.5, world_z)
	var center := lerpf(4.75, 22.25, pow(1.0 - up, 2.5))
	var flank := smoothstep(3.0, 7.5, absf(side))
	if flank <= 0.0:
		return center
	# Vary the flank's descent rate without rippling upward near the toe:
	# each lateral transect must remain monotonically downhill to the pool.
	var exponent := 2.5 + 0.3 * sin(side * 0.5 + 1.3)
	var wall := lerpf(4.75, 22.25, pow(1.0 - up, exponent))
	return lerpf(center, wall, flank)

## Elliptical basin under the spill: full depth inside 70% of the rim,
## smoothly blended out to the river bed.
static func _plunge_pool_weight(world_x: float, world_z: float) -> float:
	var d := Vector2(world_x, world_z) - POOL_CENTER
	var r := Vector2(d.x / POOL_RADIUS.x, d.y / POOL_RADIUS.y).length()
	return 1.0 - smoothstep(0.7, 1.0, r)

static func _meadow_weight(rect: Rect2, world_x: float, world_z: float, blend: float) -> float:
	var point := Vector2(world_x, world_z)
	var nearest := point.clamp(rect.position, rect.end)
	return 1.0 - smoothstep(0.0, blend, point.distance_to(nearest))

static func _ring_height(world_x: float, world_z: float) -> float:
	return 24.0 + sin(world_x * 0.065 + world_z * 0.047) * 2.0 + sin(world_x * 0.11 - world_z * 0.08 + 2.0)

static func valley_radius(world_x: float, world_z: float) -> float:
	var delta := Vector2(world_x, world_z) - VALLEY_CENTER
	var angle := atan2(delta.y, delta.x)
	return delta.length() + 2.0 * sin(angle * 3.0) + 1.5 * sin(angle * 5.0 + 0.7)

static func _ring_weight(world_x: float, world_z: float) -> float:
	var weight := smoothstep(FOOTHILL_RADIUS, MOUNTAIN_RADIUS, valley_radius(world_x, world_z))
	# Only the downstream end opens through the mountains. Upstream is the
	# reservoir's solid backing, rather than a second river exit.
	var outlet := lerpf(_river_corridor_falloff(world_x, world_z), 1.0, smoothstep(130.0, 146.0, world_z))
	return weight * outlet

static func _river_corridor_falloff(world_x: float, world_z: float) -> float:
	return smoothstep(0.0, 6.0, absf(world_x - river_center_x(world_z)) - river_half_width(world_z))

static func _original_height(world_x: float, world_z: float) -> float:
	# v5: doubled v4 planar layout, identical height profile (8 m plateau,
	# 5.65 m valley floor, 4.375 m river bed, 5.125 m banks).
	var height := 8.0 + (world_x - 48.0) / 64.0 + sin(world_z * 0.075) * 0.4
	if world_x >= 26.0 and world_x <= 62.0 and world_z >= 22.0 and world_z <= 50.0:
		height = 8.0
	var low_bank := 5.65 + sin(world_z * 0.155 + world_x * 0.035) * 0.3
	if world_x > 62.0:
		height = lerpf(height, low_bank, smoothstep(62.0, 73.0, world_x))
	var distance := absf(world_x - river_center_x(world_z))
	var half_width := river_half_width(world_z)
	if distance <= half_width:
		return 4.375 + snappedf(sin(world_z * 0.145) * 0.125, VOXEL_SCALE)
	if distance <= half_width + 5.0:
		# The dry bank begins above water, then grades into unequal grassy
		# shoulders. Long waves keep its silhouette from reading as a ruler.
		var side := -1.0 if world_x < river_center_x(world_z) else 1.0
		var bank_span := 3.5 + 0.65 * sin(world_z * 0.087 + side * 1.7)
		var bank_blend := smoothstep(0.0, 1.0, (distance - half_width) / bank_span)
		var inner_height := 5.35 + 0.22 * sin(world_z * 0.11 + side)
		return lerpf(inner_height, height, bank_blend) if distance < half_width + bank_span else height
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
	# The dry inlet banks transition into the green mountain slopes. Keep the
	# rocky lip and submerged bed intact; the steep upper cut is mossy rock.
	if world_z > 142.0 and world_z < 155.0 and height > SOURCE_LEVEL + 0.25 and _waterfall_inlet_weight(world_x, world_z) > 0.35:
		return GroundMaterials.MOSS if height < 26.5 else GroundMaterials.DENSE_GRASS
	# Sand stays submerged. Above the waterline a thin gravel seam gives
	# way immediately to green banks; the old metre-wide dry gravel shelf
	# read as a pale wedge from the waterfall camera.
	if distance <= half:
		return GroundMaterials.SAND if distance <= 1.875 and height <= 4.5 else GroundMaterials.GRAVEL
	var wet_edge := half + 0.35 + 0.15 * sin(world_z * 0.16 + (0.7 if world_x > center else -0.7))
	if distance <= wet_edge:
		return GroundMaterials.GRAVEL
	if distance <= half + 4.75 and height < 7.0:
		return GroundMaterials.MOSS if sin(world_z * 0.19 + world_x * 0.24) > 0.48 else GroundMaterials.GRASS
	# v6: rock face on the waterfall cliff; the plunge pool keeps the pool
	# sand even where the basin spills onto the gravel bank.
	if _cliff_face_weight(world_x, world_z) > 0.5 and height > 5.5:
		return GroundMaterials.ROCK_FACE
	if _plunge_pool_weight(world_x, world_z) > 0.5 and height <= POOL_FLOOR + 1.0:
		return GroundMaterials.SAND
	# Hamlet highland stays the exact GrassTone grass. The authored packed-earth
	# paths replace the old unbounded 4 m terrain-painted dirt lane.
	if world_x >= 26.0 and world_x <= 62.0 and world_z >= 22.0 and world_z <= 50.0:
		return GroundMaterials.GRASS
	# New ring land (128-160 m): layered forest/mountain variation. The river
	# corridor falloff keeps the two exits green and low.
	if valley_radius(world_x, world_z) > FOOTHILL_RADIUS and height > 10.0:
		var h := _hash01(world_x, world_z)
		if height >= 12.0:
			return GroundMaterials.ROCK_FACE if h < 0.45 else GroundMaterials.DENSE_GRASS
		if height >= 10.5:
			return GroundMaterials.MOSS if h < 0.35 else GroundMaterials.DENSE_GRASS
		return GroundMaterials.DENSE_GRASS if h < 0.8 else GroundMaterials.GRASS
	# Everything else (meadow pads, lowland, old region): original grass.
	return GroundMaterials.GRASS

## Exposed cuts need the surrounding mountain's rock/moss colors: painting
## only the top two cells leaves the tall wall and inlet banks as warm stone.
## Keep this exception local; ordinary terrain stays stone below the surface.
static func waterfall_cut_material(world_x: float, world_z: float, height: float) -> int:
	if height > 5.5 and _cliff_face_weight(world_x, world_z) > 0.05:
		return GroundMaterials.ROCK_FACE
	if world_z >= SOURCE_LIP_Z and world_z < 155.0 and height > SOURCE_LEVEL - 0.5 and _waterfall_inlet_weight(world_x, world_z) > 0.05:
		return GroundMaterials.MOSS if world_z > 142.0 and _waterfall_inlet_weight(world_x, world_z) > 0.35 else GroundMaterials.ROCK_FACE
	return GroundMaterials.STONE

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
			var world_x := float(x) * VOXEL_SCALE
			var world_z := float(z) * VOXEL_SCALE
			voxels.fill_area(GroundMaterials.STONE, Vector3i(x, 0, z), Vector3i(x + 1, surface - 1, z + 1), CHANNEL_TYPE)
			var cut_material := waterfall_cut_material(world_x, world_z, height)
			if cut_material != GroundMaterials.STONE:
				voxels.fill_area(cut_material, Vector3i(x, floori(4.5 / VOXEL_SCALE), z), Vector3i(x + 1, surface - 1, z + 1), CHANNEL_TYPE)
			var material := surface_material(world_x, world_z, height)
			voxels.set_voxel(material, x, surface - 1, z, CHANNEL_TYPE)
			if surface >= 2:
				voxels.set_voxel(material, x, surface - 2, z, CHANNEL_TYPE)
	# The inherited tunnel remains volumetric (v5: 2x box, doubled position).
	voxels.fill_area(0, Vector3i(512, 80, 304), Vector3i(624, 128, 416), CHANNEL_TYPE)
	return voxels

static func expand_previous(source: Object, destination: Object = null) -> Object:
	if source == null or source.get_size() != Bounds.PREVIOUS_NATIVE_SIZE: return null
	var result: Object = destination if destination != null else generate()
	if result.get_size() != PATCH_SIZE: return null
	result.set_channel_depth(CHANNEL_TYPE, source.get_channel_depth(CHANNEL_TYPE))
	result.copy_channel_from_area(source, Vector3i.ZERO, Bounds.PREVIOUS_NATIVE_SIZE, Vector3i.ZERO, CHANNEL_TYPE)
	return result

## Copies a saved 384^3 v2 world (48 m, 0.5 m cells) into the 1280^3 v5 world
## (0.125 m cells); the v5 world's 0-48 m corner holds the v2 footprint at
## double resolution, and everything else is generated fresh.
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

## The full stage-3 material library (10 models, ids 0-9).
static func build_library() -> Object:
	return GroundMaterials.build_library()
