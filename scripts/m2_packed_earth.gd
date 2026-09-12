extends RefCounted

## Disposable packed-earth skin. No terrain writes, offsets in saves, or frame work.
## Visible soil is rasterized onto the native X/Z voxel grid; the saved route
## remains smooth authority while the exposed wear reads as part of the terrain.
const Contact = preload("res://scripts/m2_path_grass_contact.gd")
const Flora = preload("res://scripts/vegetation_mesh.gd")
const State = preload("res://scripts/landscape_state.gd")
const SPACING := 0.5
const TOP_EPSILON := 0.004
const MAX_TUFTS := 64
const MAX_PER_PATH := 8
const MAX_CELLS_PER_TUFT := 4
const VISIBLE_ROUTE_STEP := 0.5
const VISIBLE_EDGE_UNIT := 0.125
const MIN_VISIBLE_EDGE_UNIT := 0.03125
const WEAR_LEVEL_STEP := 0.25
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
		stations.append({"path_id": path_id, "index": index, "distance": distance, "centre": centre, "normal": normal, "tangent": tangent, "left": left, "right": right, "left_core": left_core, "right_core": right_core, "width": safe_width, "first": index == 0, "last": index == samples.size() - 1})
	var before := int(builder["cells"])
	_raster_soil(renderer, builder, stations, values, safe_width, path_id)
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

static func _visible_core_extent(width: float, edge_extent: float, distance: float, path_id: int, side: int) -> float:
	# Broad shoulder ownership stays deterministic, but visible cell selection
	# below is what makes the final edge genuinely voxel-stepped in world space.
	var phase := float(Contact._seed(path_id, 0, 503 + side) % 3) * 0.125
	var stepped_distance := floorf((distance + phase) / VISIBLE_ROUTE_STEP) * VISIBLE_ROUTE_STEP
	var lateral_step := minf(VISIBLE_EDGE_UNIT, maxf(MIN_VISIBLE_EDGE_UNIT, width * 0.10))
	var raw := edge_extent * _core_fraction(stepped_distance, path_id, side)
	var stepped := snappedf(raw, lateral_step)
	var minimum := width * 0.19
	var maximum := floorf((edge_extent - lateral_step * 0.25) / lateral_step) * lateral_step
	maximum = maxf(minimum, maximum)
	return clampf(stepped, minimum, maximum)

static func _interior_wear(path_id: int, distance: float, signed_offset: float, width: float) -> Vector2:
	# Broad localized compaction patches remain route-scale rather than footprint
	# marks, but both their sampling and strength are quantized. Raster emission
	# assigns one colour per merged cell block, so these no longer airbrush across
	# the path surface.
	var half_width := maxf(width * 0.5, 0.0001)
	var stepped_distance := snappedf(distance, VISIBLE_ROUTE_STEP)
	var lateral_step := minf(VISIBLE_EDGE_UNIT, maxf(MIN_VISIBLE_EDGE_UNIT, width * 0.10))
	var stepped_offset := snappedf(signed_offset, lateral_step)
	var across := stepped_offset / half_width
	const WEAR_CELL_LENGTH := 5.2
	var cell := floori(stepped_distance / WEAR_CELL_LENGTH)
	var local := stepped_distance - float(cell) * WEAR_CELL_LENGTH
	var centre := 1.55 + float(Contact._seed(path_id, cell, 401) % 121) / 100.0
	var before_radius := 1.00 + float(Contact._seed(path_id, cell, 419) % 36) / 100.0
	var after_radius := 1.15 + float(Contact._seed(path_id, cell, 431) % 41) / 100.0
	var delta := local - centre
	var radius := before_radius if delta < 0.0 else after_radius
	var along_profile := 1.0 - smoothstep(radius * 0.16, radius, absf(delta))
	var centre_offset := (float(Contact._seed(path_id, cell, 443) % 25) - 12.0) / 100.0
	centre_offset += sin(stepped_distance * 0.23 + float(Contact._seed(path_id, 0, 449) % 6283) / 1000.0) * 0.045
	var across_profile := 1.0 - smoothstep(0.05, 0.72, absf(across - centre_offset))
	var centre_wear := along_profile * across_profile

	const PATCH_CELL_LENGTH := 7.1
	var patch_cell := floori(stepped_distance / PATCH_CELL_LENGTH)
	var patch_local := stepped_distance - float(patch_cell) * PATCH_CELL_LENGTH
	var patch_centre_distance := 2.0 + float(Contact._seed(path_id, patch_cell, 457) % 181) / 100.0
	var patch_radius := 0.72 + float(Contact._seed(path_id, patch_cell, 463) % 44) / 100.0
	var patch_along := 1.0 - smoothstep(patch_radius * 0.18, patch_radius, absf(patch_local - patch_centre_distance))
	var patch_side := -1.0 if Contact._seed(path_id, patch_cell, 467) % 2 == 0 else 1.0
	var patch_offset := patch_side * (0.10 + float(Contact._seed(path_id, patch_cell, 479) % 10) / 100.0)
	var patch_across := 1.0 - smoothstep(0.06, 0.54, absf(across - patch_offset))
	var patch_presence := 1.0 if Contact._seed(path_id, patch_cell, 487) % 4 != 0 else 0.0
	var patch_wear := patch_along * patch_across * patch_presence
	centre_wear = snappedf(clampf(centre_wear, 0.0, 1.0), WEAR_LEVEL_STEP)
	patch_wear = snappedf(clampf(patch_wear, 0.0, 1.0), WEAR_LEVEL_STEP)
	return Vector2(clampf(centre_wear, 0.0, 1.0), clampf(patch_wear, 0.0, 1.0))

static func _core_fraction(distance: float, path_id: int, side: int) -> float:
	# Broad reclaimed shoulders happen often enough to break long ruler-straight
	# runs, but each cell still returns almost to nominal width before the next.
	# The dominant side alternates; the opposite side receives only a shallow,
	# offset companion shoulder so the pair never becomes symmetric scalloping.
	const CELL_LENGTH := 4.4
	var cell := floori(distance / CELL_LENGTH)
	var local := distance - float(cell) * CELL_LENGTH
	var path_parity := Contact._seed(path_id, 0, 311) % 2
	var bite_side := -1 if posmod(cell + path_parity, 2) == 0 else 1
	var centre := 1.45 + float(Contact._seed(path_id, cell, 317) % 66) / 100.0
	var before_radius := 1.15 + float(Contact._seed(path_id, cell, 331) % 26) / 100.0
	var after_radius := 1.30 + float(Contact._seed(path_id, cell, 347) % 31) / 100.0
	var delta := local - centre
	var radius := before_radius if delta < 0.0 else after_radius

	if side != bite_side:
		var shift_sign := -1.0 if Contact._seed(path_id, cell, 373) % 2 == 0 else 1.0
		var shift := 0.25 + float(Contact._seed(path_id, cell, 379) % 21) / 100.0
		var companion_centre := clampf(centre + shift_sign * shift, 1.25, CELL_LENGTH - 1.25)
		var companion_radius := 0.80 + float(Contact._seed(path_id, cell, 383) % 26) / 100.0
		var companion := 1.0 - smoothstep(companion_radius * 0.12, companion_radius, absf(local - companion_centre))
		var companion_depth := 0.03 + float(Contact._seed(path_id, cell, 389) % 4) * 0.01
		return clampf(0.995 - companion * companion_depth, 0.93, 0.995)

	var broad_bite := 1.0 - smoothstep(radius * 0.10, radius, absf(delta))
	var deep_radius := radius * (0.46 + float(Contact._seed(path_id, cell, 353) % 9) / 100.0)
	var deep_bite := 1.0 - smoothstep(deep_radius * 0.20, deep_radius, absf(delta))
	var broad_depth := 0.22 + float(Contact._seed(path_id, cell, 359) % 5) / 100.0
	var deep_depth := 0.34 + float(Contact._seed(path_id, cell, 367) % 5) / 100.0
	return clampf(0.995 - broad_bite * broad_depth - deep_bite * deep_depth, 0.38, 0.995)

static func _raster_scale(renderer: Node, width: float) -> float:
	var native_scale := VISIBLE_EDGE_UNIT
	if renderer.backend != null: native_scale = maxf(MIN_VISIBLE_EDGE_UNIT, float(renderer.backend.get("voxel_scale")))
	# Very narrow legal paths need sub-cells so their corners can remain inside
	# the saved half-width. Normal gameplay widths use the true native 0.125 m grid.
	var requested := maxf(MIN_VISIBLE_EDGE_UNIT, snappedf(width * 0.25, MIN_VISIBLE_EDGE_UNIT))
	return minf(native_scale, requested)

static func _raster_soil(renderer: Node, builder: Dictionary, stations: Array, values: Array, width: float, path_id: int) -> void:
	if stations.size() < 2: return
	var data: Dictionary = builder["earth"]
	var scale_value := _raster_scale(renderer, width)
	var world_size := Vector2(48.0, 48.0)
	if renderer.backend != null:
		var patch: Vector3i = renderer.backend.get("patch_size")
		var native_scale := float(renderer.backend.get("voxel_scale"))
		world_size = Vector2(float(patch.x) * native_scale, float(patch.z) * native_scale)
	var limit := Vector2i(floori(world_size.x / scale_value), floori(world_size.y / scale_value))
	var candidates := {}
	var half_width := width * 0.5

	# Gather only cells near each sampled route segment. This keeps rebuild cost
	# proportional to path area rather than scanning the whole 48 m patch.
	for index in range(1, stations.size()):
		var a: Vector2 = stations[index - 1]["centre"]
		var b: Vector2 = stations[index]["centre"]
		var segment := b - a
		var length_squared := segment.length_squared()
		if length_squared < 0.0000001: continue
		var tangent := segment.normalized()
		var normal := Vector2(tangent.y, -tangent.x)
		var low := a.min(b) - Vector2.ONE * (half_width + scale_value)
		var high := a.max(b) + Vector2.ONE * (half_width + scale_value)
		var lo := Vector2i(maxi(0, floori(low.x / scale_value)), maxi(0, floori(low.y / scale_value)))
		var hi := Vector2i(mini(limit.x, ceili(high.x / scale_value)), mini(limit.y, ceili(high.y / scale_value)))
		for z in range(lo.y, hi.y):
			for x in range(lo.x, hi.x):
				var key := Vector2i(x, z)
				var centre := (Vector2(key) + Vector2.ONE * 0.5) * scale_value
				var raw_amount := (centre - a).dot(segment) / length_squared
				var amount := clampf(raw_amount, 0.0, 1.0)
				var closest := a + segment * amount
				var distance_squared := centre.distance_squared_to(closest)
				if distance_squared > pow(half_width + scale_value * 0.75, 2.0): continue
				if candidates.has(key) and float((candidates[key] as Dictionary)["distance_squared"]) <= distance_squared: continue
				var route_distance := lerpf(float(stations[index - 1]["distance"]), float(stations[index]["distance"]), amount)
				candidates[key] = {"distance_squared": distance_squared, "route_distance": route_distance, "signed_offset": (centre - closest).dot(normal), "segment_index": index, "raw_amount": raw_amount}

	var selected := {}
	var total_distance := float(stations.back()["distance"])
	var min_cell := Vector2i(2147483647, 2147483647)
	var max_cell := Vector2i(-2147483647, -2147483647)
	for key_value in candidates:
		var key: Vector2i = key_value
		var candidate: Dictionary = candidates[key]
		var route_distance := float(candidate["route_distance"])
		var signed_offset := float(candidate["signed_offset"])
		var side := -1 if signed_offset < 0.0 else 1
		var edge_extent := extent(width, route_distance, path_id, side)
		var core_extent := _visible_core_extent(width, edge_extent, route_distance, path_id, side)
		# Preserve the accepted worn-out endpoints using a grid-native narrowing
		# rather than a soft alpha/colour fade.
		var end_distance := minf(route_distance, maxf(0.0, total_distance - route_distance))
		var end_factor := lerpf(0.48, 1.0, smoothstep(0.0, 1.25, end_distance))
		core_extent *= end_factor
		if absf(signed_offset) > core_extent + scale_value * 0.18: continue
		if not _cell_inside_saved_footprint(key, scale_value, values, half_width): continue
		var height := _raster_height(renderer, data, key, scale_value)
		var shade_class := _soil_shade_class(path_id, route_distance, signed_offset, width)
		selected[key] = {"height": height, "shade": shade_class}
		min_cell = Vector2i(mini(min_cell.x, key.x), mini(min_cell.y, key.y))
		max_cell = Vector2i(maxi(max_cell.x, key.x), maxi(max_cell.y, key.y))

	if selected.is_empty(): return
	var used := {}
	for z in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			var cell := Vector2i(x, z)
			if used.has(cell) or not selected.has(cell): continue
			var info: Dictionary = selected[cell]
			var height := float(info["height"])
			var shade_class := int(info["shade"])
			var end_x := x + 1
			while end_x <= max_cell.x and _same_raster_cell(selected, used, Vector2i(end_x, z), height, shade_class): end_x += 1
			var end_z := z + 1
			while end_z <= max_cell.y:
				var same := true
				for test_x in range(x, end_x):
					if not _same_raster_cell(selected, used, Vector2i(test_x, end_z), height, shade_class):
						same = false
						break
				if not same: break
				end_z += 1
			for fill_z in range(z, end_z):
				for fill_x in range(x, end_x): used[Vector2i(fill_x, fill_z)] = true
			_emit_raster_rect(builder, Vector2i(x, z), Vector2i(end_x, end_z), scale_value, height, shade_class)
			data["terrain_rects"] = int(data["terrain_rects"]) + 1
	builder["cells"] = int(builder["cells"]) + selected.size()

static func _raster_height(renderer: Node, data: Dictionary, cell: Vector2i, scale_value: float) -> float:
	var scale_key := roundi(scale_value * 100000.0)
	var key := Vector3i(cell.x, scale_key, cell.y)
	var heights: Dictionary = data["heights"]
	if not heights.has(key):
		var point := (Vector2(cell) + Vector2.ONE * 0.5) * scale_value
		heights[key] = renderer._surface_height(point)
	return float(heights[key])

static func _same_raster_cell(selected: Dictionary, used: Dictionary, cell: Vector2i, height: float, shade_class: int) -> bool:
	if used.has(cell) or not selected.has(cell): return false
	var info: Dictionary = selected[cell]
	return int(info["shade"]) == shade_class and is_equal_approx(float(info["height"]), height)

static func _cell_inside_saved_footprint(cell: Vector2i, scale_value: float, values: Array, half_width: float) -> bool:
	var low := Vector2(cell) * scale_value
	var high := low + Vector2.ONE * scale_value
	for point: Vector2 in [low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)]:
		if _distance_to_saved_path(point, values) > half_width + 0.000001: return false
	return true

static func _distance_to_saved_path(point: Vector2, values: Array) -> float:
	var result := INF
	for index in range(1, values.size()):
		var a := Vector2(float(values[index - 1][0]), float(values[index - 1][1]))
		var b := Vector2(float(values[index][0]), float(values[index][1]))
		result = minf(result, point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)))
	return result

static func _soil_shade_class(path_id: int, route_distance: float, signed_offset: float, width: float) -> int:
	var wear := _interior_wear(path_id, route_distance, signed_offset, width)
	if wear.y >= 0.75: return 4
	if wear.x >= 0.75: return 3
	if wear.x >= 0.25: return 2
	if wear.y >= 0.25: return 1
	# Very broad deterministic base variation prevents a single flat fill while
	# avoiding one-cell checkerboard noise.
	var broad_cell := floori(route_distance / 2.0)
	return 1 if Contact._seed(path_id, broad_cell, 521) % 5 == 0 else 0

static func _soil_colour(shade_class: int) -> Color:
	match shade_class:
		1: return Color("#896852")
		2: return Color("#a48769")
		3: return Color("#b69a79")
		4: return Color("#80624f")
		_: return Color("#957058")

static func _emit_raster_rect(builder: Dictionary, low_cell: Vector2i, high_cell: Vector2i, scale_value: float, height: float, shade_class: int) -> void:
	var low := Vector2(low_cell) * scale_value
	var high := Vector2(high_cell) * scale_value
	var surface: Dictionary = builder["surfaces"][0]
	var base: int = surface["vertices"].size()
	for point: Vector2 in [low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)]:
		surface["vertices"].append(Vector3(point.x, height + TOP_EPSILON, point.y))
		surface["normals"].append(Vector3.UP)
		builder["earth"]["colours"][0].append(_soil_colour(shade_class))
	# Positive X/Z area is clockwise from above in Godot, matching the existing
	# native-facing winding contract.
	surface["indices"].append_array([base, base + 1, base + 2, base, base + 2, base + 3])

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