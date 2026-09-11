extends "res://scripts/m2_scene_decor_colour.gd"

const ColourPopover = preload("res://scripts/ui/m2_colour_popover.gd")
var _detail_colour_popover: ColourPopover
var _compact_colours_ready := false

func _ready() -> void:
	super._ready()
	_detail_colour_popover = ColourPopover.new()
	_detail_colour_popover.name = "DetailColourPopover"
	hud.add_child(_detail_colour_popover)
	for colour_id in DETAIL_COLOURS:
		var button: Button = _style_buttons["colour-" + str(colour_id)]
		_detail_colour_popover.add_choice(button, DETAIL_COLOURS[colour_id], DETAIL_COLOUR_LABELS[colour_id])
	var old_panel := _surface_material_picker_panel
	_surface_material_picker_panel = ColourPopover.new()
	_surface_material_picker_panel.name = "SurfaceColourPopover"
	hud.add_child(_surface_material_picker_panel)
	for button in _surface_material_picker_buttons:
		var id := str(button.get_meta("material_id", ""))
		var colour: Color = SURFACE_MATERIAL_COLOURS.get(id, ACCENT_COLOURS.get(id, EXTRA_ROOF_SWATCHES.get(id, Color.WHITE)))
		_surface_material_picker_panel.call("add_choice", button, colour, id.replace("_", " ").capitalize())
	old_panel.queue_free()
	_compact_colours_ready = true

func _begin_style_picker(mode: String) -> void:
	# Reparented buttons must be visible in-tree before inherited focus logic.
	if _compact_colours_ready and mode == "colour": _detail_colour_popover.show()
	super._begin_style_picker(mode)
	if _compact_colours_ready and _style_picker_mode == "colour":
		var button: Button = _style_buttons.get("colour-" + _style_picker_original_colour, null)
		if button: button.grab_focus()
		_refresh_controller_hud()
		_dock_compact_colours.call_deferred()
	elif _detail_colour_popover: _detail_colour_popover.hide()

func _end_style_picker() -> void:
	if _detail_colour_popover: _detail_colour_popover.hide()
	super._end_style_picker()
	_refresh_controller_hud()

func _open_surface_material_picker(kind: String) -> void:
	super._open_surface_material_picker(kind)
	if _compact_colours_ready: _dock_compact_colours.call_deferred()

func _input(event: InputEvent) -> void:
	if _compact_colours_ready and not menu_open and (_style_picker_mode == "colour" or _surface_material_picker_open):
		if event.is_action_pressed("m1_cycle_left") or event.is_action_pressed("ui_left"):
			_move_focus(_style_candidates("colour") if _style_picker_mode == "colour" else _surface_material_candidates(), -1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_cycle_right") or event.is_action_pressed("ui_right"):
			_move_focus(_style_candidates("colour") if _style_picker_mode == "colour" else _surface_material_candidates(), 1)
			get_viewport().set_input_as_handled()
			return
		if _style_picker_mode == "colour" and (event.is_action_pressed("m1_tools") or event.is_action_pressed("m1_pause")):
			_cancel_style_picker()
			if event.is_action_pressed("m1_pause"): super._input(event)
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _cancel_current_edit(reason: String) -> void:
	if _style_picker_mode == "colour": _cancel_style_picker()
	super._cancel_current_edit(reason)
	if _detail_colour_popover: _detail_colour_popover.hide()

func _update_camera() -> void:
	super._update_camera()
	if _compact_colours_ready: _dock_compact_colours()

func _dock_style_picker_away_from_target() -> void:
	super._dock_style_picker_away_from_target()
	if _compact_colours_ready and _style_picker_mode == "colour": _dock_compact_colours()

func _colour_target_bounds() -> Rect2:
	var view: Dictionary = building_world.get_building(selected_building_id)
	var transform_value: Transform3D = view.get("transform", Transform3D.IDENTITY)
	var dimensions: Vector3 = view.get("dimensions", Vector3.ONE)
	if _style_picker_mode == "colour":
		var detail: Dictionary = _selected_detail_record()
		var position_value: Variant = detail.get("resolved_position", null)
		if position_value is Vector3:
			var support: Dictionary = WallPlacement.surface(view, str((detail.get("anchor", {}) as Dictionary).get("surface_id", "")))
			return _detail_screen_bounds(detail, position_value, str(support.get("orientation", "front")), transform_value)
	var bounds := Rect2()
	var started := false
	for section in HouseMassing.sections_for(view):
		var rect: Rect2 = HouseMassing.section_rect(section)
		for x in [rect.position.x, rect.end.x]:
			for z in [rect.position.y, rect.end.y]:
				for y in [HouseMassing.section_bottom(section), HouseMassing.section_top(section) + dimensions.y * 0.6]:
					var world: Vector3 = transform_value * Vector3(x, y, z)
					if camera.is_position_behind(world): continue
					var point := camera.unproject_position(world)
					bounds = bounds.expand(point) if started else Rect2(point, Vector2.ZERO)
					started = true
	return bounds if started else Rect2(get_viewport().get_visible_rect().size * 0.5, Vector2.ONE)

func _dock_compact_colours() -> void:
	if not camera or not building_world: return
	var panel: PanelContainer = _detail_colour_popover if _style_picker_mode == "colour" else _surface_material_picker_panel if _surface_material_picker_open else null
	if not panel or not panel.visible: return
	var available := get_viewport().get_visible_rect().grow(-16)
	if _prompt_bar: available.size.y = maxf(0, minf(available.end.y, _prompt_bar.position.y - 18) - available.position.y)
	panel.call("place_near", _colour_target_bounds(), available)

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if not _compact_colours_ready: return
	_detail_colour_popover.visible = _style_picker_mode == "colour" and not menu_open
	if not menu_open and (_style_picker_mode == "colour" or _surface_material_picker_open):
		if tools_panel: tools_panel.hide()
		if _building_panel: _building_panel.hide()
		if _tool_card: _tool_card.hide()
		if _world_prompt: _world_prompt.hide()
		if _hover_prompt: _hover_prompt.hide()
		if _style_category_label: _style_category_label.hide()
		_set_prompts([["LEFT/RIGHT", "Choose"], ["A", "Apply"], ["B", "Cancel"], ["RS", "Orbit"]])
		_dock_compact_colours()
