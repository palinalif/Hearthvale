extends Node3D

const Placement = preload("res://scripts/wall_attachment_placement.gd")
const GHOST_COLOR := Color(0.35, 0.86, 1.0, 0.46)
const GHOST_GREEN := Color(0.46, 0.92, 0.62, 0.42)
const GHOST_FLOWER := Color(1.0, 0.62, 0.76, 0.46)
var _signature := ""

func show_attachment(building_transform: Transform3D, orientation: String, local_position: Vector3, kind: String, detail: Dictionary = {}, footprint_half: Vector2 = Vector2.ZERO, valid: bool = true, show_body: bool = true) -> void:
	visible = true
	transform = building_transform * Transform3D(_surface_basis(orientation), local_position)
	var record: Dictionary = detail if not detail.is_empty() else {"kind": kind, "asset_id": kind + "_wood"}
	var half := footprint_half if footprint_half != Vector2.ZERO else Placement.footprint_for_detail(record)
	var body_size := Placement.detail_size(record)
	var signature := "%s|%s|%s|%s|%s" % [kind, body_size, half, valid, show_body]
	if signature == _signature: return
	_signature = signature
	for child in get_children(): child.free()
	var colour := GHOST_COLOR if valid else Color(1.0, 0.35, 0.28, 0.55)
	if show_body:
		if kind == "flower_box": _build_flower_box()
		elif kind == "shutter": _build_shutter()
		else: _add_box(Vector3(0, 0, 0.12), Vector3(body_size.x, body_size.y, 0.12), colour, "OpeningPreview")
	# Full reserved placement area, including the frame/trim clearance. The
	# outline is in house-local units and follows its miniature scale and yaw.
	_add_box(Vector3(0, half.y, 0.35), Vector3(half.x * 2, 0.07, 0.06), colour, "FootprintTop")
	_add_box(Vector3(0, -half.y, 0.35), Vector3(half.x * 2, 0.07, 0.06), colour, "FootprintBottom")
	_add_box(Vector3(-half.x, 0, 0.35), Vector3(0.07, half.y * 2, 0.06), colour, "FootprintLeft")
	_add_box(Vector3(half.x, 0, 0.35), Vector3(0.07, half.y * 2, 0.06), colour, "FootprintRight")
	if not valid:
		_add_box(Vector3(0, 0.15, 0.4), Vector3(0.10, 0.4, 0.06), colour, "InvalidMark")
		_add_box(Vector3(0, -0.15, 0.4), Vector3(0.10, 0.10, 0.06), colour)

func hide_attachment() -> void:
	visible = false

func _build_flower_box() -> void:
	_add_box(Vector3(0, -0.12, 0.32), Vector3(1.6, 0.12, 0.64), GHOST_COLOR)
	_add_box(Vector3(0, 0.03, 0.60), Vector3(1.6, 0.30, 0.12), GHOST_COLOR)
	_add_box(Vector3(-0.74, 0.03, 0.32), Vector3(0.12, 0.30, 0.64), GHOST_COLOR)
	_add_box(Vector3(0.74, 0.03, 0.32), Vector3(0.12, 0.30, 0.64), GHOST_COLOR)
	for i in 7:
		_add_box(Vector3(-0.6 + i * 0.2, 0.18, 0.32), Vector3(0.24, 0.25, 0.34), GHOST_GREEN)
		_add_box(Vector3(-0.6 + i * 0.2, 0.33 + float(i % 2) * 0.08, 0.32), Vector3(0.15, 0.12, 0.18), GHOST_FLOWER)

func _build_shutter() -> void:
	_add_box(Vector3(0, 0, 0.15), Vector3(0.66, 2.9, 0.16), GHOST_COLOR)
	for row in 9:
		_add_box(Vector3(0, -1.2 + row * 0.3, 0.3), Vector3(0.55, 0.1, 0.12), GHOST_COLOR)

func _add_box(center: Vector3, size: Vector3, color: Color, node_name: String = "") -> void:
	var node := MeshInstance3D.new()
	if not node_name.is_empty(): node.name = node_name
	var mesh := BoxMesh.new(); mesh.size = size
	node.mesh = mesh
	node.position = center
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0) * 0.22
	node.material_override = material
	add_child(node)

func _surface_basis(orientation: String) -> Basis:
	if orientation == "front": return Basis(Vector3.UP, PI)
	if orientation == "left": return Basis(Vector3.UP, -PI * 0.5)
	if orientation == "right": return Basis(Vector3.UP, PI * 0.5)
	return Basis.IDENTITY
