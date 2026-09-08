extends "res://scripts/m1_scene_cottage_alignment.gd"

var _shell_hovered := false
var _needs_panel: PanelContainer
var _needs_box: VBoxContainer
var _needs_signature := ""

func _ready() -> void:
	super._ready()
	_build_needs_placement_panel()

func _process(delta: float) -> void:
	super._process(delta)
	_shell_hovered = _pointer_over_selected_shell() if view_context == "building" and not detail_move_active and not resize_active else false
	_refresh_needs_placement_panel()
	_update_shell_hud()

func _input(event: InputEvent) -> void:
	if _shutting_down:
		return
	# Make the advertised interaction literal: A only starts shell resizing when
	# the edit pointer is actually over the selected cottage and no detail owns
	# that target. Outside the cottage A does nothing rather than entering a
	# surprise resize mode.
	if view_context == "building" and not menu_open and not tools_open and not detail_open and not detail_move_active and not resize_active and not building_placement_active and event.is_action_pressed("m1_accept") and hovered_detail_id.is_empty():
		if _shell_hovered:
			_begin_resize()
			_set_status("Resize cottage • left stick changes size • D-pad left/right axis • A apply / B cancel")
		else:
			_set_status("No building detail or shell under pointer")
		get_viewport().set_input_as_handled()
		return
	super._input(event)

func _pointer_over_selected_shell() -> bool:
	if not camera or not building_world:
		return false
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty():
		return false
	var transform_value = view.get("transform", Transform3D.IDENTITY)
	var building_transform: Transform3D = transform_value if transform_value is Transform3D else Transform3D.IDENTITY
	var dims: Vector3 = view.get("dimensions", Vector3.ONE)
	var projected: Array[Vector2] = []
	for x in [-0.5, 0.5]:
		for y in [0.0, 1.0]:
			for z in [-0.5, 0.5]:
				var point := building_transform * Vector3(dims.x * x, dims.y * y, dims.z * z)
				if not camera.is_position_behind(point):
					projected.append(camera.unproject_position(point))
	if projected.is_empty():
		return false
	var min_point := projected[0]
	var max_point := projected[0]
	for point in projected:
		min_point = min_point.min(point)
		max_point = max_point.max(point)
	var rect := Rect2(min_point - Vector2(18, 18), max_point - min_point + Vector2(36, 36))
	return rect.has_point(edit_pointer)

func _build_needs_placement_panel() -> void:
	_needs_panel = PanelContainer.new()
	_needs_panel.name = "NeedsPlacementTray"
	_needs_panel.position = Vector2(920, 360)
	_needs_panel.size = Vector2(330, 250)
	_needs_panel.visible = false
	hud.add_child(_needs_panel)
	_needs_box = VBoxContainer.new()
	_needs_box.add_theme_constant_override("separation", 6)
	_needs_panel.add_child(_needs_box)

func _needs_details() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not building_world:
		return result
	var view: Dictionary = building_world.get_building(selected_building_id)
	for value in view.get("details", []):
		var detail: Dictionary = value
		if bool(detail.get("needs_placement", false)) and str(detail.get("state", "")) != "suppressed":
			result.append(detail)
	return result

func _refresh_needs_placement_panel() -> void:
	if not _needs_panel or not _needs_box:
		return
	var needs := _needs_details()
	var ids: Array[String] = []
	for detail in needs:
		ids.append(str(detail.get("id", "")))
	var signature := "%s|%s|%s" % [selected_building_id, ",".join(ids), str(resize_active)]
	if signature == _needs_signature:
		_needs_panel.visible = view_context == "building" and not needs.is_empty() and not menu_open
		return
	_needs_signature = signature
	for child in _needs_box.get_children():
		child.queue_free()
	if needs.is_empty():
		_needs_panel.visible = false
		return
	var title := Label.new()
	title.text = "NEEDS PLACEMENT  %d" % needs.size()
	title.add_theme_font_size_override("font_size", 19)
	_needs_box.add_child(title)
	var hint := Label.new()
	hint.text = "Resize displaced these details. Pick one to place it again."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(290, 0)
	_needs_box.add_child(hint)
	for detail in needs:
		var button := Button.new()
		var kind := str(detail.get("kind", "detail")).replace("_", " ").capitalize()
		button.text = "%s  •  %s" % [kind, str(detail.get("id", ""))]
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size = Vector2(0, 42)
		button.pressed.connect(_recover_needs_detail.bind(str(detail.get("id", ""))))
		_needs_box.add_child(button)
	_needs_panel.visible = view_context == "building" and not menu_open

func _recover_needs_detail(detail_id: String) -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	for value in view.get("details", []):
		var detail: Dictionary = value
		if str(detail.get("id", "")) != detail_id:
			continue
		selected_detail_id = detail_id
		selected_surface_id = str(detail.get("anchor", {}).get("surface_id", ""))
		_begin_detail_move()
		if detail_move_active:
			_set_status("Place recovered %s • left stick along wall • A place / B restore" % str(detail.get("kind", "detail")).replace("_", " "))
		return

func _commit_resize() -> bool:
	var ok := super._commit_resize()
	_needs_signature = ""
	_refresh_needs_placement_panel()
	if ok:
		var count := _needs_details().size()
		if count > 0:
			_set_status("Cottage resized • %d detail%s need placement" % [count, "s" if count != 1 else ""])
	return ok

func _update_shell_hud() -> void:
	if view_context != "building" or not target_label or detail_move_active or resize_active or tools_open or detail_open:
		return
	if hovered_detail_id.is_empty() and _shell_hovered:
		target_label.text = "Cottage shell • A resize • X building options • right stick orbit • triggers zoom • ▲ Terrain"
