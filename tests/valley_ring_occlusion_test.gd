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
	ring.free()
	print("valley_ring_occlusion_test checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
