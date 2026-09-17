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
var _water_catalogue_open := false
var _water_catalogue_panel: PanelContainer
var _water_catalogue_buttons: Array[Button] = []

func _ready() -> void:
	super._ready()
	_build_water_catalogue()

func _process(delta: float) -> void:
	super._process(delta)
	if water_placement_active and not menu_open:
		_update_water_validity()
		if water_stroking and water_kind == "stream": _sample_water_stream()
		_update_water_preview()

func _build_water_catalogue() -> void:
	_water_catalogue_panel = _make_catalogue_panel("WaterCatalogue", Vector2(540, 340))
	var box := _catalogue_box(_water_catalogue_panel)
	_add_catalogue_heading(box, "WATER", "Choose a body of water, then shape it on the terrain")
	_add_catalogue_button(box, _water_catalogue_buttons, "Stream\nDrag a centreline; the riverbed is carved to it", _choose_water_kind.bind("stream"))
	_add_catalogue_button(box, _water_catalogue_buttons, "Lake\nOutline a bounded region; its floor is carved to a basin", _choose_water_kind.bind("lake"))

func _open_water_catalogue() -> void:
	_cancel_current_edit("Water catalogue opened")
	_build_catalogue_open = false
	if _build_catalogue_panel: _build_catalogue_panel.visible = false
	_roads_catalogue_open = false
	if _roads_catalogue_panel: _roads_catalogue_panel.visible = false
	_outdoor_catalogue_open = false
	if _outdoor_catalogue_panel: _outdoor_catalogue_panel.visible = false
	_home_catalogue_open = false
	if _home_catalogue_panel: _home_catalogue_panel.visible = false
	_water_catalogue_open = true
	tools_open = true
	_water_catalogue_panel.visible = true
	if not _water_catalogue_buttons.is_empty(): _water_catalogue_buttons[0].grab_focus()
	_set_status("Water • choose a body • A select / B back")
	_refresh_controller_hud()

func _close_water_catalogue() -> void:
	if not _water_catalogue_open: return
	_water_catalogue_open = false
	_water_catalogue_panel.visible = false
	super._close_all_catalogues()

func _choose_water_kind(kind: String) -> void:
	if kind not in ["stream", "lake"]: return
	_water_catalogue_open = false
	_water_catalogue_panel.visible = false
	tools_open = false
	get_viewport().gui_release_focus()
	_set_view_context("terrain", "Water tool selected")
	water_kind = kind
	_begin_water_placement()

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
	if _water_catalogue_open and not menu_open:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_close_water_catalogue()
		elif event.is_action_pressed("m1_pause"):
			_close_water_catalogue()
			super._input(event)
			return
		elif event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner()
			if focus in _water_catalogue_buttons: (focus as Button).pressed.emit()
		elif event.is_action_pressed("m1_height_up") or event.is_action_pressed("ui_up"):
			_move_focus(_water_catalogue_buttons, -1)
		elif event.is_action_pressed("m1_height_down") or event.is_action_pressed("ui_down"):
			_move_focus(_water_catalogue_buttons, 1)
		get_viewport().set_input_as_handled()
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
			else: _cancel_water_placement("Water tool closed")
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
			_cancel_water_placement("Water tool closed by pause")
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
	if cursor_reticle:
		if _terrain_target_valid: cursor_reticle.update_target(_terrain_target_point, _terrain_target_normal, (STREAM_WIDTH * 0.5) if water_kind == "stream" else 0.25, "water", camera, true)
		else: cursor_reticle.set_target_visible(false)

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
	water_stream_points.append(point)
	_water_last_sample = point
	_water_preview_signature = ""
	return true

func _add_water_lake_vertex() -> void:
	if not water_placement_active or water_kind != "lake": return
	_update_water_validity()
	if not water_placement_valid:
		_set_status("Cannot outline: %s" % water_placement_reason)
		return
	var point := _water_cursor_point()
	if not point.is_finite(): return
	if water_lake_points.size() >= LAKE_MIN_POINTS:
		var first: Vector2 = water_lake_points[0]
		if point.distance_to(first) < LAKE_CLOSE_SNAP:
			_commit_water_lake()
			return
	if water_lake_points.is_empty() or point.distance_to(water_lake_points.back()) < WaterGrid.UNIT:
		return
	water_lake_points.append(point)
	_water_preview_signature = ""
	_set_status("Lake • %d points • near the start to close" % water_lake_points.size())
	_update_water_preview()

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
	return {"type": "stream", "level": water_stream_level, "width": STREAM_WIDTH, "points": points, "flow": [flow.x, flow.y]}

func _lake_region() -> Dictionary:
	var points: Array = []
	for p: Vector2 in water_lake_points:
		points.append([p.x, p.y])
	return {"type": "lake", "level": _lake_level(points), "points": points}

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
	_water_last_sample = Vector2(NAN, NAN)
	_water_preview_signature = ""
	_record_history("path" if terrain_changed else "landscape")
	_landscape_before.clear()
	_sync_water_visual()
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
	_water_last_sample = Vector2(NAN, NAN)
	_water_preview_signature = ""
	_landscape_before.clear()
	_set_status(reason)
	_update_water_validity()
	_update_water_preview()
	_sync_water_visual()

func _cancel_water_placement(reason: String = "Water tool closed") -> void:
	if not water_placement_active: return
	water_stroking = false
	water_placement_active = false
	water_stream_points.clear()
	water_lake_points.clear()
	_water_last_sample = Vector2(NAN, NAN)
	_water_preview_signature = ""
	_water_before.clear()
	_water_before_serialized = ""
	water_placement_reason = ""
	_set_status(reason)
	_sync_water_visual()
	_refresh_controller_hud()

func _cancel_current_edit(reason: String) -> void:
	if water_placement_active: _cancel_water_placement(reason)
	if _water_catalogue_open: _close_water_catalogue()
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
	super._on_backend_changed()
	_sync_water_visual()

func _build_browser_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = super._build_browser_entries()
	entries.append({"id": "water_stream", "name": "Stream", "category": "paths", "kind": "water", "summary": "Drag a centreline to carve a river"})
	entries.append({"id": "water_lake", "name": "Lake", "category": "paths", "kind": "water", "summary": "Outline a bounded region to carve a basin"})
	return entries

func _choose_water_tool(id: String) -> void:
	var kind := "stream" if id == "water_stream" else "lake"
	_open_water_catalogue()
	_choose_water_kind(kind)

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
	var regions: Array = landscape_state.water.duplicate(true)
	if not candidate.is_empty(): regions.append(candidate)
	var signature := "%s|%s|%s|%d" % [water_kind, JSON.stringify(candidate), water_placement_valid, _terrain_revision()]
	if signature == _water_preview_signature: return
	_water_preview_signature = signature
	water_visual.set_regions(regions)

func _update_presentation() -> void:
	super._update_presentation()
	if not water_placement_active: return
	if target_label:
		target_label.text = "%s • %s\n%s  B cancel/close  LB undo  RS orbit" % [water_kind.capitalize(), water_placement_reason, _water_status_line()]
	_update_water_preview()

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if not _tool_name or not _prompt_row or menu_open: return
	if _water_catalogue_open:
		_mode_label.text = "BUILD"
		_tool_name.text = "Water"
		_tool_meta.text = "Streams and lakes"
		_tool_card.visible = true
		if _terrain_panel: _terrain_panel.visible = false
		if _building_panel: _building_panel.visible = false
		if _world_prompt: _world_prompt.visible = false
		_set_prompts([["UP/DOWN", "Choose"], ["A", "Select"], ["B", "Back"]])
		return
	if not water_placement_active: return
	_mode_label.text = "TERRAIN"
	_tool_name.text = water_kind.capitalize()
	_tool_meta.text = water_placement_reason
	_tool_card.visible = true
	if _terrain_panel: _terrain_panel.visible = false
	if _building_panel: _building_panel.visible = false
	if _world_prompt: _world_prompt.visible = false
	if water_kind == "stream":
		_set_prompts([["A", "Hold to draw"], ["B", "Cancel/close"], ["LB", "Undo"], ["RS", "Orbit"], ["LT/RT", "Zoom"]])
	else:
		_set_prompts([["A", "Outline/close"], ["B", "Remove last/close"], ["LB", "Undo"], ["RS", "Orbit"]])
