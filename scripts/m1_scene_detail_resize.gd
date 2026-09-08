extends "res://scripts/m1_scene_house_actions.gd"
## Window and door dimensions are recipe overrides. Browsing is render-only;
## apply creates one BuildingWorld transaction and cancel restores exactly.

var detail_resize_active := false
var detail_resize_size := Vector2.ZERO
var _detail_resize_raw := Vector2.ZERO
var _detail_resize_original := Vector2.ZERO
var _detail_resize_button: Button

func _ready() -> void:
	super._ready()
	var box := _actions_box()
	if not box: return
	_detail_resize_button = Button.new()
	_detail_resize_button.name = "DetailResizeAction"
	_detail_resize_button.text = "Resize"
	_detail_resize_button.focus_mode = Control.FOCUS_ALL
	_detail_resize_button.custom_minimum_size = Vector2(0, 42)
	_detail_resize_button.pressed.connect(_begin_detail_resize)
	box.add_child(_detail_resize_button)
	_tool_buttons["Resize detail"] = _detail_resize_button

func _process(delta: float) -> void:
	super._process(delta)
	if detail_resize_active and not menu_open:
		_read_detail_resize(delta)
		_update_presentation()
		_refresh_controller_hud()

func _input(event: InputEvent) -> void:
	if detail_resize_active:
		if event.is_action_pressed("m1_accept"):
			_commit_detail_resize()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_cancel"):
			_cancel_detail_resize()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_precision"):
			precision_mode = not precision_mode
			_set_status("Detail resize precision %s" % ("ON" if precision_mode else "OFF"))
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_pause"):
			_cancel_detail_resize()
			super._input(event)
			return
		# Mode switches, menus and history cannot interrupt a live preview.
		if event.is_pressed():
			get_viewport().set_input_as_handled()
		return
	super._input(event)

func _read_camera_and_cursor(delta: float) -> void:
	if not detail_resize_active:
		super._read_camera_and_cursor(delta)
		return
	var orbit_x := Input.get_axis("m1_orbit_left", "m1_orbit_right")
	var orbit_y := Input.get_axis("m1_orbit_up", "m1_orbit_down")
	camera_yaw += orbit_x * delta * 2.2
	camera_pitch = clampf(camera_pitch + orbit_y * delta * 1.5, 0.08, 1.40)
	var zoom := Input.get_axis("m1_zoom_out", "m1_zoom_in")
	camera_distance = clampf(camera_distance - zoom * delta * 18.0, BUILDING_CAMERA_MIN_DISTANCE, BUILDING_CAMERA_MAX_DISTANCE)

func _update_action_buttons() -> void:
	super._update_action_buttons()
	if _detail_resize_button:
		var show := _context_actions_open and hovered_detail_kind in ["window", "door"]
		_detail_resize_button.visible = show
		_detail_resize_button.disabled = not show

func _begin_detail_resize() -> void:
	var detail := _selected_detail_record()
	if detail.is_empty() or str(detail.get("kind", "")) not in ["window", "door"]: return
	_detail_resize_original = WallPlacement.detail_size(detail)
	detail_resize_size = _detail_resize_original
	_detail_resize_raw = detail_resize_size
	detail_resize_active = true
	_context_actions_open = false
	tools_open = false
	detail_open = false
	if tools_panel: tools_panel.visible = false
	get_viewport().gui_release_focus()
	_clear_hover()
	_set_status("Resize %s • left stick width / height • A apply / B restore" % str(detail.get("kind", "detail")))
	_update_presentation()

func _read_detail_resize(delta: float) -> void:
	var stick := Vector2(Input.get_axis("m1_move_left", "m1_move_right"), Input.get_axis("m1_move_up", "m1_move_down"))
	if stick.length() <= 0.05: return
	var detail := _selected_detail_record()
	if detail.is_empty():
		_cancel_detail_resize()
		return
	var speed := (1.0 if precision_mode else 3.0) * pow(minf(stick.length(), 1.0), 0.7)
	_detail_resize_raw.x += stick.x * delta * speed
	_detail_resize_raw.y -= stick.y * delta * speed
	var kind := str(detail.get("kind", "window"))
	var minimum := Vector2(1.0, 1.0) if kind == "window" else Vector2(1.5, 2.5)
	var maximum := Vector2(4.0, 5.0) if kind == "window" else Vector2(3.5, 5.5)
	var view: Dictionary = building_world.get_building(selected_building_id)
	var support := WallPlacement.surface(view, str(detail.get("anchor", {}).get("surface_id", "")))
	var position: Vector3 = detail.get("resolved_position", Vector3.ZERO)
	var dimensions: Vector3 = view.get("dimensions", Vector3.ZERO)
	var orientation := str(support.get("orientation", "front"))
	var tangent := absf(position.x) if orientation in ["front", "back"] else absf(position.z)
	var extent := dimensions.x if orientation in ["front", "back"] else dimensions.z
	var clearance := Vector2(0.3, 0.3) if kind == "window" and str(detail.get("asset_id", "")).contains("round") else Vector2(0.375, 0.67) if kind == "window" else Vector2(0.38, 0.0)
	maximum.x = minf(maximum.x, 2.0 * maxf(0.0, extent * 0.5 - tangent - clearance.x))
	maximum.y = minf(maximum.y, 2.0 * maxf(0.0, minf(position.y, dimensions.y - position.y) - clearance.y))
	maximum = maximum.max(minimum)
	_detail_resize_raw = _detail_resize_raw.clamp(minimum, maximum)
	var step := 0.25 if precision_mode else 0.5
	detail_resize_size = Vector2(snappedf(_detail_resize_raw.x, step), snappedf(_detail_resize_raw.y, step)).clamp(minimum, maximum)

func _commit_detail_resize() -> bool:
	if not detail_resize_active: return false
	var changed := not detail_resize_size.is_equal_approx(_detail_resize_original)
	var ok: bool = changed and building_world.resize_detail(selected_building_id, selected_detail_id, detail_resize_size)
	detail_resize_active = false
	if ok: _record_history("building")
	_presentation_key = ""
	_set_status("Detail resized" if ok else "Size unchanged")
	_update_presentation()
	return ok

func _cancel_detail_resize() -> void:
	if not detail_resize_active: return
	detail_resize_active = false
	detail_resize_size = _detail_resize_original
	_presentation_key = ""
	_set_status("Detail resize cancelled")
	_update_presentation()

func _update_detail_hover() -> void:
	if detail_resize_active:
		_clear_hover()
		return
	super._update_detail_hover()

func _update_presentation() -> void:
	super._update_presentation()
	if not detail_resize_active: return
	var presentation: Dictionary = building_world.get_building(selected_building_id)
	for detail in presentation.get("details", []):
		if str(detail.get("id", "")) != selected_detail_id: continue
		var overrides: Dictionary = detail.get("override", {})
		overrides["size"] = [detail_resize_size.x, detail_resize_size.y]
		detail["override"] = overrides
	var revision: int = building_world.get_revision()
	for visual in _selected_visual_roots():
		visual.request_revision(revision)
		visual.apply_building(presentation, revision)
		_colour_view(presentation, visual)

func _cancel_current_edit(reason: String) -> void:
	if detail_resize_active: _cancel_detail_resize()
	super._cancel_current_edit(reason)

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if not detail_resize_active or not _tool_name: return
	_tool_name.text = "Resize detail"
	_tool_meta.text = "%.2f × %.2f%s" % [detail_resize_size.x, detail_resize_size.y, " • PRECISION" if precision_mode else ""]
	_set_prompts([["A", "Apply"], ["B", "Restore"], ["LS", "Width / height"], ["RS", "Orbit"], ["L3", "Precision"]])
