extends Node3D
class_name CottageVisual

## Small procedural renderer for one authoritative building recipe. Geometry is
## disposable; IDs, states, anchors and revisions remain in BuildingWorld.

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

func request_revision(revision: int) -> void:
	requested_revision = maxi(requested_revision, revision)

func apply_building(view: Dictionary, source_revision: int) -> bool:
	if requested_revision < 0: requested_revision = source_revision
	if source_revision != requested_revision or source_revision < applied_revision: return false
	if view.is_empty(): return false
	for child in get_children(): child.free()
	building_id = str(view.get("id", ""))
	applied_revision = source_revision
	var dimensions: Vector3 = view.get("dimensions", Vector3(18, 10, 14))
	var transform_value = view.get("transform", Transform3D.IDENTITY)
	var building_transform: Transform3D = transform_value if transform_value is Transform3D else Transform3D.IDENTITY
	# Preserve the authored transform as a whole.  Rotation and scale are part
	# of the document identity and must affect every generated child equally.
	transform = building_transform
	_build_shell(dimensions, view)
	_build_details(view, dimensions)
	return true

func _build_shell(dimensions: Vector3, view: Dictionary) -> void:
	var material_id := str(view.get("material_id", "stone_plaster"))
	var wall_color := WALL_COLOR
	if material_id == "warm_plaster": wall_color = Color("#d5a982")
	elif material_id == "timber": wall_color = Color("#9c684d")
	elif material_id == "pale_stone": wall_color = Color("#b9aa96")
	_add_box("Foundation", Vector3(dimensions.x + 0.5, 0.6, dimensions.z + 0.5), Vector3(0, 0.3, 0), STONE_COLOR)
	var deleted := {}
	for surface_value in view.get("surfaces", []):
		var surface: Dictionary = surface_value
		if str(surface.get("kind", "wall")) == "wall": deleted[str(surface.get("orientation", ""))] = bool(surface.get("deleted", false))
	for orientation in ["front", "back", "left", "right"]:
		if not bool(deleted.get(orientation, false)):
			_build_wall(orientation, dimensions, view, wall_color)
	_add_box("FrontTrim", Vector3(dimensions.x + 0.2, 0.18, 0.22), Vector3(0, dimensions.y - 0.75, -dimensions.z * 0.5 - 0.08), TRIM_COLOR)
	_add_box("BackTrim", Vector3(dimensions.x + 0.2, 0.18, 0.22), Vector3(0, dimensions.y - 0.75, dimensions.z * 0.5 + 0.08), TRIM_COLOR)
	_add_box("FrontCornice", Vector3(dimensions.x + 0.3, 0.16, 0.28), Vector3(0, dimensions.y - 0.68, -dimensions.z * 0.5 - 0.18), CORNICE_COLOR)
	_add_box("BackCornice", Vector3(dimensions.x + 0.3, 0.16, 0.28), Vector3(0, dimensions.y - 0.68, dimensions.z * 0.5 + 0.18), CORNICE_COLOR)
	var roof_run := dimensions.z * 0.5 + 0.45
	var roof_angle := atan2(dimensions.y * 0.42, dimensions.z * 0.5)
	var roof_length := sqrt(roof_run * roof_run + (dimensions.y * 0.42) * (dimensions.y * 0.42))
	var left := _add_box("RoofLeft", Vector3(dimensions.x + 0.7, 0.35, roof_length), Vector3(0, dimensions.y + dimensions.y * 0.21, -roof_run * 0.5), ROOF_COLOR)
	left.rotation.x = -roof_angle
	var right := _add_box("RoofRight", Vector3(dimensions.x + 0.7, 0.35, roof_length), Vector3(0, dimensions.y + dimensions.y * 0.21, roof_run * 0.5), ROOF_COLOR)
	right.rotation.x = roof_angle
	_add_box("RidgeTrim", Vector3(dimensions.x + 0.8, 0.22, 0.24), Vector3(0, dimensions.y + dimensions.y * 0.42, 0), TRIM_COLOR)
	_add_box("RidgeCap", Vector3(dimensions.x + 0.82, 0.16, 0.34), Vector3(0, dimensions.y + dimensions.y * 0.43, 0), CORNICE_COLOR)
	_build_roof_tile_batches(dimensions, roof_angle)
	if not bool(deleted.get("left", false)):
		_build_door(dimensions)
	# The ridge follows X, so the stepped gable infill belongs on the two
	# narrow X ends. Derive each quarter-unit row from the actual roof triangle
	# so there are no teeth outside the slope or an open gap below the ridge.
	var eave_y := dimensions.y
	var rise := dimensions.y * 0.42
	var gable_run := dimensions.z * 0.5 + 0.45
	var row_height := 0.25
	var row_count := maxi(1, ceili(rise / row_height))
	for step in row_count:
		var level := eave_y + row_height * (float(step) + 0.5)
		var row_top := level + row_height * 0.5
		var ratio := clampf((row_top - eave_y) / rise, 0.0, 1.0)
		var span := maxf(0.12, gable_run * 2.0 * (1.0 - ratio) - 0.12)
		_add_box("GableLeft_%d" % step, Vector3(0.22, row_height + 0.015, span), Vector3(-dimensions.x * 0.5, level, 0), wall_color)
		_add_box("GableRight_%d" % step, Vector3(0.22, row_height + 0.015, span), Vector3(dimensions.x * 0.5, level, 0), wall_color)
	_build_corner_quoin_batch(dimensions)
	_build_crafted_shell(dimensions, wall_color)
	_build_entrance_canopy(dimensions, deleted)

func _build_roof_tile_batches(dimensions: Vector3, roof_angle: float) -> void:
	# Each roof half is one ArrayMesh per palette shade. This keeps the repeated
	# stepped tile treatment cheap while preserving a deterministic silhouette.
	var roof_run := dimensions.z * 0.5 + 0.45
	var roof_rise := dimensions.y * 0.42
	var roof_length := sqrt(roof_run * roof_run + roof_rise * roof_rise)
	var row_count := mini(40, maxi(1, ceili(roof_length / 0.56)))
	var span := dimensions.x + 0.58
	var segment_count := mini(64, maxi(1, ceili(span / 0.5)))
	var row_step := roof_length / float(row_count)
	var tile_depth := maxf(0.28, row_step * 0.92)
	var tile_thickness := 0.13
	for side in [-1, 1]:
		var buckets: Array = [[], [], []]
		var roof_basis := Basis(Vector3.RIGHT, roof_angle * float(side))
		var roof_origin := Vector3(0, dimensions.y + dimensions.y * 0.21, roof_run * 0.5 * float(side))
		for row in row_count:
			# The authored roof box has the same origin, angle and local Z span as
			# this batch. A positive local Y offset places tile bottoms directly on
			# its top face, avoiding a second hand-maintained slope equation.
			var local_z := float(side) * (roof_length * 0.5 - (float(row) + 0.5) * row_step)
			var tile_width := span / float(segment_count) - 0.035
			for segment in segment_count:
				var center_x := -span * 0.5 + (float(segment) + 0.5) * span / float(segment_count)
				var bucket: Array = buckets[(segment / 7 + row / 5) % 3]
				var local_center := Vector3(center_x, 0.175 + tile_thickness * 0.5 + 0.02, local_z)
				bucket.append({"center": roof_origin + roof_basis * local_center, "size": Vector3(tile_width, tile_thickness, tile_depth), "basis": roof_basis})
				buckets[(segment / 7 + row / 5) % 3] = bucket
		for shade in 3:
			var batch: Array = buckets[shade]
			var shade_color: Color = ROOF_TILE_COLORS[shade]
			_add_instanced_boxes("RoofTiles_%s_%d" % ["Left" if side < 0 else "Right", shade], batch, shade_color)

func _build_corner_quoin_batch(dimensions: Vector3) -> void:
	var boxes: Array = []
	var half_x := dimensions.x * 0.5
	var half_z := dimensions.z * 0.5
	for corner_x in [-1, 1]:
		for corner_z in [-1, 1]:
			for level in 3:
				var y := 0.9 + float(level) * 1.45
				boxes.append({"center": Vector3(half_x * float(corner_x), y, half_z * float(corner_z)), "size": Vector3(0.30, 0.70, 0.30), "basis": Basis.IDENTITY})
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
		var surface_id := str(anchor.get("surface_id", ""))
		var orientation := str(surface_orientations.get(surface_id, "front"))
		var basis := Basis.IDENTITY
		if orientation == "front": basis = Basis(Vector3.UP, PI)
		elif orientation == "left": basis = Basis(Vector3.UP, -PI * 0.5)
		elif orientation == "right": basis = Basis(Vector3.UP, PI * 0.5)
		_build_window(detail, local, basis, window_material)
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("kind", "")) != "flower_box" or not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)): continue
		var local = detail.get("resolved_position", null)
		if local is Vector3:
			var anchor: Dictionary = detail.get("anchor", {})
			var orientation := str(surface_orientations.get(str(anchor.get("surface_id", "")), "front"))
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

func _add_box(node_name: String, size: Vector3, local_position: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.material_override = material
	node.position = local_position
	add_child(node)
	return node

func _build_window(detail: Dictionary, local: Vector3, basis: Basis, window_material: StandardMaterial3D) -> void:
	var id := str(detail.get("id", "window"))
	var rounded := str(detail.get("asset_id", "window_wood")).contains("round")
	var node := MeshInstance3D.new()
	node.name = "Detail_%s" % id
	if rounded:
		var disc := CylinderMesh.new()
		disc.top_radius = 0.54; disc.bottom_radius = 0.54; disc.height = 0.10; disc.radial_segments = 12
		node.mesh = disc
	else:
		var pane := BoxMesh.new(); pane.size = Vector3(2.0, 2.8, 0.10); node.mesh = pane
	node.material_override = window_material
	node.transform = Transform3D(basis, local + basis * Vector3(0, 0, -0.20))
	if rounded: node.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	add_child(node)
	var pale: Array = []
	var timber: Array = []
	var shutters: Array = []
	if rounded:
		# Twelve stepped voussoirs retain the voxel character of the replacement.
		for i in 12:
			var angle := TAU * float(i) / 12.0
			pale.append(_piece(Vector3(snappedf(cos(angle) * 0.64, 0.1), snappedf(sin(angle) * 0.64, 0.1), 0.02), Vector3(0.24, 0.24, 0.34)))
		timber.append(_piece(Vector3(0, 0, -0.08), Vector3(0.08, 1.02, 0.10)))
		timber.append(_piece(Vector3(0, 0, -0.08), Vector3(1.02, 0.08, 0.10)))
	else:
		for side in [-1.0, 1.0]:
			pale.append(_piece(Vector3(side * 1.12, 0, 0.0), Vector3(0.24, 3.2, 0.50)))
			pale.append(_piece(Vector3(0, side * 1.51, 0.0), Vector3(2.48, 0.24, 0.50)))
			timber.append(_piece(Vector3(side * 0.96, 0, -0.10), Vector3(0.12, 2.8, 0.16)))
			# Shutters open against the facade, with recessed slats and end rails.
			shutters.append(_piece(Vector3(side * 1.58, 0, 0.12), Vector3(0.66, 2.9, 0.16)))
			for row in 9:
				shutters.append(_piece(Vector3(side * 1.58, -1.22 + row * 0.30, 0.23), Vector3(0.55, 0.10, 0.12)))
			for y in [-1.27, 1.27]:
				timber.append(_piece(Vector3(side * 1.58, y, 0.24), Vector3(0.66, 0.10, 0.10)))
		timber.append(_piece(Vector3(0, 0, -0.06), Vector3(0.11, 2.8, 0.16)))
		timber.append(_piece(Vector3(0, 0.12, -0.06), Vector3(1.98, 0.10, 0.16)))
		pale.append(_piece(Vector3(0, -1.72, 0.16), Vector3(2.75, 0.18, 0.85)))
		for x in [-0.75, 0.75]:
			pale.append(_piece(Vector3(x, -1.93, 0.08), Vector3(0.22, 0.28, 0.48)))
	for entry in [["Reveal", pale, CORNICE_COLOR], ["Joinery", timber, TRIM_COLOR], ["Shutters", shutters, SHUTTER_COLOR]]:
		if entry[1].is_empty(): continue
		var batch := _add_batched_boxes("%s_%s" % [entry[0], id], entry[1], entry[2])
		batch.transform = Transform3D(basis, local)

func _piece(center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> Dictionary:
	return {"center": center, "size": size, "basis": basis}

func _build_wall(orientation: String, dimensions: Vector3, view: Dictionary, color: Color) -> void:
	# Cut actual openings from the wall. The cuts follow resolved attachment
	# positions, so moving/suppressing an editable window also rebuilds its reveal.
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
		var position_in_wall: Vector3 = basis.inverse() * (resolved - origin)
		var half := Vector2(0.54, 0.54) if str(detail.get("asset_id", "")).contains("round") else Vector2(1.02, 1.42)
		cuts.append(Rect2(Vector2(position_in_wall.x, position_in_wall.y) - half, half * 2.0))
	if orientation == "left": cuts.append(Rect2(-0.90, 0.6, 1.80, minf(3.7, dimensions.y - 1.0)))
	var xs: Array[float] = [-span * 0.5, span * 0.5]
	var ys: Array[float] = [0.6, dimensions.y]
	for cut in cuts:
		xs.append(clampf(cut.position.x, -span * 0.5, span * 0.5)); xs.append(clampf(cut.end.x, -span * 0.5, span * 0.5))
		ys.append(clampf(cut.position.y, 0.6, dimensions.y)); ys.append(clampf(cut.end.y, 0.6, dimensions.y))
	xs.sort(); ys.sort()
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
	for side in [-1.0, 1.0]:
		frame.append(_piece(Vector3(x - 0.07, height * 0.5 + 0.6, side * 1.02), Vector3(0.52, height + 0.34, 0.24)))
	frame.append(_piece(Vector3(x - 0.07, height + 0.72, 0), Vector3(0.54, 0.28, 2.3)))
	for plank in 6:
		wood.append(_piece(Vector3(x - 0.02, height * 0.5 + 0.6, -0.72 + plank * 0.29), Vector3(0.06, height - 0.14, 0.035)))
	for y in [1.0, height - 0.10]: wood.append(_piece(Vector3(x - 0.10, y, 0), Vector3(0.12, 0.14, 1.62)))
	wood.append(_piece(Vector3(x - 0.18, 2.05, 0.53), Vector3(0.16, 0.12, 0.12)))
	for step in 3:
		frame.append(_piece(Vector3(x - 0.36 - step * 0.28, 0.50 - step * 0.16, 0), Vector3(0.42, 0.18, 2.5 + step * 0.12)))
	_add_batched_boxes("DoorSurround", frame, CORNICE_COLOR)
	_add_batched_boxes("DoorJoinery", wood, TRIM_COLOR)

func _build_crafted_shell(dimensions: Vector3, _color: Color) -> void:
	var stone: Array = []
	var timber: Array = []
	var roof: Array = []
	# Fine, long foundation courses ground the cottage; bounded repeating pieces.
	for side in [-1.0, 1.0]:
		for row in 3:
			for i in ceili(dimensions.x / 0.8):
				stone.append(_piece(Vector3(-dimensions.x * 0.5 + 0.4 + i * 0.8, 0.18 + row * 0.24, side * (dimensions.z * 0.5 + 0.12)), Vector3(0.75, 0.21, 0.26)))
			for i in ceili(dimensions.z / 0.8):
				stone.append(_piece(Vector3(side * (dimensions.x * 0.5 + 0.12), 0.18 + row * 0.24, -dimensions.z * 0.5 + 0.4 + i * 0.8), Vector3(0.26, 0.21, 0.75)))
		for i in ceili(dimensions.x / 1.15):
			timber.append(_piece(Vector3(-dimensions.x * 0.5 + 0.45 + i * 1.15, dimensions.y - 0.17, side * (dimensions.z * 0.5 + 0.25)), Vector3(0.18, 0.35, 0.80)))
		# Gable tie and king post make the end wall intentional at gameplay zoom.
		timber.append(_piece(Vector3(side * (dimensions.x * 0.5 + 0.15), dimensions.y + 0.1, 0), Vector3(0.28, 0.25, dimensions.z)))
		timber.append(_piece(Vector3(side * (dimensions.x * 0.5 + 0.15), dimensions.y * 1.20, 0), Vector3(0.24, dimensions.y * 0.4, 0.22)))
	for i in ceili((dimensions.x + 0.8) / 0.42):
		roof.append(_piece(Vector3(-dimensions.x * 0.5 - 0.2 + i * 0.42, dimensions.y * 1.42 + 0.29, 0), Vector3(0.39, 0.26, 0.48)))
	_add_batched_boxes("FoundationCourses", stone, QUOIN_COLOR)
	_add_batched_boxes("EaveJoinery", timber, TRIM_COLOR)
	_add_batched_boxes("RidgeCourses", roof, ROOF_TILE_COLORS[2])

func _add_batched_boxes(node_name: String, boxes: Array, color: Color) -> GeometryInstance3D:
	if not node_name.begins_with("Wall"):
		return _add_instanced_boxes(node_name, boxes, color)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for box_value in boxes:
		var box: Dictionary = box_value
		var box_center: Vector3 = box["center"]
		var box_size: Vector3 = box["size"]
		var box_basis: Basis = box["basis"]
		_append_box_geometry(vertices, normals, indices, box_center, box_size, box_basis)
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
	var corners: Array[Vector3] = [
		Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z), Vector3(half.x, half.y, -half.z), Vector3(-half.x, half.y, -half.z),
		Vector3(-half.x, -half.y, half.z), Vector3(half.x, -half.y, half.z), Vector3(half.x, half.y, half.z), Vector3(-half.x, half.y, half.z)
	]
	var faces: Array = [
		[0, 3, 2, 1, Vector3(0, 0, -1)], [4, 5, 6, 7, Vector3(0, 0, 1)],
		[0, 1, 5, 4, Vector3(0, -1, 0)], [3, 7, 6, 2, Vector3(0, 1, 0)],
		[0, 4, 7, 3, Vector3(-1, 0, 0)], [1, 2, 6, 5, Vector3(1, 0, 0)]
	]
	for face in faces:
		var base: int = vertices.size()
		var face_normal: Vector3 = face[4]
		var normal: Vector3 = basis * face_normal
		for corner_index in 4:
			var corner: Vector3 = corners[int(face[corner_index])]
			vertices.append(center + basis * corner)
			normals.append(normal)
		indices.append(base)
		indices.append(base + 2)
		indices.append(base + 1)
		indices.append(base)
		indices.append(base + 3)
		indices.append(base + 2)

func _build_entrance_canopy(dimensions: Vector3, deleted: Dictionary) -> void:
	if bool(deleted.get("left", false)): return
	var x := -dimensions.x * 0.5
	var y := minf(4.8, dimensions.y - 0.25)
	var timber: Array = []
	var tiles: Array = []
	for side in [-1.0, 1.0]:
		timber.append(_piece(Vector3(x - 0.35, y - 0.40, side * 1.45), Vector3(0.20, 0.9, 0.18)))
		timber.append(_piece(Vector3(x - 0.70, y - 0.25, side * 1.45), Vector3(1.0, 0.17, 0.18), Basis(Vector3.FORWARD, 0.45)))
	for row in 5:
		for column in 10:
			tiles.append(_piece(Vector3(x - 0.13 - row * 0.24, y - row * 0.11, -1.65 + column * 0.36), Vector3(0.29, 0.14, 0.34)))
	_add_batched_boxes("PorchBrackets", timber, TRIM_COLOR)
	_add_batched_boxes("PorchTileCourses", tiles, ROOF_TILE_COLORS[1])
	# A small stepped louvred gable vent, derived architectural joinery.
	var vent: Array = []
	for row in 7:
		var width := 1.0 - absf(float(row) - 3.0) * 0.13
		vent.append(_piece(Vector3(x - 0.17, dimensions.y + 0.35 + row * 0.17, -2.0), Vector3(0.22, 0.13, width)))
	_add_batched_boxes("GableVent", vent, SHUTTER_COLOR)

func _add_instanced_boxes(node_name: String, boxes: Array, color: Color) -> MultiMeshInstance3D:
	# Reuse native cube geometry; rebuilding a recipe uploads transforms, not
	# tens of thousands of GDScript-generated vertices. Six roof draw groups.
	var cube := BoxMesh.new(); cube.size = Vector3.ONE
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = cube
	multi.instance_count = boxes.size()
	for i in boxes.size():
		var piece: Dictionary = boxes[i]
		var basis: Basis = piece["basis"]
		multi.set_instance_transform(i, Transform3D(basis.scaled_local(piece["size"]), piece["center"]))
	var node := MultiMeshInstance3D.new()
	node.name = node_name; node.multimesh = multi
	var material := StandardMaterial3D.new(); material.albedo_color = color
	node.material_override = material
	add_child(node)
	return node
