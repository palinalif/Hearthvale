## Valley surround: a layered distant MOUNTAIN RANGE around the M2 starter
## valley, not a wall.
##
## The terrain only extends to 40 m, so the world boundary is built in three
## presentation layers plus a flat plain:
##
##   * DistantPlain — a flat unshaded meadow annulus (36 → 260 m) just below
##     the terrain-edge level, so the mountains sit on ground and fade into
##     haze instead of floating in sky.
##   * InnerRidge — the original jagged ridge, pushed out to 120 m (was 40 m).
##     Peak band 56–70 m (floor 56 must stay above the camera's max reach of
##     ~49.1 m, see tests/valley_ring_occlusion_test.gd). Carries the subtle
##     rock detail: low-frequency radial wobble and vertex-colour mottling
##     with darker scree patches.
##   * MidRidge — 170 m, peaks 95–120 m, deep-blue atmospheric layers.
##   * FarRidge — 225 m, peaks 135–170 m, lighter deep-blue atmospheric
##     layers (farther ridge stays lighter for atmospheric depth).
##
## Each ridge is a smooth-normal cylinder (per-vertex Gouraud normals, no
## faceting) whose TOP ridgeline is jagged by multi-frequency value noise;
## the sides stay clean smooth slopes. Each ridge uses a different noise
## seed/profile so the silhouettes never align — the parallax between layers
## is what makes it read as a mountain range rather than concentric rings.
##
## River corridors: at the world edges where the river flows out, the inner
## ridge drops to water level so the valley reads as a valley with a
## flowing-out river, not a sealed box.
##
## Pure presentation: no collision, no picking, no input, excluded from
## save/load and undo. The root is a plain MeshInstance3D (the inner ridge,
## never a VoxelTerrain mesh) so it stays in scene-space and out of the
## native 32 m height bound; the plain and the two far ridges are child
## MeshInstance3D nodes with unshaded/basic materials.

class_name ValleySurround
extends MeshInstance3D

const _Gen := preload("res://scripts/m1_patch_generator.gd")

const WORLD_SIZE := 80.0
const RING_CENTER := Vector2(WORLD_SIZE * 0.5, WORLD_SIZE * 0.5)

## Ring radii. The inner ridge sits ~3x beyond the terrain edge so the
## boundary reads as a distant range; the two far ridges sit behind it.
const INNER_RADIUS := 120.0
const RING_RADIUS := INNER_RADIUS
const MID_RADIUS := 170.0
const FAR_RADIUS := 225.0

## Inner ridge profile (unchanged from the wall-era design: the 56 m peak
## floor is a hard contract against the ~49.1 m max camera reach).
const PEAK_HEIGHT := 56.0
const PEAK_BAND_RADIUS := 14.0
const RIVER_WATER_LEVEL := 4.375
const OUTER_MIN_HEIGHT := 20.0
const EDGE_TERRAIN_LEVEL := 8.0
const CORRIDOR_EXTRA_WIDTH := 3.0
const _OUTER_SAMPLE_RADIUS := 30.0

## Distant plain: flat meadow from just under the terrain edge out past the
## far ridges, sitting 0.1 m below the terrain edge so terrain never floats
## above it.
const PLAIN_INNER_RADIUS := 36.0
const PLAIN_OUTER_RADIUS := 260.0
const PLAIN_LEVEL := 7.9

const _SEGMENTS := 128
const _MID_SEGMENTS := 192
const _FAR_SEGMENTS := 160

var _plain: MeshInstance3D
var _mid_ridge: MeshInstance3D
var _far_ridge: MeshInstance3D

func _ready() -> void:
	_plain = MeshInstance3D.new()
	_plain.name = "DistantPlain"
	_mid_ridge = MeshInstance3D.new()
	_mid_ridge.name = "MidRidge"
	_far_ridge = MeshInstance3D.new()
	_far_ridge.name = "FarRidge"
	add_child(_plain)
	add_child(_mid_ridge)
	add_child(_far_ridge)

## Rebuild all presentation layers. Called by the scene on initial load and
## when an edit near the ring edge occurs.
func rebuild(_backend) -> void:
	_build_all()

func _build_all() -> void:
	mesh = _build_inner_ridge()
	_plain.mesh = _build_plain()
	_mid_ridge.mesh = _build_ridge(
		MID_RADIUS, _MID_SEGMENTS, 18.0, 22.0,
		95.0, 25.0, 30.0,
		Color("#4c5d70"), Color("#62748a"), Color("#778da0"),
		2.3, [3, 7, 13],
		0.0, 0.0
	)
	_far_ridge.mesh = _build_ridge(
		FAR_RADIUS, _FAR_SEGMENTS, 24.0, 28.0,
		135.0, 35.0, 35.0,
		Color("#606e7f"), Color("#768598"), Color("#90a2b2"),
		5.9, [5, 9, 17],
		0.0, 0.0
	)

## Presentation ring stats (used by tests and capture reports).
func stats() -> Dictionary:
	var vertices := 0
	if mesh != null:
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			if not arrays.is_empty() and arrays[0] is PackedVector3Array:
				vertices += arrays[0].size()
	return {
		"peak_height": PEAK_HEIGHT,
		"segments": int(_SEGMENTS),
		"vertices": vertices,
		"water_level": RIVER_WATER_LEVEL,
		"inner_radius": INNER_RADIUS,
		"mid_radius": MID_RADIUS,
		"far_radius": FAR_RADIUS,
	}

## True if an edit in [bounds] is close enough to the world edge to warrant
## a rebuild (the ring itself is static, but the terrain edge may shift
## under a sculpt near the border).
func affected_by(bounds: AABB) -> bool:
	if bounds.size == Vector3.ZERO:
		return false
	var c := bounds.get_center()
	var r := bounds.size * 0.5
	var margin := 8.0
	return (
		c.x - r.x < margin
		or c.x + r.x > WORLD_SIZE - margin
		or c.z - r.z < margin
		or c.z + r.z > WORLD_SIZE - margin
	)

## Maximum height of the inner ridge at this bearing.
## Always >= PEAK_HEIGHT (56 m), which clears the camera's maximum reach
## (target_y + sin(max_pitch) * max_dist ≈ 49.1 m, see
## tests/valley_ring_occlusion_test.gd). The ridge profile is a sum of
## slow/medium/fast sinusoids, folded positive and sharpened, so the
## silhouette reads as a jagged mountain ridge (several pronounced peaks,
## deep passes) instead of a uniform cylinder.
func peak_height(xz: Vector2) -> float:
	var ang := _bearing(xz)
	var raw := sin(ang * 2.0 + 0.7) * 0.45 + sin(ang * 5.0 + 2.1) * 0.35 + sin(ang * 9.0 + 4.4) * 0.2
	var sharpened := pow(maxf(raw, 0.0), 1.6)
	return PEAK_HEIGHT + 14.0 * sharpened

## Normalised ridge height at a bearing (0 at the floor, 1 at the tallest
## peak). Used to drive the vertex-colour gradient and per-peak tint.
func ridge_elevation(xz: Vector2) -> float:
	var ang := _bearing(xz)
	var raw := sin(ang * 2.0 + 0.7) * 0.45 + sin(ang * 5.0 + 2.1) * 0.35 + sin(ang * 9.0 + 4.4) * 0.2
	return pow(maxf(raw, 0.0), 1.6)

## Height of the inner ridge wall at a radial offset beyond the ring.
## [radius] is the distance beyond the ring: 0 = at the ring,
## PEAK_BAND_RADIUS = peak band, _OUTER_SAMPLE_RADIUS = outer wall.
## Returns water level in river corridors.
func ring_height(radius: float, xz: Vector2) -> float:
	if _in_river_corridor(xz):
		return RIVER_WATER_LEVEL
	if radius <= PEAK_BAND_RADIUS:
		var t := radius / PEAK_BAND_RADIUS
		return lerpf(EDGE_TERRAIN_LEVEL, PEAK_HEIGHT, smoothstep(0.0, 1.0, t))
	var t := clampf(
		(radius - PEAK_BAND_RADIUS) / (_OUTER_SAMPLE_RADIUS - PEAK_BAND_RADIUS),
		0.0,
		1.0
	)
	return lerpf(PEAK_HEIGHT, OUTER_MIN_HEIGHT, t)

func _in_river_corridor(xz: Vector2) -> bool:
	var river_x: float = _Gen.river_center_x(xz.y)
	var river_w: float = _Gen.river_half_width(xz.y)
	return absf(xz.x - river_x) < river_w + CORRIDOR_EXTRA_WIDTH

func _bearing(xz: Vector2) -> float:
	return atan2(xz.y - RING_CENTER.y, xz.x - RING_CENTER.x)

## Multi-frequency 1-D value noise around the circumference. [u] is the
## normalised angle 0..1, [freqs] are integer feature counts per lap (so
## the pattern wraps seamlessly) and [seed] selects a fixed pseudo-random
## phase per lattice point. The result is folded positive and sharpened so
## the silhouette reads as a jagged ridgeline with several pronounced
## peaks and deep passes.
func _ridge_noise(u: float, seed: float, freqs: Array) -> float:
	var v := _value_noise(u, int(freqs[0]), seed) * 0.5 \
		+ _value_noise(u, int(freqs[1]), seed) * 0.3 \
		+ _value_noise(u, int(freqs[2]), seed) * 0.2
	return pow(clampf(v, 0.0, 1.0), 1.6)

func _value_noise(u: float, freq: int, seed: float) -> float:
	var scaled := fmod(u, 1.0) * float(freq)
	var i := int(floorf(scaled))
	var f := scaled - float(i)
	var a := _hash(float(i % freq), seed)
	var b := _hash(float((i + 1) % freq), seed)
	return lerpf(a, b, f * f * (3.0 - 2.0 * f))

func _hash(i: float, seed: float) -> float:
	var r := fmod(sin(i * 127.1 + seed * 311.7) * 43758.5453, 1.0)
	return r if r >= 0.0 else r + 1.0

## Inner ridge: the original profile (56–70 m jagged peaks, river corridors,
## outer slope to 20 m) at the pushed-out 120 m radius, plus the rock detail
## layer: a low-frequency ±0.5 m radial wobble (normals are recomputed from
## the displaced positions so the surface stays smooth) and vertex-colour
## mottling — grey-green rock tones with a few darker scree patches.
func _build_inner_ridge() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Lit standard material carrying the mountain gradient in vertex colour:
	# dark mossy rock at the base, muted rock grey through the middle, hazy
	# blue-grey at the peaks. Smooth per-vertex normals let the sun shade the
	# ridges continuously (no flat-column stripes).
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1)
	mat.rim = 0.15
	mat.rim_tint = 0.3
	st.set_material(mat)

	const _BASE_COLOUR := Color("#405262")
	const _MID_COLOUR := Color("#4e5f70")
	const _PEAK_COLOUR := Color("#5f7489")
	const _ROCK_COLOUR := Color(0.48, 0.50, 0.46)
	const _SCREE_COLOUR := Color(0.22, 0.24, 0.23)
	const _JITTER_SEED := 9.4

	var radial_offsets := _ring_offsets(PEAK_BAND_RADIUS, _OUTER_SAMPLE_RADIUS)
	var rings: Array = []
	for ro in radial_offsets:
		var ring: Array[Vector3] = []
		for i in _SEGMENTS:
			var ang := float(i) / float(_SEGMENTS) * TAU
			var x := RING_CENTER.x + (RING_RADIUS + ro) * cos(ang)
			var z := RING_CENTER.y + (RING_RADIUS + ro) * sin(ang)
			var p := Vector2(x, z)
			var h: float = ring_height(ro, p)
			if ro == PEAK_BAND_RADIUS:
				# Jagged ridgeline on the top row only; the outer slope
				# descends from it.
				h = peak_height(p)
			# Low-frequency radial wobble: ±0.5 m so the wall silhouette
			# stops reading as a perfect circle from any vantage.
			var wobble := (_value_noise(ang / TAU, 3, _JITTER_SEED) * 0.6
				+ _value_noise(ang / TAU, 7, _JITTER_SEED) * 0.4) - 0.5
			ring.append(Vector3(x + wobble * cos(ang), h, z + wobble * sin(ang)))
		rings.append(ring)

	var normals := _smooth_normals(rings, RING_CENTER)

	for ri in range(rings.size() - 1):
		for i in _SEGMENTS:
			var ni := (i + 1) % _SEGMENTS
			var quad: Array = [
				[ri, i], [ri, ni], [ri + 1, i],
				[ri, ni], [ri + 1, ni], [ri + 1, i],
			]
			for pair in quad:
				var p: Vector3 = rings[pair[0]][pair[1]]
				var elev := ridge_elevation(Vector2(p.x, p.z))
				var t := clampf((p.y - EDGE_TERRAIN_LEVEL) / (PEAK_HEIGHT + 14.0 - EDGE_TERRAIN_LEVEL), 0.0, 1.0)
				var c: Color
				if t < 0.5:
					c = _BASE_COLOUR.lerp(_MID_COLOUR, t * 2.0)
				else:
					c = _MID_COLOUR.lerp(_PEAK_COLOUR, (t - 0.5) * 2.0)
				# Slight per-peak tint: taller peaks get a touch lighter.
				c = c.lerp(c.lightened(0.08), elev * 0.5)
				# Rock mottling: low-frequency grey-green rock tone, and a
				# sparser darker scree pattern on the upper wall.
				var mottle := _value_noise(_bearing(Vector2(p.x, p.z)) / TAU, 5, 6.1)
				c = c.lerp(_ROCK_COLOUR, mottle * 0.30)
				var scree := _value_noise(_bearing(Vector2(p.x, p.z)) / TAU, 9, 8.3)
				c = c.lerp(_SCREE_COLOUR, clampf((scree - 0.55) / 0.45, 0.0, 1.0) * 0.35 * t)
				st.set_normal(normals[pair[0]][pair[1]])
				st.set_color(c)
				st.set_uv(Vector2(float(pair[1]), float(pair[0])))
				st.add_vertex(p)

	st.index()
	return st.commit()

## A generic smooth-normal ridge ring for the two distant layers: flat plain
## base up a clean smooth slope to a jagged top ridgeline, then a broad
## descent. [seed]/[freqs] differ per ring so the silhouettes never align.
func _build_ridge(
	radius: float, segments: int, band: float, outer_extend: float,
	peak_floor: float, peak_amp: float, outer_min: float,
	base_color: Color, mid_color: Color, peak_color: Color,
	seed: float, freqs: Array,
	_radial_jitter: float, _mottle: float
) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1)
	st.set_material(mat)

	var radial_offsets := _ring_offsets(band, outer_extend)
	var rings: Array = []
	for ro in radial_offsets:
		var ring: Array[Vector3] = []
		for i in segments:
			var ang := float(i) / float(segments) * TAU
			var x := RING_CENTER.x + (radius + ro) * cos(ang)
			var z := RING_CENTER.y + (radius + ro) * sin(ang)
			var h := _layer_height(ro, band, outer_extend, PLAIN_LEVEL,
				peak_floor + peak_amp * _ridge_noise(ang / TAU, seed, freqs), outer_min)
			ring.append(Vector3(x, h, z))
		rings.append(ring)

	var normals := _smooth_normals(rings, RING_CENTER)

	for ri in range(rings.size() - 1):
		for i in segments:
			var ni := (i + 1) % segments
			var quad: Array = [
				[ri, i], [ri, ni], [ri + 1, i],
				[ri, ni], [ri + 1, ni], [ri + 1, i],
			]
			for pair in quad:
				var p: Vector3 = rings[pair[0]][pair[1]]
				# Height-based gradient across the layer's vertical extent;
				# the farthest layers fade toward their hazy peak tone so
				# they read as distance, not mass.
				var t := clampf((p.y - PLAIN_LEVEL) / (peak_floor + peak_amp - PLAIN_LEVEL), 0.0, 1.0)
				var c: Color
				if t < 0.5:
					c = base_color.lerp(mid_color, t * 2.0)
				else:
					c = mid_color.lerp(peak_color, (t - 0.5) * 2.0)
				st.set_normal(normals[pair[0]][pair[1]])
				st.set_color(c)
				st.set_uv(Vector2(float(pair[1]), float(pair[0])))
				st.add_vertex(p)

	st.index()
	return st.commit()

func _ring_offsets(band: float, outer: float) -> Array[float]:
	var offsets: Array[float] = [0.0, 0.125]
	for i in 4:
		offsets.append(band * (i + 1) / 4.0)
	for i in 4:
		offsets.append(band + outer * (i + 1) / 4.0)
	return offsets

## Smooth profile for a layered ridge: plain base, eased rise to the (already
## jagged) peak, linear broad descent to [outer_min].
func _layer_height(ro: float, band: float, outer: float, base: float, peak: float, outer_min: float) -> float:
	if ro <= band:
		return lerpf(base, peak, smoothstep(0.0, 1.0, ro / band))
	var t := clampf((ro - band) / outer, 0.0, 1.0)
	return lerpf(peak, outer_min, t)

## Flat unshaded meadow annulus from just under the terrain edge out past
## the far ridges. Slight low-frequency tone mottling plus a haze fade
## toward the outer edge so the plain reads as farmland dissolving into the
## valley haze.
func _build_plain() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	st.set_material(mat)

	const _MEADOW := Color(0.60, 0.68, 0.30)
	const _MEADOW_DRY := Color(0.66, 0.70, 0.36)
	const _HAZE := Color(0.56, 0.63, 0.34)
	const _STEPS := 10

	var rings: Array = []
	for s in _STEPS:
		var ring: Array[Vector3] = []
		var r := lerpf(PLAIN_INNER_RADIUS, PLAIN_OUTER_RADIUS, float(s) / float(_STEPS - 1))
		for i in _SEGMENTS:
			var ang := float(i) / float(_SEGMENTS) * TAU
			ring.append(Vector3(
				RING_CENTER.x + r * cos(ang),
				PLAIN_LEVEL,
				RING_CENTER.y + r * sin(ang)
			))
		rings.append(ring)

	var up := Vector3.UP
	for ri in range(rings.size() - 1):
		for i in _SEGMENTS:
			var ni := (i + 1) % _SEGMENTS
			var quad: Array = [
				[ri, i], [ri, ni], [ri + 1, i],
				[ri, ni], [ri + 1, ni], [ri + 1, i],
			]
			for pair in quad:
				var p: Vector3 = rings[pair[0]][pair[1]]
				var mottle := _value_noise(_bearing(Vector2(p.x, p.z)) / TAU, 5, 4.7) \
					* _value_noise(_bearing(Vector2(p.x, p.z)) / TAU, 11, 7.2)
				var c := _MEADOW.lerp(_MEADOW_DRY, mottle)
				# Fade the outer third into the valley haze.
				var r := (p - Vector3(RING_CENTER.x, 0.0, RING_CENTER.y)).length()
				var fade := clampf((r - PLAIN_INNER_RADIUS * 1.5) / (PLAIN_OUTER_RADIUS - PLAIN_INNER_RADIUS * 1.5), 0.0, 1.0)
				c = c.lerp(_HAZE, fade * 0.30)
				st.set_normal(up)
				st.set_color(c)
				st.set_uv(Vector2(float(pair[1]), float(pair[0])))
				st.add_vertex(p)

	st.index()
	return st.commit()

## Per-vertex interpolated normals (Gouraud): cross of the circumferential
## tangent and the radial tangent at each vertex, so each ring shades as one
## continuous curved surface. The ring is a closed loop, so neighbours wrap
## around. Works for displaced (wobbled) positions too — the normal is
## always computed from the final vertex positions.
func _smooth_normals(rings: Array, center: Vector2) -> Array:
	var normals: Array = []
	for ri in rings.size():
		var segments := (rings[ri] as Array).size()
		var row: Array[Vector3] = []
		for i in segments:
			var ni := (i + 1) % segments
			var p: Vector3 = rings[ri][i]
			var ring_below: int = ri - 1 if ri > 0 else 0
			var ring_above: int = ri + 1 if ri < rings.size() - 1 else rings.size() - 1
			var tangent_r: Vector3
			if ring_above == ring_below:
				tangent_r = ((rings[ring_below][i] as Vector3) - p).normalized()
			else:
				var above: Vector3 = rings[ring_above][i]
				var below: Vector3 = rings[ring_below][i]
				tangent_r = (above - below).normalized()
			var tangent_c: Vector3 = ((rings[ri][ni] as Vector3) - p).normalized()
			var n: Vector3 = tangent_c.cross(tangent_r).normalized()
			# Outward = away from the ring centre in the horizontal plane.
			var outward := Vector3(p.x - center.x, 0.0, p.z - center.y).normalized()
			if n.dot(outward) < 0.0:
				n = -n
			row.append(n)
		normals.append(row)
	return normals
