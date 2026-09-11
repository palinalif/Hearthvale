extends SceneTree

const Layout = preload("res://scripts/joined_roof_course_layout.gd")
const Massing = preload("res://scripts/m2_house_massing.gd")
const Visual = preload("res://scripts/m2_house_massing_visual.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	# Independent solid-voxel oracle checks every emitted face, including
	# negative addresses, steps, a hole, disconnected levels and seam backing.
	for cells in [
		{Vector2i(-1, -1): Vector3i(3, 5, 0)},
		{Vector2i(0, 0): Vector3i(3, 5, 0), Vector2i(1, 0): Vector3i(4, 6, 1), Vector2i(0, 1): Vector3i(3, 4, 0), Vector2i(1, 1): Vector3i(9, 11, 2)},
		{Vector2i(-1, -1): Vector3i(0, 2, 0), Vector2i(-1, 0): Vector3i(0, 2, 1), Vector2i(-1, 1): Vector3i(0, 2, 2), Vector2i(0, 1): Vector3i(0, 2, 0), Vector2i(1, 1): Vector3i(0, 2, 1), Vector2i(1, 0): Vector3i(0, 2, 2), Vector2i(1, -1): Vector3i(0, 2, 0)},
	]: _check_faces(cells)
	var builder := Visual.new()
	for scale_value in [0.25, 0.5, 1.0]:
		var unit := Vector3.ONE * 0.0625 / float(scale_value)
		for shape in ["l_shape", "t_shape", "u_shape"]:
			var view := {"dimensions": Vector3(18, 7, 14), "seed": 37, "roof_profile": "gentle_gable"}
			view["massing_sections"] = Massing.preset_sections(view, shape)
			for upper in [false, true]:
				if upper: view["massing_sections"].append({"id": "upper", "offset": Vector3(0, 7, 0), "size": Vector3(6, 7, 6), "level": 1})
				var before := JSON.stringify(view)
				var tiles := Massing.roof_tiles(view)
				var by_cell: Dictionary = {}
				for tile in tiles: by_cell[tile["cell"]] = tile
				var slopes: Dictionary = {}
				for tile in tiles: slopes[tile["cell"]] = builder._roof_gradient(tile, by_cell)
				var cells := Layout.columns(tiles, slopes, unit, 37)
				var label := "%s scale=%s upper=%s" % [shape, scale_value, upper]
				check(not cells.is_empty(), label + ": approved scales produce detail cells")
				check(cells.size() == tiles.size() * roundi(pow(0.5 / unit.x, 2)), label + ": exact union-cell coverage, no courtyard bridging")
				check(cells == Layout.columns(tiles, slopes, unit, 37), label + ": deterministic regeneration")
				var coverage := true
				var backing := true
				var seams := 0
				for key: Vector2i in cells:
					var x := (key.x + 0.5) * unit.x
					var z := (key.y + 0.5) * unit.z
					coverage = coverage and Massing._height_at_sections(Massing.sections_for(view), x, z) > 0
					var value: Vector3i = cells[key]
					backing = backing and value.y > value.x and value.y - value.x <= 2
					if value.y - value.x == 1: seams += 1
				check(coverage and backing and seams > 0 and seams < cells.size(), label + ": real recessed joints keep a solid backing and the courtyard empty")
				check(JSON.stringify(view) == before, label + ": layout leaves all recipe fields unchanged")
				# The actual handheld tier is the performance-critical comparison.
				if scale_value == 0.25:
					var faces := Layout.quads(cells)
					check(faces.size() * 2 <= tiles.size() * 12, label + ": fewer triangles than the original box tiles")
					_check_mesh(faces, unit)
					var boxes := Layout.pick_boxes(cells, unit)
					var projected_area := 0.0
					for box in boxes: projected_area += box.size.x * box.size.z
					check(is_equal_approx(projected_area, cells.size() * unit.x * unit.z), label + ": picking uses complete disjoint solid runs, not overall AABB")
	builder.free()
	var empty: Array[Dictionary] = []
	check(Layout.columns(empty, {}, Vector3.ZERO, 0).is_empty(), "invalid grid is safely rejected")
	check(Layout.columns(empty, {}, Vector3(0.25,0.5,0.25), 0).is_empty(), "detail cells cannot be stretched")
	var huge: Array[Dictionary] = []
	huge.resize(Layout.MAX_COLUMNS + 1)
	check(Layout.columns(huge, {}, Vector3.ONE * 0.25, 0).is_empty(), "oversized tessellation falls back before processing cells")
	print("joined_roof_course_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _check_faces(cells: Dictionary) -> void:
	var solid: Dictionary = {}
	for key: Vector2i in cells:
		var value: Vector3i = cells[key]
		for y in range(value.x, value.y): solid[Vector3i(key.x, y, key.y)] = true
	var expected: Dictionary = {}
	for voxel: Vector3i in solid:
		for axis in 3:
			for sign_value in [-1, 1]:
				var direction := Vector3i.ZERO
				direction[axis] = sign_value
				if solid.has(voxel + direction): continue
				var corner := voxel
				if sign_value > 0: corner[axis] += 1
				expected[str([axis,sign_value,corner])] = true
	var actual: Dictionary = {}
	var unique := true
	var faces := Layout.quads(cells)
	for face in faces:
		var plane: Vector4i = face["plane"]
		var start: Vector2i = face["start"]
		var size: Vector2i = face["size"]
		for x in size.x:
			for y in size.y:
				var corner := Vector3i.ZERO
				corner[plane.x] = plane.z
				corner[(plane.x + 1) % 3] = start.x + x
				corner[(plane.x + 2) % 3] = start.y + y
				var key := str([plane.x,plane.y,corner])
				unique = unique and not actual.has(key)
				actual[key] = true
	check(unique and actual == expected, "greedy mesh covers every and only exposed face exactly once")
	check(faces == Layout.quads(cells), "greedy merge is deterministic and read-only")
	_check_mesh(faces, Vector3.ONE * 0.25)

func _check_mesh(faces: Array[Dictionary], unit: Vector3) -> void:
	var triangles := 0
	for shade in 3:
		var mesh := Layout.make_mesh(faces, unit, shade)
		if mesh.get_surface_count() == 0: continue
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var on_grid := true
		var winding := true
		for vertex in vertices: on_grid = on_grid and vertex.is_equal_approx(vertex.snapped(unit))
		for i in range(0, indices.size(), 3):
			var a := vertices[indices[i]]
			var b := vertices[indices[i + 1]]
			var c := vertices[indices[i + 2]]
			winding = winding and (b-a).cross(c-a).dot(normals[indices[i]]) < 0
		triangles += indices.size() / 3
		check(on_grid and winding, "actual mesh has cubic-grid vertices, positive face area and outward clockwise winding")
	check(triangles == faces.size() * 2, "three material draws contain exactly the intended exposed quads")
