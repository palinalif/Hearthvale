## Valley ring: a tall mountain wall around the M2 starter valley.
##
## Hides the skybox from every reachable camera pose. The ring follows the
## world edge (radius = world_size/2) and rises monotonically from the
## terrain edge to a peak band, then slopes outward. The peak height is
## chosen to clear the camera's maximum reach (target_y + sin(max_pitch)
## * max_dist, see m2_camera_boundary.gd).
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
func peak_height(xz: Vector2) -> float:
	var ang := _bearing(xz)
	var variation := maxf(0.0, sin(ang * 3.0) * 0.5 + sin(ang * 7.0 + 1.0) * 0.3)
	return PEAK_HEIGHT + variation

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

	# Radial profile: edge to peak band to outer slope.
	var radial_offsets: Array[float] = []
	radial_offsets.append(0.0)
	radial_offsets.append(0.125)
	for i in 1:
		radial_offsets.append(i * (PEAK_BAND_RADIUS / 4.0))
	for i in 1:
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

	# Connect consecutive rings with triangle strips.
	for ri in range(rings.size() - 1):
		var inner: Array[Vector3] = rings[ri]
		var outer: Array[Vector3] = rings[ri + 1]
		for i in _SEGMENTS:
			var ni := (i + 1) % _SEGMENTS
			var base := ri * _SEGMENTS + i
			st.add_vertex(inner[i])
			st.add_vertex(inner[ni])
			st.add_vertex(outer[i])
			st.add_vertex(inner[ni])
			st.add_vertex(outer[ni])
			st.add_vertex(outer[i])

	var m := ArrayMesh.new()
	m.add_surface(st.commit())
	self.mesh = m
