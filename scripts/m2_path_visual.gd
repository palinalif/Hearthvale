extends Node3D
class_name M2PathVisual

## Disposable presentation for painted path authority. Saved paths are structural
## 0.125 m cells; this node never reconstructs a centreline or writes terrain.
const Grid = preload("res://scripts/visual_grid.gd")
const Region = preload("res://scripts/m2_painted_path_region.gd")
const STYLE_ORDER: Array[String] = ["packed_earth", "cobblestone", "stepping_stones"]
const PATH_THICKNESS := 0.035
const TOP_EPSILON := 0.004
const STYLE_COLOURS := {
	"packed_earth": [Color("#8d674d"), Color("#ad8567")],
	"cobblestone": [Color("#89908b"), Color("#b6b9a5")],
	"stepping_stones": [Color("#97958c"), Color("#c8b996")],
}

var backend: Node
var _style_nodes: Dictionary = {}
var _preview_node: MeshInstance3D
var _preview_marker: MeshInstance3D
var _stats: Dictionary = {"styles": {}, "draw_calls": 0, "geometry_cells": 0, "preview_cells": 0}

func attach_backend(value: Node) -> void:
	backend = value

func rebuild(path_values: Array, terrain_backend: Node = null) -> void:
	if terrain_backend != null: backend = terrain_backend
	_clear_authoritative_nodes()
	var geometry_cells := 0
	for style_id in STYLE_ORDER:
		var cells := _cells_for_style(path_values, style_id)
		if cells.is_empty(): continue
		var builder := _new_builder()
		_append_cells(builder, style_id, cells)
		var mesh := _mesh_from_builder(builder, STYLE_COLOURS[style_id])
		if mesh == null: continue
		var node := MeshInstance3D.new()
		node.name = "PathBatch_" + style_id
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_style_nodes[style_id] = node
		geometry_cells += cells.size()
		_stats["styles"][style_id] = {"geometry": true, "surfaces": mesh.get_surface_count(), "cells": cells.size()}
		if style_id == "packed_earth":
			var profile := Region.packed_earth_profile(cells)
			var depths := {0: 0, 1: 0, 2: 0}
			for cell in profile:
				var step := int(profile[cell])
				depths[step] = int(depths.get(step, 0)) + 1
			_stats["packed_earth"] = {"cells": cells.size(), "profile_depth_steps": depths, "triangles": _builder_triangles(builder), "vertices": _builder_vertices(builder)}
	_stats["draw_calls"] = _style_nodes.size()
	_stats["geometry_cells"] = geometry_cells

func show_cell_preview(style_id: String, cell_values: Array, valid: bool, reason: String = "") -> void:
	hide_preview()
	if not STYLE_ORDER.has(style_id): return
	var cells := Region.normalize_cells(cell_values)
	if cells.is_empty(): return
	var builder := _new_builder()
	_append_cells(builder, style_id, cells)
	var colours := _preview_colours(style_id, valid)
	var mesh := _mesh_from_builder(builder, colours)
	if mesh != null:
		_preview_node = MeshInstance3D.new()
		_preview_node.name = "PathPreview"
		_preview_node.mesh = mesh
		for surface in mesh.get_surface_count():
			mesh.surface_set_material(surface, _preview_material(colours[mini(surface, 1)], 0.48))
		_preview_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_preview_node)
	var last: Vector2i = cells.back()
	var point := Region.cell_center(last)
	_preview_marker = MeshInstance3D.new()
	_preview_marker.name = "PathPreviewMarker_%s" % ("Valid" if valid else "Invalid")
	_preview_marker.mesh = _marker_mesh(point, valid)
	_preview_marker.material_override = _preview_material(Color("#a6e39b") if valid else Color("#f08a78"), 0.92)
	_preview_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_preview_marker)
	_stats["preview_cells"] = cells.size()

## Temporary caller bridge while scene interaction finishes moving to paint.
func show_preview(style_id: String, width: float, point_values: Array, valid: bool, reason: String) -> void:
	var cells: Array = []
	var radius := maxf(Grid.UNIT * 0.5, width * 0.5)
	var previous := Vector2(NAN, NAN)
	for value in point_values:
		var point := _point_from_value(value)
		if not point.is_finite(): continue
		cells = Region.union_cells(cells, Region.brush_cells(point, radius)) if not previous.is_finite() else Region.union_cells(cells, Region.stroke_cells(previous, point, radius))
		previous = point
	show_cell_preview(style_id, cells, valid, reason)

func hide_preview() -> void:
	if is_instance_valid(_preview_node): _preview_node.queue_free()
	if is_instance_valid(_preview_marker): _preview_marker.queue_free()
	_preview_node = null
	_preview_marker = null
	_stats["preview_cells"] = 0

func stats() -> Dictionary:
	var result := _stats.duplicate(true)
	result["grass_contact"] = {"tufts": 0, "cells": 0, "vertices": 0, "triangles": 0, "draw_calls": 0, "max_tufts": 0}
	var opaque_surface_draws := 0
	for style: Dictionary in result["styles"].values(): opaque_surface_draws += int(style["surfaces"])
	result["opaque_surface_draws"] = opaque_surface_draws
	return result

func _clear_authoritative_nodes() -> void:
	for style_id in _style_nodes:
		var node: Node = _style_nodes[style_id]
		if is_instance_valid(node): node.queue_free()
	_style_nodes.clear()
	_stats = {"styles": {}, "draw_calls": 0, "geometry_cells": 0, "preview_cells": _stats.get("preview_cells", 0)}

func _cells_for_style(path_values: Array, style_id: String) -> Array:
	var cells: Array = []
	for value in path_values:
		if not value is Dictionary: continue
		var path: Dictionary = value
		if str(path.get("style_id", "")) != style_id: continue
		cells = Region.union_cells(cells, path.get("cells", []))
	return cells

func _append_cells(builder: Dictionary, style_id: String, cells: Array) -> void:
	var normalized := Region.normalize_cells(cells)
	var profile := Region.distance_field(normalized)
	for cell: Vector2i in normalized:
		var point := Region.cell_center(cell)
		var surface_y := _surface_height(point)
		var material_index := 0
		match style_id:
			"packed_earth":
				material_index = 1 if int(profile.get(cell, 0)) > 0 else 0
			"cobblestone":
				material_index = posmod(cell.x + cell.y, 2)
			"stepping_stones":
				# Painted stepping-stone authority is an area mask. Presentation keeps
				# a sparse cadence so the mask never becomes a solid patio.
				if posmod(cell.x * 17 + cell.y * 31, 5) > 1: continue
				material_index = posmod(cell.x + cell.y, 2)
		var size := Vector3(Grid.UNIT, PATH_THICKNESS, Grid.UNIT)
		if style_id == "stepping_stones": size = Vector3(Grid.UNIT * 0.82, PATH_THICKNESS * 1.4, Grid.UNIT * 0.82)
		var centre := Vector3(point.x, surface_y + TOP_EPSILON - size.y * 0.5, point.y)
		_append_box(builder, centre, size, Basis.IDENTITY, material_index)

func _surface_height(point: Vector2) -> float:
	if backend == null or not backend.has_method("voxel_at"): return 8.0
	var scale_value := maxf(0.001, float(backend.get("voxel_scale")))
	var patch: Vector3i = backend.get("patch_size")
	var x := clampi(floori(point.x / scale_value), 0, patch.x - 1)
	var z := clampi(floori(point.y / scale_value), 0, patch.z - 1)
	for y in range(patch.y - 2, -1, -1):
		if int(backend.voxel_at(Vector3i(x, y, z))) != 0 and int(backend.voxel_at(Vector3i(x, y + 1, z))) == 0:
			return float(y + 1) * scale_value
	return 8.0

func _point_from_value(value: Variant) -> Vector2:
	if value is Vector2: return value
	if value is Array and value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float): return Vector2(float(value[0]), float(value[1]))
	return Vector2(NAN, NAN)

func _new_builder() -> Dictionary:
	return {"surfaces": [{"vertices": [], "normals": [], "indices": []}, {"vertices": [], "normals": [], "indices": []}], "cells": 0}

func _append_box(builder: Dictionary, center: Vector3, size: Vector3, basis: Basis, material_index: int) -> void:
	var surface: Dictionary = builder["surfaces"][material_index]
	var vertices: Array = surface["vertices"]
	var normals: Array = surface["normals"]
	var indices: Array = surface["indices"]
	var half := size * 0.5
	var faces := [
		[Vector3.UP, [Vector3(-half.x, half.y, -half.z), Vector3(half.x, half.y, -half.z), Vector3(half.x, half.y, half.z), Vector3(-half.x, half.y, half.z)]],
		[Vector3.DOWN, [Vector3(-half.x, -half.y, half.z), Vector3(half.x, -half.y, half.z), Vector3(half.x, -half.y, -half.z), Vector3(-half.x, -half.y, -half.z)]],
		[Vector3.FORWARD, [Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z), Vector3(half.x, half.y, -half.z), Vector3(-half.x, half.y, -half.z)]],
		[Vector3.BACK, [Vector3(half.x, -half.y, half.z), Vector3(-half.x, -half.y, half.z), Vector3(-half.x, half.y, half.z), Vector3(half.x, half.y, half.z)]],
		[Vector3.LEFT, [Vector3(-half.x, -half.y, half.z), Vector3(-half.x, -half.y, -half.z), Vector3(-half.x, half.y, -half.z), Vector3(-half.x, half.y, half.z)]],
		[Vector3.RIGHT, [Vector3(half.x, -half.y, -half.z), Vector3(half.x, -half.y, half.z), Vector3(half.x, half.y, half.z), Vector3(half.x, half.y, -half.z)]],
	]
	for face in faces:
		var normal: Vector3 = basis * face[0]
		var base := vertices.size()
		for corner in face[1]:
			vertices.append(center + basis * (corner as Vector3))
			normals.append(normal)
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	surface["vertices"] = vertices
	surface["normals"] = normals
	surface["indices"] = indices
	builder["surfaces"][material_index] = surface
	builder["cells"] = int(builder["cells"]) + 1

func _mesh_from_builder(builder: Dictionary, colours: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var has_geometry := false
	for index in 2:
		var surface: Dictionary = builder["surfaces"][index]
		if (surface["vertices"] as Array).is_empty(): continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(surface["vertices"])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(surface["normals"])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(surface["indices"])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _path_material(colours[index]))
		has_geometry = true
	return mesh if has_geometry else null

func _builder_cell_count(builder: Dictionary) -> int:
	return int(builder.get("cells", 0))

func _builder_triangles(builder: Dictionary) -> int:
	var total := 0
	for surface: Dictionary in builder["surfaces"]: total += (surface["indices"] as Array).size() / 3
	return total

func _builder_vertices(builder: Dictionary) -> int:
	var total := 0
	for surface: Dictionary in builder["surfaces"]: total += (surface["vertices"] as Array).size()
	return total

func _path_material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.96
	return material

func _preview_colours(style_id: String, valid: bool) -> Array:
	var tint := Color("#a7e0a0") if valid else Color("#ef8b78")
	var base: Color = STYLE_COLOURS.get(style_id, [Color.WHITE, Color.WHITE])[0]
	return [base.lerp(tint, 0.48), base.lerp(tint, 0.66)]

func _preview_material(colour: Color, alpha: float) -> StandardMaterial3D:
	var material := _path_material(colour)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = alpha
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func _marker_mesh(point: Vector2, valid: bool) -> ArrayMesh:
	var builder := _new_builder()
	var y := _surface_height(point) + 0.25
	if valid:
		_append_box(builder, Vector3(point.x, y, point.y), Vector3(0.6, 0.12, 0.12), Basis.IDENTITY, 0)
		_append_box(builder, Vector3(point.x, y, point.y), Vector3(0.12, 0.12, 0.6), Basis.IDENTITY, 0)
	else:
		_append_box(builder, Vector3(point.x, y, point.y), Vector3(0.65, 0.12, 0.10), Basis(Vector3.UP, deg_to_rad(45.0)), 0)
		_append_box(builder, Vector3(point.x, y + 0.02, point.y), Vector3(0.65, 0.12, 0.10), Basis(Vector3.UP, deg_to_rad(-45.0)), 0)
	return _mesh_from_builder(builder, [Color.WHITE, Color.WHITE])
