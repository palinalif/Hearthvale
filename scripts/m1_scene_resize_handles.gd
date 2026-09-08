extends "res://scripts/m1_scene_thor_retest.gd"
## Direct, camera-relative side/corner/top manipulation. All accepted terrain
## and cottage controls stay inherited outside this temporary resize action.
const ResizeWorld = preload("res://scripts/cottage_resize_world.gd")
const ResizeOverlay = preload("res://scripts/cottage_resize_overlay.gd")
const HANDLE_SIDES := {"left": Vector3.LEFT, "right": Vector3.RIGHT, "front": Vector3.FORWARD, "back": Vector3.BACK, "front_left": Vector3(-1, 0, -1), "front_right": Vector3(1, 0, -1), "back_left": Vector3(-1, 0, 1), "back_right": Vector3(1, 0, 1), "height": Vector3.UP}
var _resize_overlay: Control
var _resize_hint: Label
var _handle_hover := ""
var _grabbed_handle := ""
var _handle_source: Dictionary = {}
var _handle_preview: Dictionary = {}
var _handle_revision := -1
var _handle_raw_dimensions := Vector3.ZERO
var _handle_render_dirty := false

func _build_world() -> void:
	super._build_world()
	# This factory seam runs BEFORE loading saves or connecting model signals.
	# The subclass inherits the exact seed recipe, serialization and history.
	building_world = ResizeWorld.new()

func _ready() -> void:
	super._ready()
	_resize_overlay = ResizeOverlay.new()
	_resize_overlay.name = "DirectResizeHandles"
	hud.add_child(_resize_overlay)
	_resize_hint = Label.new()
	_resize_hint.name = "ResizeHandleHint"
	_resize_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resize_hint.add_theme_font_size_override("font_size", 18)
	_resize_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	_resize_hint.add_theme_constant_override("shadow_offset_x", 2)
	_resize_hint.add_theme_constant_override("shadow_offset_y", 2)
	hud.add_child(_resize_hint)
	_update_resize_handles()

func _set_view_context(next_context: String, reason: String = "Context changed") -> bool:
	var changed := super._set_view_context(next_context, reason)
	if changed and view_context == "building":
		_set_status("Point at a handle to resize, or a detail to move")
	return changed

func _update_direct_edit_hud() -> void:
	super._update_direct_edit_hud()
	if resize_active and _pointer_label: _pointer_label.visible = false

func _input(event: InputEvent) -> void:
	if _shutting_down: return
	if _blocked_until_accept_release:
		super._input(event)
		return
	if resize_active and not _grabbed_handle.is_empty() and not menu_open:
		if event.is_action_pressed("m1_accept"): _commit_resize()
		elif event.is_action_pressed("m1_cancel"): _cancel_resize()
		elif event.is_action_pressed("m1_pause"): _set_menu(true)
		elif event.is_action_pressed("m1_precision"): precision_mode = not precision_mode
		# D-pad no longer changes an invisible axis or selects another cottage.
		get_viewport().set_input_as_handled()
		return
	if _idle_building() and event.is_action_pressed("m1_accept"):
		_update_detail_hover()
		if not _handle_hover.is_empty():
			_begin_handle_resize(_handle_hover)
			get_viewport().set_input_as_handled()
			return
		if hovered_detail_id.is_empty():
			_set_status("Point at an edge, corner or height handle, then A to grab")
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _begin_resize() -> void:
	# Legacy callers must not reactivate the axis-selector interaction.
	if not _handle_hover.is_empty(): _begin_handle_resize(_handle_hover)

func _begin_handle_resize(handle_id: String) -> void:
	if not _idle_building() or not HANDLE_SIDES.has(handle_id): return
	_handle_source = building_world.get_building(selected_building_id)
	if _handle_source.is_empty(): return
	_handle_revision = building_world.get_revision()
	_grabbed_handle = handle_id
	resize_dimensions = _handle_source["dimensions"]
	resize_preview_dimensions = resize_dimensions
	_handle_raw_dimensions = resize_dimensions
	resize_active = true
	resize_locked = false
	_clear_hover()
	if _pointer_label: _pointer_label.visible = false
	_refresh_handle_preview()
	get_viewport().gui_release_focus()
	_set_status("Drag %s with left stick; A apply / B restore" % handle_id.replace("_", " "))
	_refresh_controller_hud()

func _refresh_handle_preview() -> void:
	_handle_preview = building_world.preview_handle_resize(str(_handle_source["id"]), resize_preview_dimensions, HANDLE_SIDES[_grabbed_handle], _handle_revision)
	_presentation_key = ""
	_handle_render_dirty = true
	_update_presentation()

func _read_camera_and_cursor(delta: float) -> void:
	if not resize_active or _grabbed_handle.is_empty():
		super._read_camera_and_cursor(delta)
		return
	_read_building_overlay_camera(delta)
	if building_world.get_revision() != _handle_revision or selected_building_id != str(_handle_source["id"]):
		_cancel_resize()
		_set_status("Cottage changed; resize cancelled rather than overwriting newer edits")
		return
	var stick := Vector2(Input.get_axis("m1_move_left", "m1_move_right"), Input.get_axis("m1_move_up", "m1_move_down"))
	if stick.length() <= 0.05: return
	stick = stick.normalized() * pow(minf(stick.length(), 1.0), 1.35)
	var transform_value: Transform3D = _handle_source["transform"]
	var scale_value := transform_value.basis.get_scale().abs()
	var sides: Vector3 = HANDLE_SIDES[_grabbed_handle]
	var point := _selected_building_camera_target()
	var movement := Vector3.ZERO
	if sides.y > 0.0:
		movement.y = stick.dot(_screen_direction(point, Vector3.UP))
	elif sides.x != 0.0 and sides.z != 0.0:
		var x_axis := _screen_direction(point, transform_value.basis.x.normalized())
		var z_axis := _screen_direction(point, transform_value.basis.z.normalized())
		var determinant := x_axis.cross(z_axis)
		if absf(determinant) > 0.08:
			movement.x = stick.cross(z_axis) / determinant
			movement.z = x_axis.cross(stick) / determinant
		else:
			movement.x = stick.dot(x_axis)
			movement.z = stick.dot(z_axis)
		movement = movement.limit_length(1.0)
	else:
		var axis := transform_value.basis.x.normalized() if sides.x != 0.0 else transform_value.basis.z.normalized()
		var amount := stick.dot(_screen_direction(point, axis))
		if sides.x != 0.0: movement.x = amount
		else: movement.z = amount
	var speed := 0.7 if precision_mode else 2.0
	_handle_raw_dimensions += movement * sides / scale_value * maxf(delta, 0.0) * speed
	_handle_raw_dimensions = _handle_raw_dimensions.clamp(BuildingWorldScript.MIN_DIMENSIONS, BuildingWorldScript.MAX_DIMENSIONS)
	var next := ResizeWorld.handle_dimensions(resize_dimensions, _handle_raw_dimensions, scale_value, sides, precision_mode)
	if next != resize_preview_dimensions:
		resize_preview_dimensions = next
		_refresh_handle_preview()

func _screen_direction(point: Vector3, direction: Vector3) -> Vector2:
	return (camera.unproject_position(point + direction * 0.25) - camera.unproject_position(point)).normalized()

func _selected_building_camera_target() -> Vector3:
	if resize_active and not _handle_preview.is_empty():
		var view: Dictionary = _handle_preview["view"]
		var transform_value: Transform3D = view["transform"]
		var dimensions: Vector3 = view["dimensions"]
		return transform_value * Vector3(0, dimensions.y * 0.5, 0)
	return super._selected_building_camera_target()

func _commit_resize() -> bool:
	if _grabbed_handle.is_empty(): return false
	var id := str(_handle_source["id"])
	var sides: Vector3 = HANDLE_SIDES[_grabbed_handle]
	# Clear the active preview before the authoritative changed signal renders.
	resize_active = false
	var ok: bool = building_world.commit_handle_resize(id, resize_preview_dimensions, sides, _handle_revision)
	if ok: _record_history("building")
	_clear_handle_resize()
	_needs_signature = ""
	_refresh_needs_placement_panel()
	_set_status("Cottage resized; %d details need placement" % _needs_details().size() if ok else "No resize committed")
	return ok

func _cancel_resize() -> void:
	if _grabbed_handle.is_empty():
		super._cancel_resize()
		return
	resize_active = false
	resize_preview_dimensions = resize_dimensions
	_clear_handle_resize()
	_set_status("Resize cancelled; original cottage restored")

func _clear_handle_resize() -> void:
	_grabbed_handle = ""
	_handle_preview = {}
	_handle_source = {}
	_handle_hover = ""
	_presentation_key = ""
	_colour_render_key = ""
	_update_presentation()
	_update_camera()
	_update_detail_hover()
	_update_direct_edit_hud()
	_refresh_controller_hud()

func _update_presentation() -> void:
	if resize_active and not _handle_preview.is_empty():
		if building_world.get_revision() != _handle_revision: return
		var view: Dictionary = _handle_preview["view"]
		var visual: Node3D = cottage_visuals.get(str(view["id"]))
		if visual and _handle_render_dirty:
			visual.request_revision(_handle_revision)
			visual.apply_building(view, _handle_revision)
			_colour_view(view, visual)
			_handle_render_dirty = false
		_update_resize_handles()
		return
	super._update_presentation()

func _handle_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not camera or not building_world or view_context != "building": return result
	var view: Dictionary = _handle_preview.get("view", {}) if resize_active else building_world.get_building(selected_building_id)
	if view.is_empty(): return result
	var dimensions: Vector3 = view["dimensions"]
	var transform_value: Transform3D = view["transform"]
	var scale_value := transform_value.basis.get_scale().abs()
	var camera_local := transform_value.affine_inverse() * camera.global_position
	var viewport_rect := get_viewport().get_visible_rect().grow(-20.0)
	for id_value in HANDLE_SIDES:
		var id := str(id_value)
		var sides: Vector3 = HANDLE_SIDES[id]
		var facing := sides.y > 0.0 or (sides.x != 0.0 and camera_local.x * sides.x > dimensions.x * 0.5) or (sides.z != 0.0 and camera_local.z * sides.z > dimensions.z * 0.5)
		if not facing and id != _grabbed_handle: continue
		var anchor := Vector3(dimensions.x * 0.5 * sides.x, 0.25, dimensions.z * 0.5 * sides.z)
		var local := anchor + Vector3(0.35 / scale_value.x * sides.x, 0, 0.35 / scale_value.z * sides.z)
		if sides.y > 0.0:
			anchor = Vector3(0, dimensions.y * 1.43, 0)
			local = anchor + Vector3(0, 0.40 / scale_value.y, 0)
		var world_point := transform_value * local
		if camera.is_position_behind(world_point): continue
		var screen := camera.unproject_position(world_point)
		if not viewport_rect.has_point(screen): continue
		var shell := _pick_cottage(screen)
		if not shell.is_empty() and str(shell["id"]) != selected_building_id and float(shell["distance"]) < camera.global_position.distance_to(world_point): continue
		result.append({"id": id, "screen": screen, "anchor_screen": camera.unproject_position(transform_value * anchor), "arrow": _screen_direction(world_point, (transform_value.basis * sides).normalized())})
	return result

func _update_detail_hover() -> void:
	_handle_hover = ""
	if _idle_building():
		var best := 22.0 * 22.0
		for candidate in _handle_candidates():
			var distance: float = edit_pointer.distance_squared_to(candidate["screen"])
			if distance < best:
				best = distance
				_handle_hover = str(candidate["id"])
	if not _handle_hover.is_empty(): _clear_hover()
	else: super._update_detail_hover()

func _update_resize_handles() -> void:
	if resize_handles: resize_handles.visible = false
	if not _resize_overlay or not _resize_hint: return
	var show := view_context == "building" and not menu_open and not tools_open and not detail_open and not detail_move_active and not building_placement_active and not _restoring
	_resize_overlay.visible = show
	_resize_hint.visible = false
	if not show: return
	var candidates := _handle_candidates()
	_resize_overlay.set_layout(candidates, [], _handle_hover, _grabbed_handle)
	var highlighted := _grabbed_handle if resize_active else _handle_hover
	for candidate in candidates:
		if str(candidate["id"]) != highlighted: continue
		_resize_hint.text = "%s  A %s" % [highlighted.replace("_", " ").capitalize(), "Apply / B Restore" if resize_active else "Grab"]
		var screen: Vector2 = candidate["screen"]
		var size_value := get_viewport().get_visible_rect().size
		_resize_hint.position = Vector2(clampf(screen.x + 18, 18, size_value.x - 345), clampf(screen.y - 32, 24, size_value.y - 110))
		_resize_hint.visible = true

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if not _tool_name or not _prompt_row or menu_open or tools_open or detail_open or view_context != "building": return
	if resize_active and not _grabbed_handle.is_empty():
		_tool_name.text = "Resize %s" % _grabbed_handle.replace("_", " ")
		var transform_value: Transform3D = _handle_source["transform"]
		var world_dimensions := resize_preview_dimensions * transform_value.basis.get_scale().abs()
		var step := 0.125 if _grabbed_handle == "height" else 0.25
		if not precision_mode: step *= 2.0
		_tool_meta.text = "%.2f x %.2f x %.2f\nSnap %.3f | %d need placement" % [world_dimensions.x, world_dimensions.y, world_dimensions.z, step, _handle_preview.get("needs_placement", []).size()]
		_set_prompts([["A", "Apply"], ["B", "Restore"], ["LS", "Drag handle"], ["RS", "Orbit"], ["LT/RT", "Zoom"], ["L3", "Precision"]])
	elif _idle_building() and hovered_detail_id.is_empty():
		var prompts: Array = [["LS", "Point at handles"], ["X", "Cottage options"], ["B", "Finish editing"], ["RS", "Orbit"]]
		if not _handle_hover.is_empty(): prompts.push_front(["A", "Grab handle"])
		if building_world.get_buildings().size() > 1: prompts.append(["LEFT/RIGHT", "Cottage"])
		_set_prompts(prompts)
