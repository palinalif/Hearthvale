extends "res://scripts/m2_path_visual.gd"

var _packed_detail_patches := 0
var _packed_shoulder_omissions := 0
var _packed_exposed_shoulder_patches := 0
var _packed_stone_flecks := 0
var _packed_merged_quads := 0
var _cobble_stones := 0
var _cobble_raised_stones := 0
var _stepping_stones := 0
var _stepping_offset_stones := 0

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
		for quadrant in 4:
			if depth == 0:
				var omit := _omit_shoulder_quadrant(cell_hash, quadrant, exposed)
				if omit:
					_packed_shoulder_omissions += 1
					continue
				if _quadrant_touches_exposed_edge(quadrant, exposed):
					_packed_exposed_shoulder_patches += 1
			var sx := -1 if quadrant % 2 == 0 else 1
			var sz := -1 if quadrant < 2 else 1
			var center := Vector3(point.x + float(sx) * quarter, surface_y + TOP_EPSILON, point.y + float(sz) * quarter)
			var patch_hash := absi(cell_hash ^ (quadrant + 1) * 83492791)
			var material_index := 1 if posmod(patch_hash, 7) < (3 if depth >= 1 else 2) else 0
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

func _append_stepping_stone_cells(builder: Dictionary, cells: Array) -> void:
	_stepping_stones = 0
	_stepping_offset_stones = 0
	var normalized := Region.normalize_cells(cells)
	var occupied := {}
	for cell: Vector2i in normalized: occupied[cell] = true
	for cell: Vector2i in normalized:
		# A stable staggered lattice gives a readable walking cadence inside any
		# painted region without reconstructing or saving a hidden centreline.
		if posmod(cell.x + cell.y * 2, 4) != 0:
			continue
		var point := Region.cell_center(cell)
		var surface_y := _surface_height(point)
		var cell_hash := absi(cell.x * 73856093 ^ cell.y * 19349663)
		var offset_axis := posmod(cell_hash, 2)
		var offset_sign := -1.0 if posmod(cell_hash / 3, 2) == 0 else 1.0
		var offset := Grid.COTTAGE_DETAIL_UNIT * 0.16 * offset_sign
		var center := Vector3(point.x, surface_y + TOP_EPSILON * 1.25, point.y)
		if offset_axis == 0: center.x += offset
		else: center.z += offset
		var size_hash := posmod(cell_hash, 3)
		var size := Vector2(Grid.UNIT * (0.74 + float(size_hash) * 0.04), Grid.UNIT * (0.62 + float(posmod(cell_hash / 5, 3)) * 0.04))
		var angle := deg_to_rad(float(posmod(cell_hash, 17) - 8))
		var material_index := 1 if posmod(cell_hash, 5) == 0 else 0
		_append_rotated_top_quad(builder, center, size, angle, material_index)
		_stepping_stones += 1
		if absf(offset) > 0.00001: _stepping_offset_stones += 1

func stats() -> Dictionary:
	var result := super.stats()
	result["packed_earth_polish"] = {
		"detail_patches": _packed_detail_patches,
		"shoulder_omissions": _packed_shoulder_omissions,
		"exposed_shoulder_patches": _packed_exposed_shoulder_patches,
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
		"cadence_period": 4,
		"detail_unit": Grid.COTTAGE_DETAIL_UNIT,
	}
	return result

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

func _omit_shoulder_quadrant(cell_hash: int, quadrant: int, exposed: int) -> bool:
	var touches_exposed := _quadrant_touches_exposed_edge(quadrant, exposed)
	if touches_exposed:
		return posmod(cell_hash + quadrant * 11, 3) != 0
	if exposed == 0:
		var fallback := posmod(cell_hash / 7, 4)
		return quadrant == fallback
	return false

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

func _append_rotated_top_quad(builder: Dictionary, center: Vector3, size: Vector2, angle: float, material_index: int) -> void:
	var surface: Dictionary = builder["surfaces"][material_index]
	var vertices: Array = surface["vertices"]
	var normals: Array = surface["normals"]
	var indices: Array = surface["indices"]
	var half := size * 0.5
	var basis := Basis(Vector3.UP, angle)
	var base := vertices.size()
	for corner in [Vector3(-half.x, 0.0, -half.y), Vector3(half.x, 0.0, -half.y), Vector3(half.x, 0.0, half.y), Vector3(-half.x, 0.0, half.y)]:
		vertices.append(center + basis * corner)
		normals.append(Vector3.UP)
	indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	surface["vertices"] = vertices
	surface["normals"] = normals
	surface["indices"] = indices
	builder["surfaces"][material_index] = surface
	builder["cells"] = int(builder["cells"]) + 1

func _append_top_quad(builder: Dictionary, center: Vector3, size: Vector2, material_index: int) -> void:
	_append_rotated_top_quad(builder, center, size, 0.0, material_index)
