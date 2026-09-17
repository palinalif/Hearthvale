extends Node3D
class_name M1WaterVisual
## Presentation-only render of the player-authored water regions. The
## authoritative records live in LandscapeState (see water_region_geometry.gd);
## this node turns them into a clipped, animated surface. It owns no records,
## writes no terrain, and stores no save data. Water is an editable scenery
## layer, not a fluid simulation.
const Geometry = preload("res://scripts/water_region_geometry.gd")
const Waterfall = preload("res://scripts/waterfall_geometry.gd")
const Grid = preload("res://scripts/visual_grid.gd")
const WATER_SHADER = preload("res://shaders/water_surface.gdshader")
const FALL_SHADER = preload("res://shaders/waterfall_fall.gdshader")

const WATER_CELL := Grid.UNIT
const WATER_COLOR := Color(0.16, 0.44, 0.52, 0.82)
const WATER_DEEP_COLOR := Color(0.07, 0.26, 0.36, 0.82)
const DEPTH_SCALE := 4.0
const FALL_COLOR := Color(0.62, 0.80, 0.88, 0.70)
const SPLASH_COLOR := Color(0.86, 0.96, 1.0, 0.55)

var _backend: Node
var _nodes: Array = []
var _regions: Array = []
var _last_key := ""
var _suppressions: Array = []
var _waterfalls: Array = []
var _fall_nodes: Array = []
# Per-cell terrain cache so a local edit only re-samples the cells near it
# (mirroring the river and waterfall bounds) instead of scanning every column.
var _cell_cache: Dictionary = {}
var _regions_key := ""
var _rebuild_scheduled := false
var _dirty_accum := Rect2()

func attach_backend(backend: Node) -> void:
	_backend = backend
	if backend != null and backend.has_signal("changed") and not backend.is_connected("changed", _on_terrain_changed):
		backend.connect("changed", _on_terrain_changed)
	_rebuild()

func set_regions(regions: Array) -> void:
	_regions = regions
	_rebuild()

## Cache-aware rebuild: reuse the cached terrain tops, resample only new or
## invalidated cells, then build the mesh from the cache. Cheap for a growing
## stroke preview and for a commit that reuses the startup + preview cache
## instead of resampling every water column — the old full rebuild (clear +
## resample all) froze the frame on mobile for large regions.
func set_regions_incremental(regions: Array, invalidate_cells: Array = []) -> void:
	if _backend == null or not _backend.has_method("voxel_at"):
		return
	if _backend.has_method("is_ready") and not _backend.is_ready():
		return
	_regions = regions
	_regions_key = _regions_signature()
	for cell in invalidate_cells:
		_cell_cache.erase(cell)
	var world_x := _world_x()
	for region: Dictionary in _regions:
		for cell: Vector2i in Geometry.footprint_cells(region, world_x):
			if _cell_cache.has(cell):
				continue
			var px := float(cell.x) * WATER_CELL + WATER_CELL * 0.5
			var pz := float(cell.y) * WATER_CELL + WATER_CELL * 0.5
			_cell_cache[cell] = _terrain_top(px, pz)
	_build_mesh_from_cache()
	_last_key = _key()

func refresh_terrain() -> void:
	# Full resample (startup / unknown bounds). Local terrain edits use
	# refresh_surface_from_bounds() to only resample near the edit.
	_rebuild()

## Resample only the cells near the given terrain-edit bounds and rebuild the
## surface, coalescing rapid edits into one deferred rebuild. Edits that touch
## no water cell leave the cached surface untouched (a no-op for far digging).
func refresh_surface_from_bounds(bounds: AABB) -> void:
	if _backend == null:
		return
	if bounds.size == Vector3.ZERO:
		_rebuild()
		return
	var rkey := _regions_signature()
	if rkey != _regions_key:
		_rebuild()
		return
	var rect := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
	rect = rect.grow(3.0)
	_dirty_accum = rect if _dirty_accum.size == Vector2.ZERO else _dirty_accum.merge(rect)
	if _rebuild_scheduled:
		return
	_rebuild_scheduled = true
	call_deferred("_do_surface_rebuild")

func _do_surface_rebuild() -> void:
	_rebuild_scheduled = false
	var rect := _dirty_accum
	_dirty_accum = Rect2()
	if _backend == null or not _backend.has_method("voxel_at"):
		return
	if _backend.has_method("is_ready") and not _backend.is_ready():
		return
	var resampled := false
	for region: Dictionary in _regions:
		for cell: Vector2i in Geometry.footprint_cells(region, _world_x()):
			if not rect.has_point(Vector2(float(cell.x) * WATER_CELL, float(cell.y) * WATER_CELL)):
				continue
			var px := float(cell.x) * WATER_CELL + WATER_CELL * 0.5
			var pz := float(cell.y) * WATER_CELL + WATER_CELL * 0.5
			_cell_cache[cell] = _terrain_top(px, pz)
			resampled = true
	if not resampled:
		return
	_build_mesh_from_cache()
	_last_key = _key()

func _on_terrain_changed() -> void:
	# Localize via the last edit bounds (matches the river + waterfalls); the
	# scene also calls refresh_surface_from_bounds and the debounce coalesces.
	if _backend != null and _backend.has_method("get_last_edit_bounds"):
		refresh_surface_from_bounds(_backend.get_last_edit_bounds())
	else:
		_rebuild()

## --- Derived waterfalls (presentation only; the only stored state is the
## suppressions the player chose, kept in LandscapeState) -----------------------
func set_waterfall_suppressions(keys: Array) -> void:
	_suppressions = keys
	_refresh_waterfalls(Waterfall.FULL_RECT)

## Re-derive waterfalls only inside dirty_rect and rebuild their cascade meshes.
## The scene grows a terrain edit-bounds by Waterfall.SAMPLE_MARGIN before calling
## this (mirroring the path rebuild), so a local edit only samples that area and
## never the whole map. Falls outside the rect keep their cached state.
func refresh_waterfalls(dirty_rect: Rect2) -> void:
	_refresh_waterfalls(dirty_rect)

## Re-derive a bounded area from a terrain edit AABB (or the whole map when the
## bounds are unset/zero-size), growing the edit by the sampling margin.
func refresh_waterfalls_from_bounds(bounds: AABB) -> void:
	if bounds.size == Vector3.ZERO:
		_refresh_waterfalls(Waterfall.FULL_RECT)
		return
	var rect := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
	_refresh_waterfalls(rect.grow(Waterfall.SAMPLE_MARGIN))

func refresh_waterfalls_full() -> void:
	_refresh_waterfalls(Waterfall.FULL_RECT)

func _refresh_waterfalls(dirty_rect: Rect2) -> void:
	if _backend == null or not _backend.has_method("voxel_at"):
		return
	if _backend.has_method("is_ready") and not _backend.is_ready():
		return
	var kept: Array = []
	for fall in _waterfalls:
		if not dirty_rect.has_point(_fall_crown(fall)):
			kept.append(fall)
	_waterfalls = kept
	var derived := Waterfall.derive(_regions, _waterfall_sample(), dirty_rect)
	var present := {}
	for fall in _waterfalls:
		present[str(fall["key"])] = true
	for fall in derived:
		var key := str(fall["key"])
		if present.has(key) or _suppressions.has(key):
			continue
		_waterfalls.append(fall)
	_waterfalls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["key"]) < str(b["key"]))
	_rebuild_falls()

func _waterfall_sample() -> Callable:
	return func(p: Vector2) -> float: return _terrain_top(p.x, p.y)

static func _fall_crown(fall: Dictionary) -> Vector2:
	return Vector2(float(fall["crown"][0]), float(fall["crown"][1]))

func _rebuild_falls() -> void:
	for node: MeshInstance3D in _fall_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_fall_nodes = []
	for fall in _waterfalls:
		var node := _build_cascade(fall)
		if node != null:
			add_child(node)
			_fall_nodes.append(node)

func _build_cascade(fall: Dictionary) -> MeshInstance3D:
	var crown := _fall_crown(fall)
	var width := maxf(0.25, float(fall["width"]))
	var top := float(fall["top_level"])
	var bottom := float(fall["bottom_level"])
	if bottom >= top:
		return null
	var flow := Vector2(float(fall["flow"][0]), float(fall["flow"][1]))
	if flow.length() < 0.0001:
		flow = Vector2(1.0, 0.0)
	flow = flow.normalized()
	var perp := Vector2(-flow.y, flow.x)
	var half := width * 0.5
	var mesh := ArrayMesh.new()
	# Surface 0: the falling curtain, a vertical sheet from lip down to the pool.
	var a := crown + perp * half
	var b := crown - perp * half
	var cv := PackedVector3Array([Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(b.x, bottom, b.y), Vector3(a.x, bottom, a.y)])
	var cn := PackedVector3Array([Vector3(flow.x, 0.0, flow.y), Vector3(flow.x, 0.0, flow.y), Vector3(flow.x, 0.0, flow.y), Vector3(flow.x, 0.0, flow.y)])
	var cc := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	var ci := PackedInt32Array([0, 1, 2, 0, 2, 3])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _surface_arrays(cv, cn, cc, ci))
	mesh.surface_set_material(0, _fall_material(top - bottom))
	# Surface 1: a flat foam splash just above the pool at the base.
	var s := width * 0.7
	var eps := 0.02
	var sv := PackedVector3Array([Vector3(crown.x - s, bottom + eps, crown.y - s), Vector3(crown.x + s, bottom + eps, crown.y - s), Vector3(crown.x + s, bottom + eps, crown.y + s), Vector3(crown.x - s, bottom + eps, crown.y + s)])
	var sn := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	var sc := PackedColorArray([SPLASH_COLOR, SPLASH_COLOR, SPLASH_COLOR, SPLASH_COLOR])
	var si := PackedInt32Array([0, 1, 2, 0, 2, 3])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _surface_arrays(sv, sn, sc, si))
	var splash_material := StandardMaterial3D.new()
	splash_material.albedo = SPLASH_COLOR
	splash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	splash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	splash_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(1, splash_material)
	var node := MeshInstance3D.new()
	node.name = "Waterfall_%d-%d" % [int(fall["upper_id"]), int(fall["lower_id"])]
	node.mesh = mesh
	# The particle aspect of the fall: a short-lived base spray (droplets thrown
	# up and out, pulled back by gravity) plus a prewarmed, slowly rising soft mist.
	node.add_child(_make_spray(crown, bottom, width))
	node.add_child(_make_mist(crown, bottom, width))
	return node

func _surface_arrays(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays

func _fall_material(span: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FALL_SHADER
	material.set_shader_parameter("fall_color", FALL_COLOR)
	material.set_shader_parameter("height", span)
	return material

## A unit billboard quad carrying a soft, unshaded alpha material; the particle
## scale (scale_min/scale_max) sizes each instance.
func _particle_quad(color: Color) -> QuadMesh:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo = color
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat
	return quad

## Base spray: droplets emitted from a flat disc at the pool, thrown up and out and
## pulled back down. Short-lived, no prewarm (so it reads as fresh splashes).
func _make_spray(center: Vector2, level: float, width: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Spray"
	p.position = Vector3(center.x, level + 0.05, center.y)
	p.amount = 64
	p.lifetime = 0.6
	p.visibility_range_end = 40.0
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(width * 0.5, 0.05, width * 0.5)
	m.direction = Vector3.UP
	m.spread = 34.0
	m.initial_velocity_min = 1.0
	m.initial_velocity_max = 2.3
	m.gravity = Vector3(0.0, -9.8, 0.0)
	m.scale_min = 0.04
	m.scale_max = 0.1
	m.color = Color(0.86, 0.96, 1.0, 0.5)
	m.damping_min = 8.0
	m.damping_max = 12.0
	p.process_material = m
	p.draw_pass_1 = _particle_quad(Color(0.9, 0.97, 1.0, 0.5))
	return p

## Soft mist: a prewarmed bed of large, faint billboards that drifts up slowly, so
## the base always reads as hazy without pop-in.
func _make_mist(center: Vector2, level: float, width: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Mist"
	p.position = Vector3(center.x, level + 0.2, center.y)
	p.amount = 28
	p.lifetime = 1.6
	p.preprocess = 1.6   # simulate a full lifetime on start so the mist never pops in
	p.visibility_range_end = 40.0
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(width * 0.6, 0.1, width * 0.6)
	m.direction = Vector3.UP
	m.spread = 14.0
	m.initial_velocity_min = 0.15
	m.initial_velocity_max = 0.45
	m.gravity = Vector3(0.0, -0.25, 0.0)
	m.scale_min = 0.4
	m.scale_max = 0.85
	m.color = Color(0.9, 0.97, 1.0, 0.1)
	m.damping_min = 3.0
	m.damping_max = 5.0
	p.process_material = m
	p.draw_pass_1 = _particle_quad(Color(0.9, 0.97, 1.0, 0.12))
	return p

func _rebuild() -> void:
	if _backend == null or not _backend.has_method("voxel_at"):
		return
	if _backend.has_method("is_ready") and not _backend.is_ready():
		return
	var key := _key()
	if key == _last_key:
		return
	_last_key = key
	_regions_key = _regions_signature()
	# Single pass (level-load fast path): scan each column once, cache the
	# result for localized edits, and build the surface in the same loop.
	_cell_cache.clear()
	var world_x := _world_x()
	_clear()
	for region: Dictionary in _regions:
		var level := Geometry.surface_level(region)
		var flow := Geometry.flow_direction(region)
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		var base := 0
		for cell: Vector2i in Geometry.footprint_cells(region, world_x):
			var cx := float(cell.x) * WATER_CELL
			var cz := float(cell.y) * WATER_CELL
			var surface_y := _terrain_top(cx + WATER_CELL * 0.5, cz + WATER_CELL * 0.5)
			_cell_cache[cell] = surface_y
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
		mesh.surface_set_material(0, _region_material(flow))
		var node := MeshInstance3D.new()
		node.name = "WaterRegion_%d" % int(region.get("id", 0))
		node.mesh = mesh
		add_child(node)
		_nodes.append(node)

func _build_mesh_from_cache() -> void:
	_clear()
	var world_x := _world_x()
	for region: Dictionary in _regions:
		var level := Geometry.surface_level(region)
		var flow := Geometry.flow_direction(region)
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		var base := 0
		for cell: Vector2i in Geometry.footprint_cells(region, world_x):
			var cx := float(cell.x) * WATER_CELL
			var cz := float(cell.y) * WATER_CELL
			var surface_y: Variant = _cell_cache.get(cell, NAN)
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
		mesh.surface_set_material(0, _region_material(flow))
		var node := MeshInstance3D.new()
		node.name = "WaterRegion_%d" % int(region.get("id", 0))
		node.mesh = mesh
		add_child(node)
		_nodes.append(node)

func _world_x() -> float:
	if _backend == null:
		return 0.0
	var scale := maxf(0.001, float(_backend.get("voxel_scale")))
	var patch: Vector3i = _backend.get("patch_size")
	return float(patch.x) * scale

func _regions_signature() -> String:
	var payload: Array = []
	for region: Dictionary in _regions:
		payload.append([int(region.get("id", 0)), str(region.get("type", "")), float(region.get("level", 0.0)), int((region.get("points", []) as Array).size())])
	return var_to_bytes(payload).hex_encode().sha256_text()

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
	for node: MeshInstance3D in _fall_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_fall_nodes = []

## Deterministic quad count of the current surface (test hook).
func surface_quad_count() -> int:
	var total := 0
	for node: MeshInstance3D in _nodes:
		var mesh: ArrayMesh = node.mesh
		if mesh != null and mesh.get_surface_count() > 0:
			var arrays: Array = mesh.surface_get_arrays(0)
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4
	return total

## Deterministic fall count (test hook).
func waterfall_count() -> int:
	return _waterfalls.size()

## The active (non-suppressed) derived falls, each with crown/levels/key (read-only copy).
func active_waterfalls() -> Array:
	return _waterfalls.duplicate(false)

## Number of particle emitters under the active falls (spray + mist each) — test hook.
func waterfall_particle_node_count() -> int:
	var total := 0
	for node: MeshInstance3D in _fall_nodes:
		if node != null:
			for child: Node in node.get_children():
				if child is GPUParticles3D:
					total += 1
	return total

## Keys of the active (non-suppressed) falls, sorted (test hook).
func waterfall_keys() -> Array:
	var keys: Array = []
	for fall in _waterfalls:
		keys.append(str(fall["key"]))
	return keys
