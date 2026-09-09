extends "res://scripts/m1_scene_detail_resize.gd"

const HomeSilhouette = preload("res://scripts/m2_home_silhouette.gd")
const WALL_MATERIALS: Array[String] = ["stone_plaster", "warm_plaster", "timber", "chalk_white", "moss_stone", "rose_lime"]
const ROOF_MATERIALS: Array[String] = ["terracotta", "moss_tile", "slate", "thatch"]

var _home_catalogue_open := false
var _home_catalogue_panel: PanelContainer
var _home_catalogue_buttons: Array[Button] = []
var _place_home_button: Button
var _catalogue_designs: Dictionary = {}
var _catalogue_buttons_by_id: Dictionary = {}
var _catalogue_wall_choices: Dictionary = {}
var _catalogue_roof_choices: Dictionary = {}

func _ready() -> void:
	super._ready()
	_install_place_home_action()
	_build_home_catalogue()

func _install_place_home_action() -> void:
	if not _building_panel: return
	var margin := _building_panel.get_child(0) as MarginContainer
	var box := margin.get_child(0) as VBoxContainer
	var title := box.get_child(0) as Label
	title.text = "HOMES & DETAILS"
	_add_building_button(box, "Place new home", _open_home_catalogue)
	_place_home_button = box.get_child(box.get_child_count() - 1) as Button
	box.move_child(_place_home_button, 1)
	for button in _building_buttons:
		if button.text.begins_with("Material:"): button.text = "Wall material: next"
	_add_building_button(box, "Roof material: next", _cycle_selected_roof)
	var ordered: Array[Button] = [_place_home_button]
	for prefix in ["Duplicate", "Add flower box", "Add shutter", "Wall material", "Roof material", "Needs placement", "Close"]:
		for child in box.get_children():
			if child is Button and (child as Button).text.begins_with(prefix) and child not in ordered: ordered.append(child)
	for index in ordered.size(): box.move_child(ordered[index], index + 1)
	_building_buttons = ordered

func _build_home_catalogue() -> void:
	_home_catalogue_panel = PanelContainer.new()
	_home_catalogue_panel.name = "ResidentialCatalogue"
	_home_catalogue_panel.position = Vector2(28, 150)
	_home_catalogue_panel.custom_minimum_size = Vector2(570, 430)
	_home_catalogue_panel.visible = false
	hud.add_child(_home_catalogue_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	_home_catalogue_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var title := Label.new()
	title.text = "PLACE NEW HOME"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Choose a design • adjust walls and roof before preview"
	subtitle.modulate = Color("#aab9a8")
	box.add_child(subtitle)
	for design in BuildingWorldScript.home_catalogue():
		var design_id := str(design["id"])
		_catalogue_designs[design_id] = design
		_catalogue_wall_choices[design_id] = str(design["wall_material_id"])
		_catalogue_roof_choices[design_id] = str(design["roof_material_id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		row.add_child(HomeSilhouette.new(str(design["shape_id"])))
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(410, 82)
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_choose_home_design.bind(design_id))
		row.add_child(button)
		_home_catalogue_buttons.append(button)
		_catalogue_buttons_by_id[design_id] = button
		_refresh_catalogue_button(design_id)

func _input(event: InputEvent) -> void:
	if _home_catalogue_open and not menu_open:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_close_home_catalogue(true)
		elif event.is_action_pressed("m1_pause"):
			_close_home_catalogue(false)
			super._input(event)
		elif event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner()
			if focus in _home_catalogue_buttons: (focus as Button).pressed.emit()
		elif event.is_action_pressed("m1_height_up") or event.is_action_pressed("ui_up"):
			_move_focus(_home_catalogue_buttons, -1)
		elif event.is_action_pressed("m1_height_down") or event.is_action_pressed("ui_down"):
			_move_focus(_home_catalogue_buttons, 1)
		elif event.is_action_pressed("m1_cycle_left") or event.is_action_pressed("m1_cycle_right"):
			_cycle_catalogue_material("wall", -1 if event.is_action_pressed("m1_cycle_left") else 1)
		elif event.is_action_pressed("m1_undo") or event.is_action_pressed("m1_redo"):
			_cycle_catalogue_material("roof", -1 if event.is_action_pressed("m1_undo") else 1)
		get_viewport().set_input_as_handled()
		return
	super._input(event)

func _open_home_catalogue() -> void:
	_home_catalogue_open = true
	tools_open = true
	if _building_panel: _building_panel.visible = false
	_home_catalogue_panel.visible = true
	if not _home_catalogue_buttons.is_empty(): _home_catalogue_buttons[0].grab_focus()
	_set_status("Choose a home • D-pad navigate • A preview • B back")
	_refresh_controller_hud()

func _close_home_catalogue(return_to_options: bool) -> void:
	_home_catalogue_open = false
	_home_catalogue_panel.visible = false
	tools_open = return_to_options
	if _building_panel: _building_panel.visible = return_to_options
	if return_to_options and _place_home_button: _place_home_button.grab_focus()
	else: get_viewport().gui_release_focus()
	_set_status("Home options" if return_to_options else "Cottage editing")
	_refresh_controller_hud()

func _choose_home_design(design_id: String) -> void:
	_home_catalogue_open = false
	_home_catalogue_panel.visible = false
	tools_open = false
	if _building_panel: _building_panel.visible = false
	get_viewport().gui_release_focus()
	_begin_new_building_placement(design_id, str(_catalogue_wall_choices[design_id]), str(_catalogue_roof_choices[design_id]))
	_refresh_controller_hud()

func _focused_design_id() -> String:
	var focus := get_viewport().gui_get_focus_owner()
	for design_id in _catalogue_buttons_by_id:
		if _catalogue_buttons_by_id[design_id] == focus: return str(design_id)
	return str(_catalogue_designs.keys()[0]) if not _catalogue_designs.is_empty() else ""

func _cycle_catalogue_material(kind: String, direction: int) -> void:
	var design_id := _focused_design_id()
	if design_id.is_empty(): return
	var choices := WALL_MATERIALS if kind == "wall" else ROOF_MATERIALS
	var selected: Dictionary = _catalogue_wall_choices if kind == "wall" else _catalogue_roof_choices
	var current := str(selected[design_id])
	selected[design_id] = choices[posmod(choices.find(current) + direction, choices.size())]
	_refresh_catalogue_button(design_id)
	_set_status("%s %s: %s" % [str(_catalogue_designs[design_id]["name"]), kind, str(selected[design_id]).replace("_", " ").capitalize()])

func _refresh_catalogue_button(design_id: String) -> void:
	var design: Dictionary = _catalogue_designs[design_id]
	var button: Button = _catalogue_buttons_by_id[design_id]
	button.text = "%s\n%s\nWalls: %s   Roof: %s" % [design["name"], design["summary"], str(_catalogue_wall_choices[design_id]).replace("_", " ").capitalize(), str(_catalogue_roof_choices[design_id]).replace("_", " ").capitalize()]

func _cycle_selected_roof() -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty(): return
	var current := str(view.get("roof_material_id", "terracotta"))
	var next_material := ROOF_MATERIALS[posmod(ROOF_MATERIALS.find(current) + 1, ROOF_MATERIALS.size())]
	if building_world.set_roof_material(selected_building_id, next_material): _record_history("building")
	_set_status("Roof material: %s" % next_material.replace("_", " ").capitalize())

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if not _home_catalogue_panel: return
	_home_catalogue_panel.visible = _home_catalogue_open and not menu_open
	if _home_catalogue_open:
		if _building_panel: _building_panel.visible = false
		_tool_name.text = "Place new home"
		_tool_meta.text = "Independent saved design"
		_set_prompts([["▲▼", "Choose"], ["◀▶", "Walls"], ["LB", "Roof -"], ["RB", "Roof +"], ["A", "Preview"], ["B", "Back"]])
