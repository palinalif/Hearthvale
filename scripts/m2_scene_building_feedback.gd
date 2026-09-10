extends "res://scripts/m2_scene_path_feedback.gd"
## M2 playtest corrections for direct building-detail editing.

const SURFACE_MATERIAL_CHOICES := {
	"wall": [
		["stone_plaster", "Stone plaster", Color("#e7cfab")],
		["warm_plaster", "Warm plaster", Color("#d5a982")],
		["timber", "Timber", Color("#9c684d")],
		["chalk_white", "Chalk white", Color("#e8e2d5")],
		["moss_stone", "Moss stone", Color("#a5b19b")],
		["rose_lime", "Rose lime", Color("#d7aaa0")],
	],
	"roof": [
		["terracotta", "Terracotta", Color("#b9654c")],
		["moss_tile", "Moss tile", Color("#66765d")],
		["slate", "Slate", Color("#59636d")],
		["thatch", "Thatch", Color("#aa8a52")],
	],
}

var _duplicate_detail_button: Button
var _duplicate_source_detail: Dictionary = {}
var _surface_picker_mode := ""
var _surface_picker_original := ""
var _surface_picker_preview := ""
var _surface_picker_panel: PanelContainer
var _surface_picker_title: Label
var _surface_picker_buttons: Dictionary = {}
var _wall_material_button: Button
var _roof_material_button: Button

func _ready() -> void:
	super._ready()
	_install_duplicate_detail_action()
	_install_surface_material_picker()

func _install_duplicate_detail_action() -> void:
	var box := _actions_box()
	if not box: return
	_duplicate_detail_button = Button.new()
	_duplicate_detail_button.name = "DuplicateDetailAction"
	_duplicate_detail_button.text = "Duplicate"
	_duplicate_detail_button.focus_mode = Control.FOCUS_ALL
	_duplicate_detail_button.custom_minimum_size = Vector2(0, 42)
	_duplicate_detail_button.pressed.connect(_begin_duplicate_selected_detail)
	box.add_child(_duplicate_detail_button)
	_tool_buttons["Duplicate selected detail"] = _duplicate_detail_button

func _install_surface_material_picker() -> void:
	_surface_picker_panel = PanelContainer.new()
	_surface_picker_panel.name = "SurfaceMaterialPicker"
	_surface_picker_panel.position = Vector2(28, 150)
	_surface_picker_panel.custom_minimum_size = Vector2(380, 0)
	_surface_picker_panel.visible = false
	hud.add_child(_surface_picker_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	_surface_picker_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	_surface_picker_title = Label.new()
	_surface_picker_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_surface_picker_title)
	var hint := Label.new()
	hint.text = "Browse to preview • A apply • B cancel"
	hint.modulate = Color("#aab9a8")
	box.add_child(hint)
	for mode in ["wall", "roof"]:
		for spec_value in SURFACE_MATERIAL_CHOICES[mode]:
			var spec: Array = spec_value
			var id := str(spec[0])
			var key := "%s:%s" % [mode, id]
			var button := Button.new()
			button.name = "%sMaterial_%s" % [mode.capitalize(), id]
			button.text = str(spec[1])
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.focus_mode = Control.FOCUS_ALL
			button.custom_minimum_size = Vector2(0, 44)
			button.icon = _colour_swatch(spec[2])
			button.visible = false
			button.set_meta("surface_material_mode", mode)
			button.focus_entered.connect(_preview_surface_material.bind(id))
			button.pressed.connect(_commit_surface_material.bind(id))
			box.add_child(button)
			_surface_picker_buttons[key] = button
	for button in _building_buttons:
		if button.text.begins_with("Wall material"):
			_wall_material_button = button
			_rewire_surface_material_button(button, "Wall colour", "wall")
		elif button.text.begins_with("Roof material"):
			_roof_material_button = button
			_rewire_surface_material_button(button, "Roof colour", "roof")

func _rewire_surface_material_button(button: Button, label: String, mode: String) -> void:
	for connection_value in button.pressed.get_connections():
		var connection: Dictionary = connection_value
		var callback: Callable = connection.get("callable", Callable())
		if callback.is_valid() and button.pressed.is_connected(callback): button.pressed.disconnect(callback)
	button.text = label
	button.pressed.connect(_begin_surface_material_picker.bind(mode))

func _input(event: InputEvent) -> void:
	if not _surface_picker_mode.is_empty() and not menu_open:
		if event.is_action_pressed("m1_cancel"):
			_cancel_surface_material_picker()
		elif event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner()
			if focus is Button and focus in _surface_picker_candidates(): (focus as Button).pressed.emit()
		elif event.is_action_pressed("m1_height_down") or event.is_action_pressed("ui_down"):
			_move_focus(_surface_picker_candidates(), 1)
		elif event.is_action_pressed("m1_height_up") or event.is_action_pressed("ui_up"):
			_move_focus(_surface_picker_candidates(), -1)
		elif event.is_action_pressed("m1_pause"):
			_cancel_surface_material_picker()
			super._input(event)
			return
		get_viewport().set_input_as_handled()
		return
	super._input(event)

func _update_action_buttons() -> void:
	super._update_action_buttons()
	if not _duplicate_detail_button: return
	var show := _context_actions_open and not selected_detail_id.is_empty() and hovered_detail_kind in ["window", "door", "shutter", "flower_box"]
	_duplicate_detail_button.visible = show
	_duplicate_detail_button.disabled = not show

func _begin_surface_material_picker(mode: String) -> void:
	if mode not in ["wall", "roof"] or not _surface_picker_panel: return
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty(): return
	_surface_picker_mode = mode
	_surface_picker_original = str(view.get("wall_material_id", view.get("material_id", "stone_plaster"))) if mode == "wall" else str(view.get("roof_material_id", "terracotta"))
	_surface_picker_preview = _surface_picker_original
	tools_open = true
	detail_open = false
	_context_actions_open = false
	if tools_panel: tools_panel.visible = false
	if _building_panel: _building_panel.visible = false
	_surface_picker_panel.visible = true
	_surface_picker_title.text = "WALL COLOUR" if mode == "wall" else "ROOF COLOUR"
	for button_value in _surface_picker_buttons.values():
		var button := button_value as Button
		var show := str(button.get_meta("surface_material_mode", "")) == mode
		button.visible = show
		button.disabled = not show
	var candidates := _surface_picker_candidates()
	var focus_button: Button
	for button_value in candidates:
		var button := button_value as Button
		if button.name.ends_with("_" + _surface_picker_original): focus_button = button
	if not focus_button and not candidates.is_empty(): focus_button = candidates[0]
	if focus_button: focus_button.grab_focus()
	_apply_surface_material_preview()
	_set_status("Choose %s colour • browse to preview • A apply / B cancel" % mode)
	_refresh_controller_hud()

func _surface_picker_candidates() -> Array:
	var result: Array = []
	for button_value in _surface_picker_buttons.values():
		var button := button_value as Button
		if str(button.get_meta("surface_material_mode", "")) == _surface_picker_mode: result.append(button)
	return result

func _preview_surface_material(material_id: String) -> void:
	if _surface_picker_mode.is_empty(): return
	_surface_picker_preview = material_id
	_apply_surface_material_preview()

func _apply_surface_material_preview() -> void:
	if _surface_picker_mode.is_empty() or _surface_picker_preview.is_empty(): return
	var presentation: Dictionary = building_world.get_building(selected_building_id)
	if presentation.is_empty(): return
	if _surface_picker_mode == "wall":
		presentation["wall_material_id"] = _surface_picker_preview
		presentation["material_id"] = _surface_picker_preview
	else:
		presentation["roof_material_id"] = _surface_picker_preview
	var revision := building_world.get_revision()
	for visual in _selected_visual_roots():
		if visual.has_method("request_revision"): visual.request_revision(revision)
		if visual.has_method("apply_building"): visual.apply_building(presentation, revision)

func _commit_surface_material(material_id: String) -> void:
	if _surface_picker_mode.is_empty(): return
	_surface_picker_preview = material_id
	var mode := _surface_picker_mode
	var ok: bool = building_world.set_wall_material(selected_building_id, material_id) if mode == "wall" else building_world.set_roof_material(selected_building_id, material_id)
	_end_surface_material_picker()
	if ok:
		_record_history("building")
		_set_status("%s colour updated" % mode.capitalize())
	else:
		_set_status("No %s colour change" % mode)
	_presentation_key = ""
	_update_presentation()

func _cancel_surface_material_picker() -> void:
	if _surface_picker_mode.is_empty(): return
	var mode := _surface_picker_mode
	_end_surface_material_picker()
	_presentation_key = ""
	_update_presentation()
	_set_status("%s colour change cancelled" % mode.capitalize())

func _end_surface_material_picker() -> void:
	_surface_picker_mode = ""
	_surface_picker_original = ""
	_surface_picker_preview = ""
	tools_open = false
	detail_open = false
	if _surface_picker_panel: _surface_picker_panel.visible = false
	if _building_panel: _building_panel.visible = false
	get_viewport().gui_release_focus()

func _begin_duplicate_selected_detail() -> void:
	if not _context_actions_open or selected_detail_id.is_empty(): return
	var source := _selected_detail_record()
	if source.is_empty(): return
	var kind := str(source.get("kind", ""))
	if kind not in ["window", "door", "shutter", "flower_box"]: return
	_duplicate_source_detail = source.duplicate(true)
	_context_actions_open = false
	_begin_new_attachment(kind)
	if not detail_move_active:
		_duplicate_source_detail.clear()
		return
	placement_asset_id = str(source.get("asset_id", placement_asset_id))
	var surface_id := str((source.get("anchor", {}) as Dictionary).get("surface_id", detail_move_surface_id))
	var source_position = source.get("resolved_position", null)
	var view: Dictionary = building_world.get_building(selected_building_id)
	if source_position is Vector3 and not surface_id.is_empty():
		var support := WallPlacement.surface(view, surface_id)
		var half := WallPlacement.footprint_for_detail(source)
		var axis := 0 if str(support.get("orientation", "front")) in ["front", "back"] else 2
		var intended: Vector3 = source_position
		intended[axis] += half.x * 2.0 + 0.25
		var available := WallPlacement.nearest_available(view, "", surface_id, intended, half)
		if available.is_empty():
			intended = source_position
			intended[axis] -= half.x * 2.0 + 0.25
			available = WallPlacement.nearest_available(view, "", surface_id, intended, half)
		if not available.is_empty():
			selected_surface_id = surface_id
			detail_move_surface_id = surface_id
			detail_move_original_surface_id = surface_id
			detail_move_position = available["position"]
	_set_status("Duplicate %s • left stick place on wall • A place / B cancel" % kind.replace("_", " "))
	_update_presentation()

func _commit_detail_move() -> bool:
	if _duplicate_source_detail.is_empty() or placement_kind.is_empty():
		return super._commit_detail_move()
	if not detail_move_active: return false
	var source_id := str(_duplicate_source_detail.get("id", ""))
	var kind := str(_duplicate_source_detail.get("kind", placement_kind))
	var new_id := _duplicate_detail_at(source_id, detail_move_surface_id, detail_move_position)
	var ok := not new_id.is_empty()
	detail_move_active = false
	if ok:
		selected_detail_id = new_id
		selected_surface_id = detail_move_surface_id
		_record_history("building")
	else:
		selected_detail_id = placement_previous_detail_id
		selected_surface_id = placement_previous_surface_id
	_duplicate_source_detail.clear()
	_clear_placement_state()
	_set_status(("%s duplicated" % kind.replace("_", " ").capitalize()) if ok else "Duplicate placement rejected")
	super._update_presentation()
	return ok

func _duplicate_detail_at(source_id: String, surface_id: String, local_position: Vector3) -> String:
	if source_id.is_empty() or surface_id.is_empty() or not local_position.is_finite(): return ""
	var building_index: int = building_world._building_index(selected_building_id)
	if building_index < 0: return ""
	var total_details := 0
	for value in building_world._document.get("buildings", []): total_details += ((value as Dictionary).get("details", []) as Array).size()
	if total_details >= 256: return ""
	var before: Dictionary = building_world.get_document()
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[building_index]
	var source_index: int = building_world._detail_index(building, source_id)
	if source_index < 0: return ""
	var source: Dictionary = (building["details"] as Array)[source_index]
	if str(source.get("state", "")) == "suppressed": return ""
	var copy: Dictionary = source.duplicate(true)
	var new_id: String = building_world._allocate_id("detail")
	copy["id"] = new_id
	copy["state"] = "manual"
	copy["generated"] = false
	copy["needs_placement"] = false
	copy.erase("default")
	copy.erase("suppressed_from_state")
	copy["anchor"] = {"surface_id": surface_id, "policy": "surface_local", "local_position": [local_position.x, local_position.y, local_position.z]}
	var overrides: Dictionary = (copy.get("override", {}) as Dictionary).duplicate(true)
	overrides.erase("surface_id")
	overrides.erase("local_position")
	overrides.erase("suppressed")
	if not str(copy.get("asset_id", "")).is_empty(): overrides["asset_id"] = str(copy["asset_id"])
	if overrides.is_empty(): copy.erase("override")
	else: copy["override"] = overrides
	var details: Array = building["details"]
	details.append(copy)
	building["details"] = details
	building_world._refresh_buckets(building)
	buildings[building_index] = building
	if not building_world._record_change(before): return ""
	return new_id

func _cancel_detail_move() -> void:
	var duplicating := not _duplicate_source_detail.is_empty()
	super._cancel_detail_move()
	if duplicating: _duplicate_source_detail.clear()

func _update_presentation() -> void:
	super._update_presentation()
	if not _surface_picker_mode.is_empty(): _apply_surface_material_preview()

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if _surface_picker_mode.is_empty() or menu_open: return
	if _building_panel: _building_panel.visible = false
	if _surface_picker_panel: _surface_picker_panel.visible = true
	if _tool_name:
		_tool_name.text = "Wall colour" if _surface_picker_mode == "wall" else "Roof colour"
		_tool_meta.text = str(_surface_picker_preview).replace("_", " ").capitalize()
	if _tool_card: _tool_card.visible = true
	_set_prompts([["UP/DOWN", "Choose"], ["A", "Apply"], ["B", "Cancel"], ["RS", "Orbit"]])

func _cancel_current_edit(reason: String) -> void:
	_duplicate_source_detail.clear()
	if not _surface_picker_mode.is_empty():
		_surface_picker_mode = ""
		_surface_picker_original = ""
		_surface_picker_preview = ""
		if _surface_picker_panel: _surface_picker_panel.visible = false
	super._cancel_current_edit(reason)
