extends "res://scripts/m2_scene_catalogue.gd"

## First Roads & Paths slice. Catalogue state belongs to the catalogue layer;
## the live polyline and its preview belong here and never touch terrain until
## the final landscape transaction is accepted.

const PathVisual = preload("res://scripts/m2_path_visual.gd")
const PathState = preload("res://scripts/landscape_state.gd")
const PathGrid = preload("res://scripts/visual_grid.gd")

const PATH_STYLES := {
	"packed_earth": {"name": "Packed-earth footpath", "width": 0.75, "summary": "A narrow continuous trail with a soft irregular edge"},
	"cobblestone": {"name": "Cobblestone lane", "width": 1.50, "summary": "A broad lane of readable courses and edge stones"},
	"stepping_stones": {"name": "Stepping-stone trail", "width": 1.00, "summary": "Separated stone clusters with visible ground gaps"},
}
const PATH_STYLE_ORDER: Array[String] = ["packed_earth", "cobblestone", "stepping_stones"]

var _roads_catalogue_open := false
var _roads_catalogue_panel: PanelContainer
var _roads_catalogue_buttons: Array[Button] = []
var path_visual

var path_placement_active := false
var path_style_id := "packed_earth"
var path_width := 0.75
var path_points: Array = []
var path_placement_valid := false
var path_placement_reason := ""
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
		_update_path_preview()
		_refresh_controller_hud()

func _build_roads_catalogue() -> void:
	_roads_catalogue_panel = _make_catalogue_panel("RoadsCatalogue", Vector2(540, 410))
	var box := _catalogue_box(_roads_catalogue_panel)
	_add_catalogue_heading(box, "ROADS & PATHS", "Choose a surface, then draw a route across the terrain")
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
	_set_status("Roads & paths • choose a style • A start / B categories")
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
			_add_path_point()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_tools"):
			_commit_path()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_cancel"):
			_cancel_path_placement("Path cancelled")
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_undo"):
			_remove_last_path_point()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_pause"):
			_cancel_path_placement("Path cancelled by pause")
			super._input(event)
			return
		# A path is a modal terrain tool. Do not let D-pad Up switch context,
		# nor let redo/history/terrain-tool actions leak through to the base.
		if event.is_action_pressed("m1_mode_switch") or event.is_action_pressed("m1_view") or event.is_action_pressed("m1_redo") or event.is_action_pressed("m1_cycle_left") or event.is_action_pressed("m1_cycle_right") or event.is_action_pressed("m1_height_up") or event.is_action_pressed("m1_height_down"):
			get_viewport().set_input_as_handled()
			return
		# Consume the release of A too; this is important for mouse left-click
		# and keeps the inherited terrain stroke from seeing the same event.
		if event.is_action_released("m1_accept"):
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _choose_path_style(style_id: String) -> void:
	if not PATH_STYLES.has(style_id): return
	_roads_catalogue_open = false
	_roads_catalogue_panel.visible = false
	tools_open = false
	get_viewport().gui_release_focus()
	_set_view_context("terrain", "Path placement selected")
	path_style_id = style_id
	path_width = float(PATH_STYLES[style_id]["width"])
	_begin_path_placement()

func _begin_path_placement() -> void:
	if path_placement_active or stroke_active or landscape_active or detail_move_active or resize_active or building_placement_active: return
	if view_context != "terrain": _set_view_context("terrain", "Path placement selected")
	path_placement_active = true
	path_points.clear()
	path_placement_valid = false
	path_placement_reason = "Find a terrain surface"
	_path_before = landscape_state.document()
	_path_before_serialized = JSON.stringify(_path_before)
	_path_building_revision = building_world.get_revision()
	_path_terrain_revision = _terrain_revision()
	_landscape_before.clear()
	tools_open = false
	detail_open = false
	if tools_panel: tools_panel.visible = false
	if _terrain_panel: _terrain_panel.visible = false
	get_viewport().gui_release_focus()
	_preview_key = ""
	_set_status("%s • A add point / X finish / B cancel" % _path_style_name())
	_update_brush_preview()
	_update_path_validity()
	_update_path_preview()
	_refresh_controller_hud()

func _read_camera_and_cursor(delta: float) -> void:
	# The inherited camera path already preserves right-stick orbit, triggers,
	# and controller-relative cursor travel. Keep it active while drawing.
	super._read_camera_and_cursor(delta)
	if path_placement_active:
		_update_path_validity()

func _update_brush_preview() -> void:
	if not path_placement_active:
		super._update_brush_preview()
		return
	# Retain a live terrain hit query but hide all sculpt-specific geometry.
	_terrain_target_valid = false
	if backend and backend.is_ready():
		var sample: Dictionary = backend.sample_surface_plane(cursor, Vector3.UP, 1.5)
		if not bool(sample.get("valid", false)):
			sample = _find_local_surface(cursor, Vector3.UP, float(backend.voxel_scale))
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
		if _terrain_target_valid: cursor_reticle.update_target(_terrain_target_point, _terrain_target_normal, 0.25, "path", camera, true)
		else: cursor_reticle.set_target_visible(false)

func _update_path_validity() -> void:
	path_placement_valid = false
	path_placement_reason = "No terrain surface under cursor"
	if not path_placement_active: return
	if _terrain_revision() != _path_terrain_revision:
		path_placement_reason = "Terrain changed; restart path"
		return
	if building_world.get_revision() != _path_building_revision:
		path_placement_reason = "Home layout changed; restart path"
		return
	var cursor_point := _path_cursor_point()
	if not cursor_point.is_finite(): return
	if cursor_point.x < 0.0 or cursor_point.x > 48.0 or cursor_point.y < 0.0 or cursor_point.y > 48.0:
		path_placement_reason = "Outside editable world"
		return
	if path_points.size() >= PathState.PATH_MAX_POINTS:
		path_placement_reason = "Point limit reached (64)"
		return
	if path_points.is_empty():
		path_placement_valid = true
		path_placement_reason = "Valid starting point"
		return
	var previous: Vector2 = path_points.back()
	if previous.distance_to(cursor_point) < PathState.PATH_MIN_SEGMENT - 0.000001:
		path_placement_reason = "Move farther for a meaningful segment"
		return
	if _segment_hits_home_interior(previous, cursor_point):
		path_placement_reason = "Path crosses the interior of a home"
		return
	if not _candidate_points_fit_limits(path_points + [cursor_point]):
		path_placement_reason = "Path render limit reached"
		return
	path_placement_valid = true
	path_placement_reason = "Valid next point"

func _update_path_preview() -> void:
	if not path_visual or not path_placement_active: return
	var preview_points: Array = path_points.duplicate()
	var cursor_point := _path_cursor_point()
	if cursor_point.is_finite(): preview_points.append(cursor_point)
	if preview_points.is_empty(): return
	var signature := "%s|%.3f|%s|%s|%d" % [path_style_id, path_width, JSON.stringify(preview_points), path_placement_valid, _terrain_revision()]
	if signature == _path_preview_signature: return
	_path_preview_signature = signature
	path_visual.show_preview(path_style_id, path_width, preview_points, path_placement_valid, path_placement_reason)

func _add_path_point() -> bool:
	if not path_placement_active: return false
	_update_path_validity()
	if not path_placement_valid:
		_set_status("Cannot add point: %s" % path_placement_reason)
		return false
	var point := _path_cursor_point()
	if not point.is_finite(): return false
	path_points.append(point)
	_set_status("%s • %d point%s • A add / X finish / B cancel / LB remove" % [_path_style_name(), path_points.size(), "" if path_points.size() == 1 else "s"])
	_path_preview_signature = ""
	_update_path_validity()
	_update_path_preview()
	return true

func _remove_last_path_point() -> bool:
	if not path_placement_active or path_points.is_empty():
		_set_status("No point to remove")
		return false
	path_points.pop_back()
	_set_status("Point removed • %d point%s" % [path_points.size(), "" if path_points.size() == 1 else "s"])
	_path_preview_signature = ""
	_update_path_validity()
	_update_path_preview()
	return true

func _commit_path() -> bool:
	if not path_placement_active: return false
	if JSON.stringify(landscape_state.document()) != _path_before_serialized:
		path_placement_reason = "Landscape changed; restart path"
		_set_status("Cannot finish path: landscape changed; restart the preview")
		return false
	if _terrain_revision() != _path_terrain_revision or building_world.get_revision() != _path_building_revision:
		path_placement_reason = "World changed; restart path"
		_set_status("Cannot finish path: world changed; restart the preview")
		return false
	var finished_reason := _finished_path_reason()
	if not finished_reason.is_empty():
		path_placement_reason = finished_reason
		_set_status("Cannot finish path: %s" % finished_reason)
		_update_path_preview()
		return false
	_landscape_before = _path_before.duplicate(true)
	var path_id := landscape_state.add_path(path_style_id, path_width, _path_arrays(path_points))
	if path_id < 1:
		_landscape_before.clear()
		path_placement_reason = "Path limit reached"
		_set_status("Cannot finish path: %s" % path_placement_reason)
		return false
	landscape_state.clear_records_along_path(_path_arrays(path_points), path_width)
	path_placement_active = false
	path_points.clear()
	path_visual.hide_preview()
	_path_preview_signature = ""
	_path_before.clear()
	_path_before_serialized = ""
	_record_history("landscape")
	_landscape_before.clear()
	_refresh_path_visual(true)
	_set_status("%s committed • LB undo" % _path_style_name())
	_refresh_controller_hud()
	return true

func _cancel_path_placement(reason: String = "Path cancelled") -> void:
	if not path_placement_active: return
	if not _path_before.is_empty():
		landscape_state.restore(_path_before)
		if garden_visual: garden_visual.reset_records(landscape_state.records)
	path_placement_active = false
	path_points.clear()
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

func _update_presentation() -> void:
	super._update_presentation()
	if not path_placement_active: return
	if target_label:
		target_label.text = "%s • %d point%s • %s\nA add point  X finish  B cancel  LB remove point  RS orbit" % [_path_style_name(), path_points.size(), "" if path_points.size() == 1 else "s", path_placement_reason]
	_update_path_preview()

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if not _tool_name or not _prompt_row or menu_open: return
	if _roads_catalogue_open:
		_mode_label.text = "BUILD"
		_tool_name.text = "Roads & paths"
		_tool_meta.text = "Three terrain-safe surface styles"
		_tool_card.visible = true
		if _terrain_panel: _terrain_panel.visible = false
		if _building_panel: _building_panel.visible = false
		if _world_prompt: _world_prompt.visible = false
		_set_prompts([["UP/DOWN", "Choose"], ["A", "Start"], ["B", "Categories"]])
		return
	if not path_placement_active: return
	_mode_label.text = "TERRAIN"
	_tool_name.text = _path_style_name()
	_tool_meta.text = "%d points • %s" % [path_points.size(), path_placement_reason]
	_tool_card.visible = true
	if _terrain_panel: _terrain_panel.visible = false
	if _building_panel: _building_panel.visible = false
	if _world_prompt: _world_prompt.visible = false
	_set_prompts([["A", "Add point"], ["X", "Finish"], ["B", "Cancel"], ["LB", "Remove point"], ["RS", "Orbit"], ["LT/RT", "Zoom"]])

func _terrain_revision() -> int:
	if not backend or not backend.has_method("stats"): return -1
	return int((backend.stats() as Dictionary).get("revision", -1))

func _path_cursor_point() -> Vector2:
	if not _terrain_target_valid: return Vector2(NAN, NAN)
	return Vector2(snappedf(_terrain_target_point.x, PathGrid.UNIT), snappedf(_terrain_target_point.z, PathGrid.UNIT))

func _path_arrays(values: Array) -> Array:
	var result: Array = []
	for point_value in values:
		var point: Vector2 = point_value
		result.append([point.x, point.y])
	return result

func _candidate_points_fit_limits(values: Array) -> bool:
	var proposed := landscape_state.document()
	var paths: Array = proposed["paths"]
	paths.append({"id": int(proposed["next_id"]), "style_id": path_style_id, "width": snappedf(path_width, PathGrid.UNIT), "points": _path_arrays(values)})
	proposed["next_id"] = int(proposed["next_id"]) + 1
	return PathState.validate(proposed)

func _finished_path_reason() -> String:
	if path_points.size() < PathState.PATH_MIN_POINTS: return "Add at least two valid points"
	if path_points.size() > PathState.PATH_MAX_POINTS: return "Path has too many points"
	for point: Vector2 in path_points:
		if not point.is_finite() or point.x < 0.0 or point.x > 48.0 or point.y < 0.0 or point.y > 48.0: return "Outside editable world"
	for index in range(1, path_points.size()):
		if path_points[index - 1].distance_to(path_points[index]) < PathState.PATH_MIN_SEGMENT - 0.000001: return "A segment is too short"
		if _segment_hits_home_interior(path_points[index - 1], path_points[index]): return "Path crosses the interior of a home"
	if not _candidate_points_fit_limits(path_points): return "Path render or count limit reached"
	return ""

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
	# The test intentionally has no clearance expansion: touching or ending at
	# the footprint edge is allowed, while traversing its strict interior is not.
	return high - low > 0.00001

func _path_style_name() -> String:
	return str(PATH_STYLES.get(path_style_id, {"name": "Path"})["name"])
