extends "res://scripts/m1_scene_building_camera.gd"
## Direct-manipulation cottage editing layer. Building mode uses a screen-space
## pointer for detail targeting while the camera remains anchored to the cottage.

const DETAIL_PICK_RADIUS_PX := 86.0
const POINTER_MARGIN := 42.0
const POINTER_SPEED := 620.0

var edit_pointer := Vector2.ZERO
var hovered_detail_id := ""
var hovered_surface_id := ""
var hovered_detail_kind := ""
var hovered_detail_position := Vector3.ZERO
var _context_actions_open := false
var _pointer_label: Label
var _hover_marker: MeshInstance3D

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
	# Building editing is screen-space targeting: left stick moves the pointer,
	# right stick orbits the stable cottage pivot, triggers zoom.
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
		_clear_hover()
	elif changed:
		_clear_hover()
	return changed

func _reset_edit_pointer() -> void:
	var size := get_viewport().get_visible_rect().size
	edit_pointer = size * 0.5
	_clamp_edit_pointer()

func _clamp_edit_pointer() -> void:
	var size := get_viewport().get_visible_rect().size
	edit_pointer.x = clampf(edit_pointer.x, POINTER_MARGIN, maxf(POINTER_MARGIN, size.x - POINTER_MARGIN))
	edit_pointer.y = clampf(edit_pointer.y, POINTER_MARGIN, maxf(POINTER_MARGIN, size.y - POINTER_MARGIN))

func _create_edit_pointer() -> void:
	_pointer_label = Label.new()
	_pointer_label.name = "CottageEditPointer"
	_pointer_label.text = "＋"
	_pointer_label.add_theme_font_size_override("font_size", 32)
	_pointer_label.add_theme_color_override("font_color", Color("#fff2c2"))
	_pointer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_pointer_label)

func _create_hover_marker() -> void:
	_hover_marker = MeshInstance3D.new()
	_hover_marker.name = "CottageDetailHoverMarker"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.65, 0.65, 0.22)
	_hover_marker.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.78, 0.32, 0.32)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.66, 0.22)
	material.emission_energy_multiplier = 0.7
	_hover_marker.material_override = material
	_hover_marker.visible = false
	add_child(_hover_marker)

func _update_detail_hover() -> void:
	if view_context != "building" or menu_open or tools_open or detail_open or detail_move_active or resize_active or building_placement_active or _restoring or not camera:
		_clear_hover()
		return
	var candidate := _pick_detail_at_screen_position(edit_pointer)
	if candidate.is_empty():
		_clear_hover()
		return
	hovered_detail_id = str(candidate.get("id", ""))
	hovered_surface_id = str(candidate.get("surface_id", ""))
	hovered_detail_kind = str(candidate.get("kind", "detail"))
	hovered_detail_position = candidate.get("world_position", Vector3.ZERO)
	if _hover_marker:
		_hover_marker.visible = true
		_hover_marker.global_position = hovered_detail_position
		var footprint := _hover_marker_size(hovered_detail_kind)
		(_hover_marker.mesh as BoxMesh).size = footprint

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
		orientations[str(surface.get("id", ""))] = str(surface.get("orientation", "front"))
	var best: Dictionary = {}
	var best_distance := DETAIL_PICK_RADIUS_PX * DETAIL_PICK_RADIUS_PX
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)):
			continue
		var local = detail.get("resolved_position", null)
		if not local is Vector3:
			continue
		var world_position: Vector3 = building_transform * (local as Vector3)
		if camera.is_position_behind(world_position):
			continue
		var surface_id := str(detail.get("anchor", {}).get("surface_id", ""))
		var orientation := str(orientations.get(surface_id, "front"))
		var outward_local := _surface_basis(orientation) * Vector3.FORWARD
		var outward_world := (building_transform.basis * outward_local).normalized()
		var toward_camera := (camera.global_position - world_position).normalized()
		# Never select details through the cottage from the opposite wall.
		if outward_world.dot(toward_camera) <= 0.04:
			continue
		var projected := camera.unproject_position(world_position)
		var distance := projected.distance_squared_to(screen_position)
		if distance < best_distance:
			best_distance = distance
			best = {"id": str(detail.get("id", "")), "kind": str(detail.get("kind", "detail")), "surface_id": surface_id, "world_position": world_position, "screen_position": projected, "distance_sq": distance}
	return best

func _hover_marker_size(kind: String) -> Vector3:
	match kind:
		"window": return Vector3(0.62, 0.86, 0.20)
		"flower_box": return Vector3(0.55, 0.28, 0.30)
		"shutter": return Vector3(0.28, 0.82, 0.20)
		_: return Vector3(0.50, 0.50, 0.22)

func _clear_hover() -> void:
	hovered_detail_id = ""
	hovered_surface_id = ""
	hovered_detail_kind = ""
	hovered_detail_position = Vector3.ZERO
	if _hover_marker:
		_hover_marker.visible = false

func _select_hovered_detail() -> bool:
	if hovered_detail_id.is_empty():
		return false
	selected_detail_id = hovered_detail_id
	selected_surface_id = hovered_surface_id
	return true

func _begin_hovered_detail_move() -> bool:
	if not _select_hovered_detail():
		return false
	_begin_detail_move()
	if detail_move_active:
		_set_status("Move %s • left stick along wall • A place / B restore • right stick orbit" % hovered_detail_kind.replace("_", " "))
		return true
	return false

func _open_hovered_detail_actions() -> bool:
	if not _select_hovered_detail():
		return false
	_context_actions_open = true
	tools_open = true
	detail_open = false
	if tools_panel:
		tools_panel.visible = true
	_update_action_buttons()
	var buttons := _visible_action_buttons()
	if not buttons.is_empty():
		(buttons[0] as Button).grab_focus()
	_set_status("%s options • A choose / B close • right stick orbit" % hovered_detail_kind.replace("_", " ").capitalize())
	return true

func _update_action_buttons() -> void:
	super._update_action_buttons()
	# Restore human-facing labels whenever this layer refreshes the inherited
	# buttons. Their bound action keys remain unchanged.
	if _tool_buttons.has("Move selected window"): (_tool_buttons["Move selected window"] as Button).text = "Move"
	if _tool_buttons.has("Replace selected"): (_tool_buttons["Replace selected"] as Button).text = "Variation"
	if _tool_buttons.has("Suppress / restore"): (_tool_buttons["Suppress / restore"] as Button).text = "Remove"
	if _tool_buttons.has("Close"): (_tool_buttons["Close"] as Button).text = "Close"
	if not _context_actions_open:
		return
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
			_pointer_label.position = edit_pointer - Vector2(16, 22)
			_pointer_label.modulate = Color("#ffd069") if not hovered_detail_id.is_empty() else Color("#fff4c7")
	if view_context != "building" or not target_label:
		return
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
