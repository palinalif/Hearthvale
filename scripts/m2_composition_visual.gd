extends Node3D
class_name M2CompositionVisual

## Disposable presentation for saved hamlet-composition records. Bridge authority
## is only two snapped X/Z points plus style/width; planks, rails, parapets and
## supports are regenerated against the current terrain surface.

const BRIDGE_COLOURS := {
	"timber": [Color("#8c6548"), Color("#5f4637")],
	"stone": [Color("#8f958d"), Color("#6f756f")],
}
const BRIDGE_PLANK_TARGET := 0.28

var backend: Node
var _bridge_nodes: Array[MeshInstance3D] = []
var _preview_node: MeshInstance3D
var _stats := {"bridge_count": 0, "geometry_cells": 0, "preview_cells": 0}

func attach_backend(value: Node) -> void:
	backend = value

func rebuild_bridges(bridge_values: Array, terrain_backend: Node = null) -> void:
	if terrain_backend != null: backend = terrain_backend
	for node in _bridge_nodes:
		if is_instance_valid(node): node.queue_free()
	_bridge_nodes.clear()
	var builders := {"timber": _new_builder(), "stone": _new_builder()}
	var count := 0
	for bridge_value in bridge_values:
		if not bridge_value is Dictionary: continue
		var bridge: Dictionary = bridge_value
		var style_id := str(bridge.get("style_id", ""))
		if not builders.has(style_id): continue
		var points: Array = bridge.get("points", [])
		if points.size() != 2: continue
		_append_bridge(builders[style_id], style_id, float(bridge.get("width", 1.0)), _point(points[0]), _point(points[1]))
		count += 1
	for style_id in ["timber", "stone"]:
		var builder: Dictionary = builders[style_id]
		var mesh := _mesh_from_builder(builder, BRIDGE_COLOURS[style_id])
		if mesh == null: continue
		var node := MeshInstance3D.new()
		node.name = "BridgeBatch_" + style_id
		node.mesh = mesh
		add_child(node)
		_bridge_nodes.append(node)
	_stats["bridge_count"] = count
	_stats["geometry_cells"] = _builder_cell_count(builders["timber"]) + _builder_cell_count(builders["stone"])

func show_bridge_preview(style_id: String, width: float, start: Vector2, finish: Vector2, valid: bool) -> void:
	hide_bridge_preview()
	if not BRIDGE_COLOURS.has(style_id) or not start.is_finite() or not finish.is_finite(): return
	var builder := _new_builder()
	_append_bridge(builder, style_id, width, start, finish)
	var tint := Color("#a7e0a0") if valid else Color("#ef8b78")
	var base: Array = BRIDGE_COLOURS[style_id]
	var colours := [(base[0] as Color).lerp(tint, 0.52), (base[1] as Color).lerp(tint, 0.64)]
	var mesh := _mesh_from_builder(builder, colours, true)
	if mesh == null: return
	_preview_node = MeshInstance3D.new()
	_preview_node.name = "BridgePreview"
	_preview_node.mesh = mesh
	_preview_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_preview_node)
	_stats["preview_cells"] = _builder_cell_count(builder)

func hide_bridge_preview() -> void:
	if is_instance_valid(_preview_node): _preview_node.queue_free()
	_preview_node = null
	_stats["preview_cells"] = 0

func stats() -> Dictionary:
	return _stats.duplicate(true)

func _append_bridge(builder: Dictionary, style_id: String, width: float, start: Vector2, finish: Vector2) -> void:
	if not start.is_finite() or not finish.is_finite(): return
	var delta := finish - start
	var length := delta.length()
	if length < 0.001: return
	var tangent := delta / length
	var basis := Basis(Vector3.UP, atan2(tangent.x, tangent.y))
	var y0 := _surface_height(start)
	var y1 := _surface_height(finish)
	var plank_count := maxi(3, ceili(length / BRIDGE_PLANK_TARGET))
	var piece_length := length / float(plank_count)
	for index in plank_count:
		var amount := (float(index) + 0.5) / float(plank_count)
		var point := start.lerp(finish, amount)
		var deck_y := lerpf(y0, y1, amount) + 0.10 + sin(amount * PI) * 0.055
		var piece_width := width - (0.04 if style_id == "timber" else 0.0)
		var yaw_wobble := 0.025 * sin(float(index * 7 + plank_count)) if style_id == "timber" else 0.0
		_append_box(builder, Vector3(point.x, deck_y, point.y), Vector3(piece_width, 0.12, piece_length * 0.94), basis * Basis(Vector3.UP, yaw_wobble), index % 2)
	if style_id == "timber":
		_append_timber_details(builder, width, start, finish, y0, y1, basis, length)
	else:
		_append_stone_details(builder, width, start, finish, y0, y1, basis, length)

func _append_timber_details(builder: Dictionary, width: float, start: Vector2, finish: Vector2, y0: float, y1: float, basis: Basis, length: float) -> void:
	var midpoint := start.lerp(finish, 0.5)
	var rail_y := (y0 + y1) * 0.5 + 0.48
	for side in [-1.0, 1.0]:
		var rail_center := Vector3(midpoint.x, rail_y, midpoint.y) + basis * Vector3(side * (width * 0.5 + 0.02), 0, 0)
		_append_box(builder, rail_center, Vector3(0.075, 0.075, length), basis, 1)
		for amount in [0.08, 0.5, 0.92]:
			var point := start.lerp(finish, amount)
			var deck_y := lerpf(y0, y1, amount) + 0.10 + sin(amount * PI) * 0.055
			var post_center := Vector3(point.x, deck_y + 0.22, point.y) + basis * Vector3(side * (width * 0.5 + 0.02), 0, 0)
			_append_box(builder, post_center, Vector3(0.10, 0.48, 0.10), basis, 1)
	# Dark longitudinal beams just below the deck stop the planks reading as a
	# floating striped carpet when the bridge crosses a low bank.
	for side in [-0.32, 0.32]:
		var beam_center := Vector3(midpoint.x, (y0 + y1) * 0.5 + 0.035, midpoint.y) + basis * Vector3(side * width, 0, 0)
		_append_box(builder, beam_center, Vector3(0.10, 0.10, length), basis, 1)

func _append_stone_details(builder: Dictionary, width: float, start: Vector2, finish: Vector2, y0: float, y1: float, basis: Basis, length: float) -> void:
	var midpoint := start.lerp(finish, 0.5)
	var center_y := (y0 + y1) * 0.5 + 0.22
	for side in [-1.0, 1.0]:
		var parapet_center := Vector3(midpoint.x, center_y, midpoint.y) + basis * Vector3(side * (width * 0.5 + 0.03), 0, 0)
		_append_box(builder, parapet_center, Vector3(0.14, 0.34, length), basis, 1)
	# Short end blocks visually tie the bridge into the banks while leaving the
	# terrain itself untouched and fully sculptable.
	for amount in [0.03, 0.97]:
		var point := start.lerp(finish, amount)
		var y := lerpf(y0, y1, amount) + 0.02
		_append_box(builder, Vector3(point.x, y, point.y), Vector3(width + 0.20, 0.22, 0.28), basis, 1)

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

func _point(value: Variant) -> Vector2:
	if value is Vector2: return value
	if value is Array and value.size() == 2: return Vector2(float(value[0]), float(value[1]))
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

func _mesh_from_builder(builder: Dictionary, colours: Array, preview: bool = false) -> ArrayMesh:
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
		var material := StandardMaterial3D.new()
		material.albedo_color = colours[index]
		material.roughness = 0.9
		if preview:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color.a = 0.56
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
		has_geometry = true
	return mesh if has_geometry else null

func _builder_cell_count(builder: Dictionary) -> int:
	return int(builder.get("cells", 0))
