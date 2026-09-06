extends Node3D
class_name BrushPreview

## Renderer-only brush feedback. Cell positions and the brush center share the
## terrain's world cell space; this node is expected to live at world origin.
## The caller owns visibility and supplies the already-computed affected cells.

const _ADD_COLOR := Color(0.96, 0.58, 0.24)
const _REMOVE_COLOR := Color(0.25, 0.78, 0.92)
const _SURFACE_OFFSET := 0.002

const _FACE_NORMALS := [
	Vector3i(-1, 0, 0), Vector3i(1, 0, 0),
	Vector3i(0, -1, 0), Vector3i(0, 1, 0),
	Vector3i(0, 0, -1), Vector3i(0, 0, 1),
]
const _FACE_CORNERS := [
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)],
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	[Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],
	[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)],
]

var BrushVolume: MeshInstance3D
var AffectedHighlight: MeshInstance3D
var AffectedOutline: MeshInstance3D
var OccludedOutline: MeshInstance3D

var _volume_material: StandardMaterial3D
var _highlight_material: StandardMaterial3D
var _outline_material: StandardMaterial3D
var _occluded_material: StandardMaterial3D

func _ready() -> void:
	_ensure_nodes()

func update_geometry(center: Vector3, radius: float, remove: bool, cells: Array[Vector3i]) -> void:
	_ensure_nodes()
	var safe_radius := maxf(radius, 0.001)
	var sphere := BrushVolume.mesh as SphereMesh
	if sphere == null:
		sphere = SphereMesh.new()
		sphere.radial_segments = 24
		sphere.rings = 12
		BrushVolume.mesh = sphere
	sphere.radius = safe_radius
	sphere.height = safe_radius * 2.0
	BrushVolume.position = center
	BrushVolume.visible = true
	_set_palette(remove)

	var unique_cells := _unique_cells(cells)
	if unique_cells.is_empty():
		AffectedHighlight.mesh = null
		AffectedOutline.mesh = null
		OccludedOutline.mesh = null
		AffectedHighlight.visible = false
		AffectedOutline.visible = false
		OccludedOutline.visible = false
		return

	AffectedHighlight.mesh = _build_face_mesh(unique_cells)
	var edge_mesh := _build_outline_mesh(unique_cells)
	AffectedOutline.mesh = edge_mesh
	OccludedOutline.mesh = edge_mesh
	AffectedHighlight.visible = true
	AffectedOutline.visible = true
	OccludedOutline.visible = true

func _ensure_nodes() -> void:
	if BrushVolume != null:
		return
	BrushVolume = MeshInstance3D.new()
	BrushVolume.name = "BrushVolume"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	BrushVolume.mesh = sphere
	# Keep the reach visible even when the brush is inside solid terrain; the
	# affected-cell tint and outlines retain the depth-tested spatial cue.
	_volume_material = _make_material(Color(_ADD_COLOR, 0.04), true)
	BrushVolume.material_override = _volume_material
	add_child(BrushVolume)

	AffectedHighlight = MeshInstance3D.new()
	AffectedHighlight.name = "AffectedHighlight"
	_highlight_material = _make_material(Color(_ADD_COLOR, 0.16), false)
	_highlight_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	AffectedHighlight.material_override = _highlight_material
	AffectedHighlight.visible = false
	add_child(AffectedHighlight)

	AffectedOutline = MeshInstance3D.new()
	AffectedOutline.name = "AffectedOutline"
	_outline_material = _make_material(Color(_ADD_COLOR, 0.65), false)
	_outline_material.render_priority = 1
	AffectedOutline.material_override = _outline_material
	AffectedOutline.visible = false
	add_child(AffectedOutline)

	OccludedOutline = MeshInstance3D.new()
	OccludedOutline.name = "OccludedOutline"
	_occluded_material = _make_material(Color(_ADD_COLOR, 0.14), true)
	_occluded_material.render_priority = 0
	OccludedOutline.material_override = _occluded_material
	OccludedOutline.visible = false
	add_child(OccludedOutline)

func _make_material(color: Color, no_depth_test: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = no_depth_test
	material.albedo_color = color
	return material

func _set_palette(remove: bool) -> void:
	var color := _REMOVE_COLOR if remove else _ADD_COLOR
	_volume_material.albedo_color = Color(color, 0.04)
	_highlight_material.albedo_color = Color(color, 0.16)
	_outline_material.albedo_color = Color(color, 0.65)
	_occluded_material.albedo_color = Color(color, 0.14)

func _unique_cells(cells: Array[Vector3i]) -> Dictionary:
	var unique := {}
	for cell in cells:
		unique[_cell_key(cell)] = cell
	return unique

func _build_face_mesh(cells: Dictionary) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for cell_value in cells.values():
		var cell: Vector3i = cell_value
		for face_index in _FACE_NORMALS.size():
			var neighbour: Vector3i = cell + _FACE_NORMALS[face_index]
			if cells.has(_cell_key(neighbour)):
				continue
			var corners: Array = _FACE_CORNERS[face_index]
			var base := vertices.size()
			for corner in corners:
				vertices.append(Vector3(cell) + corner + Vector3(_FACE_NORMALS[face_index]) * _SURFACE_OFFSET)
				normals.append(Vector3(_FACE_NORMALS[face_index]))
			indices.append(base)
			indices.append(base + 1)
			indices.append(base + 2)
			indices.append(base)
			indices.append(base + 2)
			indices.append(base + 3)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _build_outline_mesh(cells: Dictionary) -> ArrayMesh:
	var edges := {}
	for cell_value in cells.values():
		var cell: Vector3i = cell_value
		for face_index in _FACE_NORMALS.size():
			if cells.has(_cell_key(cell + _FACE_NORMALS[face_index])):
				continue
			var corners: Array = _FACE_CORNERS[face_index]
			var normal := Vector3(_FACE_NORMALS[face_index])
			for edge_index in 4:
				var a: Vector3 = Vector3(cell) + corners[edge_index]
				var b: Vector3 = Vector3(cell) + corners[(edge_index + 1) % 4]
				var key := _edge_key(a, b)
				if not edges.has(key):
					edges[key] = {"a": a, "b": b, "normals": [normal]}
				else:
					var edge: Dictionary = edges[key]
					var edge_normals: Array = edge["normals"]
					edge_normals.append(normal)
					edge["normals"] = edge_normals
					edges[key] = edge

	var vertices := PackedVector3Array()
	for edge_value in edges.values():
		var edge: Dictionary = edge_value
		var edge_normals: Array = edge["normals"]
		if edge_normals.size() > 1 and _edge_is_planar(edge_normals):
			continue
		var offset := _edge_offset(edge_normals)
		vertices.append(edge["a"] + offset)
		vertices.append(edge["b"] + offset)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh

func _edge_is_planar(normals: Array) -> bool:
	var first: Vector3 = normals[0]
	for index in range(1, normals.size()):
		var other: Vector3 = normals[index]
		if absf(absf(first.dot(other)) - 1.0) > 0.001:
			return false
	return true

func _edge_offset(normals: Array) -> Vector3:
	var direction := Vector3.ZERO
	for normal in normals:
		direction += normal
	if direction.length_squared() < 0.000001:
		direction = normals[0]
	return direction.normalized() * _SURFACE_OFFSET

func _cell_key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]

func _edge_key(a: Vector3, b: Vector3) -> String:
	var first := "%d,%d,%d" % [roundi(a.x), roundi(a.y), roundi(a.z)]
	var second := "%d,%d,%d" % [roundi(b.x), roundi(b.y), roundi(b.z)]
	return first + ":" + second if first < second else second + ":" + first
