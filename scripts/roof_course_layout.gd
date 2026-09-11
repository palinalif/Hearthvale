extends RefCounted

## Presentation-only course layout. Integer cell addresses, not instance index,
## keep tile colours and half-bond seams stable when a house is regenerated.
const Grid = preload("res://scripts/visual_grid.gd")
const TILE_COLUMNS := 6
const COURSE_ROWS := 3
# Used only by the controlled before/after review. Never stored in a save.
static var enabled := true

static func supports(material_id: String) -> bool:
	return material_id in ["terracotta", "moss_tile", "slate", "wood_shake"]

static func address(column: int, row: int, seed: int = 0) -> Dictionary:
	var course := floori(float(row) / COURSE_ROWS)
	var phase := posmod(course, 2) * (TILE_COLUMNS / 2)
	var tile := floori(float(column + phase) / TILE_COLUMNS)
	var seam := posmod(column + phase, TILE_COLUMNS) == 0
	var shade := posmod(tile * 13 + course * 7 + posmod(seed, 97) * 3, 11)
	return {"seam": seam, "shade": shade % 3, "tint": 0.96 + float(shade % 3) * 0.02}

static func spans(first: int, count: int, row: int, seed: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var column := first
	while column < first + count:
		var style := address(column, row, seed)
		var end := column + 1
		while end < first + count and address(end, row, seed) == style: end += 1
		style["first"] = column
		style["count"] = end - column
		result.append(style)
		column = end
	return result

static func piece(center: Vector3, size: Vector3, tint: float = 1.0) -> Dictionary:
	return {"center": center, "size": size, "basis": Basis.IDENTITY, "tint": Color(tint, tint, tint, 1.0)}

static func gable(dimensions: Vector3, unit: Vector3, rise_ratio: float, seed: int) -> Array:
	var buckets: Array = [[], [], []]
	var run := dimensions.z * 0.5 + 0.5
	var rise := dimensions.y * rise_ratio
	var span := dimensions.x + 0.75
	var first := roundi(-snappedf(span * 0.5, unit.x) / unit.x)
	var columns := ceili(span / (unit.x * 2.0)) * 2
	for side in [-1.0, 1.0]:
		for row in ceili(run / unit.z):
			var z := (float(row) + 0.5) * unit.z
			var height := snappedf(dimensions.y + rise * (1.0 - z / run), unit.y)
			# Continuous lower skin: recessed joints cannot open holes into the
			# building. Both layers remain inside the original roof envelope.
			buckets[0].append(piece(Vector3((first + columns * 0.5) * unit.x, height - unit.y * 0.5, side * z), Vector3(columns * unit.x, unit.y, unit.z)))
			for strip in spans(first, columns, row, seed):
				if strip["seam"]: continue
				var x := (float(strip["first"]) + float(strip["count"]) * 0.5) * unit.x
				buckets[int(strip["shade"])].append(piece(Vector3(x, height + unit.y * 0.5, side * z), Vector3(float(strip["count"]) * unit.x, unit.y, unit.z)))
	return buckets

static func box_pieces(center: Vector3, size: Vector3, unit: Vector3, seed: int) -> Array[Dictionary]:
	# Custom roofs already consist of stepped slabs. Partition, don't stack
	# coplanar geometry on them; the solid union and silhouette stay identical.
	var quantized := Grid.quantized_box(center, size, unit)
	var actual_center: Vector3 = quantized["center"]
	var actual_size: Vector3 = quantized["size"]
	var low := actual_center - actual_size * 0.5
	var first_x := roundi(low.x / unit.x)
	var first_z := roundi(low.z / unit.z)
	var count_x := roundi(actual_size.x / unit.x)
	var count_z := roundi(actual_size.z / unit.z)
	var result: Array[Dictionary] = []
	var row := first_z
	while row < first_z + count_z:
		var rows := mini(COURSE_ROWS - posmod(row, COURSE_ROWS), first_z + count_z - row)
		for strip in spans(first_x, count_x, row, seed):
			var tint: float = 0.88 if strip["seam"] else float(strip["tint"])
			result.append(piece(Vector3((float(strip["first"]) + float(strip["count"]) * 0.5) * unit.x, actual_center.y, (row + rows * 0.5) * unit.z), Vector3(float(strip["count"]) * unit.x, actual_size.y, rows * unit.z), tint))
		row += rows
	return result

static func make_batch(node_name: String, pieces: Array[Dictionary], colour: Color) -> MultiMeshInstance3D:
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = cube
	multi.instance_count = pieces.size()
	var bounds := AABB()
	for index in pieces.size():
		var record := pieces[index]
		var centre: Vector3 = record["center"]
		var size: Vector3 = record["size"]
		multi.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(size), centre))
		multi.set_instance_color(index, record["tint"])
		var box := AABB(centre - size * 0.5, size)
		bounds = box if index == 0 else bounds.merge(box)
	multi.custom_aabb = bounds
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multi
	node.material_override = material
	node.set_meta("cottage_detail_grid", Grid.COTTAGE_DETAIL_UNIT)
	return node
