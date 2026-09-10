extends "res://scripts/m2_scene_composition.gd"

## Controller-first placement for the small composition pieces that turn a set
## of houses into a hamlet. This slice exposes gardens; fences and street
## furniture join the same catalogue and saved placement grammar in later
## commits.

const DetailState = preload("res://scripts/landscape_state.gd")

const GARDEN_STYLES := {
	"cottage_flowers": {"name": "Cottage flower garden", "size": Vector2(3.0, 2.0), "summary": "Loose flowers in a low old-stone border"},
	"kitchen_rows": {"name": "Kitchen garden rows", "size": Vector2(3.5, 2.5), "summary": "Three tidy vegetable rows with warm soil"},
	"herb_garden": {"name": "Herb garden", "size": Vector2(2.25, 2.25), "summary": "Compact divided beds with mixed low herbs"},
}
const GARDEN_STYLE_ORDER: Array[String] = ["cottage_flowers", "kitchen_rows", "herb_garden"]

var _hamlet_catalogue_open := false
var _hamlet_catalogue_panel: PanelContainer
var _hamlet_catalogue_buttons: Array[Button] = []

var garden_placement_active := false
var garden_style_id := "cottage_flowers"
var garden_size := Vector2(3.0, 2.0)
var garden_yaw_quarters := 0
var garden_placement_valid := false
var garden_placement_reason := ""
var _garden_before: Dictionary = {}
var _garden_before_serialized := ""
var _garden_building_revision := -1
var _garden_terrain_revision := -1
var _garden_preview_signature := ""
var _garden_render_signature := ""

func _ready() -> void:
	super._ready()
	_install_hamlet_catalogue()
	_refresh_garden_visual(true)

func _process(delta: float) -> void:
	super._process(delta)
	if garden_placement_active and not menu_open:
		_update_garden_validity()
		_update_garden_preview()
		_refresh_controller_hud()

func _install_hamlet_catalogue() -> void:
	var root_box := _catalogue_box(_build_catalogue_panel)
	_add_catalogue_button(root_box, _build_catalogue_buttons, "Hamlet details\nGardens, fences, and street furniture", _open_hamlet_catalogue)
	_build_catalogue_panel.custom_minimum_size.y = 440
	_hamlet_catalogue_panel = _make_catalogue_panel("HamletDetailsCatalogue", Vector2(540, 430))
	var box := _catalogue_box(_hamlet_catalogue_panel)
	_add_catalogue_heading(box, "HAMLET DETAILS", "Place small details directly into the village")
	_add_catalogue_heading(box, "GARDENS", "A place • left/right rotate • B back")
	for style_id in GARDEN_STYLE_ORDER:
		var style: Dictionary = GARDEN_STYLES[style_id]
		_add_catalogue_button(box, _hamlet_catalogue_buttons, "%s\n%s" % [style["name"], style["summary"]], _choose_garden_style.bind(style_id))

func _input(event: InputEvent) -> void:
	if _shutting_down: return
	if _blocked_until_accept_release:
		super._input(event)
		return
	if _hamlet_catalogue_open and not menu_open:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_return_to_build_catalogue()
		elif event.is_action_pressed("m1_pause"):
			_close_all_catalogues()
			super._input(event)
			return
		elif event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner()
			if focus in _hamlet_catalogue_buttons: (focus as Button).pressed.emit()
		elif event.is_action_pressed("m1_height_up") or event.is_action_pressed("ui_up"):
			_move_focus(_hamlet_catalogue_buttons, -1)
		elif event.is_action_pressed("m1_height_down") or event.is_action_pressed("ui_down"):
			_move_focus(_hamlet_catalogue_buttons, 1)
		get_viewport().set_input_as_handled()
		return
	if garden_placement_active:
		if event.is_action_pressed("m1_accept"):
			_commit_garden()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_cancel_garden_placement("Garden cancelled")
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_cycle_left") or event.is_action_pressed("m1_cycle_right"):
			_rotate_garden(-1 if event.is_action_pressed("m1_cycle_left") else 1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_pause"):
			_cancel_garden_placement("Garden cancelled by pause")
			super._input(event)
			return
		if event.is_action_pressed("m1_mode_switch") or event.is_action_pressed("m1_view") or event.is_action_pressed("m1_undo") or event.is_action_pressed("m1_redo") or event.is_action_pressed("m1_height_up") or event.is_action_pressed("m1_height_down"):
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released("m1_accept"):
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _open_hamlet_catalogue() -> void:
	_cancel_current_edit("Hamlet details opened")
	_close_all_catalogues(false)
	_hamlet_catalogue_open = true
	tools_open = true
	_hamlet_catalogue_panel.visible = true
	if not _hamlet_catalogue_buttons.is_empty(): _hamlet_catalogue_buttons[0].grab_focus()
	_set_status("Hamlet details • choose a garden • A place / B categories")
	_refresh_controller_hud()

func _return_to_build_catalogue() -> void:
	_hamlet_catalogue_open = false
	if _hamlet_catalogue_panel: _hamlet_catalogue_panel.visible = false
	super._return_to_build_catalogue()

func _close_all_catalogues(clear_tools: bool = true) -> void:
	_hamlet_catalogue_open = false
	if _hamlet_catalogue_panel: _hamlet_catalogue_panel.visible = false
	super._close_all_catalogues(clear_tools)

func _choose_garden_style(style_id: String) -> void:
	if not GARDEN_STYLES.has(style_id): return
	_hamlet_catalogue_open = false
	_hamlet_catalogue_panel.visible = false
	tools_open = false
	get_viewport().gui_release_focus()
	_set_view_context("terrain", "Garden placement selected")
	garden_style_id = style_id
	garden_size = GARDEN_STYLES[style_id]["size"]
	garden_yaw_quarters = 0
	_begin_garden_placement()

func _begin_garden_placement() -> void:
	if garden_placement_active or bridge_placement_active or path_placement_active or stroke_active or landscape_active or detail_move_active or resize_active or building_placement_active: return
	if view_context != "terrain": _set_view_context("terrain", "Garden placement selected")
	garden_placement_active = true
	garden_placement_valid = false
	garden_placement_reason = "Find a terrain surface"
	_garden_before = landscape_state.document()
	_garden_before_serialized = JSON.stringify(_garden_before)
	_garden_building_revision = building_world.get_revision()
	_garden_terrain_revision = _terrain_revision()
	_landscape_before.clear()
	tools_open = false
	detail_open = false
	if tools_panel: tools_panel.visible = false
	if _terrain_panel: _terrain_panel.visible = false
	get_viewport().gui_release_focus()
	_preview_key = ""
	_set_status("%s • A place / left-right rotate / B cancel" % _garden_style_name())
	_update_brush_preview()
	_update_garden_validity()
	_update_garden_preview()
	_refresh_controller_hud()

func _read_camera_and_cursor(delta: float) -> void:
	super._read_camera_and_cursor(delta)
	if garden_placement_active: _update_garden_validity()

func _update_brush_preview() -> void:
	if not garden_placement_active:
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

func _update_garden_validity() -> void:
	garden_placement_valid = false
	garden_placement_reason = "No terrain surface under cursor"
	if not garden_placement_active: return
	if _terrain_revision() != _garden_terrain_revision:
		garden_placement_reason = "Terrain changed; restart garden"
		return
	if building_world.get_revision() != _garden_building_revision:
		garden_placement_reason = "Home layout changed; restart garden"
		return
	var point := _path_cursor_point()
	if not point.is_finite(): return
	if not _candidate_detail_fits_limits("garden", garden_style_id, point, garden_size, garden_yaw_quarters):
		garden_placement_reason = "Garden is outside the editable world or detail limit"
		return
	if _composition_hits_home(point, garden_size, garden_yaw_quarters):
		garden_placement_reason = "Garden overlaps a home"
		return
	garden_placement_valid = true
	garden_placement_reason = "Valid garden position"

func _update_garden_preview() -> void:
	if not composition_visual or not garden_placement_active: return
	var point := _path_cursor_point()
	if not point.is_finite():
		composition_visual.hide_garden_preview()
		return
	var signature := "%s|%s|%d|%s|%d" % [garden_style_id, point, garden_yaw_quarters, garden_placement_valid, _terrain_revision()]
	if signature == _garden_preview_signature: return
	_garden_preview_signature = signature
	composition_visual.show_garden_preview(garden_style_id, point, garden_size, garden_yaw_quarters, garden_placement_valid)

func _rotate_garden(direction: int) -> void:
	if not garden_placement_active: return
	garden_yaw_quarters = posmod(garden_yaw_quarters + direction, 4)
	_garden_preview_signature = ""
	_update_garden_validity()
	_update_garden_preview()
	_set_status("%s • rotated %d° • %s" % [_garden_style_name(), garden_yaw_quarters * 90, garden_placement_reason])
	_refresh_controller_hud()

func _commit_garden() -> bool:
	if not garden_placement_active: return false
	_update_garden_validity()
	if not garden_placement_valid:
		_set_status("Cannot place garden: %s" % garden_placement_reason)
		return false
	if JSON.stringify(landscape_state.document()) != _garden_before_serialized:
		garden_placement_reason = "Landscape changed; restart garden"
		_set_status("Cannot place garden: landscape changed; restart preview")
		return false
	if _terrain_revision() != _garden_terrain_revision or building_world.get_revision() != _garden_building_revision:
		garden_placement_reason = "World changed; restart garden"
		_set_status("Cannot place garden: world changed; restart preview")
		return false
	var point := _path_cursor_point()
	if not point.is_finite(): return false
	_landscape_before = _garden_before.duplicate(true)
	var object_id := landscape_state.add_composition("garden", garden_style_id, point, garden_size, garden_yaw_quarters)
	if object_id < 1:
		_landscape_before.clear()
		garden_placement_reason = "Garden limit reached"
		return false
	landscape_state.clear_records_in_footprint(point, garden_size, garden_yaw_quarters, 0.10)
	if garden_visual: garden_visual.reset_records(landscape_state.records)
	garden_placement_active = false
	composition_visual.hide_garden_preview()
	_garden_preview_signature = ""
	_garden_before.clear()
	_garden_before_serialized = ""
	_record_history("landscape")
	_landscape_before.clear()
	_refresh_garden_visual(true)
	_set_status("%s placed • LB undo" % _garden_style_name())
	_refresh_controller_hud()
	return true

func _cancel_garden_placement(reason: String = "Garden cancelled") -> void:
	if not garden_placement_active: return
	if not _garden_before.is_empty():
		landscape_state.restore(_garden_before)
		if garden_visual: garden_visual.reset_records(landscape_state.records)
	garden_placement_active = false
	garden_placement_valid = false
	garden_placement_reason = ""
	if composition_visual: composition_visual.hide_garden_preview()
	_garden_preview_signature = ""
	_garden_before.clear()
	_garden_before_serialized = ""
	_set_status(reason)
	_refresh_garden_visual(true)
	_refresh_controller_hud()

func _candidate_detail_fits_limits(kind: String, style_id: String, point: Vector2, size: Vector2, yaw_quarters: int) -> bool:
	var proposed := landscape_state.document()
	var values: Array = proposed.get("composition", [])
	values.append({"id": int(proposed["next_id"]), "kind": kind, "style_id": style_id, "position": [point.x, point.y], "size": [size.x, size.y], "yaw_quarters": posmod(yaw_quarters, 4)})
	proposed["composition"] = values
	proposed["next_id"] = int(proposed["next_id"]) + 1
	return DetailState.validate(proposed)

func _composition_hits_home(center: Vector2, size: Vector2, yaw_quarters: int) -> bool:
	var rotated := Vector2(size.y, size.x) if posmod(yaw_quarters, 4) % 2 == 1 else size
	var half := rotated * 0.5 + Vector2.ONE * 0.08
	var candidate := [center + Vector2(-half.x, -half.y), center + Vector2(half.x, -half.y), center + Vector2(half.x, half.y), center + Vector2(-half.x, half.y)]
	for building: Dictionary in building_world.get_buildings():
		var transform_value = building.get("transform", Transform3D.IDENTITY)
		if not transform_value is Transform3D: continue
		var dimensions: Vector3 = building.get("dimensions", Vector3.ZERO)
		var local_half := Vector2(dimensions.x, dimensions.z) * 0.5
		var home: Array = []
		for corner in [Vector2(-local_half.x, -local_half.y), Vector2(local_half.x, -local_half.y), Vector2(local_half.x, local_half.y), Vector2(-local_half.x, local_half.y)]:
			var world: Vector3 = (transform_value as Transform3D) * Vector3(corner.x, 0, corner.y)
			home.append(Vector2(world.x, world.z))
		if _rectangles_overlap(candidate, home): return true
	return false

func _rectangles_overlap(a: Array, b: Array) -> bool:
	for polygon in [a, b]:
		for index in 2:
			var edge: Vector2 = polygon[(index + 1) % 4] - polygon[index]
			var axis := Vector2(-edge.y, edge.x).normalized()
			var a_min := INF; var a_max := -INF; var b_min := INF; var b_max := -INF
			for point: Vector2 in a:
				var amount := point.dot(axis); a_min = minf(a_min, amount); a_max = maxf(a_max, amount)
			for point: Vector2 in b:
				var amount := point.dot(axis); b_min = minf(b_min, amount); b_max = maxf(b_max, amount)
			if a_max <= b_min + 0.0001 or b_max <= a_min + 0.0001: return false
	return true

func _cancel_current_edit(reason: String) -> void:
	if garden_placement_active: _cancel_garden_placement(reason)
	super._cancel_current_edit(reason)

func _undo() -> void:
	super._undo()
	_refresh_garden_visual(true)

func _redo() -> void:
	super._redo()
	_refresh_garden_visual(true)

func _restore_landscape(document: Dictionary) -> void:
	super._restore_landscape(document)
	_refresh_garden_visual(true)

func _on_backend_changed() -> void:
	super._on_backend_changed()
	_refresh_garden_visual(true)

func _refresh_garden_visual(force: bool = false) -> void:
	if not composition_visual: return
	if backend and composition_visual.has_method("attach_backend"): composition_visual.attach_backend(backend)
	var signature := JSON.stringify(landscape_state.composition) + "|" + str(_terrain_revision())
	if not force and signature == _garden_render_signature: return
	_garden_render_signature = signature
	composition_visual.rebuild_gardens(landscape_state.composition, backend)

func _update_presentation() -> void:
	super._update_presentation()
	if not garden_placement_active or not target_label: return
	target_label.text = "%s • %d° • %s\nA place  left/right rotate  B cancel  RS orbit" % [_garden_style_name(), garden_yaw_quarters * 90, garden_placement_reason]
	_update_garden_preview()

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if menu_open or not _tool_name or not _prompt_row: return
	if _hamlet_catalogue_open:
		_mode_label.text = "BUILD"
		_tool_name.text = "Hamlet details"
		_tool_meta.text = "Gardens now • fences and street furniture next"
		_tool_card.visible = true
		if _terrain_panel: _terrain_panel.visible = false
		if _building_panel: _building_panel.visible = false
		if _world_prompt: _world_prompt.visible = false
		_set_prompts([["UP/DOWN", "Choose"], ["A", "Place"], ["B", "Categories"]])
		return
	if not garden_placement_active: return
	_mode_label.text = "TERRAIN"
	_tool_name.text = _garden_style_name()
	_tool_meta.text = "%d° • %s" % [garden_yaw_quarters * 90, garden_placement_reason]
	_tool_card.visible = true
	if _terrain_panel: _terrain_panel.visible = false
	if _building_panel: _building_panel.visible = false
	if _world_prompt: _world_prompt.visible = false
	_set_prompts([["A", "Place"], ["LEFT/RIGHT", "Rotate"], ["B", "Cancel"], ["RS", "Orbit"], ["LT/RT", "Zoom"]])

func _garden_style_name() -> String:
	return str(GARDEN_STYLES.get(garden_style_id, {"name": "Garden"})["name"])
