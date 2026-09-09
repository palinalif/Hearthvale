extends Node3D
class_name CottageVisual

## Small procedural renderer for one authoritative building recipe. Geometry is
## disposable; IDs, states, anchors and revisions remain in BuildingWorld.
const Grid = preload("res://scripts/visual_grid.gd")
var _unit := Vector3.ONE * 0.25
var _detail_unit := Vector3.ONE * 0.125
var _craft_seed := 0
var _roof_rise_ratio := 0.42
var _roof_tile_colors: Array[Color] = [Color("#b9654c"), Color("#bf6c50"), Color("#c47457")]
var _roof_edge_color := Color("#b85f4b")
const WALL_COLOR := Color("#e7cfab")
const TRIM_COLOR := Color("#634d42")
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
	_detail_unit = _unit * (Grid.COTTAGE_DETAIL_UNIT / Grid.UNIT)
	_craft_seed = int(view.get("seed", 0))
	_roof_rise_ratio = {"swept_gable": 0.30, "steep_gable": 0.62}.get(str(view.get("roof_profile", "gentle_gable")), 0.42)
	_apply_roof_material(str(view.get("roof_material_id", "terracotta")))
	_build_shell(dimensions, view)
	_build_details(view, dimensions)
	for child in get_children():
		if child is MultiMeshInstance3D or (child is MeshInstance3D and child.mesh is ArrayMesh):
			child.position = child.position.snapped(_detail_unit if child.has_meta("cottage_detail_grid") else _unit)
	return true

func _build_shell(dimensions: Vector3, view: Dictionary) -> void:
	var material_id := str(view.get("wall_material_id", view.get("material_id", "stone_plaster")))
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
		_add_detail_boxes("Trim_%s" % side, [_piece(Vector3(0, eave - _unit.y * 2.5, z), Vector3(dimensions.x, _detail_unit.y, _unit.z))], TRIM_COLOR)
		_add_detail_boxes("Cornice_%s" % side, [_piece(Vector3(0, eave - _unit.y * 1.5, z), Vector3(dimensions.x, _detail_unit.y, _unit.z))], CORNICE_COLOR)
	var roof_angle := atan2(dimensions.y * _roof_rise_ratio, dimensions.z * 0.5)
	_build_roof_tile_batches(dimensions, roof_angle)
	var rise := dimensions.y * _roof_rise_ratio
	var gable_run := dimensions.z * 0.5 + 0.45
	var row_height := _unit.y
	var row_count := maxi(1, ceili(rise / row_height))
	for step in row_count:
		var level := dimensions.y + row_height * (float(step) + 0.5)
		var ratio := clampf((level + row_height * 0.5 - dimensions.y) / rise, 0.0, 1.0)
		var span := maxf(0.12, gable_run * 2.0 * (1.0 - ratio) - 0.12)
		_add_box("GableLeft_%d" % step, Vector3(0.22, row_height, span), Vector3(-dimensions.x * 0.5, level, 0), wall_color)
		_add_box("GableRight_%d" % step, Vector3(0.22, row_height, span), Vector3(dimensions.x * 0.5, level, 0), wall_color)
	if str(view.get("style_id", "riverside_cottage")) != "woodland_lodge": _build_corner_quoin_batch(dimensions)
	_build_crafted_shell(dimensions, wall_color)
	_build_gable_vent(dimensions, deleted)
	_build_style_accents(dimensions, str(view.get("style_id", "riverside_cottage")))

func _build_roof_tile_batches(dimensions: Vector3, _roof_angle: float) -> void:
	var buckets: Array = [[], [], []]
	var run := dimensions.z * 0.5 + 0.5
	var rise := dimensions.y * _roof_rise_ratio
	var dx := _detail_unit.x * 2.0
	var dz := _detail_unit.z
	var span := dimensions.x + 0.75
	var nx := ceili(span / dx)
	var nz := ceili(run / dz)
	for side in [-1.0, 1.0]:
		for row in nz:
			var z := (float(row) + 0.5) * dz
			var height := snappedf(dimensions.y + rise * (1.0 - z / run), _detail_unit.y)
			for column in nx:
				var x := -snappedf(span * 0.5, _detail_unit.x) + (column + 0.5) * dx
				# Preserve the broad, quiet colour rhythm while doubling geometry resolution.
				var shade := (column / 18 + row / 14) % 3
				buckets[shade].append(_piece(Vector3(x, height, side * z), Vector3(dx, _detail_unit.y * 2.0, dz)))
	for shade in 3: _add_detail_boxes("RoofTiles_%d" % shade, buckets[shade], _roof_tile_colors[shade])

func _build_corner_quoin_batch(dimensions: Vector3) -> void:
	# Corner stones straddle both wall planes. Sub-cell widths rounded inward
	# onto the wall face and produced draw-order-dependent coplanar colours.
	var boxes: Array = []
	for corner_x in [-1, 1]:
		for corner_z in [-1, 1]:
			for level in 3:
				boxes.append(_piece(Vector3(dimensions.x * 0.5 * corner_x, 0.9 + float(level) * 1.45, dimensions.z * 0.5 * corner_z), Vector3(_unit.x * 2.0, 0.70, _unit.z * 2.0)))
	_add_batched_boxes("CornerQuoins", boxes, QUOIN_COLOR)

func _apply_roof_material(material_id: String) -> void:
	var palettes := {
		"terracotta": [Color("#b9654c"), Color("#bf6c50"), Color("#c47457")],
		"moss_tile": [Color("#66765d"), Color("#718164"), Color("#7c8c6c")],
		"slate": [Color("#59636d"), Color("#636e79"), Color("#6d7883")],
		"thatch": [Color("#aa8a52"), Color("#b6975c"), Color("#c1a468")],
	}
	var selected: Array = palettes.get(material_id, palettes["terracotta"])
	_roof_tile_colors = [selected[0], selected[1], selected[2]]
	_roof_edge_color = (_roof_tile_colors[0] as Color).darkened(0.12)

func _build_style_accents(dimensions: Vector3, style_id: String) -> void:
	if style_id == "woodland_lodge":
		var beams: Array = []
		for side in [-1.0, 1.0]:
			var z: float = side * (dimensions.z * 0.5 + _detail_unit.z * 0.5)
			beams.append(_piece(Vector3(0, dimensions.y * 0.58, z), Vector3(dimensions.x, _detail_unit.y * 2.0, _detail_unit.z)))
			for x_value in [-dimensions.x * 0.34, 0.0, dimensions.x * 0.34]: beams.append(_piece(Vector3(x_value, dimensions.y * 0.50, z), Vector3(_detail_unit.x * 2.0, dimensions.y * 0.72, _detail_unit.z)))
		_add_detail_boxes("LodgeTimberFrame", beams, TRIM_COLOR)
	elif style_id == "village_gable":
		var finials: Array = []
		var top := snappedf(dimensions.y + dimensions.y * _roof_rise_ratio, _detail_unit.y)
		for x_value in [-dimensions.x * 0.5, dimensions.x * 0.5]:
			for level in 4: finials.append(_piece(Vector3(x_value, top + (level + 0.5) * _detail_unit.y, 0), _detail_unit))
		_add_detail_boxes("GableFinials", finials, CORNICE_COLOR)

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
		var basis := _surface_basis(orientation)
		var cell := (basis.inverse() * _detail_unit).abs()
		var pieces := _shutter_pieces(0.0, 0.66, 2.9, cell, _craft_variant(detail))
		_add_detail_boxes("ManualShutter_%s" % detail["id"], pieces, SHUTTER_COLOR, basis, local)
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("kind", "")) != "flower_box" or not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)): continue
		var local = detail.get("resolved_position", null)
		if local is Vector3:
			var orientation := str(surface_orientations.get(str(detail.get("anchor", {}).get("surface_id", "")), "front"))
			_build_flower_box(detail, local, _surface_basis(orientation))
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("kind", "")) != "door" or not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)): continue
		var local = detail.get("resolved_position", null)
		if not local is Vector3: continue
		var orientation := str(surface_orientations.get(str(detail.get("anchor", {}).get("surface_id", "")), "left"))
		_build_door(detail, local, orientation)

func _craft_variant(detail: Dictionary) -> int:
	# Only recipe identities select craft; position/revision never reshuffle it.
	return posmod(("%s:%s:%s" % [_craft_seed, detail.get("id", ""), detail.get("asset_id", "")]).hash(), 3)

func _shutter_pieces(x: float, width: float, height: float, cell: Vector3, variant: int) -> Array:
	var pieces: Array = []
	var columns := maxi(1, floori(width / cell.x))
	var rows := maxi(4, roundi(height / cell.y))
	var left := snappedf(x - columns * cell.x * 0.5, cell.x)
	var bottom := -floorf(rows * 0.5) * cell.y
	# Back boards and shallow alternating slats retain a connected silhouette.
	pieces.append(_piece(Vector3(left + columns * cell.x * 0.5, bottom + rows * cell.y * 0.5, cell.z * 0.5), Vector3(columns * cell.x, rows * cell.y, cell.z)))
	for row in rows:
		if row % 2 == variant % 2:
			pieces.append(_piece(Vector3(left + columns * cell.x * 0.5, bottom + (row + 0.5) * cell.y, cell.z * 1.5), Vector3(columns * cell.x, cell.y, cell.z)))
	# Two straps or a stepped diagonal, made of cubes rather than a rotated bar.
	for row in rows:
		if variant == 2 or row in [1, rows - 2]:
			var column := mini(columns - 1, row * columns / rows) if variant == 2 else 0
			pieces.append(_piece(Vector3(left + (column + 0.5) * cell.x, bottom + (row + 0.5) * cell.y, cell.z * 2.5), Vector3(cell.x if variant == 2 else columns * cell.x, cell.y, cell.z)))
	return pieces

func _build_flower_box(detail: Dictionary, local: Vector3, basis: Basis) -> void:
	var id := str(detail.get("id", ""))
	var variant := _craft_variant(detail)
	var cell := (basis.inverse() * _detail_unit).abs()
	var count := maxi(6, roundi(1.6 / cell.x))
	var left := -floorf(count * 0.5) * cell.x
	var width := count * cell.x
	var middle := left + width * 0.5
	var depth := maxi(3, roundi(0.75 / cell.z)) * cell.z
	var trough: Array = [
		_piece(Vector3(middle, -cell.y * 0.5, depth * 0.5), Vector3(width, cell.y, depth)),
		_piece(Vector3(middle, cell.y * 0.5, depth - cell.z * 0.5), Vector3(width, cell.y, cell.z)),
		_piece(Vector3(left + cell.x * 0.5, cell.y * 0.5, depth * 0.5), Vector3(cell.x, cell.y, depth)),
		_piece(Vector3(left + width - cell.x * 0.5, cell.y * 0.5, depth * 0.5), Vector3(cell.x, cell.y, depth))]
	# A narrow lip and paired feet make the trough read as built timber.
	trough.append(_piece(Vector3(middle, cell.y * 1.5, depth - cell.z * 0.5), Vector3(width, cell.y, cell.z)))
	for column in [1, count - 2]:
		trough.append(_piece(Vector3(left + (column + 0.5) * cell.x, -cell.y * 1.5, depth * 0.5), Vector3(cell.x, cell.y, depth)))
		if variant == 1:
			trough.append(_piece(Vector3(left + (column + 0.5) * cell.x, cell.y * 0.5, depth + cell.z * 0.5), cell))
	_add_detail_boxes("FlowerBox_%s" % id, trough, SHUTTER_COLOR, basis, local)
	var leaves: Array = []
	var blooms: Array = []
	var accents: Array = []
	for column in range(1, count - 1):
		var x := left + (column + 0.5) * cell.x
		var z := cell.z * (1.5 + float((column + variant) % 2))
		leaves.append(_piece(Vector3(x, cell.y * 1.5, z), cell))
		if (column + variant) % 3 != 0:
			var height := 2.5 + float((column + variant) % 2)
			leaves.append(_piece(Vector3(x, cell.y * 2.5, z), cell))
			var flower := _piece(Vector3(x, cell.y * height, z + cell.z), cell)
			if column % 3 == 1: accents.append(flower)
			else: blooms.append(flower)
	_add_detail_boxes("BoxFoliage_%s" % id, leaves, Color("#597749"), basis, local)
	if not blooms.is_empty(): _add_detail_boxes("BoxFlowers_%s" % id, blooms, [FLOWER_COLOR, Color("#bd8492"), Color("#d4ac72")][variant], basis, local)
	if not accents.is_empty(): _add_detail_boxes("BoxFlowerAccents_%s" % id, accents, Color("#e5cba0"), basis, local)

func _surface_basis(orientation: String) -> Basis:
	if orientation == "front": return Basis(Vector3.UP, PI)
	if orientation == "left": return Basis(Vector3.UP, -PI * 0.5)
	if orientation == "right": return Basis(Vector3.UP, PI * 0.5)
	return Basis.IDENTITY

func _window_layout(detail: Dictionary, local: Vector3, orientation: String) -> Dictionary:
	var basis := _surface_basis(orientation)
	var rounded := str(detail.get("asset_id", "window_wood")).contains("round")
	var authored_size := _detail_size(detail, Vector2(1.5, 1.5) if rounded else Vector2(2.0, 2.8))
	var pane_requested := Vector3(authored_size.x, authored_size.y, 0.10)
	var pane_quantized := Grid.quantized_box(Vector3.ZERO, pane_requested, _unit)
	var surface_local := basis.inverse() * local
	# Authoritative attachment positions retain their small wall-normal offset,
	# but visible cell geometry must use the shared world-grid phase on every axis.
	var snapped_surface := surface_local.snapped(_unit)
	var pane_size: Vector3 = pane_quantized["size"]
	return {"basis": basis, "rounded": rounded, "anchor_center": basis * snapped_surface, "surface_center": Vector2(snapped_surface.x, snapped_surface.y), "pane_center": pane_quantized["center"], "pane_size": pane_size, "opening_half": Vector2(pane_size.x, pane_size.y) * 0.5}

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
	var pane_center: Vector3 = layout["pane_center"]
	var pane_size: Vector3 = layout["pane_size"]
	var node := MeshInstance3D.new()
	node.name = "Detail_%s" % id
	var pane := BoxMesh.new()
	pane.size = pane_size
	node.mesh = pane
	node.material_override = window_material
	node.transform = Transform3D(basis, anchor_center + basis * (pane_center + Vector3(0, 0, -_unit.z)))
	add_child(node)
	var pale: Array = []
	var timber: Array = []
	var shutters: Array = []
	var half := Vector2(pane_size.x, pane_size.y) * 0.5
	var cell := (basis.inverse() * _detail_unit).abs()
	var variant := _craft_variant(detail)
	# Distinct coloured pieces occupy distinct grid cells, not competing faces.
	if rounded:
		var nx := maxi(2, roundi(pane_size.x / cell.x))
		var ny := maxi(2, roundi(pane_size.y / cell.y))
		# Chamfered small surround retains the original square wall opening.
		for x in range(-1, nx + 1):
			for y in range(-1, ny + 1):
				var corner := (x in [-1, nx]) and (y in [-1, ny])
				var edge := x in [-1, nx] or y in [-1, ny]
				if edge and not corner:
					pale.append(_piece(Vector3(-half.x + (x + 0.5) * cell.x, -half.y + (y + 0.5) * cell.y, cell.z * 0.5), cell))
	else:
		for side in [-1.0, 1.0]:
			pale.append(_piece(Vector3(side * (half.x + cell.x * 0.5), 0, cell.z * 0.5), Vector3(cell.x, pane_size.y, cell.z)))
			pale.append(_piece(Vector3(0, side * (half.y + cell.y * 0.5), cell.z * 0.5), Vector3(pane_size.x + 2.0 * cell.x, cell.y, cell.z)))
			if bool(detail.get("show_shutters", true)):
				var width := cell.x * 2.0
				var x: float = side * (half.x + cell.x + width * 0.5)
				shutters.append_array(_shutter_pieces(x, width, pane_size.y, cell, variant))
		pale.append(_piece(Vector3(0, -half.y - cell.y * 0.5, cell.z * 1.5), Vector3(pane_size.x + cell.x * 4.0, cell.y, cell.z)))
	# One fine mullion and either a central or raised transom. A single shared
	# timber material keeps the tiny cell divisions calm at gameplay zoom.
	timber.append(_piece(Vector3(cell.x * 0.5, 0, cell.z * 0.5), Vector3(cell.x, pane_size.y, cell.z)))
	var transom_y := cell.y * 0.5 if rounded or variant == 0 else snappedf(half.y * 0.5, cell.y) + cell.y * 0.5
	timber.append(_piece(Vector3(0, transom_y, cell.z * 0.5), Vector3(pane_size.x, cell.y, cell.z)))
	if not rounded and variant == 2:
		timber.append(_piece(Vector3(0, -transom_y, cell.z * 0.5), Vector3(pane_size.x, cell.y, cell.z)))
	for entry in [["Reveal", pale, CORNICE_COLOR], ["Joinery", timber, TRIM_COLOR], ["Shutters", shutters, SHUTTER_COLOR]]:
		if entry[1].is_empty(): continue
		_add_detail_boxes("%s_%s" % [entry[0], id], entry[1], entry[2], basis, anchor_center)

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
		var kind := str(detail.get("kind", ""))
		if kind not in ["window", "door"] or not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)): continue
		if not str(detail.get("anchor", {}).get("surface_id", "")) in surface_ids: continue
		var resolved = detail.get("resolved_position", null)
		if not resolved is Vector3: continue
		var layout := _window_layout(detail, resolved, orientation) if kind == "window" else _door_layout(detail, resolved, orientation)
		var surface_center: Vector2 = layout["surface_center"]
		var opening_half: Vector2 = layout["opening_half"]
		cuts.append(Rect2(surface_center - opening_half, opening_half * 2.0))
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

func _detail_size(detail: Dictionary, fallback: Vector2) -> Vector2:
	var value = (detail.get("override", {}) as Dictionary).get("size", null)
	if value is Array and (value as Array).size() == 2: return Vector2(float(value[0]), float(value[1]))
	return fallback

func _door_layout(detail: Dictionary, local: Vector3, orientation: String) -> Dictionary:
	var basis := _surface_basis(orientation)
	var size := _detail_size(detail, Vector2(1.75, 3.7))
	var quantized := Grid.quantized_box(Vector3.ZERO, Vector3(size.x, size.y, 0.10), _unit)
	var surface_local := (basis.inverse() * local).snapped(_unit)
	var leaf_size: Vector3 = quantized["size"]
	return {"basis": basis, "anchor_center": basis * surface_local, "surface_center": Vector2(surface_local.x, surface_local.y), "leaf_center": quantized["center"], "leaf_size": leaf_size, "opening_half": Vector2(leaf_size.x, leaf_size.y) * 0.5}

func _build_door(detail: Dictionary, local: Vector3, orientation: String) -> void:
	var id := str(detail.get("id", "door"))
	var layout := _door_layout(detail, local, orientation)
	var basis: Basis = layout["basis"]
	var anchor: Vector3 = layout["anchor_center"]
	var leaf_center: Vector3 = layout["leaf_center"]
	var leaf_size: Vector3 = layout["leaf_size"]
	var width := leaf_size.x
	var height := leaf_size.y
	var leaf := MeshInstance3D.new()
	leaf.name = "Detail_%s" % id
	var leaf_mesh := BoxMesh.new()
	leaf_mesh.size = Vector3(width, height, _unit.z)
	leaf.mesh = leaf_mesh
	var leaf_material := StandardMaterial3D.new()
	leaf_material.albedo_color = SHUTTER_COLOR
	leaf.material_override = leaf_material
	leaf.transform = Transform3D(basis, anchor + basis * (leaf_center + Vector3(0, 0, -_unit.z)))
	add_child(leaf)
	var frame: Array = []
	var wood: Array = []
	var cell := (basis.inverse() * _detail_unit).abs()
	for side in [-1.0, 1.0]: frame.append(_piece(Vector3(side * (width * 0.5 + cell.x * 1.5), 0, cell.z), Vector3(cell.x * 2.0, height + cell.y * 4.0, cell.z * 2.0)))
	frame.append(_piece(Vector3(0, height * 0.5 + cell.y, cell.z), Vector3(width + cell.x * 6.0, cell.y, cell.z * 2.0)))
	var planks := maxi(3, roundi(width / (cell.x * 2.0)))
	for plank in planks: wood.append(_piece(Vector3(-width * 0.5 + (plank + 0.5) * width / planks, 0, cell.z), Vector3(cell.x, height - cell.y * 2.0, cell.z)))
	for y in [-height * 0.3, height * 0.3]: wood.append(_piece(Vector3(0, y, cell.z * 2.0), Vector3(width - cell.x * 2.0, cell.y, cell.z)))
	wood.append(_piece(Vector3(width * 0.3, 0, cell.z * 2.5), cell))
	_add_detail_boxes("DoorSurround_%s" % id, frame, CORNICE_COLOR, basis, anchor)
	_add_detail_boxes("DoorJoinery_%s" % id, wood, TRIM_COLOR, basis, anchor)
	_build_entrance_canopy(id, width, height, basis, anchor)

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
		var rhythm := 5 + posmod(_craft_seed, 2)
		for i in ceili(dimensions.x / (_detail_unit.x * rhythm)):
			var x := -snappedf(dimensions.x * 0.5, _unit.x) + (i * rhythm + 0.5) * _detail_unit.x
			var z: float = side * (snappedf(dimensions.z * 0.5, _unit.z) + _unit.z * 1.5)
			timber.append(_piece(Vector3(x, eave - _unit.y * 1.5, z), Vector3(_detail_unit.x, _detail_unit.y, _unit.z)))
		var end_x: float = side * (snappedf((dimensions.x + 0.75) * 0.5, _unit.x) + _unit.x * 0.5)
		timber.append(_piece(Vector3(end_x, eave + _unit.y * 0.5, 0), Vector3(_unit.x, _unit.y, dimensions.z)))
		timber.append(_piece(Vector3(end_x, eave + dimensions.y * _roof_rise_ratio * 0.5, 0), Vector3(_unit.x, dimensions.y * _roof_rise_ratio, _unit.z)))
	_add_batched_boxes("FoundationCourses", stone, QUOIN_COLOR)
	_add_detail_boxes("EaveJoinery", timber, TRIM_COLOR)
	# A single crest begins above the actual highest roof top, replacing three
	# separately rounded ridge layers with conflicting colours at identical depth.
	var run := dimensions.z * 0.5 + 0.5
	var top := snappedf(dimensions.y + dimensions.y * _roof_rise_ratio * (1.0 - _unit.z * 0.5 / run), _unit.y) + _unit.y
	var crest: Array = [_piece(Vector3(0, top + _detail_unit.y * 0.5, 0), Vector3(dimensions.x + 0.75, _detail_unit.y, _unit.z * 2.0))]
	var ridge_half := snappedf((dimensions.x + 0.75) * 0.5, _unit.x)
	for i in ceili(ridge_half * 2.0 / (_detail_unit.x * 4.0)):
		crest.append(_piece(Vector3(-ridge_half + (i * 4.0 + 1.5) * _detail_unit.x, top + _detail_unit.y * 1.5, 0), Vector3(_detail_unit.x * 3.0, _detail_unit.y, _unit.z)))
	_add_detail_boxes("RidgeCourses", crest, _roof_tile_colors[2])
	_build_roof_edges(dimensions)

func _build_roof_edges(dimensions: Vector3) -> void:
	var edges: Array = []
	var run := dimensions.z * 0.5 + 0.5
	# The outer face follows the unchanged structural tile staircase, with a
	# half-cell lip below it. It does not replace any roof mass or roof anchors.
	var span := dimensions.x + 0.75
	var roof_left := -snappedf(span * 0.5, _unit.x)
	var roof_right := roof_left + ceili(span / (_unit.x * 2.0)) * _unit.x * 2.0
	for end in [roof_left - _detail_unit.x * 0.5, roof_right + _detail_unit.x * 0.5]:
		for side in [-1.0, 1.0]:
			for row in ceili(run / _unit.z):
				var z := (row + 0.5) * _unit.z
				var height := snappedf(dimensions.y + dimensions.y * _roof_rise_ratio * (1.0 - z / run), _unit.y)
				edges.append(_piece(Vector3(end, height - _detail_unit.y * 0.5, side * z), Vector3(_detail_unit.x, _detail_unit.y, _unit.z)))
	_add_detail_boxes("RoofEdgeLip", edges, _roof_edge_color)

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

func _build_entrance_canopy(id: String, width: float, height: float, basis: Basis, anchor: Vector3) -> void:
	var y := height * 0.5 + _unit.y * 2.0
	var timber: Array = []
	var tiles: Array = []
	for side in [-1.0, 1.0]:
		timber.append(_piece(Vector3(side * (width * 0.5 + _unit.x), y - _unit.y, _unit.z * 2.0), Vector3(_detail_unit.x, _unit.y * 4.0, _unit.z)))
	var columns := maxi(6, ceili((width + _unit.x * 6.0) / _detail_unit.x))
	for row in 5:
		for column in columns: tiles.append(_piece(Vector3(-(columns - 1) * _detail_unit.x * 0.5 + column * _detail_unit.x, y + _unit.y - row * _detail_unit.y, row * _detail_unit.z), _detail_unit))
	_add_detail_boxes("PorchBrackets_%s" % id, timber, TRIM_COLOR, basis, anchor)
	_add_detail_boxes("PorchTileCourses_%s" % id, tiles, _roof_tile_colors[1], basis, anchor)

func _build_gable_vent(dimensions: Vector3, deleted: Dictionary) -> void:
	if bool(deleted.get("left", false)): return
	var x := -dimensions.x * 0.5
	var vent: Array = []
	for row in 7:
		var width := 1.0 - absf(float(row) - 3.0) * 0.13
		vent.append(_piece(Vector3(x - 0.17, dimensions.y + 0.35 + row * 0.17, -2.0), Vector3(0.22, 0.13, width)))
	_add_batched_boxes("GableVent", vent, SHUTTER_COLOR)

func _add_instanced_boxes(node_name: String, boxes: Array, color: Color) -> MultiMeshInstance3D:
	return _make_instanced_boxes(node_name, boxes, color, _unit)

func _add_detail_boxes(node_name: String, boxes: Array, color: Color, basis := Basis.IDENTITY, anchor := Vector3.ZERO) -> MultiMeshInstance3D:
	# Invert the attachment's cardinal orientation before quantizing: even a
	# nonuniform cottage transform must leave world-space cells cubic.
	var unit := (basis.inverse() * _detail_unit).abs()
	var node := _make_instanced_boxes(node_name, boxes, color, unit)
	node.set_meta("cottage_detail_grid", Grid.COTTAGE_DETAIL_UNIT)
	node.transform = Transform3D(basis, anchor.snapped(_detail_unit))
	return node

func _make_instanced_boxes(node_name: String, boxes: Array, color: Color, unit: Vector3) -> MultiMeshInstance3D:
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = cube
	multi.instance_count = boxes.size()
	for i in boxes.size():
		var piece: Dictionary = boxes[i]
		var basis: Basis = piece["basis"]
		var q := Grid.quantized_box(piece["center"], piece["size"], unit)
		multi.set_instance_transform(i, Transform3D(basis.scaled_local(q["size"]), q["center"]))
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multi
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.material_override = material
	add_child(node)
	return node
