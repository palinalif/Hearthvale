extends Node3D
class_name M2HouseMassingVisual

const Massing = preload("res://scripts/m2_house_massing.gd")
const FOUNDATION_COLOUR := Color("#9a8876")
const WALL_THICKNESS := 0.42
const ROOF_THICKNESS := 0.18
const EAVE_HEIGHT := 0.12

var _signature := ""
var _highlight_enabled := false
var _highlight_grow := 0.12
var _highlight_material: StandardMaterial3D

func show_view(view: Dictionary, wall_colour: Color, roof_palette: Array, roof_edge_colour: Color) -> void:
	var signature := "%s|%s|%s|%s|%s|%s" % [JSON.stringify(_serializable_sections(view)), str(view.get("dimensions", Vector3.ZERO)), str(view.get("roof_profile", "gentle_gable")), wall_colour.to_html(), str(roof_palette), roof_edge_colour.to_html()]
	if signature == _signature: return
	_signature = signature
	for child in get_children(): child.free()
	var sections := Massing.sections_for(view)
	if sections.size() <= 1: return
	_build_foundation(view)
	_build_walls(view, wall_colour)
	_build_eaves(view, roof_edge_colour)
	_build_roof(view, roof_palette, roof_edge_colour)
	_apply_highlight()

func set_highlight(enabled: bool, grow_amount: float = 0.12) -> void:
	_highlight_enabled = enabled
	_highlight_grow = grow_amount
	_apply_highlight()

func _apply_highlight() -> void:
	var overlay: Material = _outline_material(_highlight_grow) if _highlight_enabled else null
	for child in get_children():
		if child is GeometryInstance3D: (child as GeometryInstance3D).material_overlay = overlay

func _outline_material(grow_amount: float) -> StandardMaterial3D:
	if not _highlight_material:
		_highlight_material = StandardMaterial3D.new()
		_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_highlight_material.albedo_color = Color("#ffbf3f")
		_highlight_material.emission_enabled = true
		_highlight_material.emission = Color("#ffbf3f")
		_highlight_material.cull_mode = BaseMaterial3D.CULL_FRONT
		_highlight_material.grow = true
	_highlight_material.grow_amount = grow_amount
	return _highlight_material

func _serializable_sections(view: Dictionary) -> Array:
	var result: Array = []
	for section in Massing.sections_for(view):
		var offset: Vector3 = section["offset"]
		var size: Vector3 = section["size"]
		result.append({"id": str(section.get("id", "")), "offset": [offset.x, offset.y, offset.z], "size": [size.x, size.y, size.z]})
	return result

func _build_foundation(view: Dictionary) -> void:
	var field := Massing.occupancy(view)
	if field.is_empty(): return
	var origin: Vector2 = field["origin"]
	var transforms: Array[Transform3D] = []
	for key_value in (field["cells"] as Dictionary).keys():
		var key := key_value as Vector2i
		var center := Vector3(origin.x + (float(key.x) + 0.5) * Massing.CELL, 0.30, origin.y + (float(key.y) + 0.5) * Massing.CELL)
		transforms.append(_box_transform(center, Vector3(Massing.CELL * 1.04, 0.60, Massing.CELL * 1.04)))
	_add_multimesh("JoinedFoundation", transforms, FOUNDATION_COLOUR, 0.98)

func _build_walls(view: Dictionary, wall_colour: Color) -> void:
	var buckets := {"front": [], "back": [], "left": [], "right": []}
	for face in Massing.boundary_faces(view):
		var orientation := str(face["orientation"])
		var face_position: Vector3 = face["position"]
		var top := float(face["height"])
		var layer_count := maxi(1, ceili(maxf(0.0, top - 0.60) / Massing.CELL))
		for layer in layer_count:
			var bottom := 0.60 + float(layer) * Massing.CELL
			var layer_height := minf(Massing.CELL, top - bottom)
			if layer_height <= 0.001: continue
			var y := bottom + layer_height * 0.5
			if _opening_at(view, orientation, face_position, y, layer_height): continue
			var center := Vector3(face_position.x, y, face_position.z)
			var size := Vector3(Massing.CELL, layer_height, WALL_THICKNESS) if orientation in ["front", "back"] else Vector3(WALL_THICKNESS, layer_height, Massing.CELL)
			(buckets[orientation] as Array).append(_box_transform(center, size))
	for orientation in buckets:
		var transforms: Array = buckets[orientation]
		if not transforms.is_empty(): _add_multimesh("JoinedWall_%s" % str(orientation).capitalize(), transforms, wall_colour, 0.96)

func _build_eaves(view: Dictionary, colour: Color) -> void:
	var transforms: Array[Transform3D] = []
	for face in Massing.boundary_faces(view):
		var orientation := str(face["orientation"])
		var position: Vector3 = face["position"]
		var center := Vector3(position.x, float(face["height"]) + EAVE_HEIGHT * 0.5, position.z)
		var size := Vector3(Massing.CELL * 1.08, EAVE_HEIGHT, WALL_THICKNESS * 1.25) if orientation in ["front", "back"] else Vector3(WALL_THICKNESS * 1.25, EAVE_HEIGHT, Massing.CELL * 1.08)
		transforms.append(_box_transform(center, size))
	_add_multimesh("JoinedEaves", transforms, colour, 0.9)

func _build_roof(view: Dictionary, roof_palette: Array, edge_colour: Color) -> void:
	if roof_palette.is_empty(): roof_palette = [Color("#b9654c"), Color("#bf6c50"), Color("#a95445")]
	var buckets: Array = [[], [], []]
	var edge_transforms: Array[Transform3D] = []
	var tiles: Array[Dictionary] = Massing.roof_tiles(view)
	var by_cell: Dictionary = {}
	for tile_value in tiles:
		var tile: Dictionary = tile_value
		by_cell[tile["cell"]] = tile
	for tile_value in tiles:
		var tile: Dictionary = tile_value
		var center: Vector3 = tile["center"]
		var slope: Vector2 = _roof_gradient(tile, by_cell)
		var transform := _roof_tile_transform(center, Vector3(Massing.CELL * 1.14, ROOF_THICKNESS, Massing.CELL * 1.14), slope)
		var shade := clampi(int(tile.get("shade", 0)), 0, 2)
		(buckets[shade] as Array).append(transform)
		if bool(tile.get("edge", false)):
			var normal := Vector3(-slope.x, 1.0, -slope.y).normalized()
			var edge_center := center - normal * ROOF_THICKNESS * 0.44
			edge_transforms.append(_roof_tile_transform(edge_center, Vector3(Massing.CELL * 1.17, ROOF_THICKNESS * 0.42, Massing.CELL * 1.17), slope))
	for shade in 3:
		var colour: Color = roof_palette[mini(shade, roof_palette.size() - 1)] as Color
		_add_multimesh("JoinedRoof_%d" % shade, buckets[shade], colour, 0.86)
	_add_multimesh("JoinedRoofEdge", edge_transforms, edge_colour, 0.9)

func _roof_gradient(tile: Dictionary, by_cell: Dictionary) -> Vector2:
	var key: Vector2i = tile["cell"]
	var center: Vector3 = tile["center"]
	var left_key := key + Vector2i.LEFT
	var right_key := key + Vector2i.RIGHT
	var front_key := key + Vector2i.UP
	var back_key := key + Vector2i.DOWN
	var has_left := by_cell.has(left_key)
	var has_right := by_cell.has(right_key)
	var has_front := by_cell.has(front_key)
	var has_back := by_cell.has(back_key)
	var left_height := _tile_height(by_cell, left_key, center.y)
	var right_height := _tile_height(by_cell, right_key, center.y)
	var front_height := _tile_height(by_cell, front_key, center.y)
	var back_height := _tile_height(by_cell, back_key, center.y)
	var slope_x := _axis_gradient(center.y, has_left, left_height, has_right, right_height)
	var slope_z := _axis_gradient(center.y, has_front, front_height, has_back, back_height)
	return Vector2(slope_x, slope_z)

func _tile_height(by_cell: Dictionary, key: Vector2i, fallback: float) -> float:
	if not by_cell.has(key): return fallback
	var tile: Dictionary = by_cell[key]
	var center: Vector3 = tile["center"]
	return center.y

func _axis_gradient(current: float, has_negative: bool, negative: float, has_positive: bool, positive: float) -> float:
	if has_negative and has_positive: return (positive - negative) / (Massing.CELL * 2.0)
	if has_positive: return (positive - current) / Massing.CELL
	if has_negative: return (current - negative) / Massing.CELL
	return 0.0

func _roof_tile_transform(center: Vector3, size: Vector3, slope: Vector2) -> Transform3D:
	var x_axis := Vector3(1.0, slope.x, 0.0).normalized()
	var normal := Vector3(-slope.x, 1.0, -slope.y).normalized()
	var z_axis := x_axis.cross(normal).normalized()
	x_axis = normal.cross(z_axis).normalized()
	var basis := Basis(x_axis, normal, z_axis).scaled_local(size)
	return Transform3D(basis, center)

func _opening_at(view: Dictionary, orientation: String, face_position: Vector3, y: float, layer_height: float) -> bool:
	for detail_value in view.get("details", []):
		if not detail_value is Dictionary: continue
		var detail: Dictionary = detail_value
		var kind := str(detail.get("kind", ""))
		if kind not in ["window", "door"] or not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)): continue
		var local = detail.get("resolved_position", null)
		if not local is Vector3: continue
		var point := local as Vector3
		var normal_delta := absf(point.z - face_position.z) if orientation in ["front", "back"] else absf(point.x - face_position.x)
		if normal_delta > Massing.CELL * 1.2: continue
		var surface_orientation := _detail_orientation(view, detail)
		if surface_orientation != orientation: continue
		var size := _detail_size(detail, kind)
		var tangent_delta := absf(point.x - face_position.x) if orientation in ["front", "back"] else absf(point.z - face_position.z)
		if tangent_delta > size.x * 0.5 + Massing.CELL * 0.65: continue
		if absf(point.y - y) <= size.y * 0.5 + layer_height * 0.65: return true
	return false

func _detail_orientation(view: Dictionary, detail: Dictionary) -> String:
	var surface_id := str((detail.get("anchor", {}) as Dictionary).get("surface_id", ""))
	for surface_value in view.get("surfaces", []):
		if surface_value is Dictionary and str((surface_value as Dictionary).get("id", "")) == surface_id:
			return str((surface_value as Dictionary).get("orientation", ""))
	return ""

func _detail_size(detail: Dictionary, kind: String) -> Vector2:
	var override: Dictionary = detail.get("override", {})
	var value = override.get("size", null)
	if value is Array and (value as Array).size() == 2: return Vector2(float(value[0]), float(value[1]))
	if kind == "door": return Vector2(1.75, 3.7)
	return Vector2(1.5, 1.5) if str(detail.get("asset_id", "")).contains("round") else Vector2(2.0, 2.8)

func _box_transform(center: Vector3, size: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY.scaled(size), center)

func _add_multimesh(node_name: String, transforms: Array, colour: Color, roughness: float) -> void:
	if transforms.is_empty(): return
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size(): multimesh.set_instance_transform(index, transforms[index] as Transform3D)
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multimesh
	add_child(node)