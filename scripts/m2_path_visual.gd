extends Node3D
class_name M2PathVisual

## Disposable composition renderer. Paths are sampled from their saved X/Z
## polyline and the current voxel surface every rebuild; no terrain cells are
## written by this node.

const Grid = preload("res://scripts/visual_grid.gd")
const State = preload("res://scripts/landscape_state.gd")
const STYLE_ORDER: Array[String] = ["packed_earth", "cobblestone", "stepping_stones"]
const SAMPLE_SPACING := 0.5
const PATH_THICKNESS := 0.125
const STYLE_COLOURS := {
	"packed_earth": [Color("#a8784f"), Color("#c29261")],
	"cobblestone": [Color("#89908b"), Color("#b6b9a5")],
	"stepping_stones": [Color("#a5a398"), Color("#d0c4a4")],
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
	var builders := {}
	for style_id in STYLE_ORDER: builders[style_id] = _new_builder()
	var geometry_cells := 0
	for path_value in path_values:
		if not path_value is Dictionary: continue
		var path: Dictionary = path_value
		var style_id := str(path.get("style_id", ""))
		if not builders.has(style_id): continue
		var points: Array = path.get("points", [])
		if points.size() < 2: continue
		geometry_cells += _append_path(builders[style_id], style_id, float(path.get("width", 0.0)), points, int(path.get("id", 0)))
	for style_id in STYLE_ORDER:
		var mesh := _mesh_from_builder(builders[style_id], STYLE_COLOURS[style_id])
		if mesh == null: continue
		var node := MeshInstance3D.new()
		node.name = "PathBatch_" + style_id
		node.mesh = mesh
		add_child(node)
		_style_nodes[style_id] = node
		_stats["styles"][style_id] = {"geometry": true, "surfaces": mesh.get_surface_count(), "cells": _builder_cell_count(builders[style_id])}
		_stats["draw_calls"] = _style_nodes.size()
		_stats["geometry_cells"] = geometry_cells

func show_preview(style_id: String, width: float, point_values: Array, valid: bool, reason: String) -> void:
	hide_preview()
	if point_values.size() < 1 or not STYLE_ORDER.has(style_id): return
	var builders := {}
	for candidate in STYLE_ORDER: builders[candidate] = _new_builder()
	var path_points: Array = []
	for point_value in point_values:
		var point := _point_from_value(point_value)
		if point.is_finite(): path_points.append([point.x, point.y])
	if path_points.is_empty(): return
	var needs_starter_sample := path_points.size() == 1
	if path_points.size() > 1:
		var first_point := Vector2(float(path_points[0][0]), float(path_points[0][1]))
		var last_point := Vector2(float(path_points.back()[0]), float(path_points.back()[1]))
		needs_starter_sample = first_point.distance_to(last_point) < 0.001
	if needs_starter_sample:
		# A first point still gets a small style sample so the player can see
		# which tool is active before adding the first bend.
		var p := Vector2(float(path_points[0][0]), float(path_points[0][1]))
		path_points.append([p.x + 0.25, p.y])
	_append_path(builders[style_id], style_id, width, path_points, 0)
	var mesh := _mesh_from_builder(builders[style_id], _preview_colours(style_id, valid))
	if mesh != null:
		_preview_node = MeshInstance3D.new()
		_preview_node.name = "PathPreview"
		_preview_node.mesh = mesh
		for surface in mesh.get_surface_count():
			var preview_colour: Color = _preview_colours(style_id, valid)[mini(surface, 1)]
			mesh.surface_set_material(surface, _preview_material(preview_colour, 0.48))
		_preview_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_preview_node)
	var last := Vector2(float(path_points.back()[0]), float(path_points.back()[1]))
	_preview_marker = MeshInstance3D.new()
	_preview_marker.name = "PathPreviewMarker_%s" % ("Valid" if valid else "Invalid")
	# The marker is a plus for valid aim and a blocky X for invalid aim, so
	# state is not conveyed by colour alone.
	_preview_marker.mesh = _marker_mesh(last, valid)
	_preview_marker.material_override = _preview_material(Color("#a6e39b") if valid else Color("#f08a78"), 0.92)
	_preview_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_preview_marker)
	_stats["preview_cells"] = _builder_cell_count(builders[style_id])

func hide_preview() -> void:
	if is_instance_valid(_preview_node): _preview_node.queue_free()
	if is_instance_valid(_preview_marker): _preview_marker.queue_free()
	_preview_node = null
	_preview_marker = null
	_stats["preview_cells"] = 0

func stats() -> Dictionary:
	return _stats.duplicate(true)

func _clear_authoritative_nodes() -> void:
	for style_id in _style_nodes:
		var node: Node = _style_nodes[style_id]
		if is_instance_valid(node): node.queue_free()
	_style_nodes.clear()
	_stats = {"styles": {}, "draw_calls": 0, "geometry_cells": 0, "preview_cells": _stats.get("preview_cells", 0)}

func _append_path(builder: Dictionary, style_id: String, width: float, point_values: Array, path_id: int) -> int:
	var points := _sample_polyline(point_values)
	if points.size() < 2: return 0
	var cells := 0
	var safe_width := clampf(width, State.PATH_MIN_WIDTH, State.PATH_MAX_WIDTH)
	match style_id:
		"packed_earth":
			for index in points.size() - 1:
				var sample: Dictionary = points[index]
				var tangent: Vector2 = sample["tangent"]
				var yaw := atan2(tangent.x, tangent.y)
				var irregular := 1.0 + 0.06 * sin(float(path_id * 17 + index * 13))
				_append_box(builder, sample["point"] + Vector3.UP * (PATH_THICKNESS * 0.5), Vector3(safe_width * irregular, PATH_THICKNESS, SAMPLE_SPACING + 0.12), Basis(Vector3.UP, yaw), 0)
				cells += 1
		"cobblestone":
			var rows := maxi(2, ceili(safe_width / 0.52))
			for index in points.size() - 1:
				var sample: Dictionary = points[index]
				var tangent: Vector2 = sample["tangent"]
				var basis := Basis(Vector3.UP, atan2(tangent.x, tangent.y))
				for row in rows:
					var across := (float(row) + 0.5) / float(rows) - 0.5
					var along := 0.035 * sin(float(path_id + row * 5 + index * 3))
					var local := Vector3(across * safe_width, 0, along)
					var stone_width := safe_width / float(rows) - 0.075
					_append_box(builder, sample["point"] + basis * local + Vector3.UP * (PATH_THICKNESS * 0.5), Vector3(maxf(0.20, stone_width), PATH_THICKNESS, 0.42), basis, 0 if row > 0 and row < rows - 1 else 1)
					cells += 1
		"stepping_stones":
			var stride := 2
			for index in range(0, points.size() - 1, stride):
				var sample: Dictionary = points[index]
				var tangent: Vector2 = sample["tangent"]
				var basis := Basis(Vector3.UP, atan2(tangent.x, tangent.y))
				var wobble := 0.12 * sin(float(path_id * 3 + index * 7))
				var cluster_center: Vector3 = sample["point"] + basis * Vector3(wobble, 0, 0)
				_append_box(builder, cluster_center + Vector3.UP * (PATH_THICKNESS * 0.5), Vector3(safe_width * 0.58, PATH_THICKNESS, 0.48), basis, 0)
				_append_box(builder, cluster_center + basis * Vector3(-safe_width * 0.22, 0, 0.11) + Vector3.UP * (PATH_THICKNESS * 1.5), Vector3(safe_width * 0.30, PATH_THICKNESS, 0.27), basis, 1)
				cells += 2
	return cells

func _sample_polyline(point_values: Array) -> Array:
	var result: Array = []
	for index in range(1, point_values.size()):
		var a := _point_from_value(point_values[index - 1])
		var b := _point_from_value(point_values[index])
		if not a.is_finite() or not b.is_finite(): continue
		var delta := b - a
		var distance := delta.length()
		var steps := maxi(1, ceili(distance / SAMPLE_SPACING))
		var tangent := delta.normalized() if distance > 0.0001 else Vector2(0, 1)
		for step in steps:
			var alpha := float(step) / float(steps)
			result.append({"point": Vector3(a.lerp(b, alpha).x, _surface_height(a.lerp(b, alpha)), a.lerp(b, alpha).y), "tangent": tangent})
	# Include the final point without adding a duplicate if the last segment
	# already landed on it.
	if point_values.size() >= 2:
		var final_point := _point_from_value(point_values.back())
		if final_point.is_finite() and (result.is_empty() or Vector2(result.back()["point"].x, result.back()["point"].z).distance_to(final_point) > 0.001):
			var previous := _point_from_value(point_values[point_values.size() - 2])
			var final_tangent := (final_point - previous).normalized()
			result.append({"point": Vector3(final_point.x, _surface_height(final_point), final_point.y), "tangent": final_tangent})
	return result

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

func _path_material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.92
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
		_append_box(builder, Vector3(point.x, y, point.y), Vector3(0.9, 0.18, 0.18), Basis.IDENTITY, 0)
		_append_box(builder, Vector3(point.x, y, point.y), Vector3(0.18, 0.18, 0.9), Basis.IDENTITY, 0)
		_append_box(builder, Vector3(point.x, y + 0.22, point.y), Vector3(0.24, 0.24, 0.24), Basis.IDENTITY, 1)
	else:
		_append_box(builder, Vector3(point.x, y, point.y), Vector3(1.0, 0.18, 0.16), Basis(Vector3.UP, deg_to_rad(45.0)), 0)
		_append_box(builder, Vector3(point.x, y + 0.04, point.y), Vector3(1.0, 0.18, 0.16), Basis(Vector3.UP, deg_to_rad(-45.0)), 0)
	return _mesh_from_builder(builder, [Color.WHITE, Color.WHITE])
