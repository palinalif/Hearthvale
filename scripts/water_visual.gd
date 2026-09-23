extends Node3D
class_name M1WaterVisual
## Presentation-only render of the player-authored water regions. The
## authoritative records live in LandscapeState (see water_region_geometry.gd);
## this node turns them into a clipped, animated surface. It owns no records,
## writes no terrain, and stores no save data. Water is an editable scenery
## layer, not a fluid simulation.
##
## Render machine (incremental — a local edit never reworks the whole surface):
##  - terrain is sampled once per footprint cell into _cell_cache; a cell is
##    only resampled when something invalidates it (a carve commit) or a
##    localized resample pass proves its value changed;
##  - each region keeps its built mesh arrays in _build_state plus a
##    persistent node (_region_nodes), so a growing stroke appends quads
##    instead of the old free-every-node + re-union + rebuild-everything path;
##  - work is budgeted per frame (RESAMPLE_BUDGET / BUILD_BUDGET) and drained
##    in _process, so a first-time rebuild of a big region spreads over many
##    frames instead of allocating the whole mesh at once (the one-shot
##    rebuild froze the game for 37s and exhausted scudo on Thor).
const Geometry = preload("res://scripts/water_region_geometry.gd")
const Waterfall = preload("res://scripts/waterfall_geometry.gd")
const Grid = preload("res://scripts/visual_grid.gd")
const PremadeRiver = preload("res://scripts/premade_river.gd")
const WATER_SHADER = preload("res://shaders/water_surface.gdshader")
const POOL_WATER_SHADER = preload("res://shaders/pool_water.gdshader")
const FALL_SHADER = preload("res://shaders/waterfall_fall.gdshader")
const SPLASH_SHADER = preload("res://shaders/waterfall_splash.gdshader")

const WATER_CELL := Grid.UNIT
const WATER_COLOR := Color(0.20, 0.52, 0.55, 0.85)
const WATER_DEEP_COLOR := Color(0.07, 0.26, 0.36, 0.82)
# The plunge pool's basin floor sits only ~0.75 m below the surface, so the
# 0.82 alpha of the normal sheet lets the voxel floor show through as a
# scattered dotted grid. A near-opaque sheet keeps the pool reading clean.
const POOL_COLOR := Color(0.14, 0.42, 0.50, 0.97)
const POOL_DEEP_COLOR := Color(0.06, 0.24, 0.34, 0.97)
const DEPTH_SCALE := 4.0
const FALL_COLOR := Color(0.62, 0.80, 0.88, 0.88)
const SPLASH_COLOR := Color(0.86, 0.96, 1.0, 0.55)

# Bounded per-frame work: a first-time rebuild of a large region (or a big
# carve commit invalidating its footprint) drains over many frames instead of
# one 37-second stall (measured on Thor with a 5m-wide stream stroke).
const RESAMPLE_BUDGET := 2048
const BUILD_BUDGET := 2048
# Wall-clock caps on each pass: the cell budgets above are fine on desktop but
# translate into multi-second freezes on Thor, where one native voxel read
# costs ~2.5us and a full 256-row column scan is ~194 reads (~0.5ms per cell,
# so a 20k-cell river resample was several seconds). Any work that exceeds the
# time budget spills into _pending_cells and drains over frames in _process.
const RESAMPLE_TIME_BUDGET_MS := 6.0
const BUILD_TIME_BUDGET_MS := 4.0
# Voxel rows probed above/below a hinted column top before falling back to a
# full column scan. Local terrain edits move a column by a few rows at most,
# so the band almost always hits (2-6 native reads instead of ~194).
const HINT_BAND_ROWS := 24

var _backend: Node
# region id -> MeshInstance3D. Nodes are reused across incremental updates.
var _region_nodes: Dictionary = {}
var _regions: Array = []
var _last_key := ""
var _suppressions: Array = []
var _waterfalls: Array = []
var _fall_nodes: Array = []
# Per-cell terrain cache (NAN = empty/deep column, matching the resampler).
# Only footprint cells are held, never a whole-patch table.
var _cell_cache: Dictionary = {}
var _regions_key := ""
var _rebuild_scheduled := false
# region id -> region dict (for keying + level/flow).
var _region_by_id: Dictionary = {}
# region id -> strong key of the mesh geometry; an equal key means unchanged.
var _region_keys: Dictionary = {}
# region id -> {cells, verts, norms, cols, idx, index, material}. The mesh
# arrays persist across uploads so a growing stroke appends instead of
# reallocating everything (the old rebuild reallocated the whole mesh each
# edit — the scudo-exhaustion source).
var _build_state: Dictionary = {}
# Cells awaiting resample (FIFO) plus a membership set for O(1) dedup.
var _pending_cells: Array = []
var _pending_set := {}
# cell -> last known top, kept as a probe hint when the cell is invalidated
# (the old value is almost always within a few rows of the new one).
var _resample_hint := {}
# region id -> true: its mesh must (re)build. Drained in budgeted passes.
var _dirty_regions := {}
# cell -> Array of region ids whose mesh may contain that cell: a terrain
# change under a column must rebuild every region spanning it (a stream
# crossing a lake), so ownership is tracked, not assumed.
var _cell_regions: Dictionary = {}
# Live perf snapshot for the on-screen debug HUD (Y/F1).
var water_perf: Dictionary = {}
var water_rebuilds := 0

func get_perf() -> Dictionary:
	return water_perf
func get_rebuilds() -> int:
	return water_rebuilds
func reset_rebuilds() -> void:
	water_rebuilds = 0

func attach_backend(backend: Node) -> void:
	_backend = backend
	if backend != null and backend.has_signal("changed") and not backend.is_connected("changed", _on_terrain_changed):
		backend.connect("changed", _on_terrain_changed)
	_rebuild()

func set_regions(regions: Array) -> void:
	_regions = regions
	_rebuild()

## Incremental update of the region set (preview + commit path). Regions whose
## key is unchanged are left exactly as they are (no resample, no rebuild);
## new/changed regions resample only their missing cells and rebuild only
## their own mesh, both budgeted and draining in _process. A stream candidate
## may carry "cells" (the scene's rolling stroke-cell set, already
## rasterized) and a one-shot "reset" flag; without a hint the footprint comes
## from the memoized geometry cache.
func set_regions_incremental(regions: Array, invalidate_cells: Array = []) -> void:
	if _backend == null or not _backend.has_method("voxel_at"):
		return
	if _backend.has_method("is_ready") and not _backend.is_ready():
		return
	_regions = regions
	_regions_key = _regions_signature()
	for cell in invalidate_cells:
		_invalidate_cell(cell)
	_sync_regions()
	_drain(2)

func refresh_terrain() -> void:
	# Full resample (startup / unknown bounds). Local terrain edits use
	# refresh_surface_from_bounds() to only resample near the edit.
	_rebuild()

## Resample only the cells near the given terrain-edit bounds and rebuild the
## affected regions, coalescing rapid edits into one deferred drain. Edits
## that touch no water cell — or leave every watered column unchanged — do
## nothing (a no-op for far digging).
func refresh_surface_from_bounds(bounds: AABB) -> void:
	if _backend == null:
		return
	if bounds.size == Vector3.ZERO:
		_rebuild()
		return
	var rkey := _regions_signature()
	if rkey != _regions_key:
		# The region set changed through the incremental path since the last
		# sync (e.g. a commit replacing the stroke candidate): reconcile the
		# region state instead of a full rebuild, then localize the edit.
		_regions_key = rkey
		_sync_regions()
	var rect := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
	rect = rect.grow(3.0)
	_localize_resample(rect)
	_drain(1)
	if _rebuild_scheduled:
		return
	_rebuild_scheduled = true
	call_deferred("_do_surface_rebuild")

func _do_surface_rebuild() -> void:
	_rebuild_scheduled = false
	_drain(1)

func _on_terrain_changed() -> void:
	# Localize via the last edit bounds (matches the river + waterfalls); the
	# scene also calls refresh_surface_from_bounds and the debounce coalesces.
	if _backend != null and _backend.has_method("get_last_edit_bounds"):
		refresh_surface_from_bounds(_backend.get_last_edit_bounds())
	else:
		_rebuild()

## Resample every cached cell inside rect (the edit area). A changed value
## marks every region spanning that cell for a full (budgeted) rebuild; an
## unchanged value is left alone, so a distant edit is a no-op.
func _localize_resample(rect: Rect2) -> void:
	var cells: Array = []
	for cell: Vector2i in _cell_cache.keys():
		if rect.has_point(Vector2(float(cell.x) * WATER_CELL, float(cell.y) * WATER_CELL)):
			cells.append(cell)
	var t_end := Time.get_ticks_msec() + int(RESAMPLE_TIME_BUDGET_MS)
	var i := 0
	while i < cells.size():
		var cell: Vector2i = cells[i]
		i += 1
		var previous: Variant = _cell_cache.get(cell, null)
		var top := _terrain_top(float(cell.x) * WATER_CELL + WATER_CELL * 0.5, float(cell.y) * WATER_CELL + WATER_CELL * 0.5, previous)
		_cell_cache[cell] = top
		if _terrain_value_changed(previous, top):
			var owners: Array = _cell_regions.get(cell, [])
			for rid: int in owners:
				_mark_rebuild(rid)
		if Time.get_ticks_msec() >= t_end:
			# Time budget spent mid-rect: hand the remainder to the drain so
			# _process finishes it over frames instead of stalling this one
			# (a 20k-cell river rect was several seconds of freeze on Thor).
			while i < cells.size():
				_queue_resample(cells[i])
				i += 1
			break

func _process(_delta: float) -> void:
	if _pending_cells.is_empty() and _dirty_regions.is_empty():
		return
	if _backend == null or not _backend.has_method("voxel_at"):
		return
	if _backend.has_method("is_ready") and not _backend.is_ready():
		return
	_drain(1)

## One budgeted pass: resample up to RESAMPLE_BUDGET queued cells, then build
## up to BUILD_BUDGET cells of mesh across the dirty regions. Repeats while
## work remains, so a large rebuild spreads over frames instead of stalling.
func _drain(max_passes: int) -> void:
	var rs_ms := 0.0
	var mesh_ms := 0.0
	var resampled := 0
	var passed := 0
	while passed < max_passes and (not _pending_cells.is_empty() or not _dirty_regions.is_empty()):
		var tr := Time.get_ticks_usec()
		resampled += _resample_pass()
		rs_ms += (Time.get_ticks_usec() - tr) / 1000.0
		var tb := Time.get_ticks_usec()
		_build_pass()
		mesh_ms += (Time.get_ticks_usec() - tb) / 1000.0
		passed += 1
	water_perf = {"resample_ms": rs_ms, "mesh_ms": mesh_ms, "cells_resampled": resampled, "cells_pending": _pending_cells.size(), "regions": _regions.size(), "quads": surface_quad_count()}
	water_rebuilds += 1
	_last_key = _key()

func _resample_pass() -> int:
	var t_end := Time.get_ticks_msec() + int(RESAMPLE_TIME_BUDGET_MS)
	var count := 0
	while not _pending_cells.is_empty() and count < RESAMPLE_BUDGET and Time.get_ticks_msec() < t_end:
		var cell: Vector2i = _pending_cells.pop_back()
		_pending_set.erase(cell)
		var previous: Variant = _cell_cache.get(cell, null)
		var hint: Variant = _resample_hint.get(cell, previous)
		var top := _terrain_top(float(cell.x) * WATER_CELL + WATER_CELL * 0.5, float(cell.y) * WATER_CELL + WATER_CELL * 0.5, hint)
		_cell_cache[cell] = top
		_resample_hint.erase(cell)
		count += 1
		if _terrain_value_changed(previous, top):
			var owners: Array = _cell_regions.get(cell, [])
			for rid: int in owners:
				_mark_rebuild(rid)
	return count

## Rebuild the dirty regions' meshes from the (now warm) cache, up to
## BUILD_BUDGET cells of work per pass. A region whose index reaches its cell
## count is uploaded to its reused node; the work arrays stay resident so a
## growing candidate appends to them instead of reallocating.
func _build_pass() -> void:
	var t_end := Time.get_ticks_msec() + int(BUILD_TIME_BUDGET_MS)
	var budget := BUILD_BUDGET
	for rid: int in _dirty_regions.keys():
		if budget <= 0 or Time.get_ticks_msec() >= t_end:
			break
		var state: Dictionary = _build_state.get(rid, {})
		if state.is_empty():
			_dirty_regions.erase(rid)
			continue
		var region: Dictionary = _region_by_id.get(rid, {})
		var level := Geometry.surface_level(region)
		var cells: Array = state["cells"]
		var start: int = int(state["index"])
		var end: int = mini(cells.size(), start + budget)
		var verts: PackedVector3Array = state["verts"]
		var norms: PackedVector3Array = state["norms"]
		var cols: PackedColorArray = state["cols"]
		var idx: PackedInt32Array = state["idx"]
		var base := verts.size() / 4
		for i in range(start, end):
			var cell: Vector2i = cells[i]
			var cx := float(cell.x) * WATER_CELL
			var cz := float(cell.y) * WATER_CELL
			var surface_y: Variant = _cell_cache.get(cell, NAN)
			# Terrain at/above the level is dry (shore); only below-level cells
			# (or empty deep columns) carry a water quad, clipped at the level.
			if not is_nan(surface_y) and surface_y >= level - 0.000001:
				continue
			var depth := 0.0 if is_nan(surface_y) else clampf((level - surface_y) / DEPTH_SCALE, 0.0, 1.0)
			var color := _depth_color(region, depth)
			base = _append_water_quad(verts, norms, cols, idx, base, cx, cz, level, color)
		state["index"] = end
		budget -= (end - start)
		if end < cells.size():
			continue
		_upload_region(rid)
		_dirty_regions.erase(rid)

func _terrain_value_changed(previous: Variant, top: Variant) -> bool:
	if previous == null:
		return true
	var prev_nan := previous is float and is_nan(previous)
	var top_nan := top is float and is_nan(top)
	if prev_nan != top_nan:
		return true
	if prev_nan:
		return false
	return not is_equal_approx(previous, top)

## Sync the authoritative region list against the render state: drop gone
## regions, prepare (or grow) changed ones, queue their cells.
## Sync the authoritative region list against the render state: drop gone
## regions, prepare (or grow) changed ones, queue their cells. A pure growth
## (the old footprint is a subset of the new) appends to the region's
## persistent mesh arrays instead of rebuilding it.
func _sync_regions() -> void:
	var present := {}
	for region: Dictionary in _regions:
		var id := int(region.get("id", 0))
		present[id] = true
		var old_region: Dictionary = _region_by_id.get(id, {})
		_region_by_id[id] = region
		var cells := _footprint_of(region)
		var key := _region_key(region, cells)
		var old_key: String = str(_region_keys.get(id, ""))
		var state: Dictionary = _build_state.get(id, {})
		var old_cells: Array = []
		if not state.is_empty():
			old_cells = state["cells"]
		if old_key == key and not state.is_empty() and old_cells.size() == cells.size():
			continue
		if old_key != key and not old_region.is_empty() and not bool(region.get("reset", false)) and old_region.has("cells") and region.has("cells") and _same_water_identity(old_region, region) and cells.size() >= old_cells.size():
			# A growing stroke (the scene's hint is append-only): only the new
			# suffix is appended to the persistent mesh arrays; the built
			# prefix stays valid (no realloc, no re-rasterize, no re-upload of
			# existing quads).
			for i in range(old_cells.size(), cells.size()):
				var cell: Vector2i = cells[i]
				state["cells"].append(cell)
				_map_cell(id, cell)
				_ensure_pending_one(cell)
			var new_flow := Geometry.flow_direction(region)
			var old_flow := Geometry.flow_direction(old_region)
			if new_flow != old_flow:
				# The material object is shared with the uploaded mesh, so a
				# parameter update flows to the GPU without a mesh rebuild.
				var mat: ShaderMaterial = state["material"]
				mat.set_shader_parameter("flow_dir", new_flow)
				mat.set_shader_parameter("flow_speed", 0.55 if new_flow.distance_to(Vector2(1.0, 0.0)) > 0.001 else 0.25)
			_dirty_regions[id] = true
			_region_keys[id] = key
			continue
		# New, or changed in a way that is not a pure extension: full (budgeted)
		# rebuild from the warm cache.
		_unmap_cells(id, old_cells)
		_map_cells(id, cells)
		_prepare_build(id, region, cells)
		_ensure_pending(cells)
		_dirty_regions[id] = true
		_region_keys[id] = key
	for id: Variant in _region_keys.keys():
		if not present.has(int(id)):
			_drop_region(int(id))

static func _same_water_identity(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("type", "")) == str(b.get("type", "")) and float(a.get("level", 0.0)) == float(b.get("level", 0.0))
func _prepare_build(id: int, region: Dictionary, cells: Array) -> void:
	_build_state[id] = {
		"cells": cells.duplicate(),
		"verts": PackedVector3Array(),
		"norms": PackedVector3Array(),
		"cols": PackedColorArray(),
		"idx": PackedInt32Array(),
		"index": 0,
		"material": _region_material(Geometry.flow_direction(region), region),
	}

func _mark_rebuild(id: int) -> void:
	var state: Dictionary = _build_state.get(id, {})
	if state.is_empty():
		return
	# A value-changing resample invalidates every quad of this region: clear
	# the persistent mesh arrays (index restarts at 0) or _build_pass would
	# append the rebuilt quads on top of the stale ones. The grow path
	# (_sync_regions) sets _dirty_regions directly and keeps the prefix.
	state["index"] = 0
	state["verts"].clear()
	state["norms"].clear()
	state["cols"].clear()
	state["idx"].clear()
	_dirty_regions[id] = true

func _ensure_pending(cells: Array) -> void:
	for cell: Vector2i in cells:
		_ensure_pending_one(cell)

func _ensure_pending_one(cell: Vector2i) -> void:
	if _cell_cache.has(cell) or _pending_set.has(cell):
		return
	_pending_set[cell] = true
	_pending_cells.append(cell)

## Queue a cell for resample even though it has a cached value: used when a
## localized pass spills its remaining cells to the drain (they need
## re-validation, not just first-time sampling).
func _queue_resample(cell: Vector2i) -> void:
	if _pending_set.has(cell):
		return
	_pending_set[cell] = true
	_pending_cells.append(cell)

## A committed carve: this cell's terrain changed under the water. Drop the
## cached value so the next resample re-samples it (a changed value then
## marks the owning regions for rebuild); the old value is kept as a probe
## hint because a carve usually moves the column only a few rows.
func _invalidate_cell(cell: Vector2i) -> void:
	var old: Variant = _cell_cache.get(cell, null)
	_cell_cache.erase(cell)
	if old != null:
		_resample_hint[cell] = old
	_ensure_pending_one(cell)

func _map_cell(id: int, cell: Vector2i) -> void:
	var owners: Array = _cell_regions.get(cell, [])
	if not owners.has(id):
		owners.append(id)
		_cell_regions[cell] = owners

func _map_cells(id: int, cells: Array) -> void:
	for cell: Vector2i in cells:
		_map_cell(id, cell)

func _unmap_cells(id: int, cells: Array) -> void:
	for cell: Vector2i in cells:
		var owners: Array = _cell_regions.get(cell, [])
		if owners.has(id):
			owners.erase(id)
			if owners.is_empty():
				_cell_regions.erase(cell)
			else:
				_cell_regions[cell] = owners

func _drop_region(id: int) -> void:
	var state: Dictionary = _build_state.get(id, {})
	_unmap_cells(id, state.get("cells", []))
	for cell: Vector2i in state.get("cells", []):
		_resample_hint.erase(cell)
	_region_keys.erase(id)
	_region_by_id.erase(id)
	_build_state.erase(id)
	_dirty_regions.erase(id)
	var node: MeshInstance3D = _region_nodes.get(id, null)
	if is_instance_valid(node):
		node.queue_free()
	_region_nodes.erase(id)

func _upload_region(id: int) -> void:
	var state: Dictionary = _build_state.get(id, {})
	var node := _region_node(id)
	var verts: PackedVector3Array = state["verts"]
	if verts.is_empty():
		node.mesh = null
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _surface_arrays(verts, state["norms"], state["cols"], state["idx"]))
	mesh.surface_set_material(0, state["material"])
	node.mesh = mesh

func _region_node(id: int) -> MeshInstance3D:
	var node: MeshInstance3D = _region_nodes.get(id, null)
	if node == null:
		node = MeshInstance3D.new()
		node.name = "WaterRegion_%d" % id
		add_child(node)
		_region_nodes[id] = node
	return node

## The cell set for a region: the scene's rolling hint for a stroke candidate
## (an append-only PackedVector2Array, built incrementally by the scene as the
## stroke grows — no per-frame re-union/re-rasterize) or the memoized
## geometry footprint for saved regions.
func _footprint_of(region: Dictionary) -> Array:
	var cells = region.get("cells", null)
	if cells != null and cells.size() > 0:
		return cells
	return Geometry.footprint_cells(region, _world_x())

## Identity of a region's mesh geometry. Candidate streams key on their cell
## hint size (the hint is append-only, so equal size == equal set) instead of
## the point list, which grows every frame without adding water.
static func _region_key(region: Dictionary, cells: Array) -> String:
	if region.has("cells"):
		return "c|%s|%.4f|%d" % [str(region.get("type", "")), float(region.get("level", 0.0)), cells.size()]
	return "%s|%.4f|%.4f|%.3f,%.3f|%d" % [str(region.get("type", "")), float(region.get("level", 0.0)), float(region.get("width", 0.0)), Geometry.flow_direction(region).x, Geometry.flow_direction(region).y, (region.get("points", []) as Array).size()]

## Full resample + synchronous build (startup / undo-redo / restore path).
## Callers assert the surface is complete on return. The resample stays fast
## because each column probe starts from the previous value's hint (a couple
## of native reads for an unchanged column instead of a ~194-read full scan),
## and each region allocates only its own mesh arrays, never the whole-at-once
## mesh that OOMed scudo.
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
	_pending_cells = []
	_pending_set = {}
	_dirty_regions = {}
	_build_state = {}
	_region_keys = {}
	_region_by_id = {}
	# The previous cache doubles as the hint source for the column probes: on
	# undo/redo or a local edit only the moved columns scan more than a few
	# rows; the first-ever build (no previous values) scans in full once.
	var prev_top := _cell_cache
	_cell_cache = {}
	_resample_hint = {}
	_cell_regions = {}
	_clear()
	var resampled := 0
	for region: Dictionary in _regions:
		var id := int(region.get("id", 0))
		_region_by_id[id] = region
		var cells := _footprint_of(region)
		_region_keys[id] = _region_key(region, cells)
		_map_cells(id, cells)
		for cell: Vector2i in cells:
			var px := float(cell.x) * WATER_CELL + WATER_CELL * 0.5
			var pz := float(cell.y) * WATER_CELL + WATER_CELL * 0.5
			_cell_cache[cell] = _terrain_top(px, pz, prev_top.get(cell, null))
			resampled += 1
		_prepare_build(id, region, cells)
		_build_region_full(id)
	water_perf = {"resample_ms": 0.0, "mesh_ms": 0.0, "total_ms": 0.0, "cells_resampled": resampled, "regions": _regions.size(), "quads": surface_quad_count(), "full_rebuild": true}
	water_rebuilds += 1

## The per-vertex shade for a submerged cell: the standard translucent water
## ramp, or the near-opaque pool ramp (its alpha must stay high so the basin
## floor can't show through as a dotted grid).
func _depth_color(region: Dictionary, depth: float) -> Color:
	if _is_plunge_pool(region):
		return POOL_COLOR.lerp(POOL_DEEP_COLOR, depth)
	return WATER_COLOR.lerp(WATER_DEEP_COLOR, depth)

## Synchronous full build of one region from the warm cache.
func _build_region_full(id: int) -> void:
	var state: Dictionary = _build_state.get(id, {})
	if state.is_empty():
		return
	var cells: Array = state["cells"]
	var region: Dictionary = _region_by_id.get(id, {})
	var level := Geometry.surface_level(region)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var base := 0
	for cell: Vector2i in cells:
		var cx := float(cell.x) * WATER_CELL
		var cz := float(cell.y) * WATER_CELL
		var surface_y: Variant = _cell_cache.get(cell, NAN)
		if not is_nan(surface_y) and surface_y >= level - 0.000001:
			continue
		var depth := 0.0 if is_nan(surface_y) else clampf((level - surface_y) / DEPTH_SCALE, 0.0, 1.0)
		var color := _depth_color(region, depth)
		base = _append_water_quad(verts, norms, cols, idx, base, cx, cz, level, color)
	state["verts"] = verts
	state["norms"] = norms
	state["cols"] = cols
	state["idx"] = idx
	state["index"] = cells.size()
	_upload_region(id)

func _clear() -> void:
	for node: Variant in _region_nodes.values():
		if is_instance_valid(node):
			(node as Node).queue_free()
	_region_nodes = {}

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
	var top := float(fall["top_level"])
	var bottom := float(fall["bottom_level"])
	if bottom >= top:
		return null
	var flow := Vector2(float(fall["flow"][0]), float(fall["flow"][1]))
	if flow.length() < 0.0001:
		flow = Vector2(1.0, 0.0)
	flow = flow.normalized()
	# The curtain is NOT a thin 1.5 m pole: it spans the submerged channel.
	# The top edge is the wide lip at the crown, the bottom edge flares to
	# the full plunge-pool run, and the sheet tilts downstream over
	# cascade_run so its base lands where the cliff foot meets the pool
	# (matching the ~4 m run of the generated cliff face).
	var crown_width := maxf(Waterfall.CASCADE_WIDTH, float(fall.get("crown_width", Waterfall.CASCADE_WIDTH)))
	var impact_width := maxf(crown_width, float(fall.get("impact_width", crown_width)))
	var head := top - bottom
	var run := Waterfall.cascade_run(head)
	var impact := crown + flow * run
	# A fall into a lake lands in the lake's centre: the fixed run past the lip
	# overshoots the plunge pool (the sheet was ending on dry ground south of
	# the pool). The run is recomputed from the true lip-to-centre distance.
	if fall.has("lower_centroid") and (fall["lower_centroid"] as Array).size() == 2:
		var lc := Vector2(float((fall["lower_centroid"] as Array)[0]), float((fall["lower_centroid"] as Array)[1]))
		if (lc - crown).length() > 0.25:
			impact = lc
			run = (lc - crown).length()
	# Head scales the sheet's presence: a 20 m cliff is a dense curtain; a 2 m
	# river step is a faint shimmer across the channel, not a flat wall. Tall
	# falls also widen past a narrow lip scan so the curtain reads big.
	var sheet_strength := 1.0 if head >= 4.0 else clampf(0.25 + head * 0.1, 0.25, 1.0)
	if head >= 10.0:
		crown_width = maxf(crown_width, 8.0)
		impact_width = maxf(crown_width, impact_width)
	# Lift the curtain off the voxel face to avoid coplanar flicker.
	crown += flow * 0.04
	var perp := Vector2(-flow.y, flow.x)
	var mesh := ArrayMesh.new()
	# Surface 0: the falling curtain, a tilted trapezoid sheet from the lip
	# down to the pool.
	var a := crown + perp * (crown_width * 0.5)
	var b := crown - perp * (crown_width * 0.5)
	var c := impact + perp * (impact_width * 0.5)
	var d := impact - perp * (impact_width * 0.5)
	var cv := PackedVector3Array([Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(d.x, bottom, d.y), Vector3(c.x, bottom, c.y)])
	var down3 := Vector3(impact.x - crown.x, bottom - top, impact.y - crown.y)
	var n3 := Vector3(perp.x, 0.0, perp.y).cross(down3).normalized()
	if n3.dot(Vector3(flow.x, 0.0, flow.y)) < 0.0:
		n3 = -n3
	var cn := PackedVector3Array([n3, n3, n3, n3])
	var cc := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	var ci := PackedInt32Array([0, 1, 2, 0, 2, 3])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _surface_arrays(cv, cn, cc, ci))
	mesh.surface_set_material(0, _fall_material(head, top, sheet_strength))
	# Surface 1: a soft elliptical foam bed where the curtain lands (a hard
	# flat square read as a painted decal). Shallow steps skip it — a faint
	# shimmer doesn't churn.
	if head >= 4.0:
		var s_x := maxf(impact_width * 0.5, 3.0)
		var s_z := maxf(run * 0.5, 1.75)
		var sv := PackedVector3Array([Vector3(impact.x, bottom + 0.02, impact.y)])
		for i in 16:
			var aa := TAU * float(i) / 16.0
			sv.append(Vector3(impact.x + cos(aa) * s_x, bottom + 0.02, impact.y + sin(aa) * s_z))
		var sn := PackedVector3Array()
		sn.resize(17)
		for i in 17:
			sn[i] = Vector3.UP
		var sc := PackedColorArray()
		sc.resize(17)
		for i in 17:
			sc[i] = Color.WHITE
		var si := PackedInt32Array()
		for i in 15:
			si.append_array([0, i + 1, i + 2])
		si.append_array([0, 16, 15])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _surface_arrays(sv, sn, sc, si))
		var smat := ShaderMaterial.new()
		smat.shader = SPLASH_SHADER
		smat.set_shader_parameter("center", Vector2(impact.x, impact.y))
		smat.set_shader_parameter("radius", Vector2(s_x, s_z))
		smat.set_shader_parameter("strength", 0.5 * sheet_strength)
		mesh.surface_set_material(1, smat)
	var node := MeshInstance3D.new()
	node.name = "Waterfall_%d-%d" % [int(fall["upper_id"]), int(fall["lower_id"])]
	node.mesh = mesh
	# The particle aspect of the fall: a short-lived base spray (droplets thrown
	# up and out, pulled back by gravity) plus a prewarmed, slowly rising soft mist.
	node.add_child(_make_spray(impact, bottom, impact_width))
	node.add_child(_make_mist(impact, bottom, impact_width))
	return node

func _surface_arrays(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays

func _fall_material(span: float, top: float, strength: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FALL_SHADER
	material.set_shader_parameter("fall_color", FALL_COLOR)
	material.set_shader_parameter("height", span)
	material.set_shader_parameter("top_level", top)
	material.set_shader_parameter("sheet_strength", strength)
	return material

## A unit billboard quad carrying a soft, unshaded alpha material; the particle
## scale (scale_min/scale_max) sizes each instance.
func _particle_quad(color: Color) -> QuadMesh:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
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

## The premade plunge pool is the one body whose bed is too close to the
## surface for the translucent sheet: it gets the near-opaque pool material
## instead. Matched against the generated basin's exact level + points, so it
## stays in sync with PremadeRiver without persisting extra region flags.
func _is_plunge_pool(region: Dictionary) -> bool:
	return PremadeRiver.matches_pool(region, PremadeRiver.plunge_pool_region())

func _region_material(flow: Vector2, region: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	if _is_plunge_pool(region):
		material.shader = POOL_WATER_SHADER
		material.set_shader_parameter("pool_color", POOL_COLOR)
		material.set_shader_parameter("flow_dir", Vector2(1.0, 0.0))
		material.set_shader_parameter("flow_speed", 0.25)  # calm: no streaks in a pool
		return material
	material.shader = WATER_SHADER
	material.set_shader_parameter("water_color", WATER_COLOR)
	material.set_shader_parameter("flow_dir", flow)
	material.set_shader_parameter("flow_speed", 0.55 if flow.distance_to(Vector2(1.0, 0.0)) > 0.001 else 0.25)
	return material

## World Y of the top face of the topmost solid voxel in the column, or NAN when
## the column is empty (a deep hole, which is always submerged). When a last-
## known top (world Y, e.g. from _cell_cache) is given as `hint`, a band of
## HINT_BAND_ROWS around it is probed first: an unchanged column resolves in a
## couple of native reads instead of a ~194-read full 256-row scan (the scan
## cost is what made resamples freeze the game on Thor).
func _terrain_top(x: float, z: float, hint: Variant = null) -> float:
	var scale := maxf(0.001, float(_backend.get("voxel_scale")))
	var patch: Vector3i = _backend.get("patch_size")
	var vx := int(floori(x / scale))
	var vz := int(floori(z / scale))
	if vx < 0 or vz < 0 or vx >= patch.x or vz >= patch.z:
		return NAN
	if hint != null and not (hint is float and is_nan(hint)):
		var hint_row := int(floori(float(hint) / scale)) - 1
		if hint_row >= 0:
			var top_row := int(patch.y) - 1
			var hi := mini(hint_row + HINT_BAND_ROWS, top_row)
			var lo := maxi(hint_row - HINT_BAND_ROWS, 0)
			for y in range(hi, lo - 1, -1):
				if int(_backend.voxel_at(Vector3i(vx, y, vz))) != 0:
					return float(y + 1) * scale
	for y in range(int(patch.y) - 1, -1, -1):
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

## Deterministic quad count of the current surface (test hook).
func surface_quad_count() -> int:
	var total := 0
	for node: Variant in _region_nodes.values():
		var mesh: ArrayMesh = (node as MeshInstance3D).mesh
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
