extends RefCounted

const Earth = preload("res://scripts/m2_packed_earth.gd")

static func _area(polygon: Array[Vector4]) -> float:
	var area := 0.0
	for index in polygon.size():
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		area += a.x * b.y - a.y * b.x
	return absf(area) * 0.5

static func run(checker: SceneTree, scene: Node) -> void:
	# Exercise both complementary clips, including constant threshold plateaus.
	# Their areas must partition the input, not leave gaps or double-cover it.
	var conserved := true
	var finite := true
	var correct_side := true
	var cases := 0
	for seed_value in 64:
		var triangle: Array[Vector4] = []
		for vertex in 3:
			var light := float((seed_value * 17 + vertex * 29) % 101) / 100.0
			var dark := float((seed_value * 31 + vertex * 13) % 101) / 100.0
			if seed_value == 0: light = Earth.COMPACTION_THRESHOLD
			if seed_value == 1: dark = Earth.SCUFF_THRESHOLD
			triangle.append(Vector4(1.0 if vertex == 1 else 0.0, 1.0 if vertex == 2 else 0.0, light, dark))
		var scuff := Earth._clip_wear(triangle, 3, Earth.SCUFF_THRESHOLD, true)
		var rest := Earth._clip_wear(triangle, 3, Earth.SCUFF_THRESHOLD, false)
		var light := Earth._clip_wear(rest, 2, Earth.COMPACTION_THRESHOLD, true)
		var soil := Earth._clip_wear(rest, 2, Earth.COMPACTION_THRESHOLD, false)
		conserved = conserved and absf(_area(scuff) + _area(light) + _area(soil) - 0.5) < 0.000001
		for region: Array in [scuff, light, soil]:
			for point: Vector4 in region: finite = finite and point.is_finite()
		for point: Vector4 in scuff: correct_side = correct_side and point.w >= Earth.SCUFF_THRESHOLD - 0.000001
		for point: Vector4 in light: correct_side = correct_side and point.z >= Earth.COMPACTION_THRESHOLD - 0.000001 and point.w <= Earth.SCUFF_THRESHOLD + 0.000001
		for point: Vector4 in soil: correct_side = correct_side and point.z <= Earth.COMPACTION_THRESHOLD + 0.000001 and point.w <= Earth.SCUFF_THRESHOLD + 0.000001
		cases += 1
	checker._check(conserved and finite and correct_side, "soil colour cuts partition 64 triangles without gaps, overlap, NaNs or threshold duplication")

	var source: Array = [
		{"point": Vector3(2.0, 1.0, 3.0), "tangent": Vector2.RIGHT},
		{"point": Vector3(2.5, 1.0, 3.0), "tangent": Vector2.DOWN},
		{"point": Vector3(2.5, 1.0, 3.5), "tangent": Vector2.DOWN},
	]
	var saved := var_to_bytes(source)
	var samples := Earth._detail_samples(source)
	var samples_ok := samples.size() == 5 and var_to_bytes(source) == saved
	samples_ok = samples_ok and samples[0]["point"] == source[0]["point"] and samples[2]["point"] == source[1]["point"] and samples[4]["point"] == source[2]["point"]
	for index in range(1, samples.size()):
		var a: Vector3 = samples[index - 1]["point"]
		var b: Vector3 = samples[index]["point"]
		samples_ok = samples_ok and a.distance_to(b) <= Earth.FACET_ROUTE_STEP + 0.000001
	checker._check(samples_ok and is_equal_approx(float(samples.back()["distance"]), 1.0), "detail sampling preserves every bend, endpoint, distance and input record")
	checker._check(Earth._detail_samples([]).is_empty(), "empty presentation input emits no samples")

	# The shade is flat within each patch, and all pieces share the native top.
	var builder: Dictionary = scene.path_visual._new_builder()
	builder["earth"] = {"colours": [[], []]}
	var triangle: Array[Vector4] = [Vector4(0.0, 0.0, 0.0, 0.0), Vector4(1.0, 0.0, 0.0, 0.0), Vector4(0.0, 1.0, 0.0, 0.0)]
	Earth._emit_patch(builder, triangle, 2.0, Earth.SOIL_COMPACTED)
	triangle.reverse()
	Earth._emit_patch(builder, triangle, 3.0, Earth.SOIL_BASE)
	var surface: Dictionary = builder["surfaces"][0]
	var winding := true
	var indices: Array = surface["indices"]
	for index in range(0, indices.size(), 3):
		var a: Vector3 = surface["vertices"][indices[index]]
		var b: Vector3 = surface["vertices"][indices[index + 1]]
		var c: Vector3 = surface["vertices"][indices[index + 2]]
		winding = winding and (b - a).cross(c - a).dot(Vector3.UP) < 0.0 and is_equal_approx(a.y, b.y) and is_equal_approx(b.y, c.y)
	checker._check(indices.size() == 6 and winding, "colour patches preserve clockwise winding for either input order without bridging terrain heights")
	checker._check(builder["earth"]["colours"][0] == [Earth.SOIL_COMPACTED, Earth.SOIL_COMPACTED, Earth.SOIL_COMPACTED, Earth.SOIL_BASE, Earth.SOIL_BASE, Earth.SOIL_BASE], "wear colours are explicit uniform patches, not near-invisible vertex washes")
	var light_delta := Earth.SOIL_COMPACTED.r - Earth.SOIL_BASE.r
	var dark_delta := Earth.SOIL_BASE.r - Earth.SOIL_SCUFF.r
	checker._check(light_delta >= 12.0 / 255.0 and dark_delta >= 8.0 / 255.0, "soil palette keeps measurable light/dark separation for Mobile review")
	print("PACKED_EARTH_SURFACE_AUDIT " + JSON.stringify({"partition_cases": cases, "detail_spacing": Earth.FACET_ROUTE_STEP, "palette_size": 3}))
