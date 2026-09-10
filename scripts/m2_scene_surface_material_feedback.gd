extends "res://scripts/m2_scene_building_feedback.gd"
## M2 playtest correction: wall and roof colours use the same browse/preview/
## confirm/cancel contract as editable detail colours.

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

var _surface_picker_mode := ""
var _surface_picker_original := ""
var _surface_picker_preview := ""
var _surface_picker_panel: PanelContainer
var _surface_picker_title: Label
var _surface_picker_buttons: Array[Button] = []

func _ready() -> void:
    super._ready()
    _build_surface_material_picker()
    for button in _building_buttons:
        if button.text.begins_with("Wall material"):
            button.text = "Wall colour"
        elif button.text.begins_with("Roof material"):
            button.text = "Roof colour"

func _cycle_cottage_material() -> void:
    _begin_surface_material_picker("wall")

func _cycle_selected_roof() -> void:
    _begin_surface_material_picker("roof")

func _build_surface_material_picker() -> void:
    _surface_picker_panel = PanelContainer.new()
    _surface_picker_panel.name = "SurfaceMaterialPicker"
    _surface_picker_panel.position = Vector2(28, 150)
    _surface_picker_panel.custom_minimum_size = Vector2(380, 0)
    _surface_picker_panel.visible = false
    hud.add_child(_surface_picker_panel)
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 18)
    margin.add_theme_constant_override("margin_right", 18)
    margin.add_theme_constant_override("margin_top", 18)
    margin.add_theme_constant_override("margin_bottom", 18)
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
        for value in SURFACE_MATERIAL_CHOICES[mode]:
            var spec: Array = value
            var button := Button.new()
            button.name = "%sMaterial_%s" % [mode.capitalize(), str(spec[0])]
            button.text = str(spec[1])
            button.alignment = HORIZONTAL_ALIGNMENT_LEFT
            button.focus_mode = Control.FOCUS_ALL
            button.custom_minimum_size = Vector2(0, 44)
            button.icon = _colour_swatch(spec[2])
            button.visible = false
            button.set_meta("surface_mode", mode)
            button.set_meta("surface_material_id", str(spec[0]))
            button.focus_entered.connect(_preview_surface_material.bind(str(spec[0])))
            button.pressed.connect(_commit_surface_material.bind(str(spec[0])))
            box.add_child(button)
            _surface_picker_buttons.append(button)

func _input(event: InputEvent) -> void:
    if not _surface_picker_mode.is_empty() and not menu_open:
        if event.is_action_pressed("m1_cancel"):
            _cancel_surface_material_picker()
        elif event.is_action_pressed("m1_accept"):
            var focus := get_viewport().gui_get_focus_owner()
            if focus is Button:
                var focused_button := focus as Button
                if focused_button in _surface_picker_candidates():
                    focused_button.pressed.emit()
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

func _begin_surface_material_picker(mode: String) -> void:
    if mode != "wall" and mode != "roof": return
    var view: Dictionary = building_world.get_building(selected_building_id)
    if view.is_empty(): return
    _surface_picker_mode = mode
    if mode == "wall":
        _surface_picker_original = str(view.get("wall_material_id", view.get("material_id", "stone_plaster")))
    else:
        _surface_picker_original = str(view.get("roof_material_id", "terracotta"))
    _surface_picker_preview = _surface_picker_original
    tools_open = true
    detail_open = false
    _context_actions_open = false
    if tools_panel: tools_panel.visible = false
    if _building_panel: _building_panel.visible = false
    _surface_picker_panel.visible = true
    _surface_picker_title.text = "WALL COLOUR" if mode == "wall" else "ROOF COLOUR"
    var candidates := _surface_picker_candidates()
    var focus_button: Button = null
    for button in candidates:
        button.visible = true
        button.disabled = false
        if str(button.get_meta("surface_material_id", "")) == _surface_picker_original:
            focus_button = button
    for button in _surface_picker_buttons:
        if button not in candidates:
            button.visible = false
            button.disabled = true
    if focus_button == null and not candidates.is_empty():
        focus_button = candidates[0]
    if focus_button != null:
        focus_button.grab_focus()
    _apply_surface_material_preview()
    _set_status("Choose %s colour • browse to preview • A apply / B cancel" % mode)
    _refresh_controller_hud()

func _surface_picker_candidates() -> Array[Button]:
    var result: Array[Button] = []
    for button in _surface_picker_buttons:
        if str(button.get_meta("surface_mode", "")) == _surface_picker_mode:
            result.append(button)
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
        if visual.has_method("request_revision"):
            visual.request_revision(revision)
        if visual.has_method("apply_building"):
            visual.apply_building(presentation, revision)

func _commit_surface_material(material_id: String) -> void:
    if _surface_picker_mode.is_empty(): return
    var mode := _surface_picker_mode
    var changed := false
    if mode == "wall":
        changed = building_world.set_wall_material(selected_building_id, material_id)
    else:
        changed = building_world.set_roof_material(selected_building_id, material_id)
    _close_surface_material_picker()
    if changed:
        _record_history("building")
        _set_status("%s colour updated" % mode.capitalize())
    else:
        _set_status("No %s colour change" % mode)
    _presentation_key = ""
    _update_presentation()

func _cancel_surface_material_picker() -> void:
    if _surface_picker_mode.is_empty(): return
    var mode := _surface_picker_mode
    _close_surface_material_picker()
    _presentation_key = ""
    _update_presentation()
    _set_status("%s colour change cancelled" % mode.capitalize())

func _close_surface_material_picker() -> void:
    _surface_picker_mode = ""
    _surface_picker_original = ""
    _surface_picker_preview = ""
    tools_open = false
    detail_open = false
    if _surface_picker_panel: _surface_picker_panel.visible = false
    get_viewport().gui_release_focus()

func _update_presentation() -> void:
    super._update_presentation()
    if not _surface_picker_mode.is_empty():
        _apply_surface_material_preview()

func _refresh_controller_hud() -> void:
    super._refresh_controller_hud()
    if _surface_picker_mode.is_empty() or menu_open: return
    if _building_panel: _building_panel.visible = false
    if _surface_picker_panel: _surface_picker_panel.visible = true
    if _tool_name:
        _tool_name.text = "Wall colour" if _surface_picker_mode == "wall" else "Roof colour"
    if _tool_meta:
        _tool_meta.text = _surface_picker_preview.replace("_", " ").capitalize()
    if _tool_card: _tool_card.visible = true
    _set_prompts([["UP/DOWN", "Choose"], ["A", "Apply"], ["B", "Cancel"], ["RS", "Orbit"]])

func _cancel_current_edit(reason: String) -> void:
    if not _surface_picker_mode.is_empty():
        _surface_picker_mode = ""
        _surface_picker_original = ""
        _surface_picker_preview = ""
        if _surface_picker_panel: _surface_picker_panel.visible = false
    super._cancel_current_edit(reason)
