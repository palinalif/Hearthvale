extends Node3D
class_name M2JoinedRoofBeamVisual

const Massing = preload("res://scripts/m2_house_massing.gd")
const BEAM_COLOUR := Color("#634d42")
const BEAM_THICKNESS := 0.14
const BEAM_WIDTH := 0.16
const BEAM_LIFT := 0.11

var _signature := ""

func show_view(view: Dictionary) -> void:
	var signature: String = "%s|%s|%s" % [JSON.stringify(_serializable_sections(view)), str(view.get("roof_profile", "gentle_gable")), BEAM_COLOUR.to_html()]
	if signature == _signature: return
	_signature = signature
	for child in get_children(): child.free()
	if Massing.sections_for(view).size() <= 1: return
	_build_eave_beams(view)
	_build_ridge_beams(view)

func _serializable_sections(view: Dictionary) -> Array:
	var result: Array = []
	for section_value in Massing.sections_for(view):
		var section: Dictionary = section_value
		var offset: Vector3 = section["offset"]
		var size: Vector3 = section["size"]
		result.append({"id": str(section.get("id", "")), "level": Massing.section_level(section), "offset": [offset.x, offset.y, offset.z], "size": [size.x, size.y, size.z]})
	return result

func _build_eave_beams(view: Dictionary) -> void:
	var transforms: Array[Transform3D] = []
	for face_value in Massing.boundary_faces(view):
		var face: Dictionary = face_value
		var orientation: String = str(face.get("orientation", "front"))
		var position: Vector3 = face.get("position", Vector3.ZERO)
		var roof_y: float = Massing.roof_height_at(view, position.x, position.z) + BEAM_LIFT
		var center: Vector3 = Vector3(position.x, roof_y, position.z)
		transforms.append(_beam_transform(center, Massing.CELL * 1.08, orientation in ["left", "right"]))
	_add_multimesh("JoinedRoofEaveBeams", transforms)

func _build_ridge_beams(view: Dictionary) -> void:
	var tiles: Array[Dictionary] = Massing.roof_tiles(view)
	var by_cell: Dictionary = {}
	for tile_value in tiles:
		var tile: Dictionary = tile_value
		by_cell[tile["cell"]] = tile
	var transforms: Array[Transform3D] = []
	for tile_value in tiles:
		var tile: Dictionary = tile_value
		var key: Vector2i = tile["cell"]
		var distance: int = int(tile.get("distance", 0))
		if distance <= 0: continue
		var base_height: float = float(tile.get("base_height", 0.0))
		var left: int = _distance_at(by_cell, key + Vector2i.LEFT, base_height)
		var right: int = _distance_at(by_cell, key + Vector2i.RIGHT, base_height)
		var front: int = _distance_at(by_cell, key + Vector2i.UP, base_height)
		var back: int = _distance_at(by_cell, key + Vector2i.DOWN, base_height)
		var ridge_x: bool = (left == distance or right == distance) and distance >= front and distance >= back and (front < distance or back < distance)
		var ridge_z: bool = (front == distance or back == distance) and distance >= left and distance >= right and (left < distance or right < distance)
		if not ridge_x and not ridge_z: continue
		var center: Vector3 = tile["center"]
		center.y += BEAM_LIFT * 1.35
		if ridge_x: transforms.append(_beam_transform(center, Massing.CELL * 1.10, false))
		if ridge_z: transforms.append(_beam_transform(center, Massing.CELL * 1.10, true))
	_add_multimesh("JoinedRoofRidgeBeams", transforms)

func _distance_at(by_cell: Dictionary, key: Vector2i, base_height: float) -> int:
	if not by_cell.has(key): return -999
	var tile: Dictionary = by_cell[key]
	if absf(float(tile.get("base_height", 0.0)) - base_height) > Massing.JOIN_EPSILON: return -999
	return int(tile.get("distance", 0))

func _beam_transform(center: Vector3, length: float, along_z: bool) -> Transform3D:
	var rotation: Basis = Basis(Vector3.UP, PI * 0.5) if along_z else Basis.IDENTITY
	return Transform3D(rotation.scaled_local(Vector3(length, BEAM_THICKNESS, BEAM_WIDTH)), center)

func _add_multimesh(node_name: String, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty(): return
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var material := StandardMaterial3D.new()
	material.albedo_color = BEAM_COLOUR
	material.roughness = 0.96
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size(): multimesh.set_instance_transform(index, transforms[index])
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multimesh
	add_child(node)
