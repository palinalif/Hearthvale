extends "res://scripts/m2_scene_catalogue.gd"

## Roads and paths are painted structural-grid areas. A live stroke is preview
## only; releasing A commits its cells and planting clear as one landscape undo
## transaction. Saved authority never contains a centreline.
const PathVisual = preload("res://scripts/m2_path_visual.gd")
const PathState = preload("res://scripts/landscape_state.gd")
const PathGrid = preload("res://scripts/visual_grid.gd")
const PathRegion = preload("res://scripts/m2_painted_path_region.gd")
const PathAuthority = preload("res://scripts/m2_painted_path_authority.gd")

const PATH_STYLES := {
	"packed_earth": {"name": "Packed-earth footpath", "width": 0.75, "summary": "Paint compacted dirt from footpaths to broad commons"},
	"cobblestone": {"name": "Cobblestone lane", "width": 1.50, "summary": "Paint stone lanes, courts and town squares"},
	"stepping_stones": {"name": "Stepping-stone trail", "width": 1.00, "summary": "Paint an area for a sparse stepping-stone trail"},
}
const PATH_STYLE_ORDER: Array[String] = ["packed_earth", "cobblestone", "stepping_stones"]

var _roads_catalogue_open := false
var _roads_catalogue_panel: PanelContainer
var _roads_catalogue_buttons: Array[Button] = []
var path_visual

var path_placement_active := false
var path_painting := false
var path_style_id := "packed_earth"
var path_width := 0.75
var path_cells: Array = []
var path_placement_valid := false
var path_placement_reason := ""
var _path_last_sample := Vector2(NAN, NAN)
var _path_before: Dictionary = {}
var _path_before_serialized := ""
var _path_building_revision := -1
var _path_terrain_revision := -1
var _path_render_signature := ""
var _path_preview_signature := ""

func _ready() -> void:
	super._ready()
	_build_roads_catalogue()
	path_visual = PathVisual.new()
	path_visual.name = "M2PathVisual"
	add_child(path_visual)
	if backend: path_visual.attach_backend(backend)
	_refresh_path_visual(true)

func _process(delta: float) -> void:
	super._process(delta)
	if path_placement_active and not menu_open:
		_update_path_validity()
		if path_painting: _sample_path_stroke()
		_update_path_preview()
		_refresh_controller_hud()

func _build_roads_catalogue() -> void:
	_roads_catalogue_panel = _make_catalogue_panel("RoadsCatalogue", Vector2(540, 410))
	var box := _catalogue_box(_roads_catalogue_panel)
	_add_catalogue_heading(box, "ROADS & PATHS", "Choose a surface, then hold A to paint it across the terrain")
	for style_id in PATH_STYLE_ORDER:
		var style: Dictionary = PATH_STYLES[style_id]
		_add_catalogue_button(box, _roads_catalogue_buttons, "%s\n%s" % [style["name"], style["summary"]], _choose_path_style.bind(style_id))

func _open_roads_catalogue() -> void:
	_cancel_current_edit("Roads catalogue opened")
	_build_catalogue_open = false
	if _build_catalogue_panel: _build_catalogue_panel.visible = false
	_outdoor_catalogue_open = false
	if _outdoor_catalogue_panel: _outdoor_catalogue_panel.visible = false
	_home_catalogue_open = false
	if _home_catalogue_panel: _home_catalogue_panel.visible = false
	_roads_catalogue_open = true
	tools_open = true
	_roads_catalogue_panel.visible = true
	if not _roads_catalogue_buttons.is_empty(): _roads_catalogue_buttons[0].grab_focus()
	_set_status("Roads & paths • choose a style • A select / B categories")
	_refresh_controller_hud()

func _return_to_build_catalogue() -> void:
	_roads_catalogue_open = false
	if _roads_catalogue_panel: _roads_catalogue_panel.visible = false
	super._return_to_build_catalogue()

func _close_all_catalogues(clear_tools: bool = true) -> void:
	_roads_catalogue_open = false
	if _roads_catalogue_panel: _roads_catalogue_panel.visible = false
	super._close_all_catalogues(clear_tools)

func _input(event: InputEvent) -> void:
	if _shutting_down: return
	if _blocked_until_accept_release:
		super._input(event)
		return
	if _roads_catalogue_open and not menu_open:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_return_to_build_catalogue()
		elif event.is_action_pressed("m1_pause"):
			_close_all_catalogues()
			super._input(event)
			return
		elif event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner()
			if focus in _roads_catalogue_buttons: (focus as Button).pressed.emit()
		elif event.is_action_pressed("m1_height_up") or event.is_action_pressed("ui_up"):
			_move_focus(_roads_catalogue_buttons, -1)
		elif event.is_action_pressed("m1_height_down") or event.is_action_pressed("ui_down"):
			_move_focus(_roads_catalogue_buttons, 1)
		get_viewport().set_input_as_handled()
		return
	if path_placement_active:
		if event.is_action_pressed("m1_accept"):
			_start_path_stroke()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released("m1_accept"):
			_commit_path_stroke()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_cancel"):
			if path_painting: _cancel_path_stroke("Stroke cancelled")
			else: _cancel_path_placement("Path painting closed")
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_undo"):
			if path_painting:
				_cancel_path_stroke("Stroke cancelled")
			else:
				_undo()
				_reset_path_baseline()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_pause"):
			_cancel_path_placement("Path painting closed by pause")
			super._input(event)
			return
		if event.is_action_pressed("m1_mode_switch") or event.is_action_pressed("m1_view") or event.is_action_pressed("m1_redo") or event.is_action_pressed("m1_cycle_left") or event.is_action_pressed("m1_cycle_right") or event.is_action_pressed("m1_height_up") or event.is_action_pressed("m1_height_down") or event.is_action_pressed("m1_tools"):
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _choose_path_style(style_id: String) -> void:
	if not PATH_STYLES.has(style_id): return
	_roads_catalogue_open = false
	_roads_catalogue_panel.visible = false
	tools_open = false
	get_viewport().gui_release_focus()
	_set_view_context("terrain", "Path paint selected")
	path_style_id = style_id
	path_width = float(PATH_STYLES[style_id]["width"])
	_begin_path_placement()

func _begin_path_placement() -> void:
	if path_placement_active or stroke_active or landscape_active or detail_move_active or resize_active or building_placement_active: return
	if view_context != "terrain": _set_view_context("terrain", "Path paint selected")
	path_placement_active = true
	path_painting = false
	path_cells.clear()
	_path_last_sample = Vector2(NAN, NAN)
	path_placement_valid = false
	path_placement_reason = "Find a terrain surface"
	_path_building_revision = building_world.get_revision()
	_path_terrain_revision = _terrain_revision()
	_reset_path_baseline()
	_landscape_before.clear()
	tools_open = false
	detail_open = false
	if tools_panel: tools_panel.visible = false
	if _terrain_panel: _terrain_panel.visible = false
	get_viewport().gui_release_focus()
	_preview_key = ""
	_set_status("%s • hold A paint / B close / LB undo" % _path_style_name())
	_update_brush_preview()
	_update_path_validity()
	_update_path_preview()
	_refresh_controller_hud()

func _read_camera_and_cursor(delta: float) -> void:
	super._read_camera_and_cursor(delta)
	if path_placement_active: _update_path_validity()

func _update_brush_preview() -> void:
	if not path_placement_active:
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
		if _terrain_target_valid: cursor_reticle.update_target(_terrain_target_point, _terrain_target_normal, path_width * 0.5, "path", camera, true)
		else: cursor_reticle.set_target_visible(false)

func _update_path_validity() -> void:
	path_placement_valid = false
	path_placement_reason = "No terrain surface under cursor"
	if not path_placement_active: return
	if _terrain_revision() != _path_terrain_revision:
		path_placement_reason = "Terrain changed; restart path painting"
		return
	if building_world.get_revision() != _path_building_revision:
		path_placement_reason = "Home layout changed; restart path painting"
		return
	if JSON.stringify(landscape_state.document()) != _path_before_serialized:
		path_placement_reason = "Landscape changed; restart path painting"
		return
	var point := _path_cursor_point()
	if not point.is_finite(): return
	if point.x < 0.0 or point.x >= PathState.EDITABLE_WORLD_SIZE or point.y < 0.0 or point.y >= PathState.EDITABLE_WORLD_SIZE:
		path_placement_reason = "Outside editable world"
		return
	var stamp := PathRegion.brush_cells(point, path_width * 0.5, PathState.EDITABLE_WORLD_SIZE)
	if stamp.is_empty():
		path_placement_reason = "Outside editable world"
		return
	if _cells_hit_home_interior(stamp):
		path_placement_reason = "Brush overlaps the interior of a home"
		return
	var candidate := PathRegion.union_cells(path_cells, stamp, PathState.EDITABLE_WORLD_SIZE)
	if not _candidate_cells_fit_limits(candidate):
		path_placement_reason = "Path render limit reached"
		return
	path_placement_valid = true
	path_placement_reason = "Painting" if path_painting else "Ready to paint"

func _start_path_stroke() -> bool:
	if not path_placement_active or path_painting: return false
	_update_path_validity()
	if not path_placement_valid:
		_set_status("Cannot paint: %s" % path_placement_reason)
		return false
	path_painting = true
	path_cells.clear()
	_path_last_sample = _path_cursor_point()
	var stamp := PathRegion.brush_cells(_path_last_sample, path_width * 0.5, PathState.EDITABLE_WORLD_SIZE)
	path_cells = PathRegion.union_cells(path_cells, stamp, PathState.EDITABLE_WORLD_SIZE)
	_path_preview_signature = ""
	_set_status("%s • painting %d cells • release A to commit" % [_path_style_name(), path_cells.size()])
	_update_path_preview()
	return true

func _sample_path_stroke() -> bool:
	if not path_painting: return false
	_update_path_validity()
	if not path_placement_valid: return false
	var point := _path_cursor_point()
	if not point.is_finite(): return false
	var sweep := PathRegion.stroke_cells(_path_last_sample, point, path_width * 0.5, PathState.EDITABLE_WORLD_SIZE)
	if _cells_hit_home_interior(sweep):
		path_placement_reason = "Brush overlaps the interior of a home"
		path_placement_valid = false
		return false
	var candidate := PathRegion.union_cells(path_cells, sweep, PathState.EDITABLE_WORLD_SIZE)
	if not _candidate_cells_fit_limits(candidate):
		path_placement_reason = "Path render limit reached"
		path_placement_valid = false
		return false
	path_cells = candidate
	_path_last_sample = point
	_path_preview_signature = ""
	return true

func _commit_path_stroke() -> bool:
	if not path_painting: return false
	if path_cells.is_empty():
		_cancel_path_stroke("Empty stroke cancelled")
		return false
	if JSON.stringify(landscape_state.document()) != _path_before_serialized or _terrain_revision() != _path_terrain_revision or building_world.get_revision() != _path_building_revision:
		_cancel_path_stroke("World changed; stroke cancelled")
		return false
	if _cells_hit_home_interior(path_cells) or not _candidate_cells_fit_limits(path_cells):
		_cancel_path_stroke("Invalid stroke cancelled")
		return false
	_landscape_before = _path_before.duplicate(true)
	var path_id := landscape_state.paint_path_cells(path_style_id, path_cells)
	if path_id < 1:
		_landscape_before.clear()
		_cancel_path_stroke("Path limit reached")
		return false
	landscape_state.clear_records_in_path_cells(path_cells)
	if garden_visual: garden_visual.reset_records(landscape_state.records)
	path_painting = false
	var committed_cells := path_cells.size()
	path_cells.clear()
	_path_last_sample = Vector2(NAN, NAN)
	path_visual.hide_preview()
	_path_preview_signature = ""
	_record_history("landscape")
	_landscape_before.clear()
	_refresh_path_visual(true)
	_reset_path_baseline()
	_set_status("%s • %d cells painted • hold A for another stroke • LB undo" % [_path_style_name(), committed_cells])
	_update_path_validity()
	_update_path_preview()
	_refresh_controller_hud()
	return true

func _cancel_path_stroke(reason: String = "Stroke cancelled") -> void:
	path_painting = false
	path_cells.clear()
	_path_last_sample = Vector2(NAN, NAN)
	_path_preview_signature = ""
	_set_status(reason)
	_update_path_validity()
	_update_path_preview()

func _cancel_path_placement(reason: String = "Path painting closed") -> void:
	if not path_placement_active: return
	path_painting = false
	path_placement_active = false
	path_cells.clear()
	_path_last_sample = Vector2(NAN, NAN)
	path_visual.hide_preview()
	_path_preview_signature = ""
	_path_before.clear()
	_path_before_serialized = ""
	path_placement_reason = ""
	_set_status(reason)
	_refresh_path_visual(true)
	_refresh_controller_hud()

func _cancel_current_edit(reason: String) -> void:
	if path_placement_active: _cancel_path_placement(reason)
	super._cancel_current_edit(reason)

func _undo() -> void:
	super._undo()
	_refresh_path_visual(true)

func _redo() -> void:
	super._redo()
	_refresh_path_visual(true)

func _restore_landscape(document: Dictionary) -> void:
	super._restore_landscape(document)
	_refresh_path_visual(true)

func _on_backend_changed() -> void:
	super._on_backend_changed()
	_refresh_path_visual(true)

func _refresh_path_visual(force: bool = false) -> void:
	if not path_visual: return
	if backend and path_visual.has_method("attach_backend"): path_visual.attach_backend(backend)
	var signature := JSON.stringify(landscape_state.paths) + "|" + str(_terrain_revision())
	if not force and signature == _path_render_signature: return
	_path_render_signature = signature
	path_visual.rebuild(landscape_state.paths, backend)

func _update_path_preview() -> void:
	if not path_visual or not path_placement_active: return
	var preview_cells: Array = path_cells.duplicate()
	var point := _path_cursor_point()
	if point.is_finite(): preview_cells = PathRegion.union_cells(preview_cells, PathRegion.brush_cells(point, path_width * 0.5, PathState.EDITABLE_WORLD_SIZE), PathState.EDITABLE_WORLD_SIZE)
	var signature := "%s|%s|%s|%d" % [path_style_id, JSON.stringify(PathRegion.encode_cells(preview_cells)), path_placement_valid, _terrain_revision()]
	if signature == _path_preview_signature: return
	_path_preview_signature = signature
	if preview_cells.is_empty(): path_visual.hide_preview()
	else: path_visual.show_cell_preview(path_style_id, preview_cells, path_placement_valid, path_placement_reason)

func _update_presentation() -> void:
	super._update_presentation()
	if not path_placement_active: return
	if target_label:
		target_label.text = "%s • %.2f m brush • %s\nHold A paint  release commit  B cancel/close  LB undo  RS orbit" % [_path_style_name(), path_width, path_placement_reason]
	_update_path_preview()

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if not _tool_name or not _prompt_row or menu_open: return
	if _roads_catalogue_open:
		_mode_label.text = "BUILD"
		_tool_name.text = "Roads & paths"
		_tool_meta.text = "Paint terrain surfaces"
		_tool_card.visible = true
		if _terrain_panel: _terrain_panel.visible = false
		if _building_panel: _building_panel.visible = false
		if _world_prompt: _world_prompt.visible = false
		_set_prompts([["UP/DOWN", "Choose"], ["A", "Select"], ["B", "Categories"]])
		return
	if not path_placement_active: return
	_mode_label.text = "TERRAIN"
	_tool_name.text = _path_style_name()
	_tool_meta.text = "%s • %d live cells" % [path_placement_reason, path_cells.size()]
	_tool_card.visible = true
	if _terrain_panel: _terrain_panel.visible = false
	if _building_panel: _building_panel.visible = false
	if _world_prompt: _world_prompt.visible = false
	_set_prompts([["A", "Hold to paint"], ["B", "Cancel/close"], ["LB", "Undo"], ["RS", "Orbit"], ["LT/RT", "Zoom"]])

func _terrain_revision() -> int:
	if not backend or not backend.has_method("stats"): return -1
	return int((backend.stats() as Dictionary).get("revision", -1))

func _path_cursor_point() -> Vector2:
	if not _terrain_target_valid: return Vector2(NAN, NAN)
	return Vector2(snappedf(_terrain_target_point.x, PathGrid.UNIT), snappedf(_terrain_target_point.z, PathGrid.UNIT))

func _candidate_cells_fit_limits(values: Array) -> bool:
	var result := PathAuthority.paint(landscape_state.paths, landscape_state.next_id, path_style_id, values)
	if not bool(result.get("changed", false)) and values.is_empty(): return false
	var proposed := landscape_state.document()
	proposed["paths"] = result.get("paths", landscape_state.paths)
	proposed["next_id"] = int(result.get("next_id", landscape_state.next_id))
	return PathState.validate(proposed)

func _cells_hit_home_interior(values: Array) -> bool:
	for cell: Vector2i in PathRegion.normalize_cells(values, PathState.EDITABLE_WORLD_SIZE):
		var centre := PathRegion.cell_center(cell)
		var half := PathGrid.UNIT * 0.49
		for offset in [Vector2.ZERO, Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]:
			var point := centre + offset
			if _segment_hits_home_interior(point, point): return true
	return false

func _segment_hits_home_interior(a: Vector2, b: Vector2) -> bool:
	for building: Dictionary in building_world.get_buildings():
		if _segment_crosses_home_interior(a, b, building): return true
	return false

func _segment_crosses_home_interior(a: Vector2, b: Vector2, building: Dictionary) -> bool:
	var transform_value = building.get("transform", Transform3D.IDENTITY)
	if not transform_value is Transform3D: return false
	var inverse: Transform3D = (transform_value as Transform3D).affine_inverse()
	var local_a := inverse * Vector3(a.x, 0, a.y)
	var local_b := inverse * Vector3(b.x, 0, b.y)
	var delta := local_b - local_a
	var dimensions: Vector3 = building.get("dimensions", Vector3.ZERO)
	if dimensions.x <= 0.0 or dimensions.z <= 0.0: return false
	var low := 0.0
	var high := 1.0
	for axis in [0, 2]:
		var origin := local_a[axis]
		var direction := delta[axis]
		var half := dimensions[axis] * 0.5
		if absf(direction) < 0.000001:
			if absf(origin) < half - 0.00001: continue
			return false
		var t0 := (-half - origin) / direction
		var t1 := (half - origin) / direction
		if t0 > t1:
			var swap := t0; t0 = t1; t1 = swap
		low = maxf(low, t0)
		high = minf(high, t1)
		if high - low <= 0.00001: return false
	return high - low > 0.00001

func _reset_path_baseline() -> void:
	_path_before = landscape_state.document()
	_path_before_serialized = JSON.stringify(_path_before)
	_path_building_revision = building_world.get_revision()
	_path_terrain_revision = _terrain_revision()

func _path_style_name() -> String:
	return str(PATH_STYLES.get(path_style_id, {"name": "Path"})["name"])
