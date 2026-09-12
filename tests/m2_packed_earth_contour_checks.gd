extends RefCounted

const Earth = preload("res://scripts/m2_packed_earth.gd")

static func _area(polygon: Array[Vector4]) -> float:
	var result := 0.0
	if polygon.size() < 3: return result
	var a := Vector2(polygon[0].x, polygon[0].y)
	for index in range(1, polygon.size() - 1):
		var b := Vector2(polygon[index].x, polygon[index].y)
		var c := Vector2(polygon[index + 1].x, polygon[index + 1].y)
		result += absf((b - a).cross(c - a)) * 0.5
	return result

static func run(checker: SceneTree, scene: Node) -> void:
	var document := JSON.stringify(scene.landscape_state.document())
	var rng := RandomNumberGenerator.new()
	rng.seed = 719521
	var partitions_ok := true
	var fields_ok := true
	var emissions_ok := true
	# Exhaust all below/on/above combinations for both fields at three vertices,
	# then exercise non-quantized intersections. No random global state is used.
	for sample in 857:
		var triangle: Array[Vector4] = [Vector4(0, 0, 0, 0), Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0)]
		var code := sample
		for vertex in 3:
			for component in [2, 3]:
				var threshold: float = Earth.WORN_THRESHOLD if component == 2 else Earth.SCUFF_THRESHOLD
				triangle[vertex][component] = [0.0, threshold, 1.0][code % 3] if sample < 729 else rng.randf()
				code = floori(float(code) / 3.0)
		var unscuffed := Earth._clip_wear(triangle, 3, Earth.SCUFF_THRESHOLD, false)
		var scuff := Earth._clip_wear(triangle, 3, Earth.SCUFF_THRESHOLD, true)
		var worn := Earth._clip_wear(unscuffed, 2, Earth.WORN_THRESHOLD, true)
		var base := Earth._clip_wear(unscuffed, 2, Earth.WORN_THRESHOLD, false)
		partitions_ok = partitions_ok and absf(_area(scuff) + _area(worn) + _area(base) - 0.5) < 0.00001
		for point: Vector4 in scuff:
			fields_ok = fields_ok and point.w >= Earth.SCUFF_THRESHOLD - 0.00001
		for point: Vector4 in worn:
			fields_ok = fields_ok and point.w <= Earth.SCUFF_THRESHOLD + 0.00001 and point.z >= Earth.WORN_THRESHOLD - 0.00001
		for point: Vector4 in base:
			fields_ok = fields_ok and point.w <= Earth.SCUFF_THRESHOLD + 0.00001 and point.z <= Earth.WORN_THRESHOLD + 0.00001
		var builder: Dictionary = scene.path_visual._new_builder()
		builder["earth"] = {"colours": [[], []]}
		Earth._emit_patch(builder, scuff, 8.0, Earth.SOIL_SCUFF)
		Earth._emit_patch(builder, worn, 8.0, Earth.SOIL_WORN)
		Earth._emit_patch(builder, base, 8.0, Earth.SOIL_BASE)
		var surface: Dictionary = builder["surfaces"][0]
		var vertices: Array = surface["vertices"]
		var indices: Array = surface["indices"]
		var colours: Array = builder["earth"]["colours"][0]
		emissions_ok = emissions_ok and vertices.size() == colours.size() and indices.size() <= 21
		var emitted_area := 0.0
		for index in range(0, indices.size(), 3):
			var a: Vector3 = vertices[indices[index]]
			var b: Vector3 = vertices[indices[index + 1]]
			var c: Vector3 = vertices[indices[index + 2]]
			var winding := (b - a).cross(c - a).y
			emitted_area += absf(winding) * 0.5
			emissions_ok = emissions_ok and winding < 0.0 and is_equal_approx(a.y, 8.0 + Earth.TOP_EPSILON) and is_equal_approx(b.y, a.y) and is_equal_approx(c.y, a.y)
			emissions_ok = emissions_ok and colours[indices[index]] == colours[indices[index + 1]] and colours[indices[index]] == colours[indices[index + 2]]
		emissions_ok = emissions_ok and absf(emitted_area - 0.5) < 0.00001
	checker._check(partitions_ok and fields_ok, "857 wear partitions cover their source triangle without holes or overlapping colour regions, including exact threshold cases")
	checker._check(emissions_ok, "contour triangles retain flat colours, clockwise winding, grounded height and at most seven triangles per input triangle")
	checker._check(Earth.SOIL_WORN.g - Earth.SOIL_BASE.g > 10.0 / 255.0 and Earth.SOIL_BASE.r - Earth.SOIL_SCUFF.r > 8.0 / 255.0, "soil palette has readable wear/scuff separation rather than near-zero blends")
	for width: float in [0.25, 0.75, 3.0]:
		var builder: Dictionary = scene.path_visual._new_builder()
		Earth.append_path(scene.path_visual, builder, width, [[7.0, 14.0], [31.0, 14.0]], 719, false)
		var surface: Dictionary = builder["surfaces"][0]
		var vertices: Array = surface["vertices"]
		var indices: Array = surface["indices"]
		var colours: Array = builder["earth"]["colours"][0]
		var areas := {Earth.SOIL_BASE: 0.0, Earth.SOIL_WORN: 0.0, Earth.SOIL_SCUFF: 0.0}
		for index in range(0, indices.size(), 3):
			var a: Vector3 = vertices[indices[index]]
			var b: Vector3 = vertices[indices[index + 1]]
			var c: Vector3 = vertices[indices[index + 2]]
			var colour: Color = colours[indices[index]]
			areas[colour] = float(areas[colour]) + (b - a).cross(c - a).length() * 0.5
		var total: float = areas[Earth.SOIL_BASE] + areas[Earth.SOIL_WORN] + areas[Earth.SOIL_SCUFF]
		checker._check(total > 0.0 and areas[Earth.SOIL_BASE] / total > 0.55 and areas[Earth.SOIL_WORN] > 0.0 and areas[Earth.SOIL_SCUFF] > 0.0, "actual soil mesh has a dominant quiet base plus visible wear and scuffs at width " + str(width))
		var stations: Array = builder["earth"]["stations"]
		for station: Dictionary in [stations.front(), stations.back()]:
			var visible_width: float = station["left_core"] + station["right_core"]
			checker._check(visible_width > width * 0.25 and visible_width < width * 0.68, "end taper is applied to the rendered boundary, not the invisible envelope: " + str(width))
	checker._check(JSON.stringify(scene.landscape_state.document()) == document, "contour checks leave the full authored document unchanged")
