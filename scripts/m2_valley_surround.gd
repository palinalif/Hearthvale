## Layered mountain scenery follows the rounded native foothills. The nearest
## range overlaps the native boundary, concealing the square storage footprint.
## Its northern spur backs the editable reservoir; only the downstream valley
## has an outlet. Scenery remains derived, with no save or collision authority.

class_name ValleySurround
extends MeshInstance3D

const _Gen := preload("res://scripts/m1_patch_generator.gd")

const WORLD_SIZE := 160.0
const RING_CENTER := Vector2(WORLD_SIZE * 0.5, WORLD_SIZE * 0.5)

## Broad, irregular foothills rise into distinct overlapping silhouettes.
const INNER_RADIUS := 78.0
const RING_RADIUS := INNER_RADIUS
const MID_RADIUS := 156.0
const FAR_RADIUS := 250.0
const PEAK_PASS := 42.0
const PEAK_MAX := 158.0
const _INNER_RIDGE_SEED := 7.7
const _INNER_RIDGE_FREQS: Array = [7, 13, 23]
const PEAK_BAND_RADIUS := 38.0
const RIVER_WATER_LEVEL := 5.0
const OUTER_MIN_HEIGHT := 24.0
const EDGE_TERRAIN_LEVEL := 22.0
const _OUTER_SAMPLE_RADIUS := 76.0
const PLAIN_INNER_RADIUS := 76.0
const PLAIN_OUTER_RADIUS := 410.0
# Below the river and native surface; never a green lid over the outlet.
const PLAIN_LEVEL := -1.0

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
		MID_RADIUS, _MID_SEGMENTS, 36.0, 44.0,
		82.0, 62.0, 30.0,
		Color("#4c5d70"), Color("#62748a"), Color("#778da0"),
		2.3, [3, 7, 13],
		0.0, 0.0
	)
	_far_ridge.mesh = _build_ridge(
		FAR_RADIUS, _FAR_SEGMENTS, 48.0, 56.0,
		114.0, 76.0, 40.0,
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
		"peak_min": PEAK_PASS,
		"peak_max": PEAK_MAX,
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

## Irregular skyline height at a bearing.
func peak_height(xz: Vector2) -> float:
	var u := fposmod(_bearing(xz), TAU) / TAU
	var n := _ridge_noise(u, _INNER_RIDGE_SEED, _INNER_RIDGE_FREQS)
	return PEAK_PASS + (PEAK_MAX - PEAK_PASS) * n

## Normalised ridge height at a bearing (0 at the lowest pass, 1 at the
## tallest peak). Drives the vertex-colour gradient and per-peak tint.
func ridge_elevation(xz: Vector2) -> float:
	var u := fposmod(_bearing(xz), TAU) / TAU
	return _ridge_noise(u, _INNER_RIDGE_SEED, _INNER_RIDGE_FREQS)

## Height of the inner ridge wall at a radial offset beyond the ring.
## [radius] is the distance beyond the ring: 0 = at the ring,
## PEAK_BAND_RADIUS = crest band, _OUTER_SAMPLE_RADIUS = outer wall. The
## wall rises to the jagged crest (peak_height) at the band and descends
## from it, so the whole wall follows the irregular ridgeline. Returns
## water level in river corridors.
func ring_height(radius: float, xz: Vector2) -> float:
	var crest := peak_height(xz)
	var edge := _Gen.terrain_height(clampf(xz.x, 0.0, WORLD_SIZE - 0.125), clampf(xz.y, 0.0, WORLD_SIZE - 0.125)) - 0.25
	var height := _layer_height(radius, PEAK_BAND_RADIUS, _OUTER_SAMPLE_RADIUS - PEAK_BAND_RADIUS, edge, crest, OUTER_MIN_HEIGHT)
	return lerpf(RIVER_WATER_LEVEL - 0.25, height, _outlet_weight(xz))

func _outlet_weight(xz: Vector2) -> float:
	var exit_dir := Vector2(_Gen.river_center_x(0.0), 0.0) - RING_CENTER
	var direction := xz - RING_CENTER
	var angle := absf(wrapf(direction.angle() - exit_dir.angle(), -PI, PI))
	return smoothstep(0.045, 0.15, angle)

func _in_river_corridor(xz: Vector2) -> bool:
	return _outlet_weight(xz) < 0.01

func _bearing(xz: Vector2) -> float:
	return atan2(xz.y - RING_CENTER.y, xz.x - RING_CENTER.x)

## Multi-frequency 1-D value noise around the circumference. [u] is the
## normalised angle 0..1, [freqs] are integer feature counts per lap (so
## the pattern wraps seamlessly) and [seed] selects a fixed pseudo-random
## phase per lattice point. The result is folded positive and sharpened so
## the silhouette reads as a jagged ridgeline with several pronounced
## peaks and deep passes.
func _ridge_noise(u: float, seed: float, freqs: Array) -> float:
	var v := _crest_noise(u, int(freqs[0]), seed) * 0.5 \
		+ _crest_noise(u, int(freqs[1]), seed) * 0.3 \
		+ _crest_noise(u, int(freqs[2]), seed) * 0.2
	return pow(clampf(v, 0.0, 1.0), 1.6)

# Linear crest interpolation preserves angular summits instead of rounding
# every peak into a smooth, evenly scalloped caldera rim.
func _crest_noise(u: float, freq: int, seed: float) -> float:
	var scaled := fposmod(u, 1.0) * float(freq)
	var i := floori(scaled)
	return lerpf(_hash(float(i % freq), seed), _hash(float((i + 1) % freq), seed), scaled - float(i))

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

## The near range follows the native edge, then rises to a broken crest.
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
			# Low-frequency radial wobble: ±1 m (2x) so the wall silhouette
			# stops reading as a perfect circle from any vantage.
			var wobble := 12.0 * (_value_noise(ang / TAU, 3, _JITTER_SEED) * 0.6
				+ _value_noise(ang / TAU, 7, _JITTER_SEED) * 0.4) - 6.0
			var displaced := Vector2(x + wobble * cos(ang), z + wobble * sin(ang))
			h = ring_height(ro, displaced)
			ring.append(Vector3(displaced.x, h, displaced.y))
		rings.append(ring)

	var normals := _smooth_normals(rings, RING_CENTER)

	for ri in range(rings.size() - 1):
		for i in _SEGMENTS:
			var ni := (i + 1) % _SEGMENTS
			var quad: Array = [
				[ri, i], [ri + 1, i], [ri, ni],
				[ri, ni], [ri + 1, i], [ri + 1, ni],
			]
			for pair in quad:
				var p: Vector3 = rings[pair[0]][pair[1]]
				var elev := ridge_elevation(Vector2(p.x, p.z))
				var t := clampf((p.y - EDGE_TERRAIN_LEVEL) / (PEAK_MAX - EDGE_TERRAIN_LEVEL), 0.0, 1.0)
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
			h = lerpf(RIVER_WATER_LEVEL - 0.25, h, _outlet_weight(Vector2(x, z)))
			ring.append(Vector3(x, h, z))
		rings.append(ring)

	var normals := _smooth_normals(rings, RING_CENTER)

	for ri in range(rings.size() - 1):
		for i in segments:
			var ni := (i + 1) % segments
			var quad: Array = [
				[ri, i], [ri + 1, i], [ri, ni],
				[ri, ni], [ri + 1, i], [ri + 1, ni],
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
				[ri, i], [ri + 1, i], [ri, ni],
				[ri, ni], [ri + 1, i], [ri + 1, ni],
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
func _smooth_normals(rings: Array, _center: Vector2) -> Array:
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
			# Both sides face the sky. Flipping toward radial-outward makes
			# the valley-facing slopes point down and shade incorrectly.
			if n.y < 0.0:
				n = -n
			row.append(n)
		normals.append(row)
	return normals
