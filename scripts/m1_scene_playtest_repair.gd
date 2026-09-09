extends "res://scripts/m1_scene_full_ui.gd"
## Integrated fixes for the two physical Thor playtests. Keep the accepted
## controller grammar; own selection, temporary actions and rendered identity.

var _building_actions_open := false
var _needs_open := false
var _needs_action: Button
var _world_hover: Dictionary = {}
var _world_outline: Panel
var _world_prompt: Label
var _rendered_selection := ""
var _style_render_key: Array = []
var _colour_render_key := ""
var _move_render_key := ""
var _detail_free_position := Vector3.ZERO
var _placement_camera: Dictionary = {}
var _frame_delta := 1.0 / 60.0
var _free_camera_y := 0.0
var _free_camera_valid := false
var _strength_by_tool := {"raise": 3, "dig": 3, "smooth": 5, "level": 5, "slope": 5}

func _ready() -> void:
	brush_strength_level = int(_strength_by_tool.get(sculpt_tool, 5))
	brush_strength = StrengthScale.rate(brush_strength_level)
	super._ready()
	_world_outline = Panel.new()
	_world_outline.name = "CottageWorldHover"
	_world_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color(1, 0.8, 0.4, 0.06)
	outline.border_color = Color("#ffd069")
	outline.set_border_width_all(2)
	_world_outline.add_theme_stylebox_override("panel", outline)
	_world_outline.visible = false
	hud.add_child(_world_outline)
	_world_prompt = Label.new()
	_world_prompt.name = "EditThisCottagePrompt"
	_world_prompt.text = "X  Edit cottage"
	_world_prompt.add_theme_font_size_override("font_size", 20)
	_world_prompt.add_theme_color_override("font_shadow_color", Color.BLACK)
	_world_prompt.add_theme_constant_override("shadow_offset_x", 2)
	_world_prompt.add_theme_constant_override("shadow_offset_y", 2)
	_world_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_prompt.visible = false
	hud.add_child(_world_prompt)
	var box := _building_buttons[0].get_parent() as VBoxContainer
	_add_building_button(box, "Needs placement", _open_needs_placement)
	_needs_action = _building_buttons.back()
	box.move_child(_needs_action, box.get_child_count() - 2)
	_refresh_controller_hud()

func _process(delta: float) -> void:
	_frame_delta = delta
	super._process(delta)
	_update_world_hover()

func _idle_building() -> bool:
	return view_context == "building" and not menu_open and not tools_open and not detail_open and not detail_move_active and not resize_active and not building_placement_active and not _restoring

func _input(event: InputEvent) -> void:
	if _shutting_down: return
	# Releases must reach the safety latch even when an overlay owns input.
	if _blocked_until_accept_release and event.is_action_released("m1_accept"):
		_blocked_until_accept_release = false
		get_viewport().set_input_as_handled()
		return
	if _blocked_until_accept_release and event.is_action_pressed("m1_accept"):
		get_viewport().set_input_as_handled()
		return
	if _needs_open:
		if event.is_action_pressed("m1_pause"):
			_set_menu(true)
		elif event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_close_needs_placement()
		elif event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner()
			if focus is Button and _needs_box.is_ancestor_of(focus): (focus as Button).pressed.emit()
		elif event.is_action_pressed("m1_height_up"):
			_move_focus(_needs_buttons(), -1)
		elif event.is_action_pressed("m1_height_down"):
			_move_focus(_needs_buttons(), 1)
		get_viewport().set_input_as_handled()
		return
	if not _style_picker_mode.is_empty():
		if event.is_action_pressed("m1_pause"): _set_menu(true)
		else: _handle_overlay_input(event)
		get_viewport().set_input_as_handled()
		return
	if view_context == "terrain" and not menu_open and not tools_open and not detail_open and not stroke_active and not landscape_active and event.is_action_pressed("m1_tools"):
		_update_world_hover()
		if not _world_hover.is_empty():
			selected_building_id = str(_world_hover["id"])
			_set_view_context("building", "Editing selected cottage")
			get_viewport().set_input_as_handled()
			return
	if _idle_building():
		if event.is_action_pressed("m1_cancel"):
			_set_view_context("terrain", "Cottage editing finished")
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_tools"):
			_update_detail_hover()
			if hovered_detail_id.is_empty(): _open_building_panel()
			else: _open_hovered_detail_actions()
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _ray_box_distance(origin: Vector3, direction: Vector3, bounds: AABB) -> float:
	var near_t := 0.0
	var far_t := INF
	for axis in 3:
		if absf(direction[axis]) < 0.000001:
			if origin[axis] < bounds.position[axis] or origin[axis] > bounds.end[axis]: return -1.0
			continue
		var a := (bounds.position[axis] - origin[axis]) / direction[axis]
		var b := (bounds.end[axis] - origin[axis]) / direction[axis]
		near_t = maxf(near_t, minf(a, b))
		far_t = minf(far_t, maxf(a, b))
		if far_t < near_t: return -1.0
	return near_t

func _pick_cottage(screen_position: Vector2) -> Dictionary:
	if not camera or not building_world: return {}
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var result: Dictionary = {}
	var best := INF
	for view in building_world.get_buildings():
		var transform_value: Transform3D = view["transform"]
		var inverse := transform_value.affine_inverse()
		var dims: Vector3 = view["dimensions"]
		var bounds := AABB(Vector3(-dims.x * 0.5, 0, -dims.z * 0.5), Vector3(dims.x, dims.y * 1.43, dims.z))
		var distance := _ray_box_distance(inverse * origin, inverse.basis * direction, bounds)
		if distance < 0 or distance >= best: continue
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for i in 8:
			var world_point := transform_value * bounds.get_endpoint(i)
			if camera.is_position_behind(world_point): continue
			var point := camera.unproject_position(world_point)
			low = low.min(point)
			high = high.max(point)
		if not low.is_finite() or not high.is_finite(): continue
		best = distance
		result = {"id": str(view["id"]), "distance": distance, "bounds": Rect2(low, high - low)}
	return result

func _update_world_hover() -> void:
	_world_hover = {}
	if _world_outline: _world_outline.visible = false
	if _world_prompt: _world_prompt.visible = false
	if view_context != "terrain" or menu_open or tools_open or detail_open or stroke_active or landscape_active or _restoring or not camera: return
	var point := _terrain_target_point if _terrain_target_valid else cursor
	if camera.is_position_behind(point): return
	_world_hover = _pick_cottage(camera.unproject_position(point))
	if _world_hover.is_empty(): return
	var bounds: Rect2 = _world_hover["bounds"]
	if _world_outline:
		_world_outline.position = bounds.position
		_world_outline.size = bounds.size
		_world_outline.visible = true
	if _world_prompt:
		_world_prompt.position = Vector2(clampf(bounds.position.x, 16, get_viewport().get_visible_rect().size.x - 220), maxf(16, bounds.position.y - 30))
		_world_prompt.visible = true

func _pointer_over_selected_shell() -> bool:
	return str(_pick_cottage(edit_pointer).get("id", "")) == selected_building_id and not selected_building_id.is_empty()

func _pick_detail_at_screen_position(screen_position: Vector2) -> Dictionary:
	var detail := super._pick_detail_at_screen_position(screen_position)
	if detail.is_empty(): return detail
	var shell := _pick_cottage(screen_position)
	if not shell.is_empty() and str(shell["id"]) != selected_building_id: return {}
	return detail

func _set_view_context(next_context: String, reason: String = "Context changed") -> bool:
	var leaving := view_context == "building" and next_context == "terrain"
	var old_yaw := camera_yaw
	var old_pitch := camera_pitch
	var old_distance := camera_distance
	var pivot := camera.global_position - camera.global_basis.z * camera_distance if camera else cursor + Vector3(0, 2, 0)
	if next_context == "building" and view_context == "terrain":
		_update_world_hover()
		if not _world_hover.is_empty(): selected_building_id = str(_world_hover["id"])
	_building_actions_open = false
	_needs_open = false
	_context_actions_open = false
	if not _style_picker_mode.is_empty(): _cancel_style_picker()
	var changed := super._set_view_context(next_context, reason)
	if changed:
		selected_detail_id = ""
		selected_surface_id = ""
		_clear_hover()
		_presentation_key = ""
	if changed and leaving:
		# Release the building pivot without teleporting back to an older view.
		camera_yaw = old_yaw
		camera_pitch = old_pitch
		camera_distance = old_distance
		cursor = pivot - Vector3(0, 2, 0)
		terrain_cursor = cursor
		_terrain_camera_state.clear()
		_free_camera_y = pivot.y
		_free_camera_valid = true
	_update_camera()
	_update_world_hover()
	return changed

func _cycle_building(direction: int) -> void:
	_clear_hover()
	selected_surface_id = ""
	_presentation_key = ""
	super._cycle_building(direction)
	_reset_edit_pointer()

func _read_camera_and_cursor(delta: float) -> void:
	var free_view := view_context == "terrain" or building_placement_active
	var old_distance := camera_distance
	var old_pitch := camera_pitch
	var old_cursor_y := cursor.y
	super._read_camera_and_cursor(delta)
	if free_view:
		# Avoid a follow-up jump caused by the old terrain minimum zoom/pitch.
		camera_distance = clampf(old_distance - Input.get_axis("m1_zoom_out", "m1_zoom_in") * delta * 18.0, 3.5, 52.0)
		camera_pitch = clampf(old_pitch + Input.get_axis("m1_orbit_up", "m1_orbit_down") * delta * 1.5, 0.08, 1.40)
		if view_context == "terrain" and Input.is_action_just_pressed("m1_mode_switch"):
			cursor.y = old_cursor_y
			terrain_cursor = cursor

func _update_camera() -> void:
	if not camera: return
	if view_context == "building" and not building_placement_active:
		super._update_camera()
		return
	var target := cursor + Vector3(0, 2, 0)
	if not _free_camera_valid:
		_free_camera_y = target.y
		_free_camera_valid = true
	# Ease committed terrain-height changes, without freezing horizontal input.
	_free_camera_y = lerpf(_free_camera_y, target.y, 1.0 - exp(-8.0 * _frame_delta))
	target.y = _free_camera_y
	var offset := Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch)) * camera_distance
	camera.position = target + offset
	camera.look_at(target, Vector3.UP)

func _begin_building_placement() -> void:
	var previous := {"yaw": camera_yaw, "pitch": camera_pitch, "distance": camera_distance}
	_building_actions_open = false
	super._begin_building_placement()
	if building_placement_active:
		_placement_camera = previous
		_free_camera_valid = false
		get_viewport().gui_release_focus()

func _cancel_building_placement() -> void:
	super._cancel_building_placement()
	_restore_placement_camera()

func _commit_building_placement() -> bool:
	var ok := super._commit_building_placement()
	_restore_placement_camera()
	_presentation_key = ""
	_update_presentation()
	_reset_edit_pointer()
	return ok

func _restore_placement_camera() -> void:
	if _placement_camera.is_empty(): return
	camera_yaw = float(_placement_camera["yaw"])
	camera_pitch = float(_placement_camera["pitch"])
	camera_distance = float(_placement_camera["distance"])
	_placement_camera.clear()
	_update_camera()

func _open_building_panel() -> void:
	_context_actions_open = false
	_building_actions_open = true
	super._open_building_panel()
	_building_actions_open = true

func _close_building_panel() -> void:
	_building_actions_open = false
	super._close_building_panel()

func _begin_style_picker(mode: String) -> void:
	_building_actions_open = false
	if _building_panel: _building_panel.visible = false
	_style_render_key.clear()
	super._begin_style_picker(mode)

func _end_style_picker() -> void:
	super._end_style_picker()
	_style_render_key.clear()
	_colour_render_key = ""
	_presentation_key = ""
	get_viewport().gui_release_focus()

func _update_action_buttons() -> void:
	super._update_action_buttons()
	if _context_actions_open and _style_picker_mode.is_empty() and _tool_buttons.has("Replace selected"):
		var variation := _tool_buttons["Replace selected"] as Button
		variation.visible = str(_selected_detail_record().get("kind", "")) == "window"
		variation.disabled = not variation.visible

func _selected_visual_roots() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var visual: Node3D = cottage_visuals.get(selected_building_id)
	if is_instance_valid(visual): result.append(visual)
	return result

func _apply_style_preview() -> void:
	var key: Array = [selected_building_id, _style_picker_detail_id, _style_picker_mode, _style_preview_asset, _style_preview_colour, building_world.get_revision(), _presentation_key]
	if key == _style_render_key: return
	_style_render_key = key
	super._apply_style_preview()

func _apply_persisted_detail_colours() -> void:
	if not building_world: return
	var key := "%d|%s|%s" % [building_world.get_revision(), selected_building_id, _presentation_key]
	if key == _colour_render_key: return
	_colour_render_key = key
	for view in building_world.get_buildings():
		var visual: Node3D = cottage_visuals.get(str(view["id"]))
		if visual: _colour_view(view, visual)

func _colour_view(view: Dictionary, visual: Node3D) -> void:
	for detail in view.get("details", []):
		var colour_id := str(detail.get("override", {}).get("color_id", "natural"))
		if colour_id == "natural": continue
		for prefix in ["Joinery_", "Shutters_", "FlowerBox_", "ManualShutter_"]:
			var geometry := visual.get_node_or_null(prefix + str(detail["id"])) as GeometryInstance3D
			if geometry:
				var material := StandardMaterial3D.new()
				material.albedo_color = DETAIL_COLOURS.get(colour_id, DETAIL_COLOURS["natural"])
				geometry.material_override = material

func _update_presentation() -> void:
	if building_world and not selected_building_id.is_empty():
		var view: Dictionary = building_world.get_building(selected_building_id)
		if not view.is_empty():
			var visual: Node3D = cottage_visuals.get(selected_building_id)
			if not is_instance_valid(visual):
				visual = CottageVisualScript.new()
				visual.name = "CottageVisual_%s" % selected_building_id
				add_child(visual)
				cottage_visuals[selected_building_id] = visual
			cottage_visual = visual
		if _rendered_selection != selected_building_id:
			_rendered_selection = selected_building_id
			_presentation_key = ""
			_colour_render_key = ""
	super._update_presentation()
	if detail_move_active and placement_kind.is_empty():
		var key := "%s|%s|%s|%s|%d" % [selected_building_id, selected_detail_id, detail_move_surface_id, str(detail_move_position), building_world.get_revision()]
		if key != _move_render_key:
			_move_render_key = key
			var view: Dictionary = building_world.get_building(selected_building_id)
			for detail in view.get("details", []):
				if str(detail["id"]) != selected_detail_id: continue
				detail["resolved_position"] = detail_move_position
				detail["anchor"]["surface_id"] = detail_move_surface_id
				detail["visible"] = true
				detail["needs_placement"] = false
			cottage_visual.request_revision(building_world.get_revision())
			cottage_visual.apply_building(view, building_world.get_revision())
			_colour_view(view, cottage_visual)
	else:
		_move_render_key = ""

func _camera_facing_wall() -> String:
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty() or not camera: return ""
	var transform_value: Transform3D = view["transform"]
	var local_camera := transform_value.affine_inverse() * camera.global_position
	var normals := {"front": Vector3.FORWARD, "back": Vector3.BACK, "left": Vector3.LEFT, "right": Vector3.RIGHT}
	var best := -INF
	var result := ""
	for surface in view.get("surfaces", []):
		if str(surface.get("kind", "")) != "wall" or bool(surface.get("deleted", false)): continue
		var normal: Vector3 = normals.get(str(surface.get("orientation", "")), Vector3.ZERO)
		var score := normal.dot(local_camera.normalized())
		if score > best:
			best = score
			result = str(surface["id"])
	return result

func _begin_new_attachment(kind: String) -> void:
	_building_actions_open = false
	selected_surface_id = _camera_facing_wall()
	selected_detail_id = ""
	super._begin_new_attachment(kind)
	_detail_free_position = detail_move_position
	get_viewport().gui_release_focus()

func _begin_detail_move() -> void:
	super._begin_detail_move()
	_detail_free_position = detail_move_position
	_building_actions_open = false
	get_viewport().gui_release_focus()

func _cycle_attachment_surface(direction: int) -> void:
	super._cycle_attachment_surface(direction)
	_detail_free_position = detail_move_position

func _read_detail_move(delta: float) -> void:
	if not detail_move_active or resize_locked: return
	var view: Dictionary = building_world.get_building(selected_building_id)
	var support := WallPlacement.surface(view, detail_move_surface_id)
	if support.is_empty(): return
	var orientation := str(support.get("orientation", "front"))
	var axis := 0 if orientation in ["front", "back"] else 2
	var stick := Vector2(Input.get_axis("m1_move_left", "m1_move_right"), Input.get_axis("m1_move_up", "m1_move_down"))
	var transform_value: Transform3D = view["transform"]
	var tangent := (transform_value.basis * (Vector3.RIGHT if axis == 0 else Vector3.BACK)).normalized()
	var horizontal_sign := 1.0 if tangent.dot(camera.global_basis.x) >= 0 else -1.0
	var speed := (0.9 if precision_mode else 3.0) * pow(minf(stick.length(), 1.0), 0.45)
	_detail_free_position[axis] += stick.x * horizontal_sign * delta * speed
	_detail_free_position.y -= stick.y * delta * speed
	var record := _selected_detail_record()
	var kind := placement_kind if not placement_kind.is_empty() else str(record.get("kind", "window"))
	var asset := placement_asset_id if not placement_kind.is_empty() else str(record.get("asset_id", "window_wood"))
	var half := WallPlacement.footprint(kind, asset) if not placement_kind.is_empty() else WallPlacement.footprint_for_detail(record)
	var clamped := WallPlacement.clamp_to_wall(view, detail_move_surface_id, _detail_free_position, half)
	if clamped.is_empty(): return
	_detail_free_position = clamped["position"]
	var aligned := WallAlignment.align(view, selected_detail_id, detail_move_surface_id, _detail_free_position, precision_mode)
	var final := WallPlacement.clamp_to_wall(view, detail_move_surface_id, aligned["position"], half)
	detail_move_position = final.get("position", _detail_free_position)
	_alignment_tangent = bool(aligned.get("tangent", false))
	_alignment_height = bool(aligned.get("height", false))
	_alignment_tangent_source = str(aligned.get("tangent_source", ""))
	_alignment_height_source = str(aligned.get("height_source", ""))
	_update_alignment_hud()
	_update_presentation()

func _open_needs_placement() -> void:
	if _needs_details().is_empty(): return
	_building_actions_open = false
	_context_actions_open = false
	tools_open = true
	detail_open = false
	if tools_panel: tools_panel.visible = false
	if _building_panel: _building_panel.visible = false
	_needs_open = true
	_refresh_needs_placement_panel()
	var buttons := _needs_buttons()
	if not buttons.is_empty(): (buttons[0] as Button).grab_focus()

func _needs_buttons() -> Array:
	var result: Array = []
	if not _needs_box: return result
	for child in _needs_box.get_children():
		if child is Button and not child.is_queued_for_deletion(): result.append(child)
	return result

func _close_needs_placement() -> void:
	_needs_open = false
	tools_open = false
	if _needs_panel: _needs_panel.visible = false
	get_viewport().gui_release_focus()

func _refresh_needs_placement_panel() -> void:
	super._refresh_needs_placement_panel()
	if _needs_panel: _needs_panel.visible = _needs_open and not menu_open and not detail_move_active
	if _needs_action:
		var count := _needs_details().size()
		_needs_action.text = "Needs placement (%d)" % count
		_needs_action.disabled = count == 0

func _recover_needs_detail(detail_id: String) -> void:
	var found := false
	for detail in _needs_details():
		if str(detail["id"]) == detail_id: found = true
	if not found: return
	_close_needs_placement()
	selected_detail_id = detail_id
	var wall := _camera_facing_wall()
	_begin_detail_move()
	if not detail_move_active: return
	detail_move_surface_id = wall
	selected_surface_id = wall
	var record := _selected_detail_record()
	var view: Dictionary = building_world.get_building(selected_building_id)
	var half := WallPlacement.footprint_for_detail(record)
	var clamped := WallPlacement.nearest_available(view, detail_id, wall, detail_move_position, half)
	if clamped.is_empty():
		_cancel_detail_move()
		_set_status("This detail needs more clear wall before it can be placed")
		return
	detail_move_position = clamped["position"]
	_detail_free_position = detail_move_position
	_presentation_key = ""
	_update_presentation()
	_set_status("Recover detail • A place • B restore • left stick moves along wall")

func _commit_detail_move() -> bool:
	if not detail_move_active: return false
	var record := _selected_detail_record()
	var kind := placement_kind if not placement_kind.is_empty() else str(record.get("kind", "window"))
	var asset := placement_asset_id if not placement_kind.is_empty() else str(record.get("asset_id", "window_wood"))
	var view: Dictionary = building_world.get_building(selected_building_id)
	var half := WallPlacement.footprint(kind, asset) if not placement_kind.is_empty() else WallPlacement.footprint_for_detail(record)
	if not WallPlacement.position_available(view, selected_detail_id, detail_move_surface_id, detail_move_position, half):
		_set_status("Overlaps another edited detail • move to clear wall • B restores")
		return false
	return super._commit_detail_move()

func _set_menu(open: bool) -> void:
	if open:
		if not _style_picker_mode.is_empty(): _cancel_style_picker()
		_needs_open = false
		_building_actions_open = false
		_context_actions_open = false
	super._set_menu(open)

func _reload_all() -> bool:
	_cancel_current_edit("Reloading saved world")
	if not _style_picker_mode.is_empty(): _cancel_style_picker()
	_context_actions_open = false
	_building_actions_open = false
	_needs_open = false
	if _layer_query: _layer_query.invalidate()
	_layer_key.clear()
	_layer_plan = {}
	_preview_key = ""
	_terrain_target_valid = false
	stroke_reference.clear()
	stroke_aim_offset = Vector3.ZERO
	var ok := super._reload_all()
	if not ok: return false
	if building_world.get_building(selected_building_id).is_empty():
		var buildings: Array = building_world.get_buildings()
		selected_building_id = str(buildings[0]["id"]) if not buildings.is_empty() else ""
	selected_detail_id = ""
	selected_surface_id = ""
	_clear_hover()
	_presentation_key = ""
	_colour_render_key = ""
	_needs_signature = ""
	_reacquire_saved_terrain()
	_update_presentation()
	_set_status("Saved world restored • resume to continue editing")
	return true

func _reacquire_saved_terrain() -> void:
	if not backend or not backend.is_ready(): return
	# One bounded column scan at reload, not a radius-cubed per-frame fallback.
	# A brush left at the bottom of an excavation may now be inside saved land.
	var hint := cursor if view_context == "terrain" else terrain_cursor
	var unit := float(backend.voxel_scale)
	var patch: Vector3i = backend.patch_size
	hint = hint.clamp(Vector3.ONE * unit, Vector3(patch - Vector3i.ONE) * unit)
	var base := Vector3i((hint / unit).floor())
	var best := INF
	var point := hint
	for y in range(patch.y - 1):
		var cell := Vector3i(base.x, y, base.z)
		if backend.voxel_at(cell) == 0 or backend.voxel_at(cell + Vector3i.UP) != 0: continue
		var height := float(y + 1) * unit
		var distance := absf(height - hint.y)
		if distance < best:
			best = distance
			point.y = height
	if best == INF: return
	terrain_cursor = point
	if view_context == "terrain": cursor = point
	_terrain_target_point = point
	_terrain_target_normal = Vector3.UP
	_terrain_target_valid = true
	reference_mode = "ground"

func set_brush_strength_level(level: int) -> void:
	super.set_brush_strength_level(level)
	_strength_by_tool[sculpt_tool] = brush_strength_level

func _set_sculpt_tool(tool: String) -> bool:
	_strength_by_tool[sculpt_tool] = brush_strength_level
	var changed := super._set_sculpt_tool(tool)
	if changed: set_brush_strength_level(int(_strength_by_tool.get(sculpt_tool, 5)))
	return changed

func _set_prompts(prompts: Array) -> void:
	if not _prompt_row or _prompt_row.get_meta("signature", "") == JSON.stringify(prompts): return
	# Immediate detachment prevents two prompt sets coexisting for one frame.
	for child in _prompt_row.get_children():
		_prompt_row.remove_child(child)
		child.queue_free()
	super._set_prompts(prompts)

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if _building_panel:
		_building_panel.visible = _building_actions_open and tools_open and view_context == "building" and not menu_open and _style_picker_mode.is_empty() and not _needs_open
	if not _tool_name or not _prompt_row or menu_open: return
	if view_context != "building": return
	if _needs_open:
		_set_prompts([["A", "Recover"], ["B", "Back"], ["D-PAD", "Choose detail"], ["RS", "Orbit"]])
		return
	if not _style_picker_mode.is_empty():
		_set_prompts([["A", "Apply"], ["B", "Restore"], ["D-PAD", "Preview"], ["RS", "Orbit"]])
		return
	if tools_open or detail_open or detail_move_active or resize_active: return
	if building_placement_active:
		_tool_meta.text = "%s%s%s" % [building_placement_reason, " • SNAP" if building_rotation_snap else " • FREE", " • PRECISION" if precision_mode else ""]
		_set_prompts([["A", "Place"], ["B", "Cancel"], ["LS", "Move"], ["◀▶", "Turn"], ["▲", "Snap"], ["RS", "Orbit"], ["L3", "Fine"]])
		return
	var prompts: Array = [["B", "Finish editing"], ["X", "Cottage options"], ["RS", "Orbit"], ["LT/RT", "Zoom"]]
	if not hovered_detail_id.is_empty():
		prompts = [["A", "Move"], ["X", "Detail options"], ["B", "Finish editing"], ["RS", "Orbit"]]
	elif _shell_hovered:
		prompts.push_front(["A", "Resize"])
	if building_world.get_buildings().size() > 1: prompts.append(["LEFT/RIGHT", "Cottage"])
	_set_prompts(prompts)
	_tool_meta.text = "%s • only this cottage is editable" % selected_building_id
