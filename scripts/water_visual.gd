extends Node3D
class_name M1WaterVisual
## Presentation-only render of the player-authored water regions. The
## authoritative records live in LandscapeState (see water_region_geometry.gd);
## this node turns them into a clipped, animated surface. It owns no records,
## writes no terrain, and stores no save data. Water is an editable scenery
## layer, not a fluid simulation.
const Geometry = preload("res://scripts/water_region_geometry.gd")
const Grid = preload("res://scripts/visual_grid.gd")
const WATER_SHADER = preload("res://shaders/water_surface.gdshader")

const WATER_CELL := Grid.UNIT
const WATER_COLOR := Color(0.16, 0.44, 0.52, 0.82)
const WATER_DEEP_COLOR := Color(0.07, 0.26, 0.36, 0.82)
const DEPTH_SCALE := 4.0

var _backend: Node
var _nodes: Array = []
var _regions: Array = []
var _last_key := ""

func attach_backend(backend: Node) -> void:
	_backend = backend
	if backend != null and backend.has_signal("changed") and not backend.is_connected("changed", _on_terrain_changed):
		backend.connect("changed", _on_terrain_changed)
	_rebuild()

func set_regions(regions: Array) -> void:
	_regions = regions
	_rebuild()

func refresh_terrain() -> void:
	_rebuild()

func _on_terrain_changed() -> void:
	_rebuild()

func _rebuild() -> void:
	if _backend == null or not _backend.has_method("voxel_at"):
		return
	if _backend.has_method("is_ready") and not _backend.is_ready():
		return
	var key := _key()
	if key == _last_key:
		return
	_last_key = key
	var scale := maxf(0.001, float(_backend.get("voxel_scale")))
	var patch: Vector3i = _backend.get("patch_size")
	var world := Vector2(float(patch.x) * scale, float(patch.z) * scale)
	_clear()
	for region: Dictionary in _regions:
		var level := Geometry.surface_level(region)
		var flow := Geometry.flow_direction(region)
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		var base := 0
		for cell: Vector2i in Geometry.footprint_cells(region, world.x):
			var cx := float(cell.x) * WATER_CELL
			var cz := float(cell.y) * WATER_CELL
			var surface_y := _terrain_top(cx + WATER_CELL * 0.5, cz + WATER_CELL * 0.5)
			# Terrain at/above the level is dry (shore); only below-level cells
			# (or empty deep columns) carry a water quad, clipped at the level.
			if not is_nan(surface_y) and surface_y >= level - 0.000001:
				continue
			var depth := 0.0 if is_nan(surface_y) else clampf((level - surface_y) / DEPTH_SCALE, 0.0, 1.0)
			var color := WATER_COLOR.lerp(WATER_DEEP_COLOR, depth)
			base = _append_water_quad(vertices, normals, colors, indices, base, cx, cz, level, color)
		if vertices.is_empty():
			continue
		var mesh := ArrayMesh.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := _region_material(flow)
		mesh.surface_set_material(0, material)
		var node := MeshInstance3D.new()
		node.name = "WaterRegion_%d" % int(region.get("id", 0))
		node.mesh = mesh
		add_child(node)
		_nodes.append(node)

func _region_material(flow: Vector2) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	material.set_shader_parameter("water_color", WATER_COLOR)
	material.set_shader_parameter("flow_dir", flow)
	material.set_shader_parameter("flow_speed", 0.55 if flow.distance_to(Vector2(1.0, 0.0)) > 0.001 else 0.25)
	return material

## World Y of the top face of the topmost solid voxel in the column, or NAN when
## the column is empty (a deep hole, which is always submerged).
func _terrain_top(x: float, z: float) -> float:
	var scale := maxf(0.001, float(_backend.get("voxel_scale")))
	var patch: Vector3i = _backend.get("patch_size")
	var vx := int(floori(x / scale))
	var vz := int(floori(z / scale))
	if vx < 0 or vz < 0 or vx >= patch.x or vz >= patch.z:
		return NAN
	for y in range(patch.y - 1, -1, -1):
		if int(_backend.voxel_at(Vector3i(vx, y, vz))) != 0:
			return float(y + 1) * scale
	return NAN

func _append_water_quad(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, base: int, cx: float, cz: float, y: float, color: Color) -> int:
	var u := WATER_CELL
	var points := [Vector3(cx, y, cz), Vector3(cx + u, y, cz), Vector3(cx + u, y, cz + u), Vector3(cx, y, cz + u)]
	for point: Vector3 in points:
		vertices.append(point)
		normals.append(Vector3.UP)
		colors.append(color)
	indices.append(base)
	indices.append(base + 1)
	indices.append(base + 2)
	indices.append(base)
	indices.append(base + 2)
	indices.append(base + 3)
	return base + 4

func _key() -> String:
	var revision := 0
	if _backend.has_method("revision"):
		revision = int(_backend.call("revision"))
	var payload: Array = []
	for region: Dictionary in _regions:
		payload.append([int(region.get("id", 0)), str(region.get("type", "")), float(region.get("level", 0.0)), int((region.get("points", []) as Array).size())])
	return "%d|%s" % [revision, var_to_bytes(payload).hex_encode().sha256_text()]

func _clear() -> void:
	for node: MeshInstance3D in _nodes:
		if is_instance_valid(node):
			node.queue_free()
	_nodes = []

## Deterministic quad count of the current surface (test hook).
func surface_quad_count() -> int:
	var total := 0
	for node: MeshInstance3D in _nodes:
		var mesh: ArrayMesh = node.mesh
		if mesh != null and mesh.get_surface_count() > 0:
			var arrays: Array = mesh.surface_get_arrays(0)
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4
	return total
