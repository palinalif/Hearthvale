extends "res://scripts/m2_path_visual.gd"
# Presentation polish stays deterministic so CI review captures remain directly comparable.

var _packed_detail_patches := 0
var _packed_shoulder_omissions := 0
var _packed_exposed_shoulder_patches := 0
var _packed_stone_flecks := 0
var _packed_merged_quads := 0
var _packed_path_contact_patches := 0
var _cobble_stones := 0
var _cobble_raised_stones := 0
var _stepping_stones := 0
var _stepping_offset_stones := 0
var _stepping_max_span := 0.0
var _style_lookup: Dictionary = {}
var _transition_edges := 0
var _transition_cobble_chips := 0
var _transition_step_stones := 0
var _smoothed_surface_cache: Dictionary = {}
var _smoothed_surface_quads := 0
var _smoothing_authoritative_rebuild := false

func rebuild(path_values: Array, terrain_backend: Node = null) -> void:
	_style_lookup.clear()
	_smoothed_surface_cache.clear()
	_smoothed_surface_quads = 0
	_transition_edges = 0
	_transition_cobble_chips = 0
	_transition_step_stones = 0
	for style_id in STYLE_ORDER:
		for cell: Vector2i in _cells_for_style(path_values, style_id):
			_style_lookup[cell] = style_id
	_smoothing_authoritative_rebuild = true
	super.rebuild(path_values, terrain_backend)
	_smoothing_authoritative_rebuild = false

func _append_cells(builder: Dictionary, style_id: String, cells: Array) -> void:
	if style_id == "packed_earth":
		_append_packed_earth_cells(builder, cells)
		return
	if style_id == "cobblestone":
		_append_cobblestone_cells(builder, cells)
		return
	if style_id == "stepping_stones":
		_append_stepping_stone_cells(builder, cells)
		return
	super._append_cells(builder, style_id, cells)

func _append_packed_earth_cells(builder: Dictionary, cells: Array) -> void:
	_packed_detail_patches = 0
	_packed_shoulder_omissions = 0
	_packed_exposed_shoulder_patches = 0
	_packed_stone_flecks = 0
	_packed_merged_quads = 0
	_packed_path_contact_patches = 0
	var normalized := Region.normalize_cells(cells)
	var occupied := {}
	for cell: Vector2i in normalized: occupied[cell] = true
	var profile := Region.packed_earth_profile(normalized)
	var detail := Grid.COTTAGE_DETAIL_UNIT
	var quarter := detail * 0.5
	var patches: Array = []
	for cell: Vector2i in normalized:
		var depth := int(profile.get(cell, 0))
		var point := Region.cell_center(cell)
		var surface_y := _surface_height(point)
		var cell_hash := absi(cell.x * 73856093 ^ cell.y * 19349663)
		var exposed := _exposed_cardinal_edges(cell, occupied)
		var path_contacts := _foreign_path_contact_edges(cell, "packed_earth")
		for quadrant in 4:
			if depth == 0:
				var touches_path := _quadrant_touches_exposed_edge(quadrant, path_contacts)
				var omit := false if touches_path else _omit_shoulder_quadrant(cell, quadrant, exposed)
				if omit:
					_packed_shoulder_omissions += 1
					continue
				if touches_path:
					_packed_path_contact_patches += 1
				if _quadrant_touches_exposed_edge(quadrant, exposed):
					_packed_exposed_shoulder_patches += 1
			var sx := -1 if quadrant % 2 == 0 else 1
			var sz := -1 if quadrant < 2 else 1
			var center := Vector3(point.x + float(sx) * quarter, surface_y + TOP_EPSILON, point.y + float(sz) * quarter)
			var patch_hash := absi(cell_hash ^ (quadrant + 1) * 83492791)
			# Use broad deterministic tone islands rather than quadrant-by-quadrant
			# alternation, so compacted earth reads as worn ground instead of tiles.
			var cluster := Vector2i(floori(float(cell.x) / 3.0), floori(float(cell.y) / 3.0))
			var cluster_hash := absi(cluster.x * 19349663 ^ cluster.y * 83492791)
			var broad_tone := posmod(cluster_hash, 5) < (3 if depth >= 1 else 2)
			var fleck_tone := posmod(patch_hash, 13) == 0
			var material_index := 1 if broad_tone != fleck_tone else 0
			patches.append({"center": center, "material": material_index})
			_packed_detail_patches += 1
		if depth >= 1 and posmod(cell_hash, 23) == 0:
			var fleck_quadrant := posmod(cell_hash / 23, 4)
			var fleck_sx := -1 if fleck_quadrant % 2 == 0 else 1
			var fleck_sz := -1 if fleck_quadrant < 2 else 1
			var fleck_center := Vector3(point.x + float(fleck_sx) * quarter, surface_y + TOP_EPSILON * 1.8, point.y + float(fleck_sz) * quarter)
			_append_top_quad(builder, fleck_center, Vector2(detail, detail), 1)
			_packed_stone_flecks += 1
	_append_merged_detail_patches(builder, patches, detail)

func _append_cobblestone_cells(builder: Dictionary, cells: Array) -> void:
	_cobble_stones = 0
	_cobble_raised_stones = 0
	var normalized := Region.normalize_cells(cells)
	var detail := Grid.COTTAGE_DETAIL_UNIT
	var gap := detail * 0.10
	for cell: Vector2i in normalized:
		var point := Region.cell_center(cell)
		var surface_y := _surface_height(point)
		var row_horizontal := posmod(cell.y, 2) == 0
		for half in 2:
			var cell_hash := absi(cell.x * 73856093 ^ cell.y * 19349663 ^ (half + 1) * 83492791)
			var material_index := posmod(cell_hash, 5) == 0 or posmod(cell_hash, 7) == 0
			var lifted := posmod(cell_hash, 11) == 0
			var center := Vector3(point.x, surface_y + TOP_EPSILON + (TOP_EPSILON * 0.75 if lifted else 0.0), point.y)
			var size := Vector2(Grid.UNIT - gap * 2.0, detail - gap * 2.0)
			if row_horizontal:
				center.z += (-0.5 if half == 0 else 0.5) * detail
			else:
				center.x += (-0.5 if half == 0 else 0.5) * detail
				size = Vector2(size.y, size.x)
			_append_top_quad(builder, center, size, 1 if material_index else 0)
			_cobble_stones += 1
			if lifted: _cobble_raised_stones += 1
		_append_cobble_transition_chips(builder, cell, point, surface_y, detail, gap)

func _append_cobble_transition_chips(builder: Dictionary, cell: Vector2i, point: Vector2, surface_y: float, detail: float, gap: float) -> void:
	for entry in _foreign_cardinal_neighbours(cell, "cobblestone"):
		var neighbour_style := str(entry.style)
		if neighbour_style != "packed_earth" and neighbour_style != "stepping_stones": continue
		var direction: Vector2i = entry.direction
		var hash_value := absi(cell.x * 92821 ^ cell.y * 68917 ^ direction.x * 2833 ^ direction.y * 4099)
		if posmod(hash_value, 3) == 0: continue
		var edge := Vector2(float(direction.x), float(direction.y))
		var center_2d := point + edge * (Grid.UNIT * 0.52)
		var center := Vector3(center_2d.x, surface_y + TOP_EPSILON * 1.55, center_2d.y)
		var along_x := direction.y != 0
		var size := Vector2(detail * (1.35 if along_x else 0.72) - gap, detail * (0.72 if along_x else 1.35) - gap)
		_append_rotated_top_quad(builder, center, size, deg_to_rad(float(posmod(hash_value, 9) - 4)), posmod(hash_value, 5) == 0 as int)
		_transition_cobble_chips += 1
		_transition_edges += 1

func _append_stepping_stone_cells(builder: Dictionary, cells: Array) -> void:
	_stepping_stones = 0
	_stepping_offset_stones = 0
	_stepping_max_span = 0.0
	var normalized := Region.normalize_cells(cells)
	# Linear-time, hash-shifted bucket selection avoids both a visible fixed grid
	# and the expensive neighbourhood scan that regressed live road painting.
	var bucket_size := 5
	var selected := {}
	for cell: Vector2i in normalized:
		var shift_x := posmod(cell.y * 3, bucket_size)
		var shift_y := posmod(cell.x * 2, bucket_size)
		var bucket := Vector2i(floori(float(cell.x + shift_x) / float(bucket_size)), floori(float(cell.y + shift_y) / float(bucket_size)))
		var score := absi(cell.x * 73856093 ^ cell.y * 19349663 ^ bucket.x * 83492791 ^ bucket.y * 2971215073)
		if not selected.has(bucket) or score > int((selected[bucket] as Dictionary).score):
			selected[bucket] = {"cell": cell, "score": score}
	for bucket in selected:
		var cell: Vector2i = (selected[bucket] as Dictionary).cell
		var point := Region.cell_center(cell)
		var surface_y := _surface_height(point)
		var cell_hash := absi(cell.x * 73856093 ^ cell.y * 19349663)
		var offset_x := (float(posmod(cell_hash, 9)) - 4.0) * Grid.UNIT * 0.055
		var offset_z := (float(posmod(cell_hash / 11, 9)) - 4.0) * Grid.UNIT * 0.055
		var center := Vector3(point.x + offset_x, surface_y + TOP_EPSILON * 1.25, point.y + offset_z)
		var size_hash := posmod(cell_hash, 3)
		var size := Vector2(Grid.UNIT * (2.85 + float(size_hash) * 0.22), Grid.UNIT * (2.35 + float(posmod(cell_hash / 5, 3)) * 0.18))
		var angle := deg_to_rad(float(posmod(cell_hash, 29) - 14))
		var material_index := 1 if posmod(cell_hash, 5) == 0 else 0
		_append_rotated_top_quad(builder, center, size, angle, material_index)
		_stepping_stones += 1
		if absf(offset_x) > 0.00001 or absf(offset_z) > 0.00001: _stepping_offset_stones += 1
		_stepping_max_span = maxf(_stepping_max_span, maxf(size.x, size.y))
	_append_step_transition_stones(builder, normalized)

func _append_step_transition_stones(builder: Dictionary, cells: Array) -> void:
	for cell: Vector2i in cells:
		var neighbours := _foreign_cardinal_neighbours(cell, "stepping_stones")
		if neighbours.is_empty(): continue
		var hash_value := absi(cell.x * 19349663 ^ cell.y * 83492791)
		if posmod(hash_value, 4) != 0: continue
		var entry: Dictionary = neighbours[posmod(hash_value / 7, neighbours.size())]
		if str(entry.style) != "packed_earth": continue
		var direction: Vector2i = entry.direction
		var point := Region.cell_center(cell) + Vector2(float(direction.x), float(direction.y)) * Grid.UNIT * 0.58
		var surface_y := _surface_height(point)
		var size := Vector2(Grid.UNIT * 2.15, Grid.UNIT * 1.72)
		var angle := deg_to_rad(float(posmod(hash_value, 25) - 12))
		_append_rotated_top_quad(builder, Vector3(point.x, surface_y + TOP_EPSILON * 1.6, point.y), size, angle, 1 if posmod(hash_value, 5) == 0 else 0)
		_transition_step_stones += 1
		_transition_edges += 1
		_stepping_stones += 1
		_stepping_max_span = maxf(_stepping_max_span, size.x)

func stats() -> Dictionary:
	var result := super.stats()
	result["packed_earth_polish"] = {
		"detail_patches": _packed_detail_patches,
		"shoulder_omissions": _packed_shoulder_omissions,
		"exposed_shoulder_patches": _packed_exposed_shoulder_patches,
		"path_contact_patches": _packed_path_contact_patches,
		"stone_flecks": _packed_stone_flecks,
		"merged_quads": _packed_merged_quads,
		"detail_unit": Grid.COTTAGE_DETAIL_UNIT,
	}
	result["cobblestone_polish"] = {
		"stones": _cobble_stones,
		"raised_stones": _cobble_raised_stones,
		"joint_gap": Grid.COTTAGE_DETAIL_UNIT * 0.10,
		"detail_unit": Grid.COTTAGE_DETAIL_UNIT,
	}
	result["stepping_stone_polish"] = {
		"stones": _stepping_stones,
		"offset_stones": _stepping_offset_stones,
		"bucket_size_cells": 5,
		"max_span": _stepping_max_span,
		"detail_unit": Grid.COTTAGE_DETAIL_UNIT,
	}
	result["style_transitions"] = {
		"edges": _transition_edges,
		"cobble_chips": _transition_cobble_chips,
		"step_stones": _transition_step_stones,
	}
	result["terrain_following"] = {
		"mode": "bilinear_cell_centres",
		"smoothed_quads": _smoothed_surface_quads,
	}
	return result

func _foreign_cardinal_neighbours(cell: Vector2i, own_style: String) -> Array:
	var result: Array = []
	for direction: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var style := str(_style_lookup.get(cell + direction, ""))
		if style != "" and style != own_style:
			result.append({"direction": direction, "style": style})
	return result

func _foreign_path_contact_edges(cell: Vector2i, own_style: String) -> int:
	var mask := 0
	var style := str(_style_lookup.get(cell + Vector2i(-1, 0), ""))
	if style != "" and style != own_style: mask |= 1
	style = str(_style_lookup.get(cell + Vector2i(1, 0), ""))
	if style != "" and style != own_style: mask |= 2
	style = str(_style_lookup.get(cell + Vector2i(0, -1), ""))
	if style != "" and style != own_style: mask |= 4
	style = str(_style_lookup.get(cell + Vector2i(0, 1), ""))
	if style != "" and style != own_style: mask |= 8
	return mask

func _exposed_cardinal_edges(cell: Vector2i, occupied: Dictionary) -> int:
	var mask := 0
	if not occupied.has(cell + Vector2i(-1, 0)): mask |= 1
	if not occupied.has(cell + Vector2i(1, 0)): mask |= 2
	if not occupied.has(cell + Vector2i(0, -1)): mask |= 4
	if not occupied.has(cell + Vector2i(0, 1)): mask |= 8
	return mask

func _quadrant_touches_exposed_edge(quadrant: int, exposed: int) -> bool:
	var left := quadrant % 2 == 0
	var top := quadrant < 2
	return (left and (exposed & 1) != 0) or (not left and (exposed & 2) != 0) or (top and (exposed & 4) != 0) or (not top and (exposed & 8) != 0)

func _omit_shoulder_quadrant(cell: Vector2i, quadrant: int, exposed: int) -> bool:
	if exposed == 0: return false
	var left := quadrant % 2 == 0
	var top := quadrant < 2
	var omit := false
	# Erode in broad deterministic runs along an exposed side, rather than making
	# each 0.0625 m quadrant independently disappear. That removes the comb/teeth
	# silhouette while keeping the packed-earth shoulder visibly worn into grass.
	if left and (exposed & 1) != 0:
		var run := floori(float(cell.y) / 4.0)
		omit = omit or posmod(run * 17 + cell.x * 5, 7) < 2
	if not left and (exposed & 2) != 0:
		var run := floori(float(cell.y) / 4.0)
		omit = omit or posmod(run * 19 + cell.x * 3, 7) < 2
	if top and (exposed & 4) != 0:
		var run := floori(float(cell.x) / 4.0)
		omit = omit or posmod(run * 23 + cell.y * 5, 7) < 2
	if not top and (exposed & 8) != 0:
		var run := floori(float(cell.x) / 4.0)
		omit = omit or posmod(run * 29 + cell.y * 3, 7) < 2
	return omit

func _append_merged_detail_patches(builder: Dictionary, patches: Array, detail: float) -> void:
	var buckets := {}
	for patch: Dictionary in patches:
		var center: Vector3 = patch.center
		var gx := roundi((center.x - detail * 0.5) / detail)
		var gz := roundi((center.z - detail * 0.5) / detail)
		var gy := roundi(center.y / 0.0005)
		var material := int(patch.material)
		var key := Vector2i(gy, material)
		if not buckets.has(key): buckets[key] = {}
		(buckets[key] as Dictionary)[Vector2i(gx, gz)] = true
	for key: Vector2i in buckets:
		var remaining: Dictionary = (buckets[key] as Dictionary).duplicate()
		while not remaining.is_empty():
			var start := _minimum_grid_cell(remaining)
			var width := 1
			while remaining.has(Vector2i(start.x + width, start.y)):
				width += 1
			var height := 1
			while _rectangle_row_exists(remaining, start, width, height):
				height += 1
			for dz in height:
				for dx in width:
					remaining.erase(Vector2i(start.x + dx, start.y + dz))
			var center_x := (float(start.x) + float(width) * 0.5) * detail
			var center_z := (float(start.y) + float(height) * 0.5) * detail
			var center_y := float(key.x) * 0.0005
			_append_top_quad(builder, Vector3(center_x, center_y, center_z), Vector2(float(width) * detail, float(height) * detail), key.y)
			_packed_merged_quads += 1

func _minimum_grid_cell(cells: Dictionary) -> Vector2i:
	var found := false
	var result := Vector2i.ZERO
	for value in cells.keys():
		var cell: Vector2i = value
		if not found or cell.y < result.y or (cell.y == result.y and cell.x < result.x):
			result = cell
			found = true
	return result

func _rectangle_row_exists(cells: Dictionary, start: Vector2i, width: int, dz: int) -> bool:
	for dx in width:
		if not cells.has(Vector2i(start.x + dx, start.y + dz)):
			return false
	return true

func _smoothed_surface_height(point: Vector2) -> float:
	# Interpolate the heights sampled at structural-cell centres. The result is a
	# continuous surface across one-voxel terrain ledges, so committed path tops
	# form short ramps instead of reproducing the raw vertical stair-step.
	var key := Vector2i(roundi(point.x / Grid.COTTAGE_DETAIL_UNIT), roundi(point.y / Grid.COTTAGE_DETAIL_UNIT))
	if _smoothed_surface_cache.has(key): return float(_smoothed_surface_cache[key])
	var gx := point.x / Grid.UNIT - 0.5
	var gz := point.y / Grid.UNIT - 0.5
	var x0 := floori(gx)
	var z0 := floori(gz)
	var tx := gx - float(x0)
	var tz := gz - float(z0)
	var h00 := _surface_height(Region.cell_center(Vector2i(x0, z0)))
	var h10 := _surface_height(Region.cell_center(Vector2i(x0 + 1, z0)))
	var h01 := _surface_height(Region.cell_center(Vector2i(x0, z0 + 1)))
	var h11 := _surface_height(Region.cell_center(Vector2i(x0 + 1, z0 + 1)))
	var height := lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
	_smoothed_surface_cache[key] = height
	return height

func _append_rotated_top_quad(builder: Dictionary, center: Vector3, size: Vector2, angle: float, material_index: int) -> void:
	var surface: Dictionary = builder["surfaces"][material_index]
	var vertices: Array = surface["vertices"]
	var normals: Array = surface["normals"]
	var indices: Array = surface["indices"]
	var half := size * 0.5
	var basis := Basis(Vector3.UP, angle)
	var base := vertices.size()
	var use_smoothed_surface: bool = _smoothing_authoritative_rebuild
	var center_surface := _surface_height(Vector2(center.x, center.z)) if use_smoothed_surface else center.y
	var lift := center.y - center_surface if use_smoothed_surface else 0.0
	var quad_vertices: Array[Vector3] = []
	for corner in [Vector3(-half.x, 0.0, -half.y), Vector3(half.x, 0.0, -half.y), Vector3(half.x, 0.0, half.y), Vector3(-half.x, 0.0, half.y)]:
		var world_corner: Vector3 = center + basis * corner
		if use_smoothed_surface:
			world_corner.y = _smoothed_surface_height(Vector2(world_corner.x, world_corner.z)) + lift
		quad_vertices.append(world_corner)
	if use_smoothed_surface: _smoothed_surface_quads += 1
	var normal_a := (quad_vertices[1] - quad_vertices[0]).cross(quad_vertices[2] - quad_vertices[0]).normalized()
	var normal_b := (quad_vertices[2] - quad_vertices[0]).cross(quad_vertices[3] - quad_vertices[0]).normalized()
	var normal := (normal_a + normal_b).normalized()
	if not normal.is_finite() or normal.length_squared() < 0.5: normal = Vector3.UP
	if normal.y < 0.0: normal = -normal
	for vertex in quad_vertices:
		vertices.append(vertex)
		normals.append(normal)
	indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	surface["vertices"] = vertices
	surface["normals"] = normals
	surface["indices"] = indices
	builder["surfaces"][material_index] = surface
	builder["cells"] = int(builder["cells"]) + 1

func _append_top_quad(builder: Dictionary, center: Vector3, size: Vector2, material_index: int) -> void:
	_append_rotated_top_quad(builder, center, size, 0.0, material_index)
