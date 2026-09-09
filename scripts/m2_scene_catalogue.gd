extends "res://scripts/m1_scene_detail_resize.gd"

const HomeSilhouette = preload("res://scripts/m2_home_silhouette.gd")
const WALL_MATERIALS: Array[String] = ["stone_plaster", "warm_plaster", "timber", "chalk_white", "moss_stone", "rose_lime"]
const ROOF_MATERIALS: Array[String] = ["terracotta", "moss_tile", "slate", "thatch"]

var _home_catalogue_open := false
var _home_catalogue_panel: PanelContainer
var _home_catalogue_buttons: Array[Button] = []
var _home_catalogue_returns_to_build := false
var _build_catalogue_open := false
var _build_catalogue_panel: PanelContainer
var _build_catalogue_buttons: Array[Button] = []
var _outdoor_catalogue_open := false
var _outdoor_catalogue_panel: PanelContainer
var _outdoor_catalogue_buttons: Array[Button] = []
var _place_home_button: Button
var _catalogue_designs: Dictionary = {}
var _catalogue_buttons_by_id: Dictionary = {}
var _catalogue_wall_choices: Dictionary = {}
var _catalogue_roof_choices: Dictionary = {}

func _ready() -> void:
	super._ready()
	_install_place_home_action()
	_build_global_catalogue()
	_build_home_catalogue()

func _install_place_home_action() -> void:
	if not _building_panel: return
	# The M2 menu has two additional structural attachment actions. Lift the
	# compact panel so every row remains above the persistent prompt bar.
	_building_panel.position = Vector2(28, 160)
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
	for prefix in ["Duplicate", "Add window", "Add door", "Add flower box", "Add shutter", "Wall material", "Roof material", "Needs placement", "Close"]:
		for child in box.get_children():
			if child is Button and (child as Button).text.begins_with(prefix) and child not in ordered: ordered.append(child)
	for index in ordered.size(): box.move_child(ordered[index], index + 1)
	_building_buttons = ordered
	box.add_theme_constant_override("separation", 4)
	for button in _building_buttons: button.custom_minimum_size.y = 38

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

func _build_global_catalogue() -> void:
	_build_catalogue_panel = _make_catalogue_panel("BuildCatalogue", Vector2(520, 360))
	var box := _catalogue_box(_build_catalogue_panel)
	_add_catalogue_heading(box, "BUILD CATALOGUE", "Choose what you want to add to the hamlet")
	_add_catalogue_button(box, _build_catalogue_buttons, "Buildings\nHomes and structural details", _open_home_catalogue)
	_add_catalogue_button(box, _build_catalogue_buttons, "Roads & paths\nCatalogue slot ready • placement tools coming next", _show_roads_catalogue)
	_add_catalogue_button(box, _build_catalogue_buttons, "Outdoor decorations\nFoliage, trees, and clearing tools", _open_outdoor_catalogue)

	_outdoor_catalogue_panel = _make_catalogue_panel("OutdoorCatalogue", Vector2(520, 390))
	var outdoor_box := _catalogue_box(_outdoor_catalogue_panel)
	_add_catalogue_heading(outdoor_box, "OUTDOOR DECORATIONS", "Choose a brush, then paint directly in the world")
	_add_catalogue_button(outdoor_box, _outdoor_catalogue_buttons, "Foliage brush\nGrass, flowers, ferns, reeds, and mushrooms", _choose_outdoor_tool.bind("foliage"))
	_add_catalogue_button(outdoor_box, _outdoor_catalogue_buttons, "Tree brush\nPlace varied orchard and riverside trees", _choose_outdoor_tool.bind("tree"))
	_add_catalogue_button(outdoor_box, _outdoor_catalogue_buttons, "Clear decorations\nRemove planting without changing terrain", _choose_outdoor_tool.bind("clear_planting"))

func _make_catalogue_panel(node_name: String, minimum: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.position = Vector2(28, 150)
	panel.custom_minimum_size = minimum
	panel.visible = false
	hud.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	return panel

func _catalogue_box(panel: PanelContainer) -> VBoxContainer:
	return panel.get_child(0).get_child(0) as VBoxContainer

func _add_catalogue_heading(box: VBoxContainer, title_text: String, subtitle_text: String) -> void:
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = subtitle_text
	subtitle.modulate = Color("#aab9a8")
	box.add_child(subtitle)

func _add_catalogue_button(box: VBoxContainer, buttons: Array[Button], label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(470, 72)
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(callback)
	box.add_child(button)
	buttons.append(button)

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
	if _outdoor_catalogue_open and not menu_open:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_return_to_build_catalogue()
		elif event.is_action_pressed("m1_pause"):
			_close_all_catalogues()
			super._input(event)
		elif event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner()
			if focus in _outdoor_catalogue_buttons: (focus as Button).pressed.emit()
		elif event.is_action_pressed("m1_height_up") or event.is_action_pressed("ui_up"):
			_move_focus(_outdoor_catalogue_buttons, -1)
		elif event.is_action_pressed("m1_height_down") or event.is_action_pressed("ui_down"):
			_move_focus(_outdoor_catalogue_buttons, 1)
		get_viewport().set_input_as_handled()
		return
	if _build_catalogue_open and not menu_open:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_close_all_catalogues()
		elif event.is_action_pressed("m1_pause"):
			_close_all_catalogues()
			super._input(event)
		elif event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner()
			if focus in _build_catalogue_buttons: (focus as Button).pressed.emit()
		elif event.is_action_pressed("m1_height_up") or event.is_action_pressed("ui_up"):
			_move_focus(_build_catalogue_buttons, -1)
		elif event.is_action_pressed("m1_height_down") or event.is_action_pressed("ui_down"):
			_move_focus(_build_catalogue_buttons, 1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("m1_mode_switch") and not menu_open and not tools_open and not detail_open and not detail_move_active and not resize_active and not building_placement_active and not stroke_active and not landscape_active:
		_open_build_catalogue()
		get_viewport().set_input_as_handled()
		return
	super._input(event)

func _top_level_up_action() -> String:
	return "Build"

func _open_build_catalogue() -> void:
	_cancel_current_edit("Build catalogue opened")
	_close_all_catalogues(false)
	_build_catalogue_open = true
	tools_open = true
	_build_catalogue_panel.visible = true
	if not _build_catalogue_buttons.is_empty(): _build_catalogue_buttons[0].grab_focus()
	_set_status("Build catalogue • D-pad choose • A open • B close")
	_refresh_controller_hud()

func _return_to_build_catalogue() -> void:
	_close_all_catalogues(false)
	_build_catalogue_open = true
	tools_open = true
	_build_catalogue_panel.visible = true
	if not _build_catalogue_buttons.is_empty(): _build_catalogue_buttons[0].grab_focus()
	_set_status("Build catalogue")
	_refresh_controller_hud()

func _close_all_catalogues(clear_tools: bool = true) -> void:
	_build_catalogue_open = false
	_outdoor_catalogue_open = false
	_home_catalogue_open = false
	_home_catalogue_returns_to_build = false
	if _build_catalogue_panel: _build_catalogue_panel.visible = false
	if _outdoor_catalogue_panel: _outdoor_catalogue_panel.visible = false
	if _home_catalogue_panel: _home_catalogue_panel.visible = false
	if clear_tools: tools_open = false
	if clear_tools:
		get_viewport().gui_release_focus()
		_set_status("Terrain editing" if view_context == "terrain" else "Home editing")
	_refresh_controller_hud()

func _show_roads_catalogue() -> void:
	_set_status("Roads & paths are the next M2 composition tool • no placement action yet")

func _open_outdoor_catalogue() -> void:
	_build_catalogue_open = false
	_build_catalogue_panel.visible = false
	_outdoor_catalogue_open = true
	_outdoor_catalogue_panel.visible = true
	if not _outdoor_catalogue_buttons.is_empty(): _outdoor_catalogue_buttons[0].grab_focus()
	_set_status("Outdoor decorations • choose a world brush • B back")
	_refresh_controller_hud()

func _choose_outdoor_tool(tool: String) -> void:
	_close_all_catalogues(false)
	tools_open = false
	get_viewport().gui_release_focus()
	_set_view_context("terrain", "Outdoor decoration selected")
	_select_terrain_tool(tool)
	_refresh_controller_hud()

func _open_home_catalogue() -> void:
	_home_catalogue_returns_to_build = _build_catalogue_open
	_build_catalogue_open = false
	if _build_catalogue_panel: _build_catalogue_panel.visible = false
	_home_catalogue_open = true
	tools_open = true
	if _building_panel: _building_panel.visible = false
	_home_catalogue_panel.visible = true
	if not _home_catalogue_buttons.is_empty(): _home_catalogue_buttons[0].grab_focus()
	_set_status("Choose a home • D-pad navigate • A preview • B back")
	_refresh_controller_hud()

func _close_home_catalogue(return_to_options: bool) -> void:
	if return_to_options and _home_catalogue_returns_to_build:
		_return_to_build_catalogue()
		return
	_home_catalogue_open = false
	_home_catalogue_returns_to_build = false
	_home_catalogue_panel.visible = false
	tools_open = return_to_options
	if _building_panel: _building_panel.visible = return_to_options
	if return_to_options and _place_home_button: _place_home_button.grab_focus()
	else: get_viewport().gui_release_focus()
	_set_status("Home options" if return_to_options else "Cottage editing")
	_refresh_controller_hud()

func _choose_home_design(design_id: String) -> void:
	_home_catalogue_open = false
	_home_catalogue_returns_to_build = false
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
	if _mode_label and not menu_open:
		_mode_label.text = "BUILD"
		_mode_label.modulate = Color("#f2c982")
	var catalogue_active := _build_catalogue_open or _outdoor_catalogue_open or _home_catalogue_open
	if catalogue_active:
		if _terrain_panel: _terrain_panel.visible = false
		if _building_panel: _building_panel.visible = false
		if _tool_card: _tool_card.visible = false
		if _world_prompt: _world_prompt.visible = false
	if _build_catalogue_panel: _build_catalogue_panel.visible = _build_catalogue_open and not menu_open
	if _outdoor_catalogue_panel: _outdoor_catalogue_panel.visible = _outdoor_catalogue_open and not menu_open
	_home_catalogue_panel.visible = _home_catalogue_open and not menu_open
	if _build_catalogue_open:
		_tool_name.text = "Build catalogue"
		_tool_meta.text = "Buildings • roads • outdoor decorations"
		_set_prompts([["UP/DOWN", "Choose"], ["A", "Open"], ["B", "Close"]])
	elif _outdoor_catalogue_open:
		_tool_name.text = "Outdoor decorations"
		_tool_meta.text = "Choose a terrain-safe planting brush"
		_set_prompts([["UP/DOWN", "Choose"], ["A", "Use brush"], ["B", "Categories"]])
	elif _home_catalogue_open:
		if _building_panel: _building_panel.visible = false
		_tool_name.text = "Place new home"
		_tool_meta.text = "Independent saved design"
		_set_prompts([["UP/DOWN", "Choose"], ["◀▶", "Walls"], ["LB", "Roof -"], ["RB", "Roof +"], ["A", "Preview"], ["B", "Back"]])
