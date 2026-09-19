extends "res://scripts/m2_scene_starter_valley.gd"

## Water is an editable scenery layer (streams + lakes), not a fluid simulation.
## A live centreline (stream) or outline (lake) is a preview only; releasing A
## (stream) or closing the outline (lake) records the region and carves its bed/
## banks as ONE landscape undo transaction. Saved authority stores only the
## region record — never a preview. Menus block the tool; cancel restores state.
const WaterState = preload("res://scripts/landscape_state.gd")
const WaterGrid = preload("res://scripts/visual_grid.gd")
const WaterRegion = preload("res://scripts/water_region_geometry.gd")
const WaterExcavation = preload("res://scripts/water_terrain_excavation.gd")

const STREAM_WIDTH := 1.5
const LAKE_MIN_POINTS := 3
const LAKE_CLOSE_SNAP := 0.5
const WATERFALL_DISMISS_RADIUS := 1.0

var water_placement_active := false
var water_kind := "stream"
var water_stroking := false
var water_stream_points: PackedVector2Array = []
var water_stream_level := 0.0
var water_lake_points: Array = []
var water_placement_valid := false
var water_placement_reason := ""
var _water_before: Dictionary = {}
var _water_before_serialized := ""
var _water_building_revision := -1
var _water_terrain_revision := -1
var _water_last_sample := Vector2(NAN, NAN)
var _water_preview_signature := ""
# Rolling stream stroke-cell hint: each sampled segment is rasterized once
# (O(segment)) and merged into a dedup set + append-only list. This replaces
# the old preview, which re-rasterized the entire growing stroke (a full
# O(N^2) union) on every frame of a stroke — the cause of the mobile freeze.
# The water visual consumes the list incrementally (appends only new cells to
# its persistent mesh arrays) and its size is the cheap preview fingerprint.
# Cleared when a stroke is cancelled or committed.
var _stroke_cells := {}
var _stroke_cell_list := PackedVector2Array()
# One-shot: set when a stroke (re)starts so the water visual replaces its
# previous candidate mesh instead of appending onto it; cleared after the
# first preview sync of the stroke.
var _stroke_reset_pending := true
# The stroke's carve width is frozen when it starts (brush keys are blocked
# while drawing) so the preview hint and the committed region match exactly.
var _stroke_width := 1.5

func _process(delta: float) -> void:
	super._process(delta)
	if water_placement_active and not menu_open:
		_update_water_validity()
		if water_stroking and water_kind == "stream": _sample_water_stream()
		_update_water_preview()

func _select_terrain_tool(tool: String) -> void:
	super._select_terrain_tool(tool)
	if tool == "water":
		water_kind = "stream"
		_begin_water_placement()
	elif water_placement_active:
		_cancel_water_placement("Terrain tool selected")

func _begin_water_placement() -> void:
	if water_placement_active or stroke_active or landscape_active or detail_move_active or resize_active or building_placement_active: return
	water_placement_active = true
	water_stroking = false
	water_stream_points.clear()
	water_stream_level = 0.0
	water_lake_points.clear()
	_water_last_sample = Vector2(NAN, NAN)
	water_placement_valid = false
	water_placement_reason = "Find a terrain surface"
	_water_building_revision = building_world.get_revision()
	_water_terrain_revision = _terrain_revision()
	_landscape_before.clear()
	_reset_water_baseline()
	tools_open = false
	detail_open = false
	if tools_panel: tools_panel.visible = false
	if _terrain_panel: _terrain_panel.visible = false
	get_viewport().gui_release_focus()
	_preview_key = ""
	_set_status(_water_status_line())
	_update_brush_preview()
	_update_water_validity()
	_update_water_preview()
	_refresh_controller_hud()

func _water_status_line() -> String:
	if water_kind == "stream":
		return "Stream • hold A to draw the centreline • release to commit • B close"
	return "Lake • A to outline • near the start to close • B remove last"

func _input(event: InputEvent) -> void:
	if _shutting_down: return
	if _blocked_until_accept_release:
		super._input(event)
		return
	if water_placement_active:
		if event.is_action_pressed("m1_accept"):
			# Aiming at a visible waterfall and pressing A dismisses it (one landscape
			# undo transaction); elsewhere A starts water placement as usual.
			if not water_stroking and water_lake_points.is_empty():
				var fall := _waterfall_at_aim(WATERFALL_DISMISS_RADIUS)
				if not fall.is_empty():
					_dismiss_waterfall(fall)
					get_viewport().set_input_as_handled()
					return
			if water_kind == "stream": _start_water_stream()
			else: _add_water_lake_vertex()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released("m1_accept"):
			if water_kind == "stream": _commit_water_stream()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_cancel"):
			if water_stroking or not water_lake_points.is_empty(): _cancel_water_stroke("Cancelled")
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released("m1_cancel"):
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_undo"):
			if water_stroking: _cancel_water_stroke("Stroke cancelled")
			else:
				_undo()
				_reset_water_baseline()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_redo"):
			if not water_stroking:
				_redo()
				_reset_water_baseline()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_pause"):
			if water_stroking: _cancel_water_stroke("Paused")
			super._input(event)
			return
		if event.is_action_pressed("m1_mode_switch") or event.is_action_pressed("m1_view") or event.is_action_pressed("m1_cycle_left") or event.is_action_pressed("m1_cycle_right") or event.is_action_pressed("m1_height_up") or event.is_action_pressed("m1_height_down") or event.is_action_pressed("m1_tools"):
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _update_brush_preview() -> void:
	if not water_placement_active:
		super._update_brush_preview()
		return
	_terrain_target_valid = false
	if backend and backend.is_ready():
		var sample: Dictionary = backend.sample_surface_plane(cursor, Vector3.UP, 1.5)
		if not bool(sample.get("valid", false)): sample = _find_local_surface(cursor, Vector3.UP, float(backend.voxel_scale))
		if bool(sample.get("valid", false)):
			_terrain_target_valid = true
			_terrain_target_point = sample["point"]
			_terrain_target_normal = sample.get("normal", Vector3.UP)
			preview_center = _terrain_target_point
	if brush_preview: brush_preview.visible = false
	if terrain_edit_preview: terrain_edit_preview.visible = false
	if reference_plane: reference_plane.visible = false
	if terrain_hit_marker: terrain_hit_marker.visible = false

## Water brush footprint (the area of effect). The terrain UX hides its reticle
## for the water tool (_sculpt_preview_visible is false for "water"), so the
## water tool owns the reticle here: a ring at the brush radius, the actual carve
## width, not a fixed small diamond.
func _update_cursor_reticle() -> void:
	if not water_placement_active:
		super._update_cursor_reticle()
		return
	if not cursor_reticle: return
	if _terrain_target_valid:
		var radius := brush_radius if water_kind == "stream" else 0.25
		cursor_reticle.update_target(_terrain_target_point, _terrain_target_normal, radius, "water", camera, true)
	else:
		cursor_reticle.set_target_visible(false)

func _update_water_validity() -> void:
	water_placement_valid = false
	water_placement_reason = "No terrain surface under cursor"
	if not water_placement_active: return
	if _terrain_revision() != _water_terrain_revision:
		water_placement_reason = "Terrain changed; restart water"
		return
	if building_world.get_revision() != _water_building_revision:
		water_placement_reason = "Home layout changed; restart water"
		return
	if JSON.stringify(landscape_state.document()) != _water_before_serialized:
		water_placement_reason = "Landscape changed; restart water"
		return
	var point := _water_cursor_point()
	if not point.is_finite(): return
	if point.x < 0.0 or point.x >= WaterState.EDITABLE_WORLD_SIZE or point.y < 0.0 or point.y >= WaterState.EDITABLE_WORLD_SIZE:
		water_placement_reason = "Outside editable world"
		return
	water_placement_valid = true
	if water_kind == "stream":
		water_placement_reason = "Drawing" if water_stroking else "Ready to draw"
	else:
		water_placement_reason = "%d points" % water_lake_points.size()

func _start_water_stream() -> bool:
	if not water_placement_active or water_stroking or water_kind != "stream": return false
	_update_water_validity()
	if not water_placement_valid:
		_set_status("Cannot draw: %s" % water_placement_reason)
		return false
	water_stroking = true
	water_stream_points.clear()
	var point := _water_cursor_point()
	water_stream_level = _terrain_top(point)
	if is_nan(water_stream_level): water_stream_level = 1.0
	water_stream_points.append(point)
	_water_last_sample = point
	_stroke_width = maxf(0.5, 2.0 * brush_radius)
	_stroke_cells.clear()
	_stroke_cell_list.clear()
	_stroke_reset_pending = true
	_water_preview_signature = ""
	_set_status("Stream • drawing • release A to commit")
	_update_water_preview()
	return true

func _sample_water_stream() -> bool:
	if not water_stroking or water_kind != "stream": return false
	_update_water_validity()
	if not water_placement_valid: return false
	var point := _water_cursor_point()
	if not point.is_finite(): return false
	# Distance gate: the centreline is a low-frequency shape edit, so jitter
	# inside a few structural cells adds nothing. Appending a point every
	# frame (the old behaviour) invalidated the preview fingerprint and forced
	# the visual's full candidate rebuild every frame.
	if point.distance_to(_water_last_sample) < 0.05:
		_water_last_sample = point
		return false
	if water_stream_points.size() > 0:
		_stroke_add_segment(water_stream_points[water_stream_points.size() - 1], point)
	water_stream_points.append(point)
	_water_last_sample = point
	_water_preview_signature = ""
	return true

## Rasterize one stroke segment once and merge its cells into the rolling
## hint. O(cells of this segment); the dedup set keeps repeated segments
## cheap and the list stays append-only for the visual's incremental append.
func _stroke_add_segment(p1: Vector2, p2: Vector2) -> void:
	if not p1.is_finite() or not p2.is_finite():
		return
	for cell: Vector2i in PathRegion.stroke_cells(p1, p2, _stroke_width, WaterState.EDITABLE_WORLD_SIZE):
		if not _stroke_cells.has(cell):
			_stroke_cells[cell] = true
			_stroke_cell_list.append(cell)

func _add_water_lake_vertex() -> void:
	if not water_placement_active or water_kind != "lake": return
	_update_water_validity()
	if not water_placement_valid:
		_set_status("Cannot outline: %s" % water_placement_reason)
		return
	var point := _water_cursor_point()
	if not point.is_finite(): return
	var action := _lake_outline_action(water_lake_points, point)
	if action == "close":
		_commit_water_lake()
		return
	if action != "add":
		return
	water_lake_points.append(point)
	_water_preview_signature = ""
	_set_status("Lake • %d points • near the start to close" % water_lake_points.size())
	_update_water_preview()

## Pure decision for a lake outline A-press: "close" when near the start with enough
## points, "ignore" when too close to the previous point (only once one exists), else
## "add". Kept pure so the outline logic is testable without the live scene.
static func _lake_outline_action(points: Array, point: Vector2) -> String:
	if points.size() >= LAKE_MIN_POINTS:
		var first: Vector2 = points[0]
		if point.distance_to(first) < LAKE_CLOSE_SNAP:
			return "close"
	if not points.is_empty() and point.distance_to(points.back()) < WaterGrid.UNIT:
		return "ignore"
	return "add"

func _commit_water_stream() -> bool:
	if not water_stroking or water_kind != "stream": return false
	if water_stream_points.size() < 2:
		_cancel_water_stroke("Too short; cancelled")
		return false
	var region := _stream_region()
	water_stroking = false
	return _commit_water(region)

func _commit_water_lake() -> bool:
	if water_lake_points.size() < LAKE_MIN_POINTS:
		_set_status("Lake needs at least %d points" % LAKE_MIN_POINTS)
		return false
	return _commit_water(_lake_region())

func _stream_region() -> Dictionary:
	var first: Vector2 = water_stream_points[0]
	var last: Vector2 = water_stream_points[water_stream_points.size() - 1]
	var flow := last - first
	if flow.length() < 0.01: flow = Vector2.RIGHT
	flow = flow.normalized()
	var points: Array = []
	for p: Vector2 in water_stream_points:
		points.append([p.x, p.y])
	# Candidate is the id-0 region (saved regions use ids >= 1). The rolling
	# cell hint lets the visual append new cells without re-rasterizing the
	# whole stroke; "reset" is the one-shot replace flag (stroke start).
	return {"id": 0, "type": "stream", "level": water_stream_level, "width": _stroke_width, "points": points, "flow": [flow.x, flow.y], "cells": _stroke_cell_list, "reset": _stroke_reset_pending}

func _lake_region() -> Dictionary:
	var points: Array = []
	for p: Vector2 in water_lake_points:
		points.append([p.x, p.y])
	return {"type": "lake", "level": _lake_level(points), "points": points}

## Rebuild the water surface from the cache, resampling only the cells the last
## terrain carve touched. The commit carves just the new region's bed, so the
## rest of the surface (starter river + prior water) keeps its cached terrain
## tops instead of a full column resample.
func _sync_water_incremental(changes: Array) -> void:
	if not water_visual: return
	var invalidated: Array = []
	var seen := {}
	for change in changes:
		var pos: Vector3i = change.get("position", Vector3i.ZERO)
		var cell := Vector2i(pos.x, pos.z)
		if seen.has(cell): continue
		seen[cell] = true
		invalidated.append(cell)
	if water_visual.has_method("set_regions_incremental"):
		water_visual.set_regions_incremental(landscape_state.water, invalidated)
	else:
		_sync_water_visual()

func _commit_water(region: Dictionary) -> bool:
	if JSON.stringify(landscape_state.document()) != _water_before_serialized or _terrain_revision() != _water_terrain_revision or building_world.get_revision() != _water_building_revision:
		_cancel_water_placement("World changed; cancelled")
		return false
	_water_before = landscape_state.document()
	var id := landscape_state.add_water(str(region.get("type", "")), float(region.get("level", 0.0)), region.get("points", []), float(region.get("width", 0.0)), region.get("flow", []))
	if id < 1:
		_cancel_water_placement("Water limit reached")
		return false
	var excavation: Dictionary = WaterExcavation.plan_bed(backend, region, WaterState.EDITABLE_WORLD_SIZE)
	if not bool(excavation.get("ok", false)):
		landscape_state.restore(_water_before)
		_cancel_water_placement("Terrain excavation unavailable")
		return false
	var changes: Array = excavation.get("changes", [])
	var terrain_changed := false
	if changes.size() > 0:
		if not backend.has_method("apply_voxel_changes") or not backend.apply_voxel_changes(changes):
			landscape_state.restore(_water_before)
			_cancel_water_placement("Terrain changed; cancelled")
			return false
		terrain_changed = true
	var cells: Array = []
	for cell: Vector2i in WaterRegion.footprint_cells(region, WaterState.EDITABLE_WORLD_SIZE):
		cells.append(cell)
	landscape_state.clear_records_in_path_cells(cells)
	if garden_visual: garden_visual.reset_records(landscape_state.records)
	water_stream_points.clear()
	water_lake_points.clear()
	_stroke_cells.clear()
	_stroke_cell_list.clear()
	_stroke_reset_pending = true
	_water_last_sample = Vector2(NAN, NAN)
	_water_preview_signature = ""
	_record_history("path" if terrain_changed else "landscape")
	_landscape_before.clear()
	# Incremental water sync: the commit carved only this region's bed, so reuse
	# the cached surface + resample just the carved cells (the old full rebuild
	# resampled every water column and froze the frame on mobile for big lakes).
	_sync_water_incremental(changes)
	_reset_water_baseline()
	_set_status("%s committed • LB undo" % (str(region.get("type", "water")).capitalize()))
	_update_water_validity()
	_update_water_preview()
	_refresh_controller_hud()
	return true

func _cancel_water_stroke(reason: String = "Cancelled") -> void:
	water_stroking = false
	water_stream_points.clear()
	water_lake_points.clear()
	_stroke_cells.clear()
	_stroke_cell_list.clear()
	_stroke_reset_pending = true
	_water_last_sample = Vector2(NAN, NAN)
	_water_preview_signature = ""
	_landscape_before.clear()
	_set_status(reason)
	_update_water_validity()
	_update_water_preview()
	# A cancelled stroke carved nothing, so the cached surface is still valid —
	# reuse it (no invalidation) instead of a full column resample.
	_sync_water_incremental([])

func _cancel_water_placement(reason: String = "Water tool closed") -> void:
	if not water_placement_active: return
	water_stroking = false
	water_placement_active = false
	water_stream_points.clear()
	water_lake_points.clear()
	_stroke_cells.clear()
	_stroke_cell_list.clear()
	_stroke_reset_pending = true
	_water_last_sample = Vector2(NAN, NAN)
	_water_preview_signature = ""
	_water_before.clear()
	_water_before_serialized = ""
	water_placement_reason = ""
	_set_status(reason)
	_sync_water_incremental([])
	_refresh_controller_hud()

func _cancel_current_edit(reason: String) -> void:
	if water_placement_active: _cancel_water_placement(reason)
	super._cancel_current_edit(reason)

func _undo() -> void:
	super._undo()
	_sync_water_visual()

func _redo() -> void:
	super._redo()
	_sync_water_visual()

func _restore_landscape(document: Dictionary) -> void:
	super._restore_landscape(document)
	_sync_water_visual()

func _on_backend_changed() -> void:
	# The base already localizes the region-water surface to the edit bounds
	# (refresh_surface_from_bounds) and re-derives waterfalls; a water commit
	# additionally syncs the new region via _sync_water_incremental. A full
	# set_regions here re-resampled every water column on every terrain edit —
	# the source of the mobile freeze.
	super._on_backend_changed()

func _water_cursor_point() -> Vector2:
	if not _terrain_target_valid: return Vector2(NAN, NAN)
	return Vector2(snappedf(_terrain_target_point.x, WaterGrid.UNIT), snappedf(_terrain_target_point.z, WaterGrid.UNIT))

## The active waterfall whose crown is within radius of the aim, or {} when none.
func _waterfall_at_aim(radius: float) -> Dictionary:
	if not water_visual or not water_visual.has_method("active_waterfalls"): return {}
	var aim := _water_cursor_point()
	if is_nan(aim.x): return {}
	var best := {}
	var best_dist := radius
	for fall in water_visual.active_waterfalls():
		var crown := Vector2(float(fall["crown"][0]), float(fall["crown"][1]))
		var d := crown.distance_to(aim)
		if d <= best_dist:
			best_dist = d
			best = fall
	return best

## Dismiss a visible waterfall: one landscape undo transaction; the visual re-derives
## and hides it. Pure scenery state — no terrain, no new water type.
func _dismiss_waterfall(fall: Dictionary) -> void:
	var key := str(fall["key"])
	if JSON.stringify(landscape_state.document()) != _water_before_serialized or _terrain_revision() != _water_terrain_revision or building_world.get_revision() != _water_building_revision:
		_set_status("World changed; cannot dismiss")
		return
	if not landscape_state.suppress_waterfall(key):
		_set_status("Waterfall already dismissed")
		return
	_record_history("landscape")
	_sync_water_visual()
	_reset_water_baseline()
	_set_status("Waterfall dismissed • LB undo")
	_refresh_controller_hud()

func _terrain_top(point: Vector2) -> float:
	if not backend or not backend.has_method("voxel_at"): return NAN
	var scale := float(backend.voxel_scale)
	var patch: Vector3i = backend.patch_size
	var x := clampi(floori(point.x / scale), 0, patch.x - 1)
	var z := clampi(floori(point.y / scale), 0, patch.z - 1)
	for y in range(patch.y - 1, -1, -1):
		if int(backend.voxel_at(Vector3i(x, y, z))) != 0:
			return float(y + 1) * scale
	return NAN

func _lake_level(points: Array) -> float:
	var level := 0.0
	var found := false
	var cells: Array = WaterRegion.footprint_cells({"type": "lake", "level": 0.0, "points": points}, WaterState.EDITABLE_WORLD_SIZE)
	for cell: Vector2i in cells:
		var top := _terrain_top(Vector2((cell.x + 0.5) * WaterGrid.UNIT, (cell.y + 0.5) * WaterGrid.UNIT))
		if not is_nan(top) and top > level:
			level = top
			found = true
	if not found: level = 1.0
	return snappedf(level, WaterGrid.UNIT)

func _reset_water_baseline() -> void:
	_water_before = landscape_state.document()
	_water_before_serialized = JSON.stringify(_water_before)
	_water_building_revision = building_world.get_revision()
	_water_terrain_revision = _terrain_revision()

func _water_candidate_region() -> Dictionary:
	if water_kind == "stream":
		if water_stream_points.size() < 2: return {}
		return _stream_region()
	if water_lake_points.size() < LAKE_MIN_POINTS: return {}
	return _lake_region()

func _update_water_preview() -> void:
	if not water_visual or not water_placement_active: return
	var candidate := _water_candidate_region()
	# Cheap preview fingerprint: the stream's rolling cell count grows only
	# when a segment adds a new cell (distance-gated, O(segment)), and the
	# lake's point count grows only on a vertex press. This replaces the old
	# fingerprint, which re-rasterized the whole stroke (a full O(N^2) union)
	# every frame just to compute the key — the cause of the mobile freeze.
	var fingerprint := 0
	if not candidate.is_empty():
		if water_kind == "stream": fingerprint = _stroke_cell_list.size()
		else: fingerprint = water_lake_points.size()
	var signature := "%s|%d|%d" % [water_kind, fingerprint, _terrain_revision()]
	if signature == _water_preview_signature: return
	_water_preview_signature = signature
	var regions: Array = landscape_state.water.duplicate(true)
	if not candidate.is_empty(): regions.append(candidate)
	water_visual.set_regions_incremental(regions)
	if water_kind == "stream" and not candidate.is_empty():
		# The one-shot reset has been delivered; later syncs of this stroke
		# grow the candidate incrementally.
		_stroke_reset_pending = false

func _update_presentation() -> void:
	var _ul_t0 := Time.get_ticks_usec()
	super._update_presentation()
	if not water_placement_active: return
	if target_label:
		target_label.text = "%s • %s\n%s  B cancel/close  LB undo  RS orbit" % [water_kind.capitalize(), water_placement_reason, _water_status_line()]
	_update_water_preview()

	var _ul_t1 := Time.get_ticks_usec()
	last_frame_costs["upd_m2_scene_water"] = (_ul_t1 - _ul_t0) / 1000.0
func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if not _tool_name or not _prompt_row or menu_open: return
	if not water_placement_active: return
	_mode_label.text = "TERRAIN"
	_tool_name.text = "Water"
	_tool_meta.text = water_placement_reason
	_tool_card.visible = true
	if _terrain_panel: _terrain_panel.visible = false
	if _building_panel: _building_panel.visible = false
	if _world_prompt: _world_prompt.visible = false
	if water_kind == "stream":
		_set_prompts([["A", "Hold to draw"], ["B", "Cancel/close"], ["LB", "Undo"], ["RS", "Orbit"], ["LT/RT", "Zoom"]])
	else:
		_set_prompts([["A", "Outline/close"], ["B", "Remove last/close"], ["LB", "Undo"], ["RS", "Orbit"]])
