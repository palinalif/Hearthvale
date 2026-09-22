extends RefCounted

## Shared, read-only site services for the house-landing decoration
## (scripts/house_edge_foliage.gd and scripts/house_dirt_rim.gd).
##
## Everything here is a pure query or a pure box emitter: no terrain write, no
## landscape record, no save data, no per-frame work and no RNG. A decorated spot
## must be open ground - inside the world, off the carved river bed and off a
## painted path cell - and must lie flat at the sampled native surface height, so
## a tuft or a dirt cell never straddles a terrace edge or floats over a drop.
const Grid = preload("res://scripts/visual_grid.gd")
const Generator = preload("res://scripts/m1_patch_generator.gd")

const PATH_STYLES: Array[String] = ["packed_earth", "cobblestone", "stepping_stones"]
const RIVER_MARGIN := 0.25
const FLAT_EPSILON := 0.0001

## Addressable site description handed to the decoration modules.
static func site(backend: Object, landscape_state: Object) -> Dictionary:
	return {"backend": backend, "path_cells": path_lookup(landscape_state), "heights": {}}

## Painted path cells (structural 0.125 grid) for every path style, so a spot can
## be tested in O(1). Built once per presentation pass, never per cell.
static func path_lookup(landscape_state: Object) -> Dictionary:
	var lookup := {}
	if landscape_state == null or not landscape_state.has_method("path_cells"): return lookup
	for style_id: String in PATH_STYLES:
		for cell in landscape_state.path_cells(style_id):
			if cell is Vector2i: lookup[cell] = true
	return lookup

static func on_painted_path(path_cells: Dictionary, point: Vector2) -> bool:
	return path_cells.has(Vector2i(floori(point.x / Grid.UNIT), floori(point.y / Grid.UNIT)))

## The starter valley carves its river bed: the "water" a house must not decorate
## is exactly the channel band of the terrain generator, so the test is the same
## deterministic geometry that built the terrain.
static func in_river(point: Vector2, margin: float = RIVER_MARGIN) -> bool:
	if not point.is_finite(): return true
	return absf(point.x - Generator.river_center_x(point.y)) <= Generator.river_half_width(point.y) + margin

## Native terrain surface height, or NAN when the column carries no ground.
static func surface_height(backend: Object, point: Vector2) -> float:
	if backend == null or not backend.has_method("voxel_at"): return NAN
	if not point.is_finite(): return NAN
	var scale_value := maxf(0.001, float(backend.get("voxel_scale")))
	var patch: Vector3i = backend.get("patch_size")
	if point.x < 0.0 or point.y < 0.0: return NAN
	if point.x >= float(patch.x) * scale_value or point.y >= float(patch.z) * scale_value: return NAN
	var x := clampi(floori(point.x / scale_value), 0, patch.x - 1)
	var z := clampi(floori(point.y / scale_value), 0, patch.z - 1)
	if backend.has_method("column_top_y"):
		var top: int = backend.column_top_y(Vector2i(x, z))
		return float(top + 1) * scale_value if top >= 0 else NAN
	for y in range(patch.y - 2, -1, -1):
		if int(backend.voxel_at(Vector3i(x, y, z))) != 0 and int(backend.voxel_at(Vector3i(x, y + 1, z))) == 0:
			return float(y + 1) * scale_value
	return NAN

## Ground height for decoration: NAN over water, painted paths or missing ground.
static func ground_height(site_value: Dictionary, point: Vector2) -> float:
	if in_river(point): return NAN
	if on_painted_path(site_value["path_cells"], point): return NAN
	# Fine decoration corners often share one native column. Sample it once
	# per presentation pass; this cache never survives a terrain revision.
	var scale_value := float(site_value["backend"].get("voxel_scale"))
	var cell := Vector2i(floori(point.x / scale_value), floori(point.y / scale_value))
	if not site_value.has("heights"): site_value["heights"] = {}
	var heights: Dictionary = site_value["heights"]
	if not heights.has(cell): heights[cell] = surface_height(site_value["backend"], point)
	var height: float = heights[cell]
	return NAN if is_nan(height) else height

## A decorative cell must agree with the terrain over its own footprint, not just
## at its centre, or it would hang off a terrace.
static func flat_at(site_value: Dictionary, point: Vector2, unit: float, height: float) -> bool:
	for corner: Vector2 in [Vector2(-0.49, -0.49), Vector2(0.49, -0.49), Vector2(0.49, 0.49), Vector2(-0.49, 0.49)]:
		var sample := ground_height(site_value, point + corner * unit)
		if is_nan(sample) or absf(sample - height) > FLAT_EPSILON: return false
	return true

## Stable integer identity for a building: FNV-1a over the record's own stable id
## characters. No RNG, no frame time and no iteration order, so the same building
## always decorates the same way (save/load, regeneration, undo/redo).
static func identity(building_id: String, salt: int = 0, position: Vector3 = Vector3.ZERO) -> int:
	var value := 2166136261
	for index in building_id.length():
		value = posmod((value ^ building_id.unicode_at(index)) * 16777619, 2147483647)
	# The quantized placement seeds the ring too, so a moved house re-derives its
	# planting from its record rather than keeping stale decoration.
	value = posmod(value * 16777619 + salt * 2833, 2147483647)
	return posmod(value ^ (roundi(position.x * 16.0) * 73856093) ^ (roundi(position.z * 16.0) * 19349663), 2147483647)

## Integer-identity hash used to vary a single cell without any RNG.
static func cell_hash(seed_value: int, a: int, b: int, salt: int = 0) -> int:
	var value := posmod(seed_value * 92821 + a * 68917 + b * 2833 + salt * 15485863, 2147483647)
	value = posmod(value * value * 31 + value * 17, 2147483647)
	return value

static func geometry() -> Dictionary:
	return {"vertices": [], "normals": [], "indices": [], "colors": []}

## Same axis-aligned box emitter the path/contact builders use: six quads, 24
## vertices, 12 triangles, one flat colour per box.
static func emit_box(target: Dictionary, center: Vector3, size: Vector3, colour: Color) -> void:
	var vertices: Array = target["vertices"]
	var normals: Array = target["normals"]
	var indices: Array = target["indices"]
	var colors: Array = target["colors"]
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
		var base := vertices.size()
		var normal: Vector3 = face[0]
		for corner in face[1]:
			vertices.append(center + (corner as Vector3))
			normals.append(normal)
			colors.append(colour)
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

## Batched single-surface mesh: one draw call for a whole house's decoration.
static func mesh_from(target: Dictionary, material: StandardMaterial3D) -> ArrayMesh:
	if (target["vertices"] as Array).is_empty(): return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(target["vertices"])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(target["normals"])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(target["indices"])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(target["colors"])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh

## Vegetation palette values are authored in sRGB, like albedo colours.
static func prop_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	material.metallic_specular = 0.0
	return material
