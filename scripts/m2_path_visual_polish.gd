extends "res://scripts/m2_path_visual.gd"

## Terrain-cut packed earth should read as worn ground, not a brown ribbon.
## Saved authority remains on the 0.125 m structural grid; this node never
## changes path ownership. Presentation may use the supported 0.0625 m detail
## grid and merge adjacent equal patches back into longer quads.
var _packed_detail_patches := 0
var _packed_shoulder_omissions := 0
var _packed_stone_flecks := 0
var _packed_merged_quads := 0

func _append_cells(builder: Dictionary, style_id: String, cells: Array) -> void:
	if style_id != "packed_earth":
		super._append_cells(builder, style_id, cells)
		return
	_packed_detail_patches = 0
	_packed_shoulder_omissions = 0
	_packed_stone_flecks = 0
	_packed_merged_quads = 0
	var normalized := Region.normalize_cells(cells)
	var profile := Region.packed_earth_profile(normalized)
	var detail := Grid.COTTAGE_DETAIL_UNIT
	var quarter := detail * 0.5
	var patches: Array = []
	for cell: Vector2i in normalized:
		var depth := int(profile.get(cell, 0))
		var point := Region.cell_center(cell)
		var surface_y := _surface_height(point)
		var cell_hash := absi(cell.x * 73856093 ^ cell.y * 19349663)
		for quadrant in 4:
			if depth == 0:
				var omit_count := 1 + posmod(cell_hash, 2)
				var omit_a := posmod(cell_hash / 7, 4)
				var omit_b := posmod(omit_a + 1 + posmod(cell_hash / 19, 2), 4)
				if quadrant == omit_a or (omit_count > 1 and quadrant == omit_b):
					_packed_shoulder_omissions += 1
					continue
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

func stats() -> Dictionary:
	var result := super.stats()
	result["packed_earth_polish"] = {
		"detail_patches": _packed_detail_patches,
		"shoulder_omissions": _packed_shoulder_omissions,
		"stone_flecks": _packed_stone_flecks,
		"merged_quads": _packed_merged_quads,
		"detail_unit": Grid.COTTAGE_DETAIL_UNIT,
	}
	return result

func _append_merged_detail_patches(builder: Dictionary, patches: Array, detail: float) -> void:
	# Index each patch by its detail-grid lower-left corner. Reconstruct merged
	# strips from grid boundaries, so every output vertex remains exactly aligned
	# to the supported 0.0625 m presentation grid.
	var buckets := {}
	for patch: Dictionary in patches:
		var center: Vector3 = patch.center
		var gx := roundi((center.x - detail * 0.5) / detail)
		var gz := roundi((center.z - detail * 0.5) / detail)
		var gy := roundi(center.y / 0.0005)
		var material := int(patch.material)
		var key := Vector3i(gz, gy, material)
		if not buckets.has(key): buckets[key] = []
		(buckets[key] as Array).append(gx)
	for key: Vector3i in buckets:
		var xs: Array = buckets[key]
		xs.sort()
		var start_x := int(xs[0])
		var previous_x := start_x
		for index in range(1, xs.size() + 1):
			var flush := index == xs.size()
			var current_x := previous_x + 2 if flush else int(xs[index])
			if current_x != previous_x + 1:
				var count := previous_x - start_x + 1
				var center_x := (float(start_x) + float(count) * 0.5) * detail
				var center_z := (float(key.x) + 0.5) * detail
				var center_y := float(key.y) * 0.0005
				_append_top_quad(builder, Vector3(center_x, center_y, center_z), Vector2(float(count) * detail, detail), key.z)
				_packed_merged_quads += 1
				start_x = current_x
			previous_x = current_x

func _append_top_quad(builder: Dictionary, center: Vector3, size: Vector2, material_index: int) -> void:
	var surface: Dictionary = builder["surfaces"][material_index]
	var vertices: Array = surface["vertices"]
	var normals: Array = surface["normals"]
	var indices: Array = surface["indices"]
	var half := size * 0.5
	var base := vertices.size()
	vertices.append_array([
		center + Vector3(-half.x, 0.0, -half.y),
		center + Vector3(half.x, 0.0, -half.y),
		center + Vector3(half.x, 0.0, half.y),
		center + Vector3(-half.x, 0.0, half.y),
	])
	for _i in 4: normals.append(Vector3.UP)
	indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	surface["vertices"] = vertices
	surface["normals"] = normals
	surface["indices"] = indices
	builder["surfaces"][material_index] = surface
	builder["cells"] = int(builder["cells"]) + 1
