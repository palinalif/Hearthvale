extends "res://scripts/m2_path_visual.gd"

## Terrain-cut packed earth should read as worn ground, not a brown ribbon.
## Saved authority remains on the 0.125 m structural grid; presentation may use
## the supported 0.0625 m detail grid to break the lawn-grade shoulder into
## deterministic scuffs while keeping the lowered interior continuous.
var _packed_detail_patches := 0
var _packed_shoulder_omissions := 0
var _packed_stone_flecks := 0

func _append_cells(builder: Dictionary, style_id: String, cells: Array) -> void:
	if style_id != "packed_earth":
		super._append_cells(builder, style_id, cells)
		return
	_packed_detail_patches = 0
	_packed_shoulder_omissions = 0
	_packed_stone_flecks = 0
	var normalized := Region.normalize_cells(cells)
	var profile := Region.packed_earth_profile(normalized)
	var detail := Grid.COTTAGE_DETAIL_UNIT
	var quarter := detail * 0.5
	for cell: Vector2i in normalized:
		var depth := int(profile.get(cell, 0))
		var point := Region.cell_center(cell)
		var surface_y := _surface_height(point)
		var cell_hash := absi(cell.x * 73856093 ^ cell.y * 19349663)
		# Four half-cell patches preserve structural authority but let the shoulder
		# fray back into lawn. Interior cells keep all four patches, so broad roads
		# and plazas still read as continuous compacted ground after excavation.
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
			_append_top_quad(builder, center, Vector2(detail, detail), material_index)
			_packed_detail_patches += 1
		# Sparse pale chips imply small embedded stones without turning dirt into
		# cobble. They stay on one detail-grid patch and use the existing second
		# packed-earth surface, so draw count is unchanged and output deterministic.
		if depth >= 1 and posmod(cell_hash, 23) == 0:
			var fleck_quadrant := posmod(cell_hash / 23, 4)
			var fleck_sx := -1 if fleck_quadrant % 2 == 0 else 1
			var fleck_sz := -1 if fleck_quadrant < 2 else 1
			var fleck_center := Vector3(point.x + float(fleck_sx) * quarter, surface_y + TOP_EPSILON * 1.8, point.y + float(fleck_sz) * quarter)
			_append_top_quad(builder, fleck_center, Vector2(detail, detail), 1)
			_packed_stone_flecks += 1

func stats() -> Dictionary:
	var result := super.stats()
	result["packed_earth_polish"] = {
		"detail_patches": _packed_detail_patches,
		"shoulder_omissions": _packed_shoulder_omissions,
		"stone_flecks": _packed_stone_flecks,
		"detail_unit": Grid.COTTAGE_DETAIL_UNIT,
	}
	return result

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
