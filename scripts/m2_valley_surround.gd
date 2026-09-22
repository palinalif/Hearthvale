## Valley ring: a tall mountain wall around the M2 starter valley.
##
## Hides the skybox from every reachable camera pose. The ring follows the
## world edge (radius = world_size/2) and rises monotonically from the
## terrain edge to a peak band, then slopes outward. The peak height is
## chosen to clear the camera's maximum reach (target_y + sin(max_pitch)
## * max_dist, see m2_camera_boundary.gd).
##
## Presentation goal (2026-09-22): read as a distant mountain RIDGE, not a
## uniform ominous cylinder — an irregular jagged ridge line (peaks rise
## above the 56 m floor, dips never go below it), smooth per-vertex
## normals (no flat-column stripes), and a height-based vertex-colour
## gradient (dark rock at the base fading to hazy blue-grey at the peaks,
## with slight per-peak brightness variation so peaks read individually).
##
## River corridors: at the world edges where the river flows out, the ring
## drops to water level so the valley reads as a valley with a flowing-out
## river, not a sealed box.
##
## The ring is pure presentation: no collision, no picking, no input,
## excluded from save/load and undo. Uses a plain MeshInstance3D (never a
## VoxelTerrain mesh) so it stays in scene-space and out of the native
## 32 m height bound.

class_name ValleySurround
extends MeshInstance3D

const _Gen := preload("res://scripts/m1_patch_generator.gd")

const WORLD_SIZE := 80.0
const RING_CENTER := Vector2(WORLD_SIZE * 0.5, WORLD_SIZE * 0.5)
const RING_RADIUS := WORLD_SIZE * 0.5

const PEAK_HEIGHT := 56.0
const PEAK_BAND_RADIUS := 14.0
const RIVER_WATER_LEVEL := 4.375
const OUTER_MIN_HEIGHT := 20.0
const EDGE_TERRAIN_LEVEL := 8.0
const CORRIDOR_EXTRA_WIDTH := 3.0
const _OUTER_SAMPLE_RADIUS := 30.0

const _SEGMENTS := 128

func _ready() -> void:
	pass

## Rebuild the ring mesh. Called by the scene on initial load and when
## an edit near the ring edge occurs.
func rebuild(_backend) -> void:
	_build_mesh()

## Presentation ring stats (used by tests and capture reports).
func stats() -> Dictionary:
	var vertices := 0
	if mesh != null:
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			if not arrays.is_empty() and arrays[0] is PackedVector3Array:
				vertices += arrays[0].size()
	return {"peak_height": PEAK_HEIGHT, "segments": int(_SEGMENTS), "vertices": vertices, "water_level": RIVER_WATER_LEVEL}

## True if an edit in [bounds] is close enough to the ring to warrant
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

## Maximum height of the ring wall at this world position.
## Always >= PEAK_HEIGHT so the skybox is hidden from every camera pose.
## The ridge profile is a sum of slow/medium/fast sinusoids, folded
## positive and sharpened, so the silhouette reads as a jagged mountain
## ridge (several pronounced peaks, deep passes) instead of a uniform
## cylinder. Amplitude is capped so peaks stay within a plausible range
## for the world's scale (56 m floor .. ~70 m peaks).
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

## Height of the ring wall at a radial offset beyond the world edge.
## [radius] is the distance beyond the edge: 0 = at the edge,
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

func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(0.55, 0.58, 0.62, 1.0))

	# Lit standard material with the mountain gradient carried in vertex
	# colour: dark mossy rock at the base, muted rock grey through the
	# middle, hazy blue-grey at the peaks. Smooth per-vertex normals let
	# the sun shade the ridges continuously (no flat-column stripes).
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1)
	mat.rim = 0.15
	mat.rim_tint = 0.3
	st.set_material(mat)

	const _BASE_COLOUR := Color(0.30, 0.33, 0.31)
	const _MID_COLOUR := Color(0.45, 0.47, 0.50)
	const _PEAK_COLOUR := Color(0.63, 0.66, 0.71)

	# Radial profile: edge to peak band to outer slope.
	var radial_offsets: Array[float] = []
	radial_offsets.append(0.0)
	radial_offsets.append(0.125)
	for i in 4:
		radial_offsets.append(i * (PEAK_BAND_RADIUS / 4.0))
	for i in 4:
		radial_offsets.append(PEAK_BAND_RADIUS + i * (_OUTER_SAMPLE_RADIUS - PEAK_BAND_RADIUS) / 4.0)

	# Build rings of vertices from inner to outer.
	var rings: Array = []
	for ro in radial_offsets:
		var ring: Array[Vector3] = []
		for i in _SEGMENTS:
			var ang := float(i) / float(_SEGMENTS) * TAU
			var x := RING_CENTER.x + (RING_RADIUS + ro) * cos(ang)
			var z := RING_CENTER.y + (RING_RADIUS + ro) * sin(ang)
			var h: float = ring_height(ro, Vector2(x, z))
			ring.append(Vector3(x, h, z))
		rings.append(ring)

	# Per-vertex interpolated normals (Gouraud): cross of the
	# circumferential tangent and the radial tangent at each vertex, so
	# the wall shades as one continuous curved surface. The ring is a
	# closed loop, so neighbours wrap around.
	var normals: Array = []
	for ri in rings.size():
		var row: Array[Vector3] = []
		for i in _SEGMENTS:
			var ni := (i + 1) % _SEGMENTS
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
			var outward := Vector3(p.x - RING_CENTER.x, 0.0, p.z - RING_CENTER.y).normalized()
			if n.dot(outward) < 0.0:
				n = -n
			row.append(n)
		normals.append(row)

	# Connect consecutive rings with triangles, using the per-vertex
	# normals and a height-based mountain colour gradient (with a slight
	# per-peak brightness variation so individual peaks read distinctly).
	for ri in range(rings.size() - 1):
		var inner: Array[Vector3] = rings[ri]
		var outer: Array[Vector3] = rings[ri + 1]
		for i in _SEGMENTS:
			var ni := (i + 1) % _SEGMENTS
			# Two triangles per quad, vertices added in triangle-list order
			# (v0, v1, v2, v1, v3, v2): SurfaceTool.index() in Godot 4.7
			# takes no arguments and de-dupes the vertex array into an
			# index array, so repeated vertices must be re-added.
			var quad: Array = [
				[ri, i], [ri, ni], [ri + 1, i],
				[ri, ni], [ri + 1, ni], [ri + 1, i],
			]
			for pair in quad:
				var row_idx: int = pair[0]
				var col_idx: int = pair[1]
				var p: Vector3 = rings[row_idx][col_idx]
				var elev := ridge_elevation(Vector2(p.x, p.z))
				# Normalise height across the wall's vertical extent.
				var t := clampf((p.y - EDGE_TERRAIN_LEVEL) / (PEAK_HEIGHT + 14.0 - EDGE_TERRAIN_LEVEL), 0.0, 1.0)
				var c: Color
				if t < 0.5:
					c = _BASE_COLOUR.lerp(_MID_COLOUR, t * 2.0)
				else:
					c = _MID_COLOUR.lerp(_PEAK_COLOUR, (t - 0.5) * 2.0)
				# Slight per-peak tint: taller peaks get a touch lighter.
				c = c.lerp(c.lightened(0.08), elev * 0.5)
				st.set_normal(normals[row_idx][col_idx])
				st.set_color(c)
				st.set_uv(Vector2(float(col_idx), float(row_idx)))
				st.add_vertex(p)

	# Godot 4.7 SurfaceTool: index() takes no arguments; it de-dupes the
	# triangle-list-ordered vertex array into an index array at commit.
	st.index()

	# SurfaceTool.commit() returns an ArrayMesh directly in Godot 4.
	self.mesh = st.commit()
