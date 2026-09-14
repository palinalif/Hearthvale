extends "res://scripts/m2_scene_composition.gd"

## Controller-first placement for small hamlet composition pieces. Gardens,
## fences and the upcoming street furniture all use one preview/rotate/commit
## transaction; the named aliases below keep tests and UI language explicit.

const DetailState = preload("res://scripts/landscape_state.gd")

const GARDEN_STYLES := {
	"cottage_flowers": {"name": "Cottage flower garden", "size": Vector2(3.0, 2.0), "summary": "Loose flowers in a low old-stone border"},
	"kitchen_rows": {"name": "Kitchen garden rows", "size": Vector2(3.5, 2.5), "summary": "Three tidy vegetable rows with warm soil"},
	"herb_garden": {"name": "Herb garden", "size": Vector2(2.25, 2.25), "summary": "Compact divided beds with mixed low herbs"},
}
const GARDEN_STYLE_ORDER: Array[String] = ["cottage_flowers", "kitchen_rows", "herb_garden"]
const FENCE_STYLES := {
	"rustic_fence": {"name": "Rustic timber fence", "size": Vector2(3.0, 0.25), "summary": "Weathered posts and two uneven rails"},
	"rustic_gate": {"name": "Rustic garden gate", "size": Vector2(1.5, 0.375), "summary": "Matching braced gate for paths and plots"},
}
const FENCE_STYLE_ORDER: Array[String] = ["rustic_fence", "rustic_gate"]

var _hamlet_catalogue_open := false
var _hamlet_catalogue_panel: PanelContainer
var _hamlet_catalogue_buttons: Array[Button] = []

var detail_placement_active := false
var detail_kind := ""
var detail_style_id := ""
var detail_size := Vector2.ZERO
var detail_yaw_quarters := 0
var detail_yaw_degrees := 0.0
var detail_placement_valid := false
var detail_placement_reason := ""
var _detail_before: Dictionary = {}
var _detail_before_serialized := ""
var _detail_building_revision := -1
var _detail_terrain_revision := -1
var _detail_preview_signature := ""
var _detail_render_signature := ""
var _detail_edit_id := -1
var _detail_selected_id := -1
var _detail_selected_colour := ""
const DETAIL_EDIT_COLOURS: Array[String] = ["natural", "sage", "blue", "berry", "cream"]
const DETAIL_SELECT_RADIUS := 1.25

# Explicit aliases used by tests and by feature-specific entry points.
var garden_placement_active := false
var garden_style_id := "cottage_flowers"
var garden_size := Vector2(3.0, 2.0)
var garden_yaw_quarters := 0
var garden_placement_valid := false
var garden_placement_reason := ""
var fence_placement_active := false
var fence_style_id := "rustic_fence"
var fence_size := Vector2(3.0, 0.25)
var fence_yaw_quarters := 0
var fence_placement_valid := false
var fence_placement_reason := ""

func _ready() -> void:
	super._ready()
	_install_hamlet_catalogue()
	_refresh_detail_visual(true)

func _process(delta: float) -> void:
	super._process(delta)
	if view_context == "terrain" and not menu_open and not tools_open and not detail_open and not detail_placement_active:
		var hover_record := _detail_near_cursor_record()
		if not hover_record.is_empty(): _show_outdoor_detail_hover(hover_record)
	if detail_placement_active and not menu_open:
		_update_detail_validity()
		_update_detail_preview()
		_sync_detail_aliases()
		_refresh_controller_hud()

func _install_hamlet_catalogue() -> void:
	var root_box := _catalogue_box(_build_catalogue_panel)
	_add_catalogue_button(root_box, _build_catalogue_buttons, "Hamlet details\nGardens, fences, and street furniture", _open_hamlet_catalogue)
	_build_catalogue_panel.custom_minimum_size.y = 440
	_hamlet_catalogue_panel = _make_catalogue_panel("HamletDetailsCatalogue", Vector2(540, 550))
	_hamlet_catalogue_panel.position.y = 80
	var box := _catalogue_box(_hamlet_catalogue_panel)
	_add_catalogue_heading(box, "HAMLET DETAILS", "Place small details directly into the village")
	_add_catalogue_heading(box, "GARDENS", "A place • left/right rotate • B back")
	for style_id in GARDEN_STYLE_ORDER:
		var style: Dictionary = GARDEN_STYLES[style_id]
		_add_catalogue_button(box, _hamlet_catalogue_buttons, "%s\n%s" % [style["name"], style["summary"]], _choose_garden_style.bind(style_id))
	_add_catalogue_heading(box, "FENCES", "Short pieces remain independent and easy to rearrange")
	for style_id in FENCE_STYLE_ORDER:
		var style: Dictionary = FENCE_STYLES[style_id]
		_add_catalogue_button(box, _hamlet_catalogue_buttons, "%s\n%s" % [style["name"], style["summary"]], _choose_fence_style.bind(style_id))

func _input(event: InputEvent) -> void:
	if _shutting_down: return
	if _blocked_until_accept_release:
		super._input(event)
		return
	if not detail_placement_active and not menu_open and not tools_open and not detail_open and view_context == "terrain":
		if event.is_action_pressed("m1_accept") and _select_detail_near_cursor():
			_begin_selected_detail_move()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_tools") and _select_detail_near_cursor():
			_cycle_selected_detail_colour()
			_detail_selected_id = -1
			get_viewport().set_input_as_handled()
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
	if detail_placement_active:
		if event.is_action_pressed("m1_accept"):
			_commit_detail()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_cancel_detail_placement("%s cancelled" % _detail_kind_label())
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_cycle_left") or event.is_action_pressed("m1_cycle_right"):
			_rotate_detail(-1 if event.is_action_pressed("m1_cycle_left") else 1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_pause"):
			_cancel_detail_placement("%s cancelled by pause" % _detail_kind_label())
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
	_set_status("Hamlet details • choose a detail • A place / B categories")
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
	garden_style_id = style_id
	garden_size = GARDEN_STYLES[style_id]["size"]
	garden_yaw_quarters = 0
	_begin_detail_placement("garden", garden_style_id, garden_size, garden_yaw_quarters)

func _choose_fence_style(style_id: String) -> void:
	if not FENCE_STYLES.has(style_id): return
	fence_style_id = style_id
	fence_size = FENCE_STYLES[style_id]["size"]
	fence_yaw_quarters = 0
	_begin_detail_placement("fence", fence_style_id, fence_size, fence_yaw_quarters)

func _begin_garden_placement() -> void:
	_begin_detail_placement("garden", garden_style_id, garden_size, garden_yaw_quarters)

func _begin_fence_placement() -> void:
	_begin_detail_placement("fence", fence_style_id, fence_size, fence_yaw_quarters)

func _begin_detail_placement(kind: String, style_id: String, size: Vector2, yaw_quarters: int = 0) -> void:
	if detail_placement_active or bridge_placement_active or path_placement_active or stroke_active or landscape_active or detail_move_active or resize_active or building_placement_active: return
	if not _detail_definition(kind, style_id).is_empty():
		_close_hamlet_for_world()
		if view_context != "terrain": _set_view_context("terrain", "%s placement selected" % kind.capitalize())
		detail_placement_active = true
		detail_kind = kind
		detail_style_id = style_id
		detail_size = size
		detail_yaw_quarters = posmod(yaw_quarters, 4)
		detail_yaw_degrees = float(detail_yaw_quarters) * 90.0
		detail_placement_valid = false
		detail_placement_reason = "Find a terrain surface"
		_detail_before = landscape_state.document()
		_detail_before_serialized = JSON.stringify(_detail_before)
		_detail_building_revision = building_world.get_revision()
		_detail_terrain_revision = _terrain_revision()
		_landscape_before.clear()
		tools_open = false
		detail_open = false
		if tools_panel: tools_panel.visible = false
		if _terrain_panel: _terrain_panel.visible = false
		get_viewport().gui_release_focus()
		_preview_key = ""
		_sync_detail_aliases()
		_set_status("%s • A place / left-right rotate / B cancel" % _detail_style_name())
		_update_brush_preview()
		_update_detail_validity()
		_update_detail_preview()
		_sync_detail_aliases()
		_refresh_controller_hud()

func _select_detail_near_cursor() -> bool:
	var point := _path_cursor_point()
	if not point.is_finite(): return false
	var best_id := -1
	var best_distance := INF
	for value in landscape_state.composition:
		if not value is Dictionary: continue
		var record: Dictionary = value
		var kind := str(record.get("kind", ""))
		if kind not in ["garden", "fence", "furniture"]: continue
		var position: Array = record.get("position", [])
		if position.size() != 2: continue
		var distance := point.distance_to(Vector2(float(position[0]), float(position[1])))
		var size_value: Array = record.get("size", [1.0, 1.0])
		var reach := maxf(DETAIL_SELECT_RADIUS, maxf(float(size_value[0]), float(size_value[1])) * 0.55)
		if distance <= reach and distance < best_distance:
			best_distance = distance
			best_id = int(record.get("id", -1))
	if best_id < 1: return false
	_detail_selected_id = best_id
	var selected := _composition_record(best_id)
	_detail_selected_colour = str(selected.get("colour_id", ""))
	_set_status("%s selected • A move • X colour • B deselect" % _composition_label(selected))
	_refresh_controller_hud()
	return true

func _composition_record(object_id: int) -> Dictionary:
	for value in landscape_state.composition:
		if value is Dictionary and int((value as Dictionary).get("id", -1)) == object_id: return (value as Dictionary).duplicate(true)
	return {}

func _composition_label(record: Dictionary) -> String:
	var definition := _detail_definition(str(record.get("kind", "")), str(record.get("style_id", "")))
	return str(definition.get("name", str(record.get("kind", "Outdoor decor")).capitalize()))

func _begin_selected_detail_move() -> void:
	var record := _composition_record(_detail_selected_id)
	if record.is_empty(): _detail_selected_id = -1; return
	var position: Array = record.get("position", [])
	var size_value: Array = record.get("size", [])
	if position.size() != 2 or size_value.size() != 2: return
	_detail_edit_id = _detail_selected_id
	_detail_selected_id = -1
	detail_kind = str(record.get("kind", ""))
	detail_style_id = str(record.get("style_id", ""))
	detail_size = Vector2(float(size_value[0]), float(size_value[1]))
	detail_yaw_quarters = int(record.get("yaw_quarters", 0))
	detail_yaw_degrees = float(record.get("yaw_degrees", detail_yaw_quarters * 90.0))
	_detail_selected_colour = str(record.get("colour_id", ""))
	cursor.x = float(position[0]); cursor.z = float(position[1])
	_begin_detail_placement(detail_kind, detail_style_id, detail_size, detail_yaw_quarters)
	if detail_placement_active:
		detail_yaw_degrees = float(record.get("yaw_degrees", detail_yaw_quarters * 90.0))
		_refresh_detail_visual(true)
		_set_status("Move %s • A place • left/right rotate • B cancel" % _composition_label(record))

func _cycle_selected_detail_colour() -> void:
	var record := _composition_record(_detail_selected_id)
	if record.is_empty(): _detail_selected_id = -1; return
	var current := str(record.get("colour_id", ""))
	var index := DETAIL_EDIT_COLOURS.find(current)
	var next_colour := DETAIL_EDIT_COLOURS[0] if index < 0 else DETAIL_EDIT_COLOURS[(index + 1) % DETAIL_EDIT_COLOURS.size()]
	var before := landscape_state.document()
	var position: Array = record.get("position", [])
	var yaw_degrees := float(record.get("yaw_degrees", NAN))
	if landscape_state.update_composition(_detail_selected_id, Vector2(float(position[0]), float(position[1])), int(record.get("yaw_quarters", 0)), yaw_degrees, next_colour):
		_landscape_before = before
		_record_history("landscape")
		_detail_selected_colour = next_colour
		_refresh_detail_visual(true)
		_set_status("%s colour: %s • A move • X colour • B deselect" % [_composition_label(record), next_colour.capitalize()])
	_refresh_controller_hud()

func _close_hamlet_for_world() -> void:
	_hamlet_catalogue_open = false
	if _hamlet_catalogue_panel: _hamlet_catalogue_panel.visible = false
	tools_open = false
	get_viewport().gui_release_focus()

func _read_camera_and_cursor(delta: float) -> void:
	super._read_camera_and_cursor(delta)
	if detail_placement_active: _update_detail_validity()

func _update_brush_preview() -> void:
	if not detail_placement_active:
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
		if _terrain_target_valid: cursor_reticle.update_target(_terrain_target_point, _terrain_target_normal, 0.30, "path", camera, true)
		else: cursor_reticle.set_target_visible(false)

func _update_detail_validity() -> void:
	detail_placement_valid = false
	detail_placement_reason = "No terrain surface under cursor"
	if not detail_placement_active: return
	if _terrain_revision() != _detail_terrain_revision:
		detail_placement_reason = "Terrain changed; restart %s" % detail_kind
		return
	if building_world.get_revision() != _detail_building_revision:
		detail_placement_reason = "Home layout changed; restart %s" % detail_kind
		return
	var point := _path_cursor_point()
	if not point.is_finite(): return
	if not _candidate_detail_fits_limits(detail_kind, detail_style_id, point, detail_size, detail_yaw_quarters):
		detail_placement_reason = "%s is outside the editable world or detail limit" % _detail_kind_label()
		return
	if _composition_hits_home(point, detail_size, detail_yaw_quarters):
		detail_placement_reason = "%s overlaps a home" % _detail_kind_label()
		return
	detail_placement_valid = true
	detail_placement_reason = "Valid %s position" % detail_kind

func _update_detail_preview() -> void:
	if not composition_visual or not detail_placement_active: return
	var point := _path_cursor_point()
	if not point.is_finite():
		_hide_detail_preview()
		return
	var signature := "%s|%s|%s|%d|%s|%d" % [detail_kind, detail_style_id, point, detail_yaw_quarters, detail_placement_valid, _terrain_revision()]
	if signature == _detail_preview_signature: return
	_detail_preview_signature = signature
	match detail_kind:
		"garden": composition_visual.show_garden_preview(detail_style_id, point, detail_size, detail_yaw_quarters, detail_placement_valid)
		"fence": composition_visual.show_fence_preview(detail_style_id, point, detail_size, detail_yaw_quarters, detail_placement_valid)

func _hide_detail_preview() -> void:
	if not composition_visual: return
	composition_visual.hide_garden_preview()
	composition_visual.hide_fence_preview()

func _rotate_detail(direction: int) -> void:
	if not detail_placement_active: return
	if detail_kind == "furniture":
		var step := 1.0 if precision_mode else 15.0
		detail_yaw_degrees = fposmod(detail_yaw_degrees + step * float(signi(direction)), 360.0)
		detail_yaw_quarters = posmod(roundi(detail_yaw_degrees / 90.0), 4)
	else:
		detail_yaw_quarters = posmod(detail_yaw_quarters + direction, 4)
		detail_yaw_degrees = float(detail_yaw_quarters) * 90.0
	_detail_preview_signature = ""
	_update_detail_validity()
	_update_detail_preview()
	_sync_detail_aliases()
	_set_status("%s • rotated %.0f° • %s" % [_detail_style_name(), detail_yaw_degrees, detail_placement_reason])
	_refresh_controller_hud()

func _rotate_garden(direction: int) -> void:
	if detail_placement_active and detail_kind == "garden": _rotate_detail(direction)

func _rotate_fence(direction: int) -> void:
	if detail_placement_active and detail_kind == "fence": _rotate_detail(direction)

func _commit_detail() -> bool:
	if not detail_placement_active: return false
	_update_detail_validity()
	_sync_detail_aliases()
	if not detail_placement_valid:
		_set_status("Cannot place %s: %s" % [detail_kind, detail_placement_reason])
		return false
	if JSON.stringify(landscape_state.document()) != _detail_before_serialized:
		detail_placement_reason = "Landscape changed; restart %s" % detail_kind
		_sync_detail_aliases()
		return false
	if _terrain_revision() != _detail_terrain_revision or building_world.get_revision() != _detail_building_revision:
		detail_placement_reason = "World changed; restart %s" % detail_kind
		_sync_detail_aliases()
		return false
	var point := _path_cursor_point()
	if not point.is_finite(): return false
	_landscape_before = _detail_before.duplicate(true)
	var placed_kind := detail_kind
	var placed_name := _detail_style_name()
	var object_id := _detail_edit_id
	var changed := false
	if _detail_edit_id > 0:
		changed = landscape_state.update_composition(_detail_edit_id, point, detail_yaw_quarters, detail_yaw_degrees if detail_kind == "furniture" else NAN, _detail_selected_colour)
	else:
		object_id = landscape_state.add_composition(detail_kind, detail_style_id, point, detail_size, detail_yaw_quarters, detail_yaw_degrees if detail_kind == "furniture" else NAN)
		changed = object_id > 0
	if not changed:
		_landscape_before.clear()
		detail_placement_reason = "%s could not be updated" % _detail_kind_label()
		_sync_detail_aliases()
		return false
	var margin := 0.10 if detail_kind == "garden" else 0.02
	landscape_state.clear_records_in_footprint(point, detail_size, detail_yaw_quarters, margin, detail_yaw_degrees if detail_kind == "furniture" else NAN)
	if garden_visual: garden_visual.reset_records(landscape_state.records)
	var was_edit := _detail_edit_id > 0
	_finish_detail_placement()
	_record_history("landscape")
	_landscape_before.clear()
	_refresh_detail_visual(true)
	_set_status(("%s moved • LB undo" if was_edit else "%s placed • LB undo") % placed_name)
	_refresh_controller_hud()
	return placed_kind in ["garden", "fence"]

func _commit_garden() -> bool:
	return _commit_detail() if detail_placement_active and detail_kind == "garden" else false

func _commit_fence() -> bool:
	return _commit_detail() if detail_placement_active and detail_kind == "fence" else false

func _cancel_detail_placement(reason: String) -> void:
	if not detail_placement_active: return
	if not _detail_before.is_empty():
		landscape_state.restore(_detail_before)
		if garden_visual: garden_visual.reset_records(landscape_state.records)
	_finish_detail_placement()
	_set_status(reason)
	_refresh_detail_visual(true)
	_refresh_controller_hud()

func _finish_detail_placement() -> void:
	_hide_detail_preview()
	detail_placement_active = false
	detail_placement_valid = false
	detail_placement_reason = ""
	_detail_preview_signature = ""
	_detail_before.clear()
	_detail_before_serialized = ""
	_detail_edit_id = -1
	_sync_detail_aliases()

func _cancel_garden_placement(reason: String = "Garden cancelled") -> void:
	if detail_placement_active and detail_kind == "garden": _cancel_detail_placement(reason)

func _cancel_fence_placement(reason: String = "Fence cancelled") -> void:
	if detail_placement_active and detail_kind == "fence": _cancel_detail_placement(reason)

func _update_garden_validity() -> void:
	if detail_placement_active and detail_kind == "garden": _update_detail_validity(); _sync_detail_aliases()

func _update_fence_validity() -> void:
	if detail_placement_active and detail_kind == "fence": _update_detail_validity(); _sync_detail_aliases()

func _update_garden_preview() -> void:
	if detail_placement_active and detail_kind == "garden": _update_detail_preview()

func _update_fence_preview() -> void:
	if detail_placement_active and detail_kind == "fence": _update_detail_preview()

func _sync_detail_aliases() -> void:
	garden_placement_active = detail_placement_active and detail_kind == "garden"
	fence_placement_active = detail_placement_active and detail_kind == "fence"
	if detail_kind == "garden":
		garden_style_id = detail_style_id
		garden_size = detail_size
		garden_yaw_quarters = detail_yaw_quarters
		garden_placement_valid = detail_placement_valid
		garden_placement_reason = detail_placement_reason
	elif detail_kind == "fence":
		fence_style_id = detail_style_id
		fence_size = detail_size
		fence_yaw_quarters = detail_yaw_quarters
		fence_placement_valid = detail_placement_valid
		fence_placement_reason = detail_placement_reason

func _detail_definition(kind: String, style_id: String) -> Dictionary:
	if kind == "garden" and GARDEN_STYLES.has(style_id): return GARDEN_STYLES[style_id]
	if kind == "fence" and FENCE_STYLES.has(style_id): return FENCE_STYLES[style_id]
	return {}

func _detail_style_name() -> String:
	var definition := _detail_definition(detail_kind, detail_style_id)
	return str(definition.get("name", _detail_kind_label()))

func _detail_kind_label() -> String:
	return detail_kind.capitalize() if not detail_kind.is_empty() else "Detail"

func _candidate_detail_fits_limits(kind: String, style_id: String, point: Vector2, size: Vector2, yaw_quarters: int) -> bool:
	var proposed := landscape_state.document()
	var values: Array = proposed.get("composition", [])
	var candidate := {"id": int(proposed["next_id"]), "kind": kind, "style_id": style_id, "position": [point.x, point.y], "size": [size.x, size.y], "yaw_quarters": posmod(yaw_quarters, 4)}
	if kind == "furniture": candidate["yaw_degrees"] = detail_yaw_degrees
	values.append(candidate)
	proposed["composition"] = values
	proposed["next_id"] = int(proposed["next_id"]) + 1
	return DetailState.validate(proposed)

func _composition_hits_home(center: Vector2, size: Vector2, yaw_quarters: int) -> bool:
	var angle := deg_to_rad(detail_yaw_degrees) if detail_kind == "furniture" else float(posmod(yaw_quarters, 4)) * PI * 0.5
	var half := size * 0.5 + Vector2.ONE * 0.08
	var cosine := cos(angle)
	var sine := sin(angle)
	var candidate: Array = []
	for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		var rotated := Vector2(corner.x * cosine - corner.y * sine, corner.x * sine + corner.y * cosine)
		candidate.append(center + rotated)
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
			var a_min := INF
			var a_max := -INF
			var b_min := INF
			var b_max := -INF
			for point: Vector2 in a:
				var amount := point.dot(axis)
				a_min = minf(a_min, amount)
				a_max = maxf(a_max, amount)
			for point: Vector2 in b:
				var amount := point.dot(axis)
				b_min = minf(b_min, amount)
				b_max = maxf(b_max, amount)
			if a_max <= b_min + 0.0001 or b_max <= a_min + 0.0001: return false
	return true

func _cancel_current_edit(reason: String) -> void:
	if detail_placement_active: _cancel_detail_placement(reason)
	super._cancel_current_edit(reason)

func _undo() -> void:
	super._undo()
	_refresh_detail_visual(true)

func _redo() -> void:
	super._redo()
	_refresh_detail_visual(true)

func _restore_landscape(document: Dictionary) -> void:
	super._restore_landscape(document)
	_refresh_detail_visual(true)

func _on_backend_changed() -> void:
	var started := Time.get_ticks_usec()
	super._on_backend_changed()
	var upstream_ms := float(Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	_refresh_detail_visual(true)
	if OS.is_debug_build():
		print("THOR_BACKEND_DETAILS " + JSON.stringify({"upstream_ms": upstream_ms, "details_ms": float(Time.get_ticks_usec() - started) / 1000.0, "items": landscape_state.composition.size()}))

func _refresh_detail_visual(force: bool = false) -> void:
	if not composition_visual: return
	if backend and composition_visual.has_method("attach_backend"): composition_visual.attach_backend(backend)
	var signature := JSON.stringify(landscape_state.composition) + "|" + str(_terrain_revision())
	if not force and signature == _detail_render_signature: return
	_detail_render_signature = signature
	composition_visual.rebuild_gardens(landscape_state.composition, backend)
	composition_visual.rebuild_fences(landscape_state.composition, backend)

func _refresh_garden_visual(force: bool = false) -> void:
	_refresh_detail_visual(force)

func _refresh_fence_visual(force: bool = false) -> void:
	_refresh_detail_visual(force)

func _update_presentation() -> void:
	super._update_presentation()
	if not detail_placement_active or not target_label: return
	target_label.text = "%s • %.0f° • %s\nA place  left/right rotate  B cancel  RS orbit" % [_detail_style_name(), detail_yaw_degrees, detail_placement_reason]
	_update_detail_preview()

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if menu_open or not _tool_name or not _prompt_row: return
	if _hamlet_catalogue_open:
		_mode_label.text = "BUILD"
		_tool_name.text = "Hamlet details"
		_tool_meta.text = "Gardens and rustic fences • street furniture next"
		_tool_card.visible = true
		if _terrain_panel: _terrain_panel.visible = false
		if _building_panel: _building_panel.visible = false
		if _world_prompt: _world_prompt.visible = false
		_set_prompts([["UP/DOWN", "Choose"], ["A", "Place"], ["B", "Categories"]])
		return
	if not detail_placement_active: return
	_mode_label.text = "TERRAIN"
	_tool_name.text = _detail_style_name()
	_tool_meta.text = "%.0f° • %s" % [detail_yaw_degrees, detail_placement_reason]
	_tool_card.visible = true
	if _terrain_panel: _terrain_panel.visible = false
	if _building_panel: _building_panel.visible = false
	if _world_prompt: _world_prompt.visible = false
	_set_prompts([["A", "Place"], ["LEFT/RIGHT", "Rotate"], ["B", "Cancel"], ["RS", "Orbit"], ["LT/RT", "Zoom"]])

func _detail_near_cursor_record() -> Dictionary:
	var point := _path_cursor_point()
	if not point.is_finite(): return {}
	var best: Dictionary = {}
	var best_distance := INF
	for value in landscape_state.composition:
		if not value is Dictionary: continue
		var record: Dictionary = value
		var kind := str(record.get("kind", ""))
		if kind not in ["garden", "fence", "furniture"]: continue
		var position: Array = record.get("position", [])
		if position.size() != 2: continue
		var distance := point.distance_to(Vector2(float(position[0]), float(position[1])))
		var size_value: Array = record.get("size", [1.0, 1.0])
		var reach := maxf(DETAIL_SELECT_RADIUS, maxf(float(size_value[0]), float(size_value[1])) * 0.55)
		if distance <= reach and distance < best_distance:
			best_distance = distance
			best = record.duplicate(true)
	return best

func _show_outdoor_detail_hover(record: Dictionary) -> void:
	if not _hover_outline or not _hover_prompt or not camera: return
	var position: Array = record.get("position", [])
	if position.size() != 2: return
	var point := Vector2(float(position[0]), float(position[1]))
	var size_value: Array = record.get("size", [1.0, 1.0])
	var size := Vector2(float(size_value[0]), float(size_value[1]))
	var y := cursor.y
	if composition_visual and composition_visual.has_method("_surface_height"):
		y = float(composition_visual.call("_surface_height", point)) + 0.45
	var center := Vector3(point.x, y, point.y)
	if camera.is_position_behind(center): return
	var screen := camera.unproject_position(center)
	var radius := clampf(maxf(size.x, size.y) * 14.0, 24.0, 70.0)
	_hover_outline.position = screen - Vector2(radius, radius * 0.65)
	_hover_outline.size = Vector2(radius * 2.0, radius * 1.3)
	_hover_outline.visible = true
	_hover_prompt.text = "%s   A Move   X Options" % _composition_label(record)
	_hover_prompt.position = screen + Vector2(-radius, -radius * 0.95)
