extends RefCounted

## Disposable packed-earth skin. No terrain writes, offsets in saves, or frame work.
## The saved route stays smooth. Its visible dirt shoulder is a continuous
## terrain-following ribbon with route-relative erosion and broad worn patches.
const Contact = preload("res://scripts/m2_path_grass_contact.gd")
const Flora = preload("res://scripts/vegetation_mesh.gd")
const State = preload("res://scripts/landscape_state.gd")
const SPACING := 0.5
const TOP_EPSILON := 0.004
const MAX_TUFTS := 64
const MAX_PER_PATH := 8
const MAX_CELLS_PER_TUFT := 4
const FACET_ROUTE_STEP := 0.5
const FACET_LATERAL_UNIT := 0.0625
const FACET_MIN_UNIT := 0.015625
const ACROSS := [-1.0, -0.64, 0.0, 0.64, 1.0]
static var _soil_material: StandardMaterial3D
static var _grass_material: StandardMaterial3D

static func append_path(renderer: Node, builder: Dictionary, width: float, values: Array, path_id: int, decorate: bool = true) -> int:
	if not builder.has("earth"):
		builder["earth"] = {"heights": {}, "colours": [[], []], "roots": [], "tufts": 0, "grass_cells": 0, "stations": [], "terrain_rects": 0}
	var data: Dictionary = builder["earth"]
	var samples: Array = renderer._sample_polyline(values)
	if samples.size() < 2: return 0
	var safe_width := clampf(width, State.PATH_MIN_WIDTH, State.PATH_MAX_WIDTH)
	var distance := 0.0
	var sections: Array = []
	var stations: Array = []
	for index in samples.size():
		var point: Vector3 = samples[index]["point"]
		var centre := Vector2(point.x, point.z)
		if index > 0:
			var previous: Vector3 = samples[index - 1]["point"]
			distance += centre.distance_to(Vector2(previous.x, previous.z))
		var tangent: Vector2 = samples[index]["tangent"]
		if index > 0 and index < samples.size() - 1:
			var incoming: Vector2 = samples[index - 1]["tangent"]
			if (incoming + tangent).length_squared() > 0.01: tangent = (incoming + tangent).normalized()
		var normal := Vector2(tangent.y, -tangent.x)
		var left := extent(safe_width, distance, path_id, -1)
		var right := extent(safe_width, distance, path_id, 1)
		var left_core := _visible_core_extent(safe_width, left, distance, path_id, -1)
		var right_core := _visible_core_extent(safe_width, right, distance, path_id, 1)
		var section := PackedVector2Array()
		var end_station_distance := mini(index, samples.size() - 1 - index)
		var end_influence := 1.0 - smoothstep(0.0, 3.5, float(end_station_distance))
		for across: float in ACROSS:
			var offset := across * (left if across < 0.0 else right)
			if is_equal_approx(absf(across), 0.64): offset = -left_core if across < 0.0 else right_core
			var end_shift := 0.0
			if end_influence > 0.0:
				var near_start := index <= samples.size() / 2
				var end_key := 101 if near_start else 107
				var side_key := end_key + (-3 if across < 0.0 else 5)
				var taper := 0.52 + float(Contact._seed(path_id, 0, side_key) % 10) * 0.014
				offset *= lerpf(1.0, taper, end_influence * pow(absf(across), 1.15))
				if index == 0 or index == samples.size() - 1:
					var neighbour: Vector3 = samples[1 if index == 0 else index - 1]["point"]
					var end_length := centre.distance_to(Vector2(neighbour.x, neighbour.z))
					end_shift = minf(end_length * 0.28, minf(0.16, safe_width * 0.20)) * pow(absf(across), 1.10) * (0.82 + 0.18 * across)
					if index != 0: end_shift = -end_shift
			section.append(centre + normal * offset + tangent * end_shift)
		sections.append(section)
		stations.append({"path_id": path_id, "index": index, "distance": distance, "centre": centre, "normal": normal, "tangent": tangent, "left": left, "right": right, "left_core": left_core, "right_core": right_core, "width": safe_width, "first": index == 0, "last": index == samples.size() - 1})
	var before := int(builder["cells"])
	for index in range(1, sections.size()):
		var a: PackedVector2Array = sections[index - 1]
		var b: PackedVector2Array = sections[index]
		for across in range(ACROSS.size() - 1):
			_ground_polygon(renderer, builder, PackedVector2Array([a[across], a[across + 1], b[across + 1], b[across]]), path_id, stations[index - 1], stations[index], across)
	data["stations"].append_array(stations)
	if decorate: _grass(renderer, builder, stations, path_id)
	return int(builder["cells"]) - before

static func extent(width: float, distance: float, path_id: int, side: int) -> float:
	var broad_phase := float(Contact._seed(path_id, 0, 200) % 6283) / 1000.0
	var drift_phase := float(Contact._seed(path_id, 0, 240) % 6283) / 1000.0
	var side_phase := float(Contact._seed(path_id, 0, 223 + side) % 6283) / 1000.0
	var broad_wave := 0.5 + 0.5 * sin(distance * 0.31 + broad_phase)
	var broad_pocket := pow(broad_wave, 3.0)
	var drift_wave := 0.5 + 0.5 * sin(distance * 0.17 + drift_phase)
	var side_wave := 0.5 + 0.5 * sin(distance * 0.53 + side_phase)
	var side_pocket := pow(side_wave, 4.0)
	var inset := width * (0.008 + 0.032 * broad_pocket + 0.008 * pow(drift_wave, 2.0) + 0.022 * side_pocket)
	return width * 0.5 - inset

static func _faceted_profile(local: float, start: float, plateau_start: float, plateau_end: float, finish: float) -> float:
	if local <= start or local >= finish: return 0.0
	if local < plateau_start:
		return clampf(inverse_lerp(start, plateau_start, local), 0.0, 1.0)
	if local <= plateau_end: return 1.0
	return clampf(1.0 - inverse_lerp(plateau_end, finish, local), 0.0, 1.0)

static func _visible_core_extent(width: float, edge_extent: float, distance: float, path_id: int, side: int) -> float:
	var stepped_distance := snappedf(distance, FACET_ROUTE_STEP)
	var fraction := _core_fraction(stepped_distance, path_id, side)
	# Preserve genuinely full tongues. Snapping a nominally full section inward
	# made every sample look eroded and also violated the render gate's contract.
	if fraction >= 0.999:
		return edge_extent
	var lateral_unit := minf(FACET_LATERAL_UNIT, maxf(FACET_MIN_UNIT, width * 0.08))
	var raw := edge_extent * fraction
	var faceted := snappedf(raw, lateral_unit)
	return clampf(faceted, width * 0.20, edge_extent)

static func _interior_wear(path_id: int, distance: float, signed_offset: float, width: float) -> Vector2:
	var half_width := maxf(width * 0.5, 0.0001)
	var sampled_distance := snappedf(distance, FACET_ROUTE_STEP)
	var across := signed_offset / half_width
	const WEAR_CELL_LENGTH := 4.8
	var cell := floori(sampled_distance / WEAR_CELL_LENGTH)
	var local := sampled_distance - float(cell) * WEAR_CELL_LENGTH
	var centre := 1.35 + float(Contact._seed(path_id, cell, 401) % 101) / 100.0
	var before_radius := 1.05 + float(Contact._seed(path_id, cell, 419) % 46) / 100.0
	var after_radius := 1.15 + float(Contact._seed(path_id, cell, 431) % 51) / 100.0
	var delta := local - centre
	var radius := before_radius if delta < 0.0 else after_radius
	var along_profile := 1.0 - smoothstep(radius * 0.18, radius, absf(delta))
	var centre_offset := (float(Contact._seed(path_id, cell, 443) % 31) - 15.0) / 100.0
	centre_offset += sin(sampled_distance * 0.21 + float(Contact._seed(path_id, 0, 449) % 6283) / 1000.0) * 0.055
	var across_profile := 1.0 - smoothstep(0.04, 0.78, absf(across - centre_offset))
	var centre_wear := along_profile * across_profile

	const PATCH_CELL_LENGTH := 6.4
	var patch_cell := floori(sampled_distance / PATCH_CELL_LENGTH)
	var patch_local := sampled_distance - float(patch_cell) * PATCH_CELL_LENGTH
	var patch_centre_distance := 1.7 + float(Contact._seed(path_id, patch_cell, 457) % 191) / 100.0
	var patch_radius := 0.78 + float(Contact._seed(path_id, patch_cell, 463) % 51) / 100.0
	var patch_along := 1.0 - smoothstep(patch_radius * 0.18, patch_radius, absf(patch_local - patch_centre_distance))
	var patch_side := -1.0 if Contact._seed(path_id, patch_cell, 467) % 2 == 0 else 1.0
	var patch_offset := patch_side * (0.12 + float(Contact._seed(path_id, patch_cell, 479) % 14) / 100.0)
	var patch_across := 1.0 - smoothstep(0.05, 0.58, absf(across - patch_offset))
	var patch_presence := 1.0 if Contact._seed(path_id, patch_cell, 487) % 5 < 3 else 0.0
	var patch_wear := patch_along * patch_across * patch_presence
	return Vector2(clampf(centre_wear, 0.0, 1.0), clampf(patch_wear, 0.0, 1.0))

static func _core_fraction(distance: float, path_id: int, side: int) -> float:
	# Irregular boundary erosion remains sparse and asymmetric, but each route
	# cell contains calm near-full shoulder around a bounded incursion. This keeps
	# the edge from becoming a continuously inset ribbon while avoiding the old
	# deterministic left/right zig-zag.
	const CELL_LENGTH := 4.4
	var cell := floori(distance / CELL_LENGTH)
	var local := distance - float(cell) * CELL_LENGTH
	var dominant_side := -1 if Contact._seed(path_id, cell, 311) % 5 < 3 else 1
	var has_primary := cell == 0 or Contact._seed(path_id, cell, 313) % 5 != 0
	var plateau_start := 1.20 + float(Contact._seed(path_id, cell, 317) % 76) / 100.0
	var plateau_length := 0.46 + float(Contact._seed(path_id, cell, 331) % 61) / 100.0
	var approach := 0.62 + float(Contact._seed(path_id, cell, 347) % 51) / 100.0
	var release := 0.72 + float(Contact._seed(path_id, cell, 353) % 61) / 100.0
	# Give the first cell an explicit full -> bite -> full cadence. The route is
	# sampled in 0.5 m steps, so this guarantees an early visible incursion with
	# undamaged tongues on both sides of it instead of depending on seed luck.
	if cell == 0:
		plateau_start = 0.95
		plateau_length = 0.65
		approach = 0.30
		release = 0.65
	var plateau_end := plateau_start + plateau_length
	var start := plateau_start - approach
	var finish := plateau_end + release

	if side == dominant_side and has_primary:
		var bite := _faceted_profile(local, start, plateau_start, plateau_end, finish)
		var depth := 0.20 + float(Contact._seed(path_id, cell, 359) % 9) / 100.0
		return clampf(1.0 - bite * depth, 0.70, 1.0)

	# The opposite side usually stays calm. Occasional shallower incursions are
	# offset along the route so the two edges do not mirror each other.
	if Contact._seed(path_id, cell, 373 + side) % 4 != 0: return 1.0
	var shift_sign := -1.0 if Contact._seed(path_id, cell, 379 + side) % 2 == 0 else 1.0
	var shift := 0.34 + float(Contact._seed(path_id, cell, 383 + side) % 36) / 100.0
	var companion_start := clampf(plateau_start + shift_sign * shift, 0.95, CELL_LENGTH - 1.55)
	var companion_length := 0.34 + float(Contact._seed(path_id, cell, 389 + side) % 31) / 100.0
	var companion_approach := 0.48 + float(Contact._seed(path_id, cell, 397 + side) % 31) / 100.0
	var companion_release := 0.54 + float(Contact._seed(path_id, cell, 409 + side) % 36) / 100.0
	var companion := _faceted_profile(local, companion_start - companion_approach, companion_start, companion_start + companion_length, companion_start + companion_length + companion_release)
	var companion_depth := 0.055 + float(Contact._seed(path_id, cell, 421 + side) % 5) * 0.012
	return clampf(1.0 - companion * companion_depth, 0.90, 1.0)

static func _height(renderer: Node, data: Dictionary, cell: Vector2i, scale_value: float) -> float:
	var heights: Dictionary = data["heights"]
	if not heights.has(cell): heights[cell] = renderer._surface_height((Vector2(cell) + Vector2.ONE * 0.5) * scale_value)
	return float(heights[cell])

static func _ground_polygon(renderer: Node, builder: Dictionary, polygon: PackedVector2Array, path_id: int, station_a: Dictionary, station_b: Dictionary, band: int) -> void:
	var data: Dictionary = builder["earth"]
	var scale_value := 0.125
	if renderer.backend != null: scale_value = maxf(0.001, float(renderer.backend.get("voxel_scale")))
	var low := polygon[0]
	var high := polygon[0]
	for point: Vector2 in polygon:
		low = low.min(point); high = high.max(point)
	var limit := Vector2i(ceili(48.0 / scale_value), ceili(48.0 / scale_value))
	if renderer.backend != null:
		var patch: Vector3i = renderer.backend.get("patch_size")
		limit = Vector2i(patch.x, patch.z)
	var lo := Vector2i(maxi(0, floori(low.x / scale_value)), maxi(0, floori(low.y / scale_value)))
	var hi := Vector2i(mini(limit.x, ceili(high.x / scale_value)), mini(limit.y, ceili(high.y / scale_value)))
	var used := {}
	for z in range(lo.y, hi.y):
		for x in range(lo.x, hi.x):
			var cell := Vector2i(x, z)
			if used.has(cell): continue
			var height := _height(renderer, data, cell, scale_value)
			var end_x := x + 1
			while end_x < hi.x and not used.has(Vector2i(end_x, z)) and is_equal_approx(_height(renderer, data, Vector2i(end_x, z), scale_value), height): end_x += 1
			var end_z := z + 1
			while end_z < hi.y:
				var same := true
				for test_x in range(x, end_x):
					if used.has(Vector2i(test_x, end_z)) or not is_equal_approx(_height(renderer, data, Vector2i(test_x, end_z), scale_value), height):
						same = false
						break
				if not same: break
				end_z += 1
			for fill_z in range(z, end_z):
				for fill_x in range(x, end_x): used[Vector2i(fill_x, fill_z)] = true
			var rect := PackedVector2Array([Vector2(x, z), Vector2(end_x, z), Vector2(end_x, end_z), Vector2(x, end_z)])
			for index in rect.size(): rect[index] *= scale_value
			for clipped: PackedVector2Array in Geometry2D.intersect_polygons(polygon, rect):
				_emit_soil(builder, clipped, height, path_id, station_a, station_b, band)
			data["terrain_rects"] = int(data["terrain_rects"]) + 1

static func _emit_soil(builder: Dictionary, polygon: PackedVector2Array, height: float, path_id: int, station_a: Dictionary, station_b: Dictionary, band: int) -> void:
	var triangles := Geometry2D.triangulate_polygon(polygon)
	if triangles.is_empty(): return
	var surface: Dictionary = builder["surfaces"][0]
	var base: int = surface["vertices"].size()
	var centre_a: Vector2 = station_a["centre"]
	var centre_b: Vector2 = station_b["centre"]
	for point: Vector2 in polygon:
		surface["vertices"].append(Vector3(point.x, height + TOP_EPSILON, point.y))
		surface["normals"].append(Vector3.UP)
		var closest := Geometry2D.get_closest_point_to_segment(point, centre_a, centre_b)
		var segment := centre_b - centre_a
		var along := clampf((closest - centre_a).dot(segment) / maxf(segment.length_squared(), 0.0000001), 0.0, 1.0)
		var normal: Vector2 = station_a["normal"]
		var signed_offset := (point - closest).dot(normal)
		var edge := clampf(absf(signed_offset) / (float(station_a["width"]) * 0.5), 0.0, 1.0)
		var outer_band := band == 0 or band == ACROSS.size() - 2
		var shade := Color("#7d9957")
		if not outer_band:
			var phase := float(Contact._seed(path_id, 0, 31) % 6283) / 1000.0
			var quiet := sin(point.x * 0.66 + point.y * 0.43 + phase) * 0.5 + 0.5
			# A quiet base still dominates, but the wear must survive normal gameplay
			# distance. Broad route-relative patches avoid checkerboard cell noise.
			shade = Color("#916b52").lerp(Color("#866149"), 0.08 + quiet * 0.10 + pow(edge, 3.0) * 0.06)
			var route_distance := lerpf(float(station_a["distance"]), float(station_b["distance"]), along)
			var wear := _interior_wear(path_id, route_distance, signed_offset, float(station_a["width"]))
			shade = shade.lerp(Color("#ad8567"), wear.x * 0.42)
			shade = shade.lerp(Color("#76533f"), wear.y * 0.18)
		builder["earth"]["colours"][0].append(shade)
	for index in range(0, triangles.size(), 3):
		var a := triangles[index]
		var b := triangles[index + 1]
		var c := triangles[index + 2]
		var signed_area := (polygon[b] - polygon[a]).cross(polygon[c] - polygon[a])
		if absf(signed_area) < 0.000000001: continue
		surface["indices"].append_array([base + a, base + b, base + c] if signed_area > 0.0 else [base + a, base + c, base + b])
	builder["cells"] = int(builder["cells"]) + 1

static func _grass(renderer: Node, builder: Dictionary, stations: Array, path_id: int) -> void:
	if renderer.backend == null or stations.size() < 5: return
	var data: Dictionary = builder["earth"]
	var count := 0
	var previous_distance := -10.0
	for index in range(2, stations.size() - 2):
		if count >= MAX_PER_PATH or int(data["tufts"]) >= MAX_TUFTS: break
		var station: Dictionary = stations[index]
		var distance := float(station["distance"])
		var seed_value := Contact._seed(path_id, floori(distance / SPACING), 61)
		if seed_value % 7 > 1 or distance - previous_distance < 1.15: continue
		var side := -1.0 if seed_value % 2 == 0 else 1.0
		var centre: Vector2 = station["centre"]
		var normal: Vector2 = station["normal"]
		var tangent: Vector2 = station["tangent"]
		var edge_extent := float(station["left"] if side < 0 else station["right"])
		var contact := centre + normal * side * (edge_extent - Contact.UNIT * 0.12)
		var first := Vector2i(floori(contact.x / Contact.UNIT), floori(contact.y / Contact.UNIT))
		var step := Vector2i(1 if tangent.x > 0 else -1, 0) if absf(tangent.x) > absf(tangent.y) else Vector2i(0, 1 if tangent.y > 0 else -1)
		var roots: Array[Vector3] = []
		for cell: Vector2i in [first, first + step]:
			var point := (Vector2(cell) + Vector2.ONE * 0.5) * Contact.UNIT
			if point.x < Contact.UNIT or point.y < Contact.UNIT or point.x > 48.0 - Contact.UNIT or point.y > 48.0 - Contact.UNIT: break
			var across := (point - centre).dot(normal) * side
			if across - Contact.UNIT * 0.71 < float(station["width"]) * 0.30: break
			var height: float = renderer._surface_height(point)
			var valid := true
			for corner: Vector2 in [Vector2(-0.49, -0.49), Vector2(0.49, -0.49), Vector2(0.49, 0.49), Vector2(-0.49, 0.49)]:
				if not is_equal_approx(float(renderer._surface_height(point + corner * Contact.UNIT)), height): valid = false
			if not valid: break
			roots.append(Vector3(point.x, height, point.y))
		if roots.size() != 2: continue
		for column in 2:
			var levels := (3 if seed_value % 5 == 0 else 2) if column == 0 else 1
			for level in levels:
				renderer._append_box(builder, roots[column] + Vector3.UP * (float(level) + 0.5) * Contact.UNIT, Vector3.ONE * Contact.UNIT, Basis.IDENTITY, 1)
				var shade: Color = Flora.COLORS[0].lerp(Flora.COLORS[2], 0.18 if seed_value % 3 == 0 else 0.0)
				for vertex in 24: data["colours"][1].append(shade)
				data["grass_cells"] = int(data["grass_cells"]) + 1
		data["roots"].append_array(roots)
		data["tufts"] = int(data["tufts"]) + 1
		count += 1
		previous_distance = distance

static func mesh_from_builder(builder: Dictionary) -> ArrayMesh:
	if not builder.has("earth"): return null
	var mesh := ArrayMesh.new()
	for index in 2:
		var surface: Dictionary = builder["surfaces"][index]
		if (surface["indices"] as Array).is_empty(): continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(surface["vertices"])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(surface["normals"])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(surface["indices"])
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray(builder["earth"]["colours"][index])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if _soil_material == null:
			_soil_material = StandardMaterial3D.new()
			_soil_material.vertex_color_use_as_albedo = true
			_soil_material.vertex_color_is_srgb = true
			_soil_material.roughness = 1.0
			_soil_material.metallic_specular = 0.0
		if _grass_material == null: _grass_material = _soil_material.duplicate() as StandardMaterial3D
		mesh.surface_set_material(mesh.get_surface_count() - 1, _soil_material if index == 0 else _grass_material)
	return mesh if mesh.get_surface_count() > 0 else null

static func stats(builder: Dictionary) -> Dictionary:
	var data: Dictionary = builder.get("earth", {})
	var vertices := 0
	var triangles := 0
	for surface: Dictionary in builder["surfaces"]:
		vertices += (surface["vertices"] as Array).size()
		triangles += (surface["indices"] as Array).size() / 3
	return {"vertices": vertices, "triangles": triangles, "tufts": data.get("tufts", 0), "grass_cells": data.get("grass_cells", 0), "terrain_columns": (data.get("heights", {}) as Dictionary).size(), "terrain_rects": data.get("terrain_rects", 0)}
