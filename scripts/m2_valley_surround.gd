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

	# Simple unshaded material so vertex color shows through.
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1)
	mat.rim = 0.15
	mat.rim_tint = 0.3
	st.set_material(mat)

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
	# For each quad (inner[i], inner[ni], outer[ni], outer[i]) emit two triangles
	# with face normals computed from the quad cross product.
	for ri in range(rings.size() - 1):
		var inner: Array[Vector3] = rings[ri]
		var outer: Array[Vector3] = rings[ri + 1]
		for i in _SEGMENTS:
			var ni := (i + 1) % _SEGMENTS
			var v0 := inner[i]
			var v1 := inner[ni]
			var v2 := outer[ni]
			var v3 := outer[i]
			# Face normal: cross of two edges of the quad
			var n := (v1 - v0).cross(v2 - v0).normalized()
			if n.y < 0.0:
				n = -n  # ensure normals face outward (away from center)
			var uv0 := Vector2(float(i), float(ri))
			var uv1 := Vector2(float(ni), float(ri))
			var uv2 := Vector2(float(ni), float(ri + 1))
			var uv3 := Vector2(float(i), float(ri + 1))
			st.set_normal(n); st.set_uv(uv0); st.add_vertex(v0)
			st.set_normal(n); st.set_uv(uv1); st.add_vertex(v1)
			st.set_normal(n); st.set_uv(uv2); st.add_vertex(v2)
			st.set_normal(n); st.set_uv(uv1); st.add_vertex(v1)
			st.set_normal(n); st.set_uv(uv2); st.add_vertex(v2)
			st.set_normal(n); st.set_uv(uv3); st.add_vertex(v3)

	# SurfaceTool.commit() returns an ArrayMesh directly in Godot 4.
	self.mesh = st.commit()
