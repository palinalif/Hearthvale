extends RefCounted
class_name GrassTone

## Deterministic meadow-tone model for the native grass surface.
##
## The visible ground is the native voxel terrain: every grass column carries
## `res://scripts/terrain_grass.gdshader`, which evaluates this model per vertex.
## The tone is a smooth multi-scale field only: an independent per-cell jitter
## aliased into a fine diagonal moire across the whole meadow at gameplay
## distance, so voxel-level texture comes from the scattered tufts. This module
## is the
## single source of truth for the palette and the patch scales —
## `M1PatchGenerator.build_library()` publishes them to the shader, and the
## automatic tuft renderer reuses `sample()` so ground foliage sits on the tone
## it grows out of.
##
## The tone of a world position is a pure function of that position: no RNG, no
## frame time, no terrain revision and no enumeration order. A regenerated patch,
## a reloaded save and an undone edit therefore reproduce the same field.
## All values stay inside the approved meadow green family; nothing here is a
## texture, a heightmap or a replacement for the volumetric terrain.

## Ordered deep -> light. The base colour stays dominant; the other greens lift
## or deepen broad hand-painted patches rather than forming salt-and-pepper noise.
const TONES: Array[Color] = [
	Color("7aa058"), # deep shade
	Color("8aad5c"), # shade
	Color("96ba66"), # base meadow green
	Color("a8c473"), # lifted green
	Color("c3d68d"), # rare light accent
]
const SIDE_SHADE := Color("688e52")
## Coherent patch scales in metres: broad wash, mid drift, fine drift.
const SCALES: Array[float] = [6.0, 1.5, 0.5]
const WEIGHTS: Array[float] = [0.45, 0.35, 0.20]
const SALTS: Array[int] = [17, 23, 29]
## Decorative presentation cell shared with the tuft scatter (0.0625 grid).
## The tone field itself is coherent only: no per-cell salt-and-pepper term.
const FINE_CELL := 0.0625
## Family guard used by the tests: every tone and every blend of them stays here.
const FAMILY_HUE := Vector2(0.17, 0.30)
const FAMILY_SATURATION := Vector2(0.20, 0.62)
const FAMILY_VALUE := Vector2(0.50, 0.92)

## Index of the base tone: the field averages back to the approved meadow green.
static func base_index() -> float:
	return float(TONES.size()) * 0.5 - 0.5

static func span() -> float:
	return float(TONES.size() - 1)

## Deterministic 0..1 hash of an integer lattice cell. Integer identity only.
static func hash_cell(cell: Vector2i, salt: int) -> float:
	var value := posmod(cell.x, 1000003) * 92821 + posmod(cell.y, 1000003) * 68917 + salt * 2833
	value = posmod(value, 104729)
	return float(posmod(value * value * 31 + value * 17, 100003)) / 100003.0

## Smoothly interpolated value noise: lattice corners hashed, then smoothstep
## blended, so neighbouring cells share tone instead of flickering.
static func lattice(x: float, z: float, scale: float, salt: int) -> float:
	var point := Vector2(x, z) / scale
	var base := Vector2i(floori(point.x), floori(point.y))
	var fraction := Vector2(point.x - float(base.x), point.y - float(base.y))
	var blend := Vector2(fraction.x * fraction.x * (3.0 - 2.0 * fraction.x), fraction.y * fraction.y * (3.0 - 2.0 * fraction.y))
	var low := lerpf(hash_cell(base, salt), hash_cell(base + Vector2i(1, 0), salt), blend.x)
	var high := lerpf(hash_cell(base + Vector2i(0, 1), salt), hash_cell(base + Vector2i(1, 1), salt), blend.x)
	return lerpf(low, high, blend.y)

## Coherent patch index before the fine per-cell breakup.
static func tone_index(x: float, z: float) -> float:
	var deviation := 0.0
	for index in SCALES.size():
		deviation += (lattice(x, z, SCALES[index], SALTS[index]) - 0.5) * 2.0 * WEIGHTS[index]
	return clampf(base_index() + deviation * base_index(), 0.0, span())

static func full_index(x: float, z: float) -> float:
	return tone_index(x, z)

## Piecewise blend across the ordered palette: soft hand-painted patches.
static func palette_color(index: float) -> Color:
	var clamped := clampf(index, 0.0, span())
	var lower := mini(floori(clamped), TONES.size() - 2)
	return TONES[lower].lerp(TONES[lower + 1], clamped - float(lower))

static func sample(x: float, z: float) -> Color:
	return palette_color(full_index(x, z))

static func in_green_family(colour: Color) -> bool:
	return colour.h >= FAMILY_HUE.x and colour.h <= FAMILY_HUE.y \
		and colour.s >= FAMILY_SATURATION.x and colour.s <= FAMILY_SATURATION.y \
		and colour.v >= FAMILY_VALUE.x and colour.v <= FAMILY_VALUE.y

## Deterministic lattice digest, used to lock regeneration stability.
static func digest(origin: Vector2, step: float, count: int) -> String:
	var payload := PackedFloat32Array()
	for row in count:
		for column in count:
			var colour := sample(origin.x + float(column) * step, origin.y + float(row) * step)
			payload.append(colour.r)
			payload.append(colour.g)
			payload.append(colour.b)
	return payload.to_byte_array().hex_encode().sha256_text()

## Shader parameters published by M1PatchGenerator.build_library(). The shader
## declares exactly these names (asserted by tests/grass_tone_test.gd), so the
## GPU field and this model cannot drift apart without failing a check.
static func shader_uniforms() -> Dictionary:
	var parameters := {
		"tone_span": span(),
		"tone_base": base_index(),
		"tone_scales": Vector3(SCALES[0], SCALES[1], SCALES[2]),
		"tone_weights": Vector3(WEIGHTS[0], WEIGHTS[1], WEIGHTS[2]),
		"tone_side_shade": SIDE_SHADE,
	}
	for index in TONES.size():
		parameters["tone_%d" % index] = TONES[index]
	return parameters

static func shader_uniform_names() -> PackedStringArray:
	var names := PackedStringArray()
	for name: String in shader_uniforms():
		names.append(name)
	names.sort()
	return names
