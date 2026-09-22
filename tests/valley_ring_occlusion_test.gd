extends SceneTree
## Validate real terrain and mesh positions, including the outlet at the crest.
const Surround = preload("res://scripts/m2_valley_surround.gd")
const Gen = preload("res://scripts/m1_patch_generator.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)
func _initialize() -> void:
	var ring := Surround.new()
	var low := INF
	var high := -INF
	for i in 128:
		var angle := TAU * float(i) / 128.0
		var direction := Vector2(cos(angle), sin(angle))
		var p := Gen.VALLEY_CENTER + direction * 78.0
		var crest_point := Gen.VALLEY_CENTER + direction * (ring.INNER_RADIUS + ring.PEAK_BAND_RADIUS)
		var crest: float = ring.peak_height(crest_point)
		low = minf(low, crest)
		high = maxf(high, crest)
		if absf(p.x - Gen.river_center_x(p.y)) > 12.0 and not Rect2(20,16,48,40).has_point(p):
			check(Gen.terrain_height(p.x,p.y) > 16.0, "foothills enclose each bearing")
		check(Gen.terrain_height(p.x,p.y) < 32.0, "native terrain remains below its height cap")
	check(high - low > 15.0, "mountain crest has distinct peaks and passes")
	check(high > 80.0 and high < 145.0, "mountains are substantial without a sky-sealing dome")
	var outlet := (Vector2(Gen.river_center_x(0.0),0.0) - Gen.VALLEY_CENTER).normalized()
	for offset in [0.0, ring.PEAK_BAND_RADIUS, 70.0]:
		var p: Vector2 = Gen.VALLEY_CENTER + outlet * (ring.INNER_RADIUS + offset)
		check(ring.ring_height(offset,p) <= 5.0, "downstream passage remains open including the crest")
	check(ring.ring_height(ring.PEAK_BAND_RADIUS, Vector2(80,200)) > 50.0, "northern mountain backs the reservoir")
	var mesh: Mesh = ring._build_inner_ridge()
	var arrays: Array = mesh.surface_get_arrays(0)
	for normal: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
		check(normal.y >= -0.001 and normal.is_finite(), "mountain slopes face sky for lighting")
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i+1]]
		var c := vertices[indices[i+2]]
		check((b-a).cross(c-a).y <= 0.001, "clockwise triangles show slopes from above")
	check(ring.PLAIN_LEVEL < 5.0, "surround ground cannot cover river water")
	# Across all scenery layers, bound the static cost and validate both sides
	# of the closed loop. Relief must neither puncture the toe nor lift the outlet.
	ring._ready()
	ring._build_all()
	var triangles := 0
	for layer: Mesh in [ring.mesh, ring._mid_ridge.mesh, ring._far_ridge.mesh]:
		var data: Array = layer.surface_get_arrays(0)
		var points: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
		var faces: PackedInt32Array = data[Mesh.ARRAY_INDEX]
		triangles += faces.size() / 3
		for point in points:
			check(point.is_finite(), "all mountain layers have finite positions")
		for j in range(0, faces.size(), 3):
			check((points[faces[j+1]] - points[faces[j]]).cross(points[faces[j+2]] - points[faces[j]]).y <= 0.001, "distant and near faces retain clockwise winding")
	check(triangles < 32000, "all three static mountain layers stay below 32k triangles")
	var strongest_relief := 0.0
	for i in 128:
		var u := float(i) / 128.0
		check(is_equal_approx(ring._slope_relief(0.0, u, 7.7, 18.0), 0.0), "detail meets native foothills without lifting the seam")
		for t in [0.25, 0.5, 0.75, 1.25]:
			var relief: float = ring._slope_relief(t, u, 7.7, 18.0)
			strongest_relief = maxf(strongest_relief, absf(relief))
			check(is_equal_approx(relief, ring._slope_relief(t, u - 1.0, 7.7, 18.0)), "erosion wraps seamlessly across positive and negative bearings")
	check(strongest_relief > 6.0 and strongest_relief < 24.0, "relief is visible at valley scale but remains bounded")
	print("Mountain triangles: %d" % triangles)
	var shoulder: Array = ring._voxel_apron.mesh.surface_get_arrays(0)
	var shoulder_points: PackedVector3Array = shoulder[Mesh.ARRAY_VERTEX]
	var shoulder_normals: PackedVector3Array = shoulder[Mesh.ARRAY_NORMAL]
	var shoulder_indices: PackedInt32Array = shoulder[Mesh.ARRAY_INDEX]
	check(shoulder_indices.size() > 0 and shoulder_indices.size()/3 < 300000, "voxel shoulder has bounded exposed geometry")
	for point in shoulder_points:
		check(point.is_equal_approx(point.snapped(Vector3.ONE * Gen.VOXEL_SCALE)), "shoulder stays on native 0.125 grid")
		check(point.y > 5.0, "voxel shoulder stays out of the river outlet")
	for j in range(0, shoulder_indices.size(), 3):
		var a := shoulder_points[shoulder_indices[j]]
		var b := shoulder_points[shoulder_indices[j+1]]
		var c := shoulder_points[shoulder_indices[j+2]]
		check((b-a).cross(c-a).dot(shoulder_normals[shoulder_indices[j]]) < 0.0, "voxel tops and risers face outwards")
	var mountain_material := ring.mesh.surface_get_material(0) as ShaderMaterial
	var meadow_material = Gen.grass_material()
	for parameter in ["tone_0", "tone_1", "tone_2", "tone_3", "tone_4", "tone_side_shade"]:
		check(mountain_material.get_shader_parameter(parameter) == meadow_material.get_shader_parameter(parameter), "mountains reuse the native terrain palette")
	check(ring.Apron.shade(80).v < ring.Apron.shade(25).v, "mountains darken gradually above the voxel foothills")
	print("Voxel shoulder triangles: %d" % (shoulder_indices.size()/3))
	ring.free()
	print("valley_ring_occlusion_test checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
