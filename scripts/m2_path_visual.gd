extends Node3D
class_name M2PathVisual

## Disposable composition renderer. Paths are sampled from their saved X/Z
## polyline and the current voxel surface every rebuild; no terrain cells are
## written by this node. Road slabs are mostly buried below the sampled surface,
## leaving only a shallow exposed skin so lanes read as inset rather than stacked
## on top of the landscape.

const Grid = preload("res://scripts/visual_grid.gd")
const State = preload("res://scripts/landscape_state.gd")
const STYLE_ORDER: Array[String] = ["packed_earth", "cobblestone", "stepping_stones"]
const SAMPLE_SPACING := 0.5
const PATH_THICKNESS := 0.125
const PATH_SURFACE_RISE := 0.012
const PATH_EDGE_RISE := 0.032
const PACKED_EARTH_TEXTURE_RISE := 0.017
const STONE_SURFACE_RISE := 0.026
const STONE_EDGE_RISE := 0.040
const STEPPING_STONE_THICKNESS := 0.16
const STEPPING_STONE_TOP_EPSILON := 0.004
const STYLE_COLOURS := {
	"packed_earth": [Color("#a8784f"), Color("#8f6244")],
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
				var basis := Basis(Vector3.UP, atan2(tangent.x, tangent.y))
				# Left and right shoulders wander independently. Shifting the strip
				# between those extents avoids the old perfectly centred ribbon look.
				var left_extent := safe_width * (0.50 + 0.11 * sin(float(path_id * 13 + index * 5 + 1)))
				var right_extent := safe_width * (0.50 + 0.10 * sin(float(path_id * 19 + index * 7 + 3)))
				var strip_width := maxf(safe_width * 0.72, left_extent + right_extent)
				var lateral_shift := (right_extent - left_extent) * 0.5
				var strip_length := SAMPLE_SPACING + 0.15 + 0.04 * sin(float(path_id * 5 + index * 11))
				var surface_rise := PATH_SURFACE_RISE + 0.003 * sin(float(path_id * 11 + index * 5))
				var strip_center: Vector3 = sample["point"] + basis * Vector3(lateral_shift, 0, 0)
				_append_box(builder, _embedded_center(strip_center, PATH_THICKNESS, surface_rise), Vector3(strip_width, PATH_THICKNESS, strip_length), basis, 0)

				# Broken shoulder fragments make the silhouette less uniform without
				# adding a new material or draw batch.
				var edge_width := clampf(strip_width * 0.10, 0.055, 0.10)
				for side in [-1.0, 1.0]:
					var edge_wave := sin(float(path_id * 23 + index * 9 + int(side) * 4))
					var edge_length := strip_length * (0.55 + 0.25 * (edge_wave * 0.5 + 0.5))
					var edge_offset: float = float(side) * (strip_width * 0.5 - edge_width * 0.45)
					var along_offset := 0.08 * sin(float(path_id * 7 + index * 13 + int(side) * 5))
					var edge_point: Vector3 = strip_center + basis * Vector3(edge_offset, 0, along_offset)
					_append_box(builder, _embedded_center(edge_point, PATH_THICKNESS, PATH_EDGE_RISE), Vector3(edge_width, PATH_THICKNESS, edge_length), basis, 1)
				cells += 3

				# Sparse darker patches suggest compacted soil, little ruts and damp
				# spots. They stay almost flush with the path so this is texture, not
				# a field of tiny speed bumps.
				if (path_id + index) % 2 == 0:
					var patch_across := strip_width * 0.24 * sin(float(path_id * 29 + index * 17))
					var patch_along := 0.15 * sin(float(path_id * 31 + index * 3))
					var patch_width := clampf(strip_width * (0.16 + 0.04 * sin(float(index * 7 + path_id))), 0.08, 0.20)
					var patch_length := 0.16 + 0.10 * (sin(float(path_id * 3 + index * 19)) * 0.5 + 0.5)
					var patch_yaw := 0.10 * sin(float(path_id * 17 + index * 2))
					var patch_point: Vector3 = strip_center + basis * Vector3(patch_across, 0, patch_along)
					_append_box(builder, _embedded_center(patch_point, PATH_THICKNESS * 0.35, PACKED_EARTH_TEXTURE_RISE), Vector3(patch_width, PATH_THICKNESS * 0.35, patch_length), basis * Basis(Vector3.UP, patch_yaw), 1)
					cells += 1
		"cobblestone":
			var rows := maxi(2, ceili(safe_width / 0.52))
			for index in points.size() - 1:
				var sample: Dictionary = points[index]
				var tangent: Vector2 = sample["tangent"]
				var path_basis := Basis(Vector3.UP, atan2(tangent.x, tangent.y))
				for row in rows:
					var across := (float(row) + 0.5) / float(rows) - 0.5
					var along := 0.04 if (row + index) % 2 == 0 else -0.04
					var local := Vector3(across * safe_width, 0, along)
					var stone_width := safe_width / float(rows) - 0.055
					var edge_stone := row == 0 or row == rows - 1
					var rise := STONE_EDGE_RISE if edge_stone else STONE_SURFACE_RISE + 0.004 * sin(float(path_id * 7 + row * 3 + index * 5))
					var stone_yaw := 0.035 * sin(float(path_id + row * 5 + index * 3))
					var stone_basis := path_basis * Basis(Vector3.UP, stone_yaw)
					var material_index := (row + index) % 2
					_append_box(builder, _embedded_center(sample["point"] + path_basis * local, PATH_THICKNESS, rise), Vector3(maxf(0.20, stone_width), PATH_THICKNESS, 0.46), stone_basis, material_index)
					cells += 1
		"stepping_stones":
			var cluster_index := 0
			for index in range(0, points.size() - 1, 2):
				var sample: Dictionary = points[index]
				var tangent: Vector2 = sample["tangent"]
				var path_basis := Basis(Vector3.UP, atan2(tangent.x, tangent.y))
				var lateral_limit := minf(safe_width * 0.22, 0.22)
				var lateral := lateral_limit * sin(float(path_id * 17 + cluster_index * 23 + 1))
				var along := 0.14 * sin(float(path_id * 31 + cluster_index * 13 + 2))
				var cluster_center: Vector3 = sample["point"] + path_basis * Vector3(lateral, 0, along)

				# Keep the established irregular walking rhythm and natural footprint.
				# The top face is seated against the highest terrain actually touched by
				# the stone footprint, with the slab body extending downward. This keeps
				# the full top visible without bringing back the old raised-puck offset.
				# Broader/narrower stones share the same centres and cadence. Limit the
				# visual width input so a wide tool cannot turn them into patio slabs.
				var stone_width_input := minf(safe_width, 1.35)
				var hero := (path_id + cluster_index * 5) % 9 == 0
				var primary_width_scale := 0.38 + 0.29 * (sin(float(path_id * 11 + cluster_index * 29 + 3)) * 0.5 + 0.5)
				if hero: primary_width_scale += 0.05
				var primary_width := clampf(stone_width_input * primary_width_scale, 0.22, maxf(0.22, minf(safe_width * 0.74, 0.90)))
				var primary_length := 0.34 + 0.28 * (sin(float(path_id * 7 + cluster_index * 19 + 4)) * 0.5 + 0.5)
				if hero: primary_length += 0.02
				var primary_yaw := 0.24 * sin(float(path_id * 5 + cluster_index * 17 + 5))
				var primary_material := 1 if sin(float(path_id * 71 + cluster_index * 31 + 14)) > 0.12 else 0
				var primary_basis := path_basis * Basis(Vector3.UP, primary_yaw)
				var primary_size := Vector3(primary_width, STEPPING_STONE_THICKNESS, primary_length)
				var primary_half_across := _stepping_stone_half_across(primary_size, primary_yaw)
				# A hairline of existing grass separates the silhouettes. No skirt,
				# extra rim, material change or lower top is needed for ground contact.
				var grass_gap := 0.025 + 0.020 * (sin(float(path_id * 83 + cluster_index * 11 + 17)) * 0.5 + 0.5)
				_append_rounded_stone(builder, _stepping_stone_center(cluster_center, primary_size, primary_basis, STEPPING_STONE_TOP_EPSILON), primary_size, primary_basis, primary_material)
				cells += 1

				var pattern := (path_id + cluster_index * 2) % 5
				if pattern in [1, 3, 4]:
					var side := -1.0 if pattern in [1, 4] else 1.0
					var companion_across := side * minf(safe_width * (0.18 + 0.07 * (sin(float(path_id * 37 + cluster_index * 11 + 7)) * 0.5 + 0.5)), 0.27)
					var companion_along := 0.10 + 0.10 * sin(float(path_id * 41 + cluster_index * 5 + 8))
					# A broad primary gets a slightly smaller partner, not a fused pair.
					var companion_scale := 0.90 if primary_width_scale > 0.62 else 1.0
					var companion_width := clampf(stone_width_input * companion_scale * (0.16 + 0.20 * (sin(float(path_id * 43 + cluster_index * 3 + 9)) * 0.5 + 0.5)), 0.13, maxf(0.13, minf(safe_width * 0.38, 0.44)))
					var companion_length := companion_scale * (0.18 + 0.20 * (sin(float(path_id * 47 + cluster_index * 7 + 10)) * 0.5 + 0.5))
					var companion_yaw := -0.32 * sin(float(path_id * 53 + cluster_index * 13 + 11))
					var companion_material := 1 if sin(float(path_id * 73 + cluster_index * 17 + 15)) > -0.18 else 0
					var companion_basis := path_basis * Basis(Vector3.UP, companion_yaw)
					var companion_size := Vector3(companion_width, STEPPING_STONE_THICKNESS * 0.92, companion_length)
					var companion_clearance := primary_half_across + _stepping_stone_half_across(companion_size, companion_yaw) + grass_gap
					companion_across = side * maxf(absf(companion_across), companion_clearance)
					var companion_point := cluster_center + path_basis * Vector3(companion_across, 0, companion_along)
					_append_rounded_stone(builder, _stepping_stone_center(companion_point, companion_size, companion_basis, STEPPING_STONE_TOP_EPSILON), companion_size, companion_basis, companion_material)
					cells += 1

				# Roughly one cluster in five receives a tiny third stone on the
				# opposite shoulder. It is intentionally sparse: enough to break the
				# repeated pair silhouette without turning the path into loose gravel.
				if pattern == 4:
					var pebble_yaw := 0.36 * sin(float(path_id * 61 + cluster_index * 19 + 13))
					var pebble_basis := path_basis * Basis(Vector3.UP, pebble_yaw)
					var pebble_width := clampf(stone_width_input * (0.10 + 0.12 * (sin(float(path_id * 59 + cluster_index * 17 + 12)) * 0.5 + 0.5)), 0.10, 0.25)
					var pebble_length := 0.13 + 0.13 * (sin(float(path_id * 67 + cluster_index * 7 + 18)) * 0.5 + 0.5)
					var pebble_size := Vector3(pebble_width, STEPPING_STONE_THICKNESS * 0.78, pebble_length)
					var pebble_across := maxf(minf(safe_width * 0.20, 0.20), primary_half_across + _stepping_stone_half_across(pebble_size, pebble_yaw) + grass_gap)
					var pebble_point := cluster_center + path_basis * Vector3(pebble_across, 0, -0.14)
					var pebble_material := 1 if sin(float(path_id * 79 + cluster_index * 23 + 16)) > 0.25 else 0
					_append_rounded_stone(builder, _stepping_stone_center(pebble_point, pebble_size, pebble_basis, STEPPING_STONE_TOP_EPSILON), pebble_size, pebble_basis, pebble_material)
					cells += 1
				cluster_index += 1
	return cells

func _embedded_center(point: Vector3, thickness: float, exposed_rise: float) -> Vector3:
	# Keep the top a hair above the voxel surface to avoid z-fighting while
	# burying the rest of the slab. Raised edge stones/rims make the central
	# walking surface read as a shallow recess without mutating terrain authority.
	return point + Vector3.UP * (exposed_rise - thickness * 0.5)

func _stepping_stone_half_across(size: Vector3, yaw: float) -> float:
	# Exact support of the clipped octagon along the path's across axis. Using
	# its rotated footprint keeps a real grass gap without oversized box margins.
	var projected_x := size.x * absf(cos(yaw))
	var projected_z := size.z * absf(sin(yaw))
	return maxf(projected_x * 0.50 + projected_z * 0.28, projected_x * 0.28 + projected_z * 0.50)

func _stepping_stone_center(point: Vector3, size: Vector3, basis: Basis, top_offset: float) -> Vector3:
	# A centre-only sample can sit below a neighbouring voxel terrace and bury the
	# entire stone except for a tiny notch. Sample inside the actual rotated slab
	# footprint instead, then place the flat top only epsilon above the highest
	# touched terrain. Unlike the old treatment, there is no extra exposed rise.
	var half_x := size.x * 0.42
	var half_z := size.z * 0.42
	var surface_y := _surface_height(Vector2(point.x, point.z))
	for local_offset in [
		Vector2(-half_x, -half_z),
		Vector2(half_x, -half_z),
		Vector2(half_x, half_z),
		Vector2(-half_x, half_z),
	]:
		var world_offset := basis * Vector3(local_offset.x, 0, local_offset.y)
		surface_y = maxf(surface_y, _surface_height(Vector2(point.x + world_offset.x, point.z + world_offset.z)))
	return Vector3(point.x, surface_y + top_offset - size.y * 0.5, point.z)

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

func _append_rounded_stone(builder: Dictionary, center: Vector3, size: Vector3, basis: Basis, material_index: int) -> void:
	# Eight-sided slab: still crisp/voxel-compatible, but the clipped corners
	# read as a naturally rounded stepping stone at play distance.
	var surface: Dictionary = builder["surfaces"][material_index]
	var vertices: Array = surface["vertices"]
	var normals: Array = surface["normals"]
	var indices: Array = surface["indices"]
	var half := size * 0.5
	var ring: Array[Vector2] = [
		Vector2(-0.50, -0.28), Vector2(-0.50, 0.28), Vector2(-0.28, 0.50), Vector2(0.28, 0.50),
		Vector2(0.50, 0.28), Vector2(0.50, -0.28), Vector2(0.50, -0.28), Vector2(0.28, -0.50), Vector2(-0.28, -0.50),
	]
	var top_center := vertices.size()
	vertices.append(center + basis * Vector3(0, half.y, 0))
	normals.append(basis * Vector3.UP)
	var bottom_center := vertices.size()
	vertices.append(center + basis * Vector3(0, -half.y, 0))
	normals.append(basis * Vector3.DOWN)
	var top_ring: Array[int] = []
	var bottom_ring: Array[int] = []
	for point in ring:
		top_ring.append(vertices.size())
		vertices.append(center + basis * Vector3(point.x * size.x, half.y, point.y * size.z))
		normals.append(basis * Vector3.UP)
		bottom_ring.append(vertices.size())
		vertices.append(center + basis * Vector3(point.x * size.x, -half.y, point.y * size.z))
		normals.append(basis * Vector3.DOWN)
	for index in ring.size():
		var next := (index + 1) % ring.size()
		# Godot treats CLOCKWISE triangles as front-facing. The ring runs the
		# opposite way viewed from above; reverse the fan, not the lighting normal.
		# Inward winding hides the top and exposes the buried underside instead.
		indices.append_array([top_center, top_ring[next], top_ring[index]])
		indices.append_array([bottom_center, bottom_ring[index], bottom_ring[next]])
		var a: Vector2 = ring[index]
		var b: Vector2 = ring[next]
		var edge := b - a
		var side_normal_local := Vector3(-edge.y / maxf(size.x, 0.001), 0, edge.x / maxf(size.z, 0.001)).normalized()
		var side_normal := basis * side_normal_local
		var side_base := vertices.size()
		vertices.append(center + basis * Vector3(a.x * size.x, -half.y, a.y * size.z))
		vertices.append(center + basis * Vector3(b.x * size.x, -half.y, b.y * size.z))
		vertices.append(center + basis * Vector3(b.x * size.x, half.y, b.y * size.z))
		vertices.append(center + basis * Vector3(a.x * size.x, half.y, a.y * size.z))
		for unused in 4: normals.append(side_normal)
		indices.append_array([side_base, side_base + 2, side_base + 1, side_base, side_base + 3, side_base + 2])
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
