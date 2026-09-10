extends "res://scripts/m2_scene_paths.gd"

## Hamlet composition layer. Bridges deliberately reuse the Roads & Paths
## catalogue and the same controller cursor as paths: choose a bridge, A anchors
## the near bank, A again anchors the far bank, B cancels. Saved authority is
## only style/width/two points; the bridge mesh is disposable presentation.

const CompositionVisual = preload("res://scripts/m2_composition_visual.gd")
const CompositionState = preload("res://scripts/landscape_state.gd")

const BRIDGE_STYLES := {
	"timber": {"name": "Timber footbridge", "width": 1.0, "summary": "Warm planks, handrails, and chunky support beams"},
	"stone": {"name": "Stone crossing", "width": 1.5, "summary": "Broad old-stone slabs with low parapet edges"},
}
const BRIDGE_STYLE_ORDER: Array[String] = ["timber", "stone"]

var composition_visual
var bridge_placement_active := false
var bridge_style_id := "timber"
var bridge_width := 1.0
var bridge_start := Vector2(NAN, NAN)
var bridge_placement_valid := false
var bridge_placement_reason := ""
var _bridge_before: Dictionary = {}
var _bridge_before_serialized := ""
var _bridge_building_revision := -1
var _bridge_terrain_revision := -1
var _bridge_preview_signature := ""
var _bridge_render_signature := ""

func _ready() -> void:
	super._ready()
	_install_bridge_catalogue()
	composition_visual = CompositionVisual.new()
	composition_visual.name = "M2CompositionVisual"
	add_child(composition_visual)
	if backend: composition_visual.attach_backend(backend)
	_refresh_bridge_visual(true)

func _process(delta: float) -> void:
	super._process(delta)
	if bridge_placement_active and not menu_open:
		_update_bridge_validity()
		_update_bridge_preview()
		_refresh_controller_hud()

func _install_bridge_catalogue() -> void:
	if not _roads_catalogue_panel: return
	var box := _catalogue_box(_roads_catalogue_panel)
	_add_catalogue_heading(box, "BRIDGES", "Anchor one bank, then the other")
	for style_id in BRIDGE_STYLE_ORDER:
		var style: Dictionary = BRIDGE_STYLES[style_id]
		_add_catalogue_button(box, _roads_catalogue_buttons, "%s\n%s" % [style["name"], style["summary"]], _choose_bridge_style.bind(style_id))
	_roads_catalogue_panel.custom_minimum_size.y = 620

func _input(event: InputEvent) -> void:
	if _shutting_down: return
	if _blocked_until_accept_release:
		super._input(event)
		return
	if bridge_placement_active:
		if event.is_action_pressed("m1_accept"):
			_accept_bridge_point()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_cancel_bridge_placement("Bridge cancelled")
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_pause"):
			_cancel_bridge_placement("Bridge cancelled by pause")
			super._input(event)
			return
		if event.is_action_pressed("m1_mode_switch") or event.is_action_pressed("m1_view") or event.is_action_pressed("m1_undo") or event.is_action_pressed("m1_redo") or event.is_action_pressed("m1_cycle_left") or event.is_action_pressed("m1_cycle_right") or event.is_action_pressed("m1_height_up") or event.is_action_pressed("m1_height_down"):
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released("m1_accept"):
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _choose_bridge_style(style_id: String) -> void:
	if not BRIDGE_STYLES.has(style_id): return
	_roads_catalogue_open = false
	_roads_catalogue_panel.visible = false
	tools_open = false
	get_viewport().gui_release_focus()
	_set_view_context("terrain", "Bridge placement selected")
	bridge_style_id = style_id
	bridge_width = float(BRIDGE_STYLES[style_id]["width"])
	_begin_bridge_placement()

func _begin_bridge_placement() -> void:
	if bridge_placement_active or path_placement_active or stroke_active or landscape_active or detail_move_active or resize_active or building_placement_active: return
	if view_context != "terrain": _set_view_context("terrain", "Bridge placement selected")
	bridge_placement_active = true
	bridge_start = Vector2(NAN, NAN)
	bridge_placement_valid = false
	bridge_placement_reason = "Find the first bank"
	_bridge_before = landscape_state.document()
	_bridge_before_serialized = JSON.stringify(_bridge_before)
	_bridge_building_revision = building_world.get_revision()
	_bridge_terrain_revision = _terrain_revision()
	_landscape_before.clear()
	tools_open = false
	detail_open = false
	if tools_panel: tools_panel.visible = false
	if _terrain_panel: _terrain_panel.visible = false
	get_viewport().gui_release_focus()
	_preview_key = ""
	_set_status("%s • A anchor first bank / B cancel" % _bridge_style_name())
	_update_brush_preview()
	_update_bridge_validity()
	_update_bridge_preview()
	_refresh_controller_hud()

func _read_camera_and_cursor(delta: float) -> void:
	super._read_camera_and_cursor(delta)
	if bridge_placement_active: _update_bridge_validity()

func _update_brush_preview() -> void:
	if not bridge_placement_active:
		super._update_brush_preview()
		return
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
		if _terrain_target_valid: cursor_reticle.update_target(_terrain_target_point, _terrain_target_normal, 0.30, "path", camera, true)
		else: cursor_reticle.set_target_visible(false)

func _update_bridge_validity() -> void:
	bridge_placement_valid = false
	bridge_placement_reason = "No terrain surface under cursor"
	if not bridge_placement_active: return
	if _terrain_revision() != _bridge_terrain_revision:
		bridge_placement_reason = "Terrain changed; restart bridge"
		return
	if building_world.get_revision() != _bridge_building_revision:
		bridge_placement_reason = "Home layout changed; restart bridge"
		return
	var cursor_point := _path_cursor_point()
	if not cursor_point.is_finite(): return
	if cursor_point.x < 0.0 or cursor_point.x > CompositionState.EDITABLE_WORLD_SIZE or cursor_point.y < 0.0 or cursor_point.y > CompositionState.EDITABLE_WORLD_SIZE:
		bridge_placement_reason = "Outside editable world"
		return
	if not bridge_start.is_finite():
		bridge_placement_valid = true
		bridge_placement_reason = "Valid first bank"
		return
	var span := bridge_start.distance_to(cursor_point)
	if span < CompositionState.BRIDGE_MIN_SPAN - 0.000001:
		bridge_placement_reason = "Move farther for a bridge span"
		return
	if span > CompositionState.BRIDGE_MAX_SPAN + 0.000001:
		bridge_placement_reason = "Bridge span is too long"
		return
	if _segment_hits_home_interior(bridge_start, cursor_point):
		bridge_placement_reason = "Bridge crosses the interior of a home"
		return
	if not _candidate_bridge_fits_limits(bridge_start, cursor_point):
		bridge_placement_reason = "Bridge count or render limit reached"
		return
	bridge_placement_valid = true
	bridge_placement_reason = "Valid far bank"

func _update_bridge_preview() -> void:
	if not composition_visual or not bridge_placement_active: return
	var cursor_point := _path_cursor_point()
	if not bridge_start.is_finite() or not cursor_point.is_finite():
		composition_visual.hide_bridge_preview()
		return
	var signature := "%s|%.3f|%s|%s|%s|%d" % [bridge_style_id, bridge_width, bridge_start, cursor_point, bridge_placement_valid, _terrain_revision()]
	if signature == _bridge_preview_signature: return
	_bridge_preview_signature = signature
	composition_visual.show_bridge_preview(bridge_style_id, bridge_width, bridge_start, cursor_point, bridge_placement_valid)

func _accept_bridge_point() -> bool:
	if not bridge_placement_active: return false
	_update_bridge_validity()
	if not bridge_placement_valid:
		_set_status("Cannot place bridge: %s" % bridge_placement_reason)
		return false
	var point := _path_cursor_point()
	if not point.is_finite(): return false
	if not bridge_start.is_finite():
		bridge_start = point
		_bridge_preview_signature = ""
		_set_status("%s • first bank anchored • A anchor far bank / B cancel" % _bridge_style_name())
		_update_bridge_validity()
		_update_bridge_preview()
		return true
	return _commit_bridge(point)

func _commit_bridge(finish: Vector2) -> bool:
	if not bridge_placement_active or not bridge_start.is_finite() or not finish.is_finite(): return false
	if JSON.stringify(landscape_state.document()) != _bridge_before_serialized:
		bridge_placement_reason = "Landscape changed; restart bridge"
		_set_status("Cannot place bridge: landscape changed; restart the preview")
		return false
	if _terrain_revision() != _bridge_terrain_revision or building_world.get_revision() != _bridge_building_revision:
		bridge_placement_reason = "World changed; restart bridge"
		_set_status("Cannot place bridge: world changed; restart the preview")
		return false
	if not _candidate_bridge_fits_limits(bridge_start, finish):
		bridge_placement_reason = "Bridge count or render limit reached"
		_set_status("Cannot place bridge: %s" % bridge_placement_reason)
		return false
	_landscape_before = _bridge_before.duplicate(true)
	var points := [[bridge_start.x, bridge_start.y], [finish.x, finish.y]]
	var bridge_id := landscape_state.add_bridge(bridge_style_id, bridge_width, points)
	if bridge_id < 1:
		_landscape_before.clear()
		bridge_placement_reason = "Bridge limit reached"
		return false
	landscape_state.clear_records_along_path(points, bridge_width + 0.25)
	bridge_placement_active = false
	bridge_start = Vector2(NAN, NAN)
	composition_visual.hide_bridge_preview()
	_bridge_preview_signature = ""
	_bridge_before.clear()
	_bridge_before_serialized = ""
	_record_history("landscape")
	_landscape_before.clear()
	_refresh_bridge_visual(true)
	_set_status("%s committed • LB undo" % _bridge_style_name())
	_refresh_controller_hud()
	return true

func _cancel_bridge_placement(reason: String = "Bridge cancelled") -> void:
	if not bridge_placement_active: return
	if not _bridge_before.is_empty():
		landscape_state.restore(_bridge_before)
		if garden_visual: garden_visual.reset_records(landscape_state.records)
	bridge_placement_active = false
	bridge_start = Vector2(NAN, NAN)
	bridge_placement_valid = false
	bridge_placement_reason = ""
	if composition_visual: composition_visual.hide_bridge_preview()
	_bridge_preview_signature = ""
	_bridge_before.clear()
	_bridge_before_serialized = ""
	_set_status(reason)
	_refresh_bridge_visual(true)
	_refresh_controller_hud()

func _candidate_bridge_fits_limits(start: Vector2, finish: Vector2) -> bool:
	var proposed := landscape_state.document()
	var bridges: Array = proposed.get("bridges", [])
	bridges.append({"id": int(proposed["next_id"]), "style_id": bridge_style_id, "width": snappedf(bridge_width, PathGrid.UNIT), "points": [[start.x, start.y], [finish.x, finish.y]]})
	proposed["bridges"] = bridges
	proposed["next_id"] = int(proposed["next_id"]) + 1
	return CompositionState.validate(proposed)

func _cancel_current_edit(reason: String) -> void:
	if bridge_placement_active: _cancel_bridge_placement(reason)
	super._cancel_current_edit(reason)

func _undo() -> void:
	super._undo()
	_refresh_bridge_visual(true)

func _redo() -> void:
	super._redo()
	_refresh_bridge_visual(true)

func _restore_landscape(document: Dictionary) -> void:
	super._restore_landscape(document)
	_refresh_bridge_visual(true)

func _on_backend_changed() -> void:
	super._on_backend_changed()
	_refresh_bridge_visual(true)

func _refresh_bridge_visual(force: bool = false) -> void:
	if not composition_visual: return
	if backend and composition_visual.has_method("attach_backend"): composition_visual.attach_backend(backend)
	var signature := JSON.stringify(landscape_state.bridges) + "|" + str(_terrain_revision())
	if not force and signature == _bridge_render_signature: return
	_bridge_render_signature = signature
	composition_visual.rebuild_bridges(landscape_state.bridges, backend)

func _update_presentation() -> void:
	super._update_presentation()
	if not bridge_placement_active or not target_label: return
	var stage := "Choose first bank" if not bridge_start.is_finite() else "Choose far bank"
	target_label.text = "%s • %s • %s\nA anchor  B cancel  RS orbit  LT/RT zoom" % [_bridge_style_name(), stage, bridge_placement_reason]
	_update_bridge_preview()

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if menu_open or not _tool_name or not _prompt_row: return
	if _roads_catalogue_open:
		_tool_meta.text = "Footpaths, lanes, stepping stones, and simple crossings"
		return
	if not bridge_placement_active: return
	_mode_label.text = "TERRAIN"
	_tool_name.text = _bridge_style_name()
	_tool_meta.text = ("Anchor first bank" if not bridge_start.is_finite() else "Anchor far bank") + " • " + bridge_placement_reason
	_tool_card.visible = true
	if _terrain_panel: _terrain_panel.visible = false
	if _building_panel: _building_panel.visible = false
	if _world_prompt: _world_prompt.visible = false
	_set_prompts([["A", "Anchor"], ["B", "Cancel"], ["RS", "Orbit"], ["LT/RT", "Zoom"]])

func _bridge_style_name() -> String:
	return str(BRIDGE_STYLES.get(bridge_style_id, {"name": "Bridge"})["name"])
