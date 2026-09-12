extends RefCounted

## Disposable packed-earth skin. No terrain writes, offsets in saves, or frame work.
## Shared ribbon stations remove box seams; native-height rectangles split ONLY
## where terrain changes. Flat ground therefore stays cheap and visibly calm.
const Contact = preload("res://scripts/m2_path_grass_contact.gd")
const Flora = preload("res://scripts/vegetation_mesh.gd")
const State = preload("res://scripts/landscape_state.gd")
const SPACING := 0.5
const TOP_EPSILON := 0.004
const MAX_TUFTS := 64
const MAX_PER_PATH := 8
const MAX_CELLS_PER_TUFT := 4
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
		var left_core := left * _core_fraction(distance, path_id, -1)
		var right_core := right * _core_fraction(distance, path_id, 1)
		var section := PackedVector2Array()
		var end_station_distance := mini(index, samples.size() - 1 - index)
		var end_influence := 1.0 - smoothstep(0.0, 3.0, float(end_station_distance))
		for across: float in ACROSS:
			var offset := across * (left if across < 0.0 else right)
			if is_equal_approx(absf(across), 0.64): offset = -left_core if across < 0.0 else right_core
			# Taper across several stations so the route wears out gradually instead
			# of ending in one clipped section. The centreline endpoint remains exact.
			var end_shift := 0.0
			if end_influence > 0.0:
				var near_start := index <= samples.size() / 2
				var end_key := 101 if near_start else 107
				var side_key := end_key + (-3 if across < 0.0 else 5)
				var taper := 0.64 + float(Contact._seed(path_id, 0, side_key) % 9) * 0.012
				offset *= lerpf(1.0, taper, end_influence * pow(absf(across), 1.25))
				if index == 0 or index == samples.size() - 1:
					var neighbour: Vector3 = samples[1 if index == 0 else index - 1]["point"]
					var end_length := centre.distance_to(Vector2(neighbour.x, neighbour.z))
					end_shift = minf(end_length * 0.20, minf(0.12, safe_width * 0.16)) * pow(absf(across), 1.15) * (0.88 + 0.12 * across)
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
	# Broad shared wear changes the route's overall width, while a stronger
	# side-local pocket produces occasional one-sided grass incursions. The
	# fourth-power side field makes those bites localized instead of turning the
	# whole edge into a procedural sine wave.
	var broad_phase := float(Contact._seed(path_id, 0, 200) % 6283) / 1000.0
	var drift_phase := float(Contact._seed(path_id, 0, 240) % 6283) / 1000.0
	var side_phase := float(Contact._seed(path_id, 0, 223 + side) % 6283) / 1000.0
	var broad_wave := 0.5 + 0.5 * sin(distance * 0.38 + broad_phase)
	var broad_pocket := pow(broad_wave, 3.0)
	var drift_wave := 0.5 + 0.5 * sin(distance * 0.22 + drift_phase)
	var side_wave := 0.5 + 0.5 * sin(distance * 0.62 + side_phase)
	var side_pocket := pow(side_wave, 4.0)
	# Even the deepest combined bite leaves more than 83% of nominal full width
	# and never expands beyond the saved footprint.
	var inset := width * (0.004 + 0.045 * broad_pocket + 0.006 * pow(drift_wave, 2.0) + 0.028 * side_pocket)
	return width * 0.5 - inset

static func _interior_wear(path_id: int, distance: float, signed_offset: float, width: float) -> Vector2:
	# Broad localized compaction patches provide readable surface character without
	# footprints, ruts or a permanent centre stripe. Each route cell has one dusty
	# worn stretch with deterministic lateral drift and unequal shoulders.
	var half_width := maxf(width * 0.5, 0.0001)
	var across := signed_offset / half_width
	const WEAR_CELL_LENGTH := 5.2
	var cell := floori(distance / WEAR_CELL_LENGTH)
	var local := distance - float(cell) * WEAR_CELL_LENGTH
	var centre := 1.55 + float(Contact._seed(path_id, cell, 401) % 121) / 100.0
	var before_radius := 1.00 + float(Contact._seed(path_id, cell, 419) % 36) / 100.0
	var after_radius := 1.15 + float(Contact._seed(path_id, cell, 431) % 41) / 100.0
	var delta := local - centre
	var radius := before_radius if delta < 0.0 else after_radius
	var along_profile := 1.0 - smoothstep(radius * 0.16, radius, absf(delta))
	var centre_offset := (float(Contact._seed(path_id, cell, 443) % 25) - 12.0) / 100.0
	centre_offset += sin(distance * 0.23 + float(Contact._seed(path_id, 0, 449) % 6283) / 1000.0) * 0.045
	# Keep the dusty wear broad enough to survive gameplay distance, but still
	# leave quiet soil along both edges instead of turning into a full-width stripe.
	var across_profile := 1.0 - smoothstep(0.05, 0.72, absf(across - centre_offset))
	var centre_wear := along_profile * across_profile

	# A second, sparser field creates occasional broad deeper scuffs offset from
	# centre. It is deliberately wider than a footprint and never forms twin ruts.
	const PATCH_CELL_LENGTH := 7.1
	var patch_cell := floori(distance / PATCH_CELL_LENGTH)
	var patch_local := distance - float(patch_cell) * PATCH_CELL_LENGTH
	var patch_centre_distance := 2.0 + float(Contact._seed(path_id, patch_cell, 457) % 181) / 100.0
	var patch_radius := 0.72 + float(Contact._seed(path_id, patch_cell, 463) % 44) / 100.0
	var patch_along := 1.0 - smoothstep(patch_radius * 0.18, patch_radius, absf(patch_local - patch_centre_distance))
	var patch_side := -1.0 if Contact._seed(path_id, patch_cell, 467) % 2 == 0 else 1.0
	var patch_offset := patch_side * (0.10 + float(Contact._seed(path_id, patch_cell, 479) % 10) / 100.0)
	var patch_across := 1.0 - smoothstep(0.06, 0.54, absf(across - patch_offset))
	var patch_presence := 1.0 if Contact._seed(path_id, patch_cell, 487) % 4 != 0 else 0.0
	var patch_wear := patch_along * patch_across * patch_presence
	return Vector2(clampf(centre_wear, 0.0, 1.0), clampf(patch_wear, 0.0, 1.0))

static func _core_fraction(distance: float, path_id: int, side: int) -> float:
	# Broad asymmetric shoulders replace the previous short notch-like bites.
	# Each long cell belongs to one side, then the next cell alternates sides.
	# A shallow outer shoulder lasts several metres and contains a deeper centre,
	# so grass looks like it gradually reclaims the path rather than punching a dent.
	const CELL_LENGTH := 5.6
	var cell := floori(distance / CELL_LENGTH)
	var local := distance - float(cell) * CELL_LENGTH
	var path_parity := Contact._seed(path_id, 0, 311) % 2
	var bite_side := -1 if posmod(cell + path_parity, 2) == 0 else 1
	if side != bite_side:
		return 0.98

	# Centres and unequal shoulders are bounded away from the cell joins, leaving
	# a genuine near-full-width recovery stretch between successive incursions.
	var centre := 2.00 + float(Contact._seed(path_id, cell, 317) % 61) / 100.0
	var before_radius := 1.45 + float(Contact._seed(path_id, cell, 331) % 31) / 100.0
	var after_radius := 1.65 + float(Contact._seed(path_id, cell, 347) % 31) / 100.0
	var delta := local - centre
	var radius := before_radius if delta < 0.0 else after_radius
	var broad_bite := 1.0 - smoothstep(radius * 0.10, radius, absf(delta))
	var deep_radius := radius * (0.48 + float(Contact._seed(path_id, cell, 353) % 9) / 100.0)
	var deep_bite := 1.0 - smoothstep(deep_radius * 0.20, deep_radius, absf(delta))
	var broad_depth := 0.24 + float(Contact._seed(path_id, cell, 359) % 5) / 100.0
	var deep_depth := 0.36 + float(Contact._seed(path_id, cell, 367) % 5) / 100.0
	return clampf(0.98 - broad_bite * broad_depth - deep_bite * deep_depth, 0.34, 0.98)

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
	# Rectangle coalescing is render-only. It neither flattens terrain nor
	# interpolates a slope through a native terrace. The cache dies on rebuild.
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
			var quiet := sin(point.x * 0.71 + point.y * 0.39 + phase) * 0.5 + 0.5
			# The inner two bands are the actual worn-soil route. The base is muted
			# enough that dusty compacted areas read at Mobile distance without making
			# the whole path orange or producing segment-by-segment colour blocks.
			shade = Color("#9a7357").lerp(Color("#86634e"), 0.12 + quiet * 0.10 + pow(edge, 3.0) * 0.06)
			var route_distance := lerpf(float(station_a["distance"]), float(station_b["distance"]), along)
			var wear := _interior_wear(path_id, route_distance, signed_offset, float(station_a["width"]))
			# Broad compacted patches are lighter and less saturated; deeper scuffs are
			# deliberately restrained so they cannot collapse back into dark stains.
			shade = shade.lerp(Color("#bda17f"), wear.x * 0.66)
			shade = shade.lerp(Color("#7a5f4f"), wear.y * 0.16)

			# Preserve the accepted worn-out endpoint treatment without softening the
			# long-side silhouette. Only the first/last short run fades back to grass.
			var direction := (centre_b - centre_a).normalized()
			var endpoint_fade := 0.0
			if bool(station_a["first"]):
				endpoint_fade = maxf(endpoint_fade, 1.0 - smoothstep(0.0, 0.18, (point - centre_a).dot(direction)))
			if bool(station_b["last"]):
				endpoint_fade = maxf(endpoint_fade, 1.0 - smoothstep(0.0, 0.18, (centre_b - point).dot(direction)))
			shade = shade.lerp(Color("#7d9957"), endpoint_fade)
		builder["earth"]["colours"][0].append(shade)
	for index in range(0, triangles.size(), 3):
		var a := triangles[index]
		var b := triangles[index + 1]
		var c := triangles[index + 2]
		var signed_area := (polygon[b] - polygon[a]).cross(polygon[c] - polygon[a])
		if absf(signed_area) < 0.000000001: continue
		# Positive X/Z signed area is clockwise from above in Godot.
		surface["indices"].append_array([base + a, base + b, base + c] if signed_area > 0.0 else [base + a, base + c, base + b])
	builder["cells"] = int(builder["cells"]) + 1

static func _grass(renderer: Node, builder: Dictionary, stations: Array, path_id: int) -> void:
	if renderer.backend == null or stations.size() < 5: return
	var data: Dictionary = builder["earth"]
	var count := 0
	var previous_distance := -10.0
	# At most one side of a selected section; long unequal bare runs are normal.
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
			# The whole cell stays outside the calm central 60%, even at 0.25 m.
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
