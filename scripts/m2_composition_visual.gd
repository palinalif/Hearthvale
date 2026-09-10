extends Node3D
class_name M2CompositionVisual

## Disposable presentation for saved hamlet-composition records. Authority stays
## compact: bridges save two bank points; small details save style, footprint and
## quarter-turn orientation. Everything visible here can be rebuilt from that.

const BRIDGE_COLOURS := {
	"timber": [Color("#8c6548"), Color("#5f4637")],
	"stone": [Color("#8f958d"), Color("#6f756f")],
}
const GARDEN_COLOURS := {
	"cottage_flowers": [Color("#6f5039"), Color("#9b9381"), Color("#55734f"), Color("#d8a2a0")],
	"kitchen_rows": [Color("#6a4932"), Color("#8e6848"), Color("#5d794d"), Color("#9aaa62")],
	"herb_garden": [Color("#73513a"), Color("#8d8069"), Color("#4f7154"), Color("#81966b")],
}
const FENCE_COLOURS := {
	"rustic_fence": [Color("#806047"), Color("#5b4435"), Color("#9a7658")],
	"rustic_gate": [Color("#806047"), Color("#5b4435"), Color("#9a7658")],
}
const BRIDGE_PLANK_TARGET := 0.28

var backend: Node
var _bridge_nodes: Array[MeshInstance3D] = []
var _garden_nodes: Array[MeshInstance3D] = []
var _fence_nodes: Array[MeshInstance3D] = []
var _bridge_preview_node: MeshInstance3D
var _garden_preview_node: MeshInstance3D
var _fence_preview_node: MeshInstance3D
var _stats := {"bridge_count": 0, "garden_count": 0, "fence_count": 0, "geometry_cells": 0, "bridge_geometry_cells": 0, "garden_geometry_cells": 0, "fence_geometry_cells": 0, "preview_cells": 0}

func attach_backend(value: Node) -> void:
	backend = value

func rebuild_bridges(bridge_values: Array, terrain_backend: Node = null) -> void:
	if terrain_backend != null: backend = terrain_backend
	_clear_nodes(_bridge_nodes)
	var builders := {"timber": _new_builder(2), "stone": _new_builder(2)}
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
	_stats["bridge_geometry_cells"] = _builder_cell_count(builders["timber"]) + _builder_cell_count(builders["stone"])
	_update_total_cells()

func rebuild_gardens(composition_values: Array, terrain_backend: Node = null) -> void:
	if terrain_backend != null: backend = terrain_backend
	_clear_nodes(_garden_nodes)
	var builders := {}
	for style_id in GARDEN_COLOURS: builders[style_id] = _new_builder(4)
	var count := 0
	for value in composition_values:
		if not value is Dictionary: continue
		var record: Dictionary = value
		if str(record.get("kind", "")) != "garden": continue
		var style_id := str(record.get("style_id", ""))
		if not builders.has(style_id): continue
		_append_garden(builders[style_id], record)
		count += 1
	var cells := 0
	for style_id in GARDEN_COLOURS:
		var builder: Dictionary = builders[style_id]
		cells += _builder_cell_count(builder)
		var mesh := _mesh_from_builder(builder, GARDEN_COLOURS[style_id])
		if mesh == null: continue
		var node := MeshInstance3D.new()
		node.name = "GardenBatch_" + style_id
		node.mesh = mesh
		add_child(node)
		_garden_nodes.append(node)
	_stats["garden_count"] = count
	_stats["garden_geometry_cells"] = cells
	_update_total_cells()

func rebuild_fences(composition_values: Array, terrain_backend: Node = null) -> void:
	if terrain_backend != null: backend = terrain_backend
	_clear_nodes(_fence_nodes)
	var builders := {}
	for style_id in FENCE_COLOURS: builders[style_id] = _new_builder(3)
	var count := 0
	for value in composition_values:
		if not value is Dictionary: continue
		var record: Dictionary = value
		if str(record.get("kind", "")) != "fence": continue
		var style_id := str(record.get("style_id", ""))
		if not builders.has(style_id): continue
		_append_fence(builders[style_id], record)
		count += 1
	var cells := 0
	for style_id in FENCE_COLOURS:
		var builder: Dictionary = builders[style_id]
		cells += _builder_cell_count(builder)
		var mesh := _mesh_from_builder(builder, FENCE_COLOURS[style_id])
		if mesh == null: continue
		var node := MeshInstance3D.new()
		node.name = "FenceBatch_" + style_id
		node.mesh = mesh
		add_child(node)
		_fence_nodes.append(node)
	_stats["fence_count"] = count
	_stats["fence_geometry_cells"] = cells
	_update_total_cells()

func show_bridge_preview(style_id: String, width: float, start: Vector2, finish: Vector2, valid: bool) -> void:
	hide_bridge_preview()
	if not BRIDGE_COLOURS.has(style_id) or not start.is_finite() or not finish.is_finite(): return
	var builder := _new_builder(2)
	_append_bridge(builder, style_id, width, start, finish)
	var mesh := _mesh_from_builder(builder, _preview_colours(BRIDGE_COLOURS[style_id], valid), true)
	if mesh == null: return
	_bridge_preview_node = MeshInstance3D.new()
	_bridge_preview_node.name = "BridgePreview"
	_bridge_preview_node.mesh = mesh
	_bridge_preview_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bridge_preview_node)
	_stats["preview_cells"] = _builder_cell_count(builder)

func hide_bridge_preview() -> void:
	if is_instance_valid(_bridge_preview_node): _bridge_preview_node.queue_free()
	_bridge_preview_node = null
	_stats["preview_cells"] = 0

func show_garden_preview(style_id: String, point: Vector2, size: Vector2, yaw_quarters: int, valid: bool) -> void:
	hide_garden_preview()
	if not GARDEN_COLOURS.has(style_id) or not point.is_finite(): return
	var record := {"kind": "garden", "style_id": style_id, "position": [point.x, point.y], "size": [size.x, size.y], "yaw_quarters": posmod(yaw_quarters, 4)}
	var builder := _new_builder(4)
	_append_garden(builder, record)
	var mesh := _mesh_from_builder(builder, _preview_colours(GARDEN_COLOURS[style_id], valid), true)
	if mesh == null: return
	_garden_preview_node = MeshInstance3D.new()
	_garden_preview_node.name = "GardenPreview"
	_garden_preview_node.mesh = mesh
	_garden_preview_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_garden_preview_node)
	_stats["preview_cells"] = _builder_cell_count(builder)

func hide_garden_preview() -> void:
	if is_instance_valid(_garden_preview_node): _garden_preview_node.queue_free()
	_garden_preview_node = null
	_stats["preview_cells"] = 0

func show_fence_preview(style_id: String, point: Vector2, size: Vector2, yaw_quarters: int, valid: bool) -> void:
	hide_fence_preview()
	if not FENCE_COLOURS.has(style_id) or not point.is_finite(): return
	var record := {"kind": "fence", "style_id": style_id, "position": [point.x, point.y], "size": [size.x, size.y], "yaw_quarters": posmod(yaw_quarters, 4)}
	var builder := _new_builder(3)
	_append_fence(builder, record)
	var mesh := _mesh_from_builder(builder, _preview_colours(FENCE_COLOURS[style_id], valid), true)
	if mesh == null: return
	_fence_preview_node = MeshInstance3D.new()
	_fence_preview_node.name = "FencePreview"
	_fence_preview_node.mesh = mesh
	_fence_preview_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fence_preview_node)
	_stats["preview_cells"] = _builder_cell_count(builder)

func hide_fence_preview() -> void:
	if is_instance_valid(_fence_preview_node): _fence_preview_node.queue_free()
	_fence_preview_node = null
	_stats["preview_cells"] = 0

func stats() -> Dictionary:
	return _stats.duplicate(true)

func _clear_nodes(nodes: Array[MeshInstance3D]) -> void:
	for node in nodes:
		if is_instance_valid(node): node.queue_free()
	nodes.clear()

func _update_total_cells() -> void:
	_stats["geometry_cells"] = int(_stats.get("bridge_geometry_cells", 0)) + int(_stats.get("garden_geometry_cells", 0)) + int(_stats.get("fence_geometry_cells", 0))

func _preview_colours(base_values: Array, valid: bool) -> Array:
	var tint := Color("#a7e0a0") if valid else Color("#ef8b78")
	var result: Array = []
	for colour_value in base_values: result.append((colour_value as Color).lerp(tint, 0.56))
	return result

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
	if style_id == "timber": _append_timber_details(builder, width, start, finish, y0, y1, basis, length)
	else: _append_stone_details(builder, width, start, finish, y0, y1, basis, length)

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
	for side in [-0.32, 0.32]:
		var beam_center := Vector3(midpoint.x, (y0 + y1) * 0.5 + 0.035, midpoint.y) + basis * Vector3(side * width, 0, 0)
		_append_box(builder, beam_center, Vector3(0.10, 0.10, length), basis, 1)

func _append_stone_details(builder: Dictionary, width: float, start: Vector2, finish: Vector2, y0: float, y1: float, basis: Basis, length: float) -> void:
	var midpoint := start.lerp(finish, 0.5)
	var center_y := (y0 + y1) * 0.5 + 0.22
	for side in [-1.0, 1.0]:
		var parapet_center := Vector3(midpoint.x, center_y, midpoint.y) + basis * Vector3(side * (width * 0.5 + 0.03), 0, 0)
		_append_box(builder, parapet_center, Vector3(0.14, 0.34, length), basis, 1)
	for amount in [0.03, 0.97]:
		var point := start.lerp(finish, amount)
		var y := lerpf(y0, y1, amount) + 0.02
		_append_box(builder, Vector3(point.x, y, point.y), Vector3(width + 0.20, 0.22, 0.28), basis, 1)

func _append_garden(builder: Dictionary, record: Dictionary) -> void:
	var style_id := str(record.get("style_id", ""))
	var point := _point(record.get("position", []))
	var size_value: Array = record.get("size", [2.0, 2.0])
	if not point.is_finite() or size_value.size() != 2: return
	var size := Vector2(float(size_value[0]), float(size_value[1]))
	var basis := Basis(Vector3.UP, float(posmod(int(record.get("yaw_quarters", 0)), 4)) * PI * 0.5)
	var center := Vector3(point.x, _surface_height(point), point.y)
	match style_id:
		"cottage_flowers": _append_cottage_flower_garden(builder, center, size, basis)
		"kitchen_rows": _append_kitchen_garden(builder, center, size, basis)
		"herb_garden": _append_herb_garden(builder, center, size, basis)

func _append_garden_base(builder: Dictionary, center: Vector3, size: Vector2, basis: Basis, border_material: int = 1) -> void:
	_append_box(builder, center + Vector3.UP * 0.025, Vector3(size.x - 0.16, 0.05, size.y - 0.16), basis, 0)
	var edge := 0.09
	_append_box(builder, center + basis * Vector3(0, 0.065, -size.y * 0.5 + edge * 0.5), Vector3(size.x, 0.13, edge), basis, border_material)
	_append_box(builder, center + basis * Vector3(0, 0.065, size.y * 0.5 - edge * 0.5), Vector3(size.x, 0.13, edge), basis, border_material)
	_append_box(builder, center + basis * Vector3(-size.x * 0.5 + edge * 0.5, 0.065, 0), Vector3(edge, 0.13, maxf(0.1, size.y - edge * 2.0)), basis, border_material)
	_append_box(builder, center + basis * Vector3(size.x * 0.5 - edge * 0.5, 0.065, 0), Vector3(edge, 0.13, maxf(0.1, size.y - edge * 2.0)), basis, border_material)

func _append_cottage_flower_garden(builder: Dictionary, center: Vector3, size: Vector2, basis: Basis) -> void:
	_append_garden_base(builder, center, size, basis)
	for index in 15:
		var u := -0.42 + float(index % 5) * 0.21 + 0.035 * sin(float(index * 7))
		var v := -0.32 + float(index / 5) * 0.32 + 0.045 * sin(float(index * 11 + 2))
		var local := Vector3(u * size.x, 0, v * size.y)
		var height := 0.18 + 0.12 * (sin(float(index * 5)) * 0.5 + 0.5)
		_append_box(builder, center + basis * local + Vector3.UP * (0.08 + height * 0.5), Vector3(0.055, height, 0.055), basis, 2)
		var bloom_size := 0.075 + 0.025 * float(index % 3)
		_append_box(builder, center + basis * local + Vector3.UP * (0.08 + height), Vector3(bloom_size, 0.07, bloom_size), basis, 3)

func _append_kitchen_garden(builder: Dictionary, center: Vector3, size: Vector2, basis: Basis) -> void:
	_append_garden_base(builder, center, size, basis, 1)
	for row in 3:
		var row_x := (float(row) - 1.0) * size.x * 0.27
		_append_box(builder, center + basis * Vector3(row_x, 0.055, 0), Vector3(size.x * 0.18, 0.11, size.y * 0.78), basis, 0)
		for plant in 5:
			var z := -size.y * 0.30 + float(plant) * size.y * 0.15
			var h := 0.14 + 0.05 * float((row + plant) % 3)
			_append_box(builder, center + basis * Vector3(row_x, 0, z) + Vector3.UP * (0.10 + h * 0.5), Vector3(0.13, h, 0.13), basis, 2 if (row + plant) % 2 == 0 else 3)

func _append_herb_garden(builder: Dictionary, center: Vector3, size: Vector2, basis: Basis) -> void:
	_append_garden_base(builder, center, size, basis)
	_append_box(builder, center + Vector3.UP * 0.075, Vector3(0.07, 0.15, size.y - 0.20), basis, 1)
	_append_box(builder, center + Vector3.UP * 0.075, Vector3(size.x - 0.20, 0.15, 0.07), basis, 1)
	for index in 16:
		var column := index % 4
		var row := index / 4
		var x := -size.x * 0.34 + float(column) * size.x * 0.225
		var z := -size.y * 0.34 + float(row) * size.y * 0.225
		var h := 0.10 + 0.08 * (sin(float(index * 4 + 1)) * 0.5 + 0.5)
		_append_box(builder, center + basis * Vector3(x, 0, z) + Vector3.UP * (0.08 + h * 0.5), Vector3(0.11, h, 0.11), basis, 2 if index % 3 else 3)

func _append_fence(builder: Dictionary, record: Dictionary) -> void:
	var style_id := str(record.get("style_id", ""))
	var point := _point(record.get("position", []))
	var size_value: Array = record.get("size", [2.0, 0.25])
	if not point.is_finite() or size_value.size() != 2: return
	var size := Vector2(float(size_value[0]), float(size_value[1]))
	var basis := Basis(Vector3.UP, float(posmod(int(record.get("yaw_quarters", 0)), 4)) * PI * 0.5)
	var center := Vector3(point.x, _surface_height(point), point.y)
	if style_id == "rustic_gate": _append_rustic_gate(builder, center, size, basis)
	else: _append_rustic_fence(builder, center, size, basis)

func _append_rustic_fence(builder: Dictionary, center: Vector3, size: Vector2, basis: Basis) -> void:
	var post_count := maxi(2, ceili(size.x / 0.75) + 1)
	for index in post_count:
		var amount := float(index) / float(post_count - 1)
		var x := lerpf(-size.x * 0.5, size.x * 0.5, amount)
		var post_height := 0.78 + 0.06 * sin(float(index * 5 + post_count))
		_append_box(builder, center + basis * Vector3(x, post_height * 0.5, 0), Vector3(0.10, post_height, 0.10), basis, 1 if index % 2 else 0)
	for height in [0.34, 0.63]:
		_append_box(builder, center + basis * Vector3(0, height, 0), Vector3(maxf(0.1, size.x - 0.08), 0.085, 0.075), basis, 2)

func _append_rustic_gate(builder: Dictionary, center: Vector3, size: Vector2, basis: Basis) -> void:
	var half := size.x * 0.5
	for side in [-1.0, 1.0]:
		_append_box(builder, center + basis * Vector3(side * half, 0.48, 0), Vector3(0.13, 0.96, 0.13), basis, 1)
	for height in [0.30, 0.66]:
		_append_box(builder, center + basis * Vector3(0, height, 0), Vector3(maxf(0.3, size.x - 0.28), 0.09, 0.075), basis, 2)
	var brace_basis := basis * Basis(Vector3.FORWARD, deg_to_rad(-28.0))
	_append_box(builder, center + basis * Vector3(0, 0.48, 0.004), Vector3(maxf(0.35, (size.x - 0.38) * 0.92), 0.075, 0.065), brace_basis, 0)
	_append_box(builder, center + basis * Vector3(half - 0.17, 0.52, -0.06), Vector3(0.08, 0.08, 0.10), basis, 1)

func _surface_height(point: Vector2) -> float:
	if backend == null or not backend.has_method("voxel_at"): return 8.0
	var scale_value := maxf(0.001, float(backend.get("voxel_scale")))
	var patch: Vector3i = backend.get("patch_size")
	var x := clampi(floori(point.x / scale_value), 0, patch.x - 1)
	var z := clampi(floori(point.y / scale_value), 0, patch.z - 1)
	for y in range(patch.y - 2, -1, -1):
		if int(backend.voxel_at(Vector3i(x, y, z))) != 0 and int(backend.voxel_at(Vector3i(x, y + 1, z))) == 0: return float(y + 1) * scale_value
	return 8.0

func _point(value: Variant) -> Vector2:
	if value is Vector2: return value
	if value is Array and value.size() == 2: return Vector2(float(value[0]), float(value[1]))
	return Vector2(NAN, NAN)

func _new_builder(surface_count: int = 2) -> Dictionary:
	var surfaces: Array = []
	for _index in maxi(1, surface_count): surfaces.append({"vertices": [], "normals": [], "indices": []})
	return {"surfaces": surfaces, "cells": 0}

func _append_box(builder: Dictionary, center: Vector3, size: Vector3, basis: Basis, material_index: int) -> void:
	var surfaces: Array = builder["surfaces"]
	if material_index < 0 or material_index >= surfaces.size(): return
	var surface: Dictionary = surfaces[material_index]
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
	surfaces[material_index] = surface
	builder["surfaces"] = surfaces
	builder["cells"] = int(builder["cells"]) + 1

func _mesh_from_builder(builder: Dictionary, colours: Array, preview: bool = false) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var has_geometry := false
	var surfaces: Array = builder["surfaces"]
	for index in surfaces.size():
		var surface: Dictionary = surfaces[index]
		if (surface["vertices"] as Array).is_empty(): continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(surface["vertices"])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(surface["normals"])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(surface["indices"])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.albedo_color = colours[mini(index, colours.size() - 1)]
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
