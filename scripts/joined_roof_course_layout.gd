extends RefCounted

## A disposable surface skin, not terrain or building authority. Integer-cell
## columns retain the union footprint; greedy exposed faces avoid hidden cubes.
const Massing = preload("res://scripts/m2_house_massing.gd")
const Courses = preload("res://scripts/roof_course_layout.gd")
const Grid = preload("res://scripts/visual_grid.gd")
const MAX_COLUMNS := 131072
static var enabled := true

static func columns(tiles: Array[Dictionary], slopes: Dictionary, unit: Vector3, seed: int) -> Dictionary:
	if not unit.is_finite() or unit.x <= 0 or not unit.is_equal_approx(Vector3.ONE * unit.x): return {}
	var subdivisions := roundi(Massing.CELL / unit.x)
	if subdivisions < 1 or not is_equal_approx(subdivisions * unit.x, Massing.CELL): return {}
	if tiles.size() > MAX_COLUMNS / (subdivisions * subdivisions): return {}
	var result: Dictionary = {}
	for tile in tiles:
		var centre: Vector3 = tile["center"]
		var slope: Vector2 = slopes.get(tile["cell"], Vector2.ZERO)
		var start := Vector2i(roundi((centre.x - Massing.CELL * 0.5) / unit.x), roundi((centre.z - Massing.CELL * 0.5) / unit.z))
		for x in subdivisions:
			for z in subdivisions:
				var key := start + Vector2i(x, z)
				var sample := Vector2((key.x + 0.5) * unit.x, (key.y + 0.5) * unit.z)
				var height := centre.y + slope.dot(sample - Vector2(centre.x, centre.z))
				# Quantize the existing tile plane, not a replacement roof pitch.
				var top := roundi((height + 0.09) / unit.y)
				var style := Courses.address(key.y, key.x, seed) if absf(slope.x) > absf(slope.y) else Courses.address(key.x, key.y, seed)
				var seam := bool(style["seam"])
				# Recess one cell at joints, leaving a continuous backing cell.
				result[key] = Vector3i(top - 2, top - (1 if seam else 0), 0 if seam else int(style["shade"]))
	return result

static func quads(cells: Dictionary) -> Array[Dictionary]:
	# Each group is one plane, normal and palette shade. Its 2D integer mask
	# stores only exposed unit faces. Internal faces never enter the mesh.
	var groups: Dictionary = {}
	for key: Vector2i in cells:
		var value: Vector3i = cells[key]
		_add_face(groups, Vector4i(1, 1, value.y, value.z), Vector2i(key.y, key.x))
		_add_face(groups, Vector4i(1, -1, value.x, 0), Vector2i(key.y, key.x))
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbour: Vector3i = cells.get(key + direction, Vector3i.ZERO)
			var axis := 0 if direction.x != 0 else 2
			var sign_value := direction.x if axis == 0 else direction.y
			var plane := (key.x if axis == 0 else key.y) + (1 if sign_value > 0 else 0)
			for y in range(value.x, value.y):
				if y >= neighbour.x and y < neighbour.y: continue
				var uv := Vector2i(y, key.y) if axis == 0 else Vector2i(key.x, y)
				_add_face(groups, Vector4i(axis, sign_value, plane, value.z), uv)
	var result: Array[Dictionary] = []
	var plane_keys := groups.keys()
	plane_keys.sort_custom(func(a: Vector4i, b: Vector4i) -> bool:
		if a.x != b.x: return a.x < b.x
		if a.y != b.y: return a.y < b.y
		if a.z != b.z: return a.z < b.z
		return a.w < b.w)
	for plane: Vector4i in plane_keys:
		var mask: Dictionary = groups[plane]
		var keys := mask.keys()
		keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y if a.y != b.y else a.x < b.x)
		for start: Vector2i in keys:
			if not mask.has(start): continue
			var width := 1
			while mask.has(start + Vector2i(width, 0)): width += 1
			var height := 1
			while _row_exists(mask, start + Vector2i(0, height), width): height += 1
			for x in width:
				for y in height: mask.erase(start + Vector2i(x, y))
			result.append({"plane": plane, "start": start, "size": Vector2i(width, height)})
	return result

static func _add_face(groups: Dictionary, plane: Vector4i, uv: Vector2i) -> void:
	if not groups.has(plane): groups[plane] = {}
	groups[plane][uv] = true

static func _row_exists(mask: Dictionary, start: Vector2i, width: int) -> bool:
	for x in width:
		if not mask.has(start + Vector2i(x, 0)): return false
	return true

static func make_mesh(faces: Array[Dictionary], unit: Vector3, shade: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for face in faces:
		var plane: Vector4i = face["plane"]
		if plane.w != shade: continue
		var start: Vector2i = face["start"]
		var size: Vector2i = face["size"]
		var u := (plane.x + 1) % 3
		var v := (plane.x + 2) % 3
		var normal := Vector3.ZERO
		normal[plane.x] = plane.y
		var origin := Vector3.ZERO
		origin[plane.x] = plane.z
		origin[u] = start.x
		origin[v] = start.y
		var du := Vector3.ZERO
		var dv := Vector3.ZERO
		du[u] = size.x
		dv[v] = size.y
		var base := vertices.size()
		for point in [origin, origin + du, origin + du + dv, origin + dv]:
			vertices.append(point * unit)
			normals.append(normal)
		# Godot's front faces are clockwise (cross product opposite normal).
		var order := [0, 2, 1, 0, 3, 2] if plane.y > 0 else [0, 1, 2, 0, 2, 3]
		for index in order: indices.append(base + index)
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func pick_boxes(cells: Dictionary, unit: Vector3) -> Array[AABB]:
	# Horizontal runs are exact solid columns, NOT the mesh's overall bounds:
	# a U courtyard and exposed lower roof must remain separately targetable.
	var result: Array[AABB] = []
	var used: Dictionary = {}
	var keys := cells.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y if a.y != b.y else a.x < b.x)
	for key: Vector2i in keys:
		if used.has(key): continue
		var value: Vector3i = cells[key]
		var count := 1
		while cells.has(key + Vector2i(count, 0)):
			var next: Vector3i = cells[key + Vector2i(count, 0)]
			if next.x != value.x or next.y != value.y: break
			used[key + Vector2i(count, 0)] = true
			count += 1
		result.append(AABB(Vector3(key.x, value.x, key.y) * unit, Vector3(count, value.y - value.x, 1) * unit))
	return result
