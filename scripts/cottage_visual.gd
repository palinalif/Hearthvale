extends Node3D
class_name CottageVisual

## Small procedural renderer for one authoritative building recipe. Geometry is
## disposable; IDs, states, anchors and revisions remain in BuildingWorld.
const Grid = preload("res://scripts/visual_grid.gd")
var _unit := Vector3.ONE * 0.25
const WALL_COLOR := Color("#e7cfab")
const TRIM_COLOR := Color("#634d42")
const ROOF_COLOR := Color("#b85f4b")
const ROOF_TILE_COLORS := [Color("#b9654c"), Color("#bf6c50"), Color("#c47457")]
const CORNICE_COLOR := Color("#f0d9a5")
const SHUTTER_COLOR := Color("#557a70")
const STONE_COLOR := Color("#a48770")
const QUOIN_COLOR := Color("#c09c78")
const WINDOW_COLOR := Color("#344e50")
const FLOWER_COLOR := Color("#d56d65")
var applied_revision := -1
var requested_revision := -1
var building_id := ""
var _applied_view: Dictionary = {}

func request_revision(revision: int) -> void:
	requested_revision = maxi(requested_revision, revision)

func apply_building(view: Dictionary, source_revision: int) -> bool:
	if requested_revision < 0: requested_revision = source_revision
	if source_revision != requested_revision or source_revision < applied_revision: return false
	if view.is_empty(): return false
	# Cancelling a preview invalidates the scene's presentation key, not every
	# cottage's geometry. Keep identical instances (and their draw order) alive.
	# Compare a private snapshot: preview dictionaries can be edited in place.
	if source_revision == applied_revision and view == _applied_view:
		return true
	_applied_view = view.duplicate(true)
	for child in get_children(): child.free()
	building_id = str(view.get("id", ""))
	applied_revision = source_revision
	var dimensions: Vector3 = view.get("dimensions", Vector3(18, 10, 14))
	var transform_value = view.get("transform", Transform3D.IDENTITY)
	var building_transform: Transform3D = transform_value if transform_value is Transform3D else Transform3D.IDENTITY
	transform = building_transform
	var world_scale := building_transform.basis.get_scale().abs()
	_unit = Vector3(Grid.UNIT / world_scale.x, Grid.UNIT / world_scale.y, Grid.UNIT / world_scale.z)
	_build_shell(dimensions, view)
	_build_details(view, dimensions)
	for child in get_children():
		if child is MultiMeshInstance3D or (child is MeshInstance3D and child.mesh is ArrayMesh):
			child.position = child.position.snapped(_unit)
	return true

func _build_shell(dimensions: Vector3, view: Dictionary) -> void:
	var material_id := str(view.get("material_id", "stone_plaster"))
	var wall_color := WALL_COLOR
	if material_id == "warm_plaster": wall_color = Color("#d5a982")
	elif material_id == "timber": wall_color = Color("#9c684d")
	elif material_id == "pale_stone": wall_color = Color("#b9aa96")
	elif material_id == "chalk_white": wall_color = Color("#e8e2d5")
	elif material_id == "moss_stone": wall_color = Color("#a5b19b")
	elif material_id == "rose_lime": wall_color = Color("#d7aaa0")
	_add_box("Foundation", Vector3(dimensions.x + 0.5, 0.6, dimensions.z + 0.5), Vector3(0, 0.3, 0), STONE_COLOR)
	var deleted := {}
	for surface_value in view.get("surfaces", []):
		var surface: Dictionary = surface_value
		if str(surface.get("kind", "wall")) == "wall": deleted[str(surface.get("orientation", ""))] = bool(surface.get("deleted", false))
	for orientation in ["front", "back", "left", "right"]:
		if not bool(deleted.get(orientation, false)): _build_wall(orientation, dimensions, view, wall_color)
	# Complete, disjoint grid courses replace different colours rounded into
	# the very same trim cells. The physical miniature scale is unchanged.
	var eave := snappedf(dimensions.y, _unit.y)
	for side in [-1.0, 1.0]:
		var z: float = side * (snappedf(dimensions.z * 0.5, _unit.z) + _unit.z * 0.5)
		_add_box("Trim_%s" % side, Vector3(dimensions.x, _unit.y, _unit.z), Vector3(0, eave - _unit.y * 2.5, z), TRIM_COLOR)
		_add_box("Cornice_%s" % side, Vector3(dimensions.x, _unit.y, _unit.z), Vector3(0, eave - _unit.y * 1.5, z), CORNICE_COLOR)
	var roof_angle := atan2(dimensions.y * 0.42, dimensions.z * 0.5)
	_build_roof_tile_batches(dimensions, roof_angle)
	if not bool(deleted.get("left", false)): _build_door(dimensions)
	var rise := dimensions.y * 0.42
	var gable_run := dimensions.z * 0.5 + 0.45
	var row_height := _unit.y
	var row_count := maxi(1, ceili(rise / row_height))
	for step in row_count:
		var level := dimensions.y + row_height * (float(step) + 0.5)
		var ratio := clampf((level + row_height * 0.5 - dimensions.y) / rise, 0.0, 1.0)
		var span := maxf(0.12, gable_run * 2.0 * (1.0 - ratio) - 0.12)
		_add_box("GableLeft_%d" % step, Vector3(0.22, row_height, span), Vector3(-dimensions.x * 0.5, level, 0), wall_color)
		_add_box("GableRight_%d" % step, Vector3(0.22, row_height, span), Vector3(dimensions.x * 0.5, level, 0), wall_color)
	_build_corner_quoin_batch(dimensions)
	_build_crafted_shell(dimensions, wall_color)
	_build_entrance_canopy(dimensions, deleted)

func _build_roof_tile_batches(dimensions: Vector3, _roof_angle: float) -> void:
	var buckets: Array = [[], [], []]
	var run := dimensions.z * 0.5 + 0.5
	var rise := dimensions.y * 0.42
	var dx := _unit.x * 2.0
	var dz := _unit.z
	var span := dimensions.x + 0.75
	var nx := ceili(span / dx)
	var nz := ceili(run / dz)
	for side in [-1.0, 1.0]:
		for row in nz:
			var z := (float(row) + 0.5) * dz
			var height := snappedf(dimensions.y + rise * (1.0 - z / run), _unit.y)
			for column in nx:
				var x := -snappedf(span * 0.5, _unit.x) + (column + 0.5) * dx
				var shade := (column / 9 + row / 7) % 3
				buckets[shade].append(_piece(Vector3(x, height, side * z), Vector3(dx, _unit.y * 2.0, dz)))
	for shade in 3: _add_instanced_boxes("RoofTiles_%d" % shade, buckets[shade], ROOF_TILE_COLORS[shade])

func _build_corner_quoin_batch(dimensions: Vector3) -> void:
	var boxes: Array = []
	for corner_x in [-1, 1]:
		for corner_z in [-1, 1]:
			for level in 3:
				boxes.append(_piece(Vector3(dimensions.x * 0.5 * corner_x, 0.9 + float(level) * 1.45, dimensions.z * 0.5 * corner_z), Vector3(0.30, 0.70, 0.30)))
	_add_batched_boxes("CornerQuoins", boxes, QUOIN_COLOR)

func _build_details(view: Dictionary, dimensions: Vector3) -> void:
	var window_material := StandardMaterial3D.new()
	window_material.albedo_color = WINDOW_COLOR
	window_material.emission_enabled = false
	window_material.emission = Color(0.55, 0.28, 0.08)
	var surface_orientations := {}
	for surface_value in view.get("surfaces", []):
		var surface: Dictionary = surface_value
		surface_orientations[str(surface.get("id", ""))] = str(surface.get("orientation", "front"))
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("kind", "")) != "window" or not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)): continue
		var local = detail.get("resolved_position", null)
		if not local is Vector3: continue
		var anchor: Dictionary = detail.get("anchor", {})
		var orientation := str(surface_orientations.get(str(anchor.get("surface_id", "")), "front"))
		_build_window(detail, local, orientation, window_material)
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("kind", "")) != "shutter" or not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)): continue
		var local = detail.get("resolved_position", null)
		if not local is Vector3: continue
		var orientation := str(surface_orientations.get(str(detail.get("anchor", {}).get("surface_id", "")), "front"))
		var pieces: Array = [_piece(Vector3(0, 0, 0.15), Vector3(0.66, 2.9, 0.16))]
		for row in 9: pieces.append(_piece(Vector3(0, -1.2 + row * 0.3, 0.3), Vector3(0.55, 0.1, 0.12)))
		var shutter := _add_instanced_boxes("ManualShutter_%s" % detail["id"], pieces, SHUTTER_COLOR)
		shutter.transform = Transform3D(_surface_basis(orientation), local)
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("kind", "")) != "flower_box" or not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)): continue
		var local = detail.get("resolved_position", null)
		if local is Vector3:
			var orientation := str(surface_orientations.get(str(detail.get("anchor", {}).get("surface_id", "")), "front"))
			var basis := _surface_basis(orientation)
			var id := str(detail.get("id", ""))
			var trough := _add_batched_boxes("FlowerBox_%s" % id, [
				_piece(Vector3(0, -0.12, 0.32), Vector3(1.6, 0.12, 0.64)),
				_piece(Vector3(0, 0.03, 0.60), Vector3(1.6, 0.30, 0.12)),
				_piece(Vector3(-0.74, 0.03, 0.32), Vector3(0.12, 0.30, 0.64)),
				_piece(Vector3(0.74, 0.03, 0.32), Vector3(0.12, 0.30, 0.64))], SHUTTER_COLOR)
			trough.transform = Transform3D(basis, local)
			var blooms: Array = []
			var leaves: Array = []
			for i in 7:
				leaves.append(_piece(Vector3(-0.6 + i * 0.2, 0.18, 0.32), Vector3(0.24, 0.25, 0.34)))
				blooms.append(_piece(Vector3(-0.6 + i * 0.2, 0.33 + float(i % 2) * 0.08, 0.32), Vector3(0.15, 0.12, 0.18)))
			var foliage := _add_batched_boxes("BoxFoliage_%s" % id, leaves, Color("#597d48"))
			foliage.transform = Transform3D(basis, local)
			var flowers := _add_batched_boxes("BoxFlowers_%s" % id, blooms, FLOWER_COLOR)
			flowers.transform = Transform3D(basis, local)

func _surface_basis(orientation: String) -> Basis:
	if orientation == "front": return Basis(Vector3.UP, PI)
	if orientation == "left": return Basis(Vector3.UP, -PI * 0.5)
	if orientation == "right": return Basis(Vector3.UP, PI * 0.5)
	return Basis.IDENTITY

func _window_layout(detail: Dictionary, local: Vector3, orientation: String) -> Dictionary:
	var basis := _surface_basis(orientation)
	var rounded := str(detail.get("asset_id", "window_wood")).contains("round")
	var pane_requested := Vector3(1.0, 1.0, 0.10) if rounded else Vector3(2.0, 2.8, 0.10)
	var pane_quantized := Grid.quantized_box(Vector3.ZERO, pane_requested, _unit)
	var surface_local := basis.inverse() * local
	var snapped_surface := Vector3(snappedf(surface_local.x, _unit.x), snappedf(surface_local.y, _unit.y), surface_local.z)
	var pane_size: Vector3 = pane_quantized["size"]
	return {"basis": basis, "rounded": rounded, "anchor_center": basis * snapped_surface, "surface_center": Vector2(snapped_surface.x, snapped_surface.y), "pane_size": pane_size, "opening_half": Vector2(pane_size.x, pane_size.y) * 0.5}

func _add_box(node_name: String, size: Vector3, local_position: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new()
	var q := Grid.quantized_box(local_position, size, _unit)
	mesh.size = q["size"]
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.material_override = material
	node.position = q["center"]
	add_child(node)
	return node

func _build_window(detail: Dictionary, local: Vector3, orientation: String, window_material: StandardMaterial3D) -> void:
	var id := str(detail.get("id", "window"))
	var layout := _window_layout(detail, local, orientation)
	var rounded: bool = bool(layout["rounded"])
	var basis: Basis = layout["basis"]
	var anchor_center: Vector3 = layout["anchor_center"]
	var pane_size: Vector3 = layout["pane_size"]
	var node := MeshInstance3D.new()
	node.name = "Detail_%s" % id
	var pane := BoxMesh.new()
	pane.size = pane_size
	node.mesh = pane
	node.material_override = window_material
	node.transform = Transform3D(basis, anchor_center + basis * Vector3(0, 0, -_unit.z))
	add_child(node)
	var pale: Array = []
	var timber: Array = []
	var shutters: Array = []
	var half := Vector2(pane_size.x, pane_size.y) * 0.5
	# Distinct coloured pieces occupy distinct grid cells, not competing faces.
	if rounded:
		for x in range(-2, 2):
			for y in range(-2, 2):
				if x in [-1, 0] and y in [-1, 0]: continue
				if x in [-2, 1] and y in [-2, 1]: continue
				pale.append(_piece(Vector3((x + 0.5) * _unit.x, (y + 0.5) * _unit.y, _unit.z * 0.5), _unit))
	else:
		for side in [-1.0, 1.0]:
			pale.append(_piece(Vector3(side * (half.x + _unit.x * 0.5), 0, _unit.z * 0.5), Vector3(_unit.x, pane_size.y, _unit.z)))
			pale.append(_piece(Vector3(0, side * (half.y + _unit.y * 0.5), _unit.z * 0.5), Vector3(pane_size.x + 2.0 * _unit.x, _unit.y, _unit.z)))
			if bool(detail.get("show_shutters", true)):
				var x: float = side * (half.x + _unit.x * 1.5)
				shutters.append(_piece(Vector3(x, 0, _unit.z * 0.5), Vector3(_unit.x, pane_size.y - _unit.y * 2.0, _unit.z)))
				for end in [-1.0, 1.0]:
					timber.append(_piece(Vector3(x, end * (half.y - _unit.y * 0.5), _unit.z * 0.5), _unit))
		pale.append(_piece(Vector3(0, -half.y - _unit.y * 0.5, _unit.z * 1.5), Vector3(pane_size.x + _unit.x * 2.0, _unit.y, _unit.z)))
	timber.append(_piece(Vector3(0, 0, _unit.z * 0.5), Vector3(_unit.x, pane_size.y, _unit.z)))
	timber.append(_piece(Vector3(0, 0, _unit.z * 0.5), Vector3(pane_size.x, _unit.y, _unit.z)))
	for entry in [["Reveal", pale, CORNICE_COLOR], ["Joinery", timber, TRIM_COLOR], ["Shutters", shutters, SHUTTER_COLOR]]:
		if entry[1].is_empty(): continue
		var batch := _add_batched_boxes("%s_%s" % [entry[0], id], entry[1], entry[2])
		batch.transform = Transform3D(basis, anchor_center)

func _piece(center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> Dictionary:
	return {"center": center, "size": size, "basis": basis}

func _build_wall(orientation: String, dimensions: Vector3, view: Dictionary, color: Color) -> void:
	var basis := _surface_basis(orientation)
	var span := dimensions.x if orientation in ["front", "back"] else dimensions.z
	var normal_distance := dimensions.z * 0.5 if orientation in ["front", "back"] else dimensions.x * 0.5
	var origin := basis * Vector3(0, 0, normal_distance)
	var cuts: Array[Rect2] = []
	var surface_ids: Array[String] = []
	for surface in view.get("surfaces", []):
		if str(surface.get("orientation", "")) == orientation: surface_ids.append(str(surface.get("id", "")))
	for detail in view.get("details", []):
		if str(detail.get("kind", "")) != "window" or not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)): continue
		if not str(detail.get("anchor", {}).get("surface_id", "")) in surface_ids: continue
		var resolved = detail.get("resolved_position", null)
		if not resolved is Vector3: continue
		var layout := _window_layout(detail, resolved, orientation)
		var surface_center: Vector2 = layout["surface_center"]
		var opening_half: Vector2 = layout["opening_half"]
		cuts.append(Rect2(surface_center - opening_half, opening_half * 2.0))
	if orientation == "left": cuts.append(Rect2(-0.90, 0.6, 1.80, minf(3.7, dimensions.y - 1.0)))
	var xs: Array[float] = [-span * 0.5, span * 0.5]
	var ys: Array[float] = [0.6, dimensions.y]
	for cut in cuts:
		xs.append(clampf(cut.position.x, -span * 0.5, span * 0.5))
		xs.append(clampf(cut.end.x, -span * 0.5, span * 0.5))
		ys.append(clampf(cut.position.y, 0.6, dimensions.y))
		ys.append(clampf(cut.end.y, 0.6, dimensions.y))
	xs.sort()
	ys.sort()
	var pieces: Array = []
	for x in xs.size() - 1:
		for y in ys.size() - 1:
			var middle := Vector2((xs[x] + xs[x+1]) * 0.5, (ys[y] + ys[y+1]) * 0.5)
			var opening := false
			for cut in cuts:
				if cut.has_point(middle): opening = true; break
			if opening or xs[x+1] - xs[x] < 0.001 or ys[y+1] - ys[y] < 0.001: continue
			pieces.append(_piece(Vector3(middle.x, middle.y, -0.22), Vector3(xs[x+1]-xs[x], ys[y+1]-ys[y], 0.44)))
	var wall := _add_batched_boxes("Wall%s" % orientation.capitalize(), pieces, color)
	wall.transform = Transform3D(basis, origin)

func _build_door(dimensions: Vector3) -> void:
	var x := -dimensions.x * 0.5
	var height := minf(3.7, dimensions.y - 1.0)
	_add_box("Door", Vector3(0.12, height, 1.74), Vector3(x + 0.10, height * 0.5 + 0.6, 0), SHUTTER_COLOR)
	var frame: Array = []
	var wood: Array = []
	for side in [-1.0, 1.0]: frame.append(_piece(Vector3(x - 0.07, height * 0.5 + 0.6, side * 1.02), Vector3(0.52, height + 0.34, 0.24)))
	frame.append(_piece(Vector3(x - 0.07, height + 0.72, 0), Vector3(0.54, 0.28, 2.3)))
	for plank in 6: wood.append(_piece(Vector3(x - 0.02, height * 0.5 + 0.6, -0.72 + plank * 0.29), Vector3(0.06, height - 0.14, 0.035)))
	for y in [1.0, height - 0.10]: wood.append(_piece(Vector3(x - 0.10, y, 0), Vector3(0.12, 0.14, 1.62)))
	wood.append(_piece(Vector3(x - 0.18, 2.05, 0.53), Vector3(0.16, 0.12, 0.12)))
	for step in 3: frame.append(_piece(Vector3(x - 0.36 - step * 0.28, 0.50 - step * 0.16, 0), Vector3(0.42, 0.18, 2.5 + step * 0.12)))
	_add_batched_boxes("DoorSurround", frame, CORNICE_COLOR)
	_add_batched_boxes("DoorJoinery", wood, TRIM_COLOR)

func _build_crafted_shell(dimensions: Vector3, _color: Color) -> void:
	var stone: Array = []
	var timber: Array = []
	var eave := snappedf(dimensions.y, _unit.y)
	var foundation := Grid.quantized_box(Vector3(0, 0.3, 0), Vector3(dimensions.x + 0.5, 0.6, dimensions.z + 0.5), _unit)
	var foundation_half: Vector3 = foundation["size"] * 0.5
	var foundation_center: Vector3 = foundation["center"]
	for side in [-1.0, 1.0]:
		stone.append(_piece(Vector3(foundation_center.x, _unit.y * 0.5, foundation_center.z + side * (foundation_half.z + _unit.z * 0.5)), Vector3(foundation_half.x * 2.0, _unit.y, _unit.z)))
		stone.append(_piece(Vector3(foundation_center.x + side * (foundation_half.x + _unit.x * 0.5), _unit.y * 0.5, foundation_center.z), Vector3(_unit.x, _unit.y, foundation_half.z * 2.0)))
		for i in ceili(dimensions.x / (_unit.x * 3.0)):
			var x := -snappedf(dimensions.x * 0.5, _unit.x) + (i * 3.0 + 0.5) * _unit.x
			var z: float = side * (snappedf(dimensions.z * 0.5, _unit.z) + _unit.z * 1.5)
			timber.append(_piece(Vector3(x, eave - _unit.y * 1.5, z), _unit))
		var end_x: float = side * (snappedf((dimensions.x + 0.75) * 0.5, _unit.x) + _unit.x * 0.5)
		timber.append(_piece(Vector3(end_x, eave + _unit.y * 0.5, 0), Vector3(_unit.x, _unit.y, dimensions.z)))
		timber.append(_piece(Vector3(end_x, eave + dimensions.y * 0.21, 0), Vector3(_unit.x, dimensions.y * 0.42, _unit.z)))
	_add_batched_boxes("FoundationCourses", stone, QUOIN_COLOR)
	_add_batched_boxes("EaveJoinery", timber, TRIM_COLOR)
	# A single crest begins above the actual highest roof top, replacing three
	# separately rounded ridge layers with conflicting colours at identical depth.
	var run := dimensions.z * 0.5 + 0.5
	var top := snappedf(dimensions.y + dimensions.y * 0.42 * (1.0 - _unit.z * 0.5 / run), _unit.y) + _unit.y
	_add_box("RidgeCourses", Vector3(dimensions.x + 0.75, _unit.y, _unit.z * 2.0), Vector3(0, top + _unit.y * 0.5, 0), ROOF_TILE_COLORS[2])

func _add_batched_boxes(node_name: String, boxes: Array, color: Color) -> GeometryInstance3D:
	if not node_name.begins_with("Wall"): return _add_instanced_boxes(node_name, boxes, color)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for box_value in boxes:
		var box: Dictionary = box_value
		var quantized := Grid.quantized_box(box["center"], box["size"], _unit)
		_append_box_geometry(vertices, normals, indices, quantized["center"], quantized["size"], box["basis"])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if not vertices.is_empty(): mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.material_override = material
	add_child(node)
	return node

func _append_box_geometry(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, center: Vector3, size: Vector3, basis: Basis) -> void:
	var half := size * 0.5
	var corners: Array[Vector3] = [Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z), Vector3(half.x, half.y, -half.z), Vector3(-half.x, half.y, -half.z), Vector3(-half.x, -half.y, half.z), Vector3(half.x, -half.y, half.z), Vector3(half.x, half.y, half.z), Vector3(-half.x, half.y, half.z)]
	var faces: Array = [[0, 3, 2, 1, Vector3(0, 0, -1)], [4, 5, 6, 7, Vector3(0, 0, 1)], [0, 1, 5, 4, Vector3(0, -1, 0)], [3, 7, 6, 2, Vector3(0, 1, 0)], [0, 4, 7, 3, Vector3(-1, 0, 0)], [1, 2, 6, 5, Vector3(1, 0, 0)]]
	for face in faces:
		var base: int = vertices.size()
		var normal: Vector3 = basis * (face[4] as Vector3)
		for corner_index in 4: vertices.append(center + basis * corners[int(face[corner_index])]); normals.append(normal)
		indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))

func _build_entrance_canopy(dimensions: Vector3, deleted: Dictionary) -> void:
	if bool(deleted.get("left", false)): return
	var x := -dimensions.x * 0.5
	var y := minf(4.8, dimensions.y - 0.25)
	var timber: Array = []
	var tiles: Array = []
	for side in [-1.0, 1.0]:
		timber.append(_piece(Vector3(x - 0.35, y - 0.40, side * 1.45), Vector3(0.20, 0.9, 0.18)))
		for step in 4: timber.append(_piece(Vector3(x - 0.25 - step * 0.25, y - 0.7 + step * 0.25, side * 1.45), Vector3(0.25, 0.25, 0.25)))
	for row in 5:
		for column in 10: tiles.append(_piece(Vector3(x - 0.13 - row * 0.24, y - row * 0.11, -1.65 + column * 0.36), Vector3(0.29, 0.14, 0.34)))
	_add_batched_boxes("PorchBrackets", timber, TRIM_COLOR)
	_add_batched_boxes("PorchTileCourses", tiles, ROOF_TILE_COLORS[1])
	var vent: Array = []
	for row in 7:
		var width := 1.0 - absf(float(row) - 3.0) * 0.13
		vent.append(_piece(Vector3(x - 0.17, dimensions.y + 0.35 + row * 0.17, -2.0), Vector3(0.22, 0.13, width)))
	_add_batched_boxes("GableVent", vent, SHUTTER_COLOR)

func _add_instanced_boxes(node_name: String, boxes: Array, color: Color) -> MultiMeshInstance3D:
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = cube
	multi.instance_count = boxes.size()
	for i in boxes.size():
		var piece: Dictionary = boxes[i]
		var basis: Basis = piece["basis"]
		var q := Grid.quantized_box(piece["center"], piece["size"], _unit)
		multi.set_instance_transform(i, Transform3D(basis.scaled_local(q["size"]), q["center"]))
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multi
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.material_override = material
	add_child(node)
	return node
