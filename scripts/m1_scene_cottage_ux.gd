extends "res://scripts/m1_scene_building_camera.gd"
## Direct-manipulation cottage editing. The picker, outline and action prompt
## refer to one detail on the selected building, never an arbitrary nearby ID.

const DETAIL_PICK_RADIUS_PX := 86.0
const DETAIL_PICK_PADDING_PX := 10.0
const POINTER_MARGIN := 42.0
const POINTER_SPEED := 620.0

var edit_pointer := Vector2.ZERO
var hovered_detail_id := ""
var hovered_surface_id := ""
var hovered_detail_kind := ""
var hovered_detail_position := Vector3.ZERO
var _hovered_building_id := ""
var _hover_bounds := Rect2()
var _context_actions_open := false
var _pointer_label: Label
var _hover_marker: MeshInstance3D
var _hover_outline: Panel
var _hover_prompt: Label

func _ready() -> void:
	super._ready()
	_create_edit_pointer()
	_create_hover_marker()
	_reset_edit_pointer()

func _process(delta: float) -> void:
	super._process(delta)
	_update_detail_hover()
	_update_direct_edit_hud()

func _input(event: InputEvent) -> void:
	if _shutting_down:
		return
	if view_context == "building" and not menu_open and not tools_open and not detail_open and not detail_move_active and not resize_active and not building_placement_active:
		if event.is_action_pressed("m1_accept") and not hovered_detail_id.is_empty():
			_begin_hovered_detail_move()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_tools") and not hovered_detail_id.is_empty():
			_open_hovered_detail_actions()
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _read_camera_and_cursor(delta: float) -> void:
	if view_context != "building" or building_placement_active or detail_move_active or resize_active:
		super._read_camera_and_cursor(delta)
		return
	var move := Vector2(Input.get_axis("m1_move_left", "m1_move_right"), Input.get_axis("m1_move_up", "m1_move_down"))
	if move.length() > 0.05:
		var magnitude := minf(move.length(), 1.0)
		edit_pointer += move.normalized() * pow(magnitude, 1.35) * delta * POINTER_SPEED * (0.35 if precision_mode else 1.0)
		_clamp_edit_pointer()
	var orbit_x := Input.get_axis("m1_orbit_left", "m1_orbit_right")
	var orbit_y := Input.get_axis("m1_orbit_up", "m1_orbit_down")
	camera_yaw += orbit_x * delta * 2.2
	camera_pitch = clampf(camera_pitch + orbit_y * delta * 1.5, 0.08, 1.40)
	var zoom := Input.get_axis("m1_zoom_out", "m1_zoom_in")
	camera_distance = clampf(camera_distance - zoom * delta * 18.0, BUILDING_CAMERA_MIN_DISTANCE, BUILDING_CAMERA_MAX_DISTANCE)
	if Input.is_action_just_pressed("m1_focus"):
		_focus_selected_building()
	if Input.is_action_just_pressed("m1_debug") and debug_label:
		debug_label.visible = not debug_label.visible

func _set_view_context(next_context: String, reason: String = "Context changed") -> bool:
	var changed := super._set_view_context(next_context, reason)
	if changed and view_context == "building":
		_reset_edit_pointer()
	if changed:
		_clear_hover()
	return changed

func _reset_edit_pointer() -> void:
	edit_pointer = get_viewport().get_visible_rect().size * 0.5
	_clamp_edit_pointer()

func _clamp_edit_pointer() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	edit_pointer.x = clampf(edit_pointer.x, POINTER_MARGIN, maxf(POINTER_MARGIN, viewport_size.x - POINTER_MARGIN))
	edit_pointer.y = clampf(edit_pointer.y, POINTER_MARGIN, maxf(POINTER_MARGIN, viewport_size.y - POINTER_MARGIN))

func _create_edit_pointer() -> void:
	# Keep the existing node reference, but draw the pointer with rectangles.
	# A full-width Unicode plus depended on desktop font fallback on Android.
	_pointer_label = Label.new()
	_pointer_label.name = "CottageEditPointer"
	_pointer_label.text = ""
	_pointer_label.size = Vector2(32, 32)
	_pointer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_pointer_label)
	for spec in [
		[Vector2(2, 13), Vector2(28, 6), Color("#17231c")],
		[Vector2(13, 2), Vector2(6, 28), Color("#17231c")],
		[Vector2(3, 15), Vector2(26, 2), Color("#fff4c7")],
		[Vector2(15, 3), Vector2(2, 26), Color("#fff4c7")],
	]:
		var line := ColorRect.new()
		line.position = spec[0]
		line.size = spec[1]
		line.color = spec[2]
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pointer_label.add_child(line)

func _create_hover_marker() -> void:
	# Screen-space feedback stays legible at miniature scale and follows the
	# selected wall's projected bounds instead of a world-aligned translucent box.
	_hover_outline = Panel.new()
	_hover_outline.name = "CottageDetailOutline"
	_hover_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color(1.0, 0.80, 0.36, 0.10)
	outline.border_color = Color("#ffd069")
	outline.set_border_width_all(2)
	_hover_outline.add_theme_stylebox_override("panel", outline)
	_hover_outline.visible = false
	hud.add_child(_hover_outline)
	_hover_prompt = Label.new()
	_hover_prompt.name = "CottageDetailActionPrompt"
	_hover_prompt.add_theme_font_size_override("font_size", 18)
	_hover_prompt.add_theme_color_override("font_color", Color("#fff4c7"))
	_hover_prompt.add_theme_color_override("font_shadow_color", Color("#101a14"))
	_hover_prompt.add_theme_constant_override("shadow_offset_x", 2)
	_hover_prompt.add_theme_constant_override("shadow_offset_y", 2)
	_hover_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_prompt.visible = false
	hud.add_child(_hover_prompt)

func _update_cursor_reticle() -> void:
	if view_context == "building":
		if cursor_reticle: cursor_reticle.set_target_visible(false)
		if brush_preview: brush_preview.visible = false
		if terrain_hit_marker: terrain_hit_marker.visible = false
		if reference_plane: reference_plane.visible = false
		return
	super._update_cursor_reticle()

func _update_detail_hover() -> void:
	if view_context != "building" or menu_open or tools_open or detail_open or detail_move_active or resize_active or building_placement_active or _restoring or not camera:
		_clear_hover()
		return
	var candidate := _pick_detail_at_screen_position(edit_pointer)
	if candidate.is_empty():
		_clear_hover()
		return
	_hovered_building_id = str(candidate["building_id"])
	hovered_detail_id = str(candidate["id"])
	hovered_surface_id = str(candidate["surface_id"])
	hovered_detail_kind = str(candidate["kind"])
	hovered_detail_position = candidate["world_position"]
	_hover_bounds = candidate["screen_bounds"]
	if _hover_outline:
		_hover_outline.position = _hover_bounds.position
		_hover_outline.size = _hover_bounds.size
		_hover_outline.visible = true
	if _hover_prompt:
		_hover_prompt.text = "%s   A Move   X Options" % hovered_detail_kind.replace("_", " ").capitalize()
		var viewport_size := get_viewport().get_visible_rect().size
		_hover_prompt.position = Vector2(clampf(_hover_bounds.position.x, 16.0, maxf(16.0, viewport_size.x - 300.0)), maxf(16.0, _hover_bounds.position.y - 28.0))
		_hover_prompt.visible = true

func _pick_detail_at_screen_position(screen_position: Vector2) -> Dictionary:
	if not building_world or not camera:
		return {}
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty():
		return {}
	var transform_value = view.get("transform", Transform3D.IDENTITY)
	var building_transform: Transform3D = transform_value if transform_value is Transform3D else Transform3D.IDENTITY
	var orientations := {}
	for surface_value in view.get("surfaces", []):
		var surface: Dictionary = surface_value
		if bool(surface.get("deleted", false)): continue
		orientations[str(surface.get("id", ""))] = str(surface.get("orientation", "front"))
	var best: Dictionary = {}
	var best_distance := INF
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)):
			continue
		var local = detail.get("resolved_position", null)
		if not local is Vector3:
			continue
		var surface_id := str(detail.get("anchor", {}).get("surface_id", ""))
		if not orientations.has(surface_id): continue
		var orientation := str(orientations[surface_id])
		var anchor_center: Vector3 = local
		var visual: Node3D = cottage_visuals.get(selected_building_id)
		if str(detail.get("kind", "")) == "window" and visual and visual.has_method("_window_layout"):
			var layout: Dictionary = visual._window_layout(detail, anchor_center, orientation)
			anchor_center = layout.get("anchor_center", anchor_center)
		var world_position: Vector3 = building_transform * anchor_center
		if camera.is_position_behind(world_position):
			continue
		# Authored detail meshes extrude in local +Z. FORWARD (-Z) was inward:
		# it accepted rear-wall details and rejected the wall the player sees.
		var outward_local: Vector3 = _orientation_basis(orientation) * Vector3.BACK
		var outward_world: Vector3 = (building_transform.basis.inverse().transposed() * outward_local).normalized()
		if outward_world.dot((camera.global_position - world_position).normalized()) <= 0.04:
			continue
		var bounds := _detail_screen_bounds(detail, anchor_center, orientation, building_transform)
		if bounds.size == Vector2.ZERO or not bounds.grow(DETAIL_PICK_PADDING_PX).has_point(screen_position):
			continue
		var projected := camera.unproject_position(world_position)
		# Exact footprint beats padded near-miss; then resolve neighbouring details
		# by distance. An 86px centre magnet could pick boxes over visible windows.
		var distance := projected.distance_squared_to(screen_position)
		if not bounds.has_point(screen_position): distance += 1000000.0
		if distance < best_distance:
			best_distance = distance
			best = {"building_id": selected_building_id, "id": str(detail.get("id", "")), "kind": str(detail.get("kind", "detail")), "surface_id": surface_id, "world_position": world_position, "screen_position": projected, "screen_bounds": bounds, "distance_sq": distance}
	return best

func _detail_screen_bounds(detail: Dictionary, local: Vector3, orientation: String, building_transform: Transform3D) -> Rect2:
	var half := WallPlacement.footprint_for_detail(detail)
	var wall_basis := _orientation_basis(orientation)
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			var point := building_transform * (local + wall_basis * Vector3(x * half.x, y * half.y, 0.0))
			if camera.is_position_behind(point): return Rect2()
			var projected := camera.unproject_position(point)
			min_point = min_point.min(projected)
			max_point = max_point.max(projected)
	return Rect2(min_point, max_point - min_point)

func _orientation_basis(orientation: String) -> Basis:
	if orientation == "front": return Basis(Vector3.UP, PI)
	if orientation == "left": return Basis(Vector3.UP, -PI * 0.5)
	if orientation == "right": return Basis(Vector3.UP, PI * 0.5)
	return Basis.IDENTITY

func _hover_marker_size(kind: String) -> Vector3:
	match kind:
		"window": return Vector3(0.62, 0.86, 0.20)
		"flower_box": return Vector3(0.55, 0.28, 0.30)
		"shutter": return Vector3(0.28, 0.82, 0.20)
		_: return Vector3(0.50, 0.50, 0.22)

func _clear_hover() -> void:
	_hovered_building_id = ""
	_hover_bounds = Rect2()
	hovered_detail_id = ""
	hovered_surface_id = ""
	hovered_detail_kind = ""
	hovered_detail_position = Vector3.ZERO
	if _hover_marker: _hover_marker.visible = false
	if _hover_outline: _hover_outline.visible = false
	if _hover_prompt: _hover_prompt.visible = false

func _select_hovered_detail() -> bool:
	if hovered_detail_id.is_empty() or (not _hovered_building_id.is_empty() and _hovered_building_id != selected_building_id):
		return false
	var view: Dictionary = building_world.get_building(selected_building_id)
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("id", "")) == hovered_detail_id and bool(detail.get("visible", false)) and not bool(detail.get("needs_placement", false)):
			selected_detail_id = hovered_detail_id
			selected_surface_id = str(detail.get("anchor", {}).get("surface_id", ""))
			return true
	return false

func _begin_hovered_detail_move() -> bool:
	if not _select_hovered_detail(): return false
	_begin_detail_move()
	if detail_move_active:
		_set_status("Move %s • left stick along wall • A place / B restore • right stick orbit" % hovered_detail_kind.replace("_", " "))
		return true
	return false

func _open_hovered_detail_actions() -> bool:
	if not _select_hovered_detail(): return false
	_context_actions_open = true
	tools_open = true
	detail_open = false
	if tools_panel: tools_panel.visible = true
	_update_action_buttons()
	var buttons := _visible_action_buttons()
	if not buttons.is_empty(): (buttons[0] as Button).grab_focus()
	_set_status("%s options • A choose / B close • right stick orbit" % hovered_detail_kind.replace("_", " ").capitalize())
	return true

func _visible_action_buttons() -> Array:
	var result: Array = []
	if not tools_panel: return result
	for node in tools_panel.find_children("*", "Button", true, false):
		var button := node as Button
		if button.visible and not button.disabled: result.append(button)
	return result

func _update_action_buttons() -> void:
	super._update_action_buttons()
	if _tool_buttons.has("Move selected window"): (_tool_buttons["Move selected window"] as Button).text = "Move"
	if _tool_buttons.has("Replace selected"): (_tool_buttons["Replace selected"] as Button).text = "Variation"
	if _tool_buttons.has("Suppress / restore"): (_tool_buttons["Suppress / restore"] as Button).text = "Remove"
	if _tool_buttons.has("Close"): (_tool_buttons["Close"] as Button).text = "Close"
	if not _context_actions_open: return
	var allowed := ["Move selected window", "Suppress / restore", "Close"]
	if hovered_detail_kind == "window": allowed.insert(1, "Replace selected")
	for key in _tool_buttons.keys():
		var button := _tool_buttons[key] as Button
		button.visible = str(key) in allowed
		button.disabled = not button.visible

func _tool_choice(choice: String) -> void:
	if _context_actions_open and choice in ["Move selected window", "Replace selected", "Suppress / restore", "Close"]:
		_context_actions_open = false
		if choice == "Move selected window":
			tools_open = false
			detail_open = false
			if tools_panel: tools_panel.visible = false
			_begin_detail_move()
			return
	super._tool_choice(choice)

func _handle_overlay_input(event: InputEvent) -> void:
	if _context_actions_open and event.is_action_pressed("m1_cancel"):
		_context_actions_open = false
		tools_open = false
		detail_open = false
		if tools_panel: tools_panel.visible = false
		_set_status("Detail options closed")
		get_viewport().set_input_as_handled()
		return
	super._handle_overlay_input(event)

func _update_direct_edit_hud() -> void:
	if _pointer_label:
		_pointer_label.visible = view_context == "building" and not menu_open and not tools_open and not detail_open and not detail_move_active and not resize_active and not building_placement_active
		if _pointer_label.visible:
			_pointer_label.position = edit_pointer - Vector2(16, 16)
	if view_context != "building" or not target_label: return
	if detail_move_active:
		target_label.text = "Move %s • left stick along wall • A place • B restore • right stick orbit • R3 reframe" % selected_detail_id
	elif not hovered_detail_id.is_empty() and not tools_open and not detail_open:
		target_label.text = "%s • A move • X options • right stick orbit • triggers zoom • ▲ Terrain" % hovered_detail_kind.replace("_", " ").capitalize()
	elif not tools_open and not detail_open and not resize_active:
		target_label.text = "Point at a detail • A move • X options • A on cottage shell resizes • right stick orbit • ▲ Terrain"

func _set_status(message: String) -> void:
	super._set_status(message)
	if context_label and view_context == "building":
		context_label.text = "BUILDING • ▲ Terrain/Building • A direct edit • X options • right stick orbit"
