extends "res://scripts/m2_scene_pc_input.gd"

## Whole-house roof silhouettes. Roof design is authoritative building data;
## preview geometry is disposable and never mutates the saved recipe until A.
const RoofGrid = preload("res://scripts/visual_grid.gd")
const ROOF_DESIGNS: Array[Dictionary] = [
	{"id": "swept_gable", "label": "Low gable", "summary": "Broad, quiet cottage roof"},
	{"id": "gentle_gable", "label": "Open gable", "summary": "Classic balanced cottage roof"},
	{"id": "steep_gable", "label": "Storybook steep gable", "summary": "Tall pointed village silhouette"},
	{"id": "hip", "label": "Hip roof", "summary": "Slopes down on all four sides"},
	{"id": "shed", "label": "Shed roof", "summary": "Single clean slope"},
	{"id": "saltbox", "label": "Saltbox", "summary": "Asymmetric long rear slope"},
	{"id": "gambrel", "label": "Gambrel", "summary": "Two-stage barn-like slopes"},
]
const CUSTOM_ROOF_PROFILES: Array[String] = ["hip", "shed", "saltbox", "gambrel"]

var _roof_design_button: Button
var _roof_design_picker: PanelContainer
var _roof_design_buttons: Array[Button] = []
var _roof_design_picker_open := false
var _roof_design_original := ""
var _roof_design_preview := ""
var _roof_overlay_signatures: Dictionary = {}

func _ready() -> void:
	super._ready()
	_install_roof_design_action()
	_build_roof_design_picker()
	_refresh_roof_overlays()

func _install_roof_design_action() -> void:
	if not _building_panel: return
	var margin := _building_panel.get_child(0) as MarginContainer
	var box := margin.get_child(0) as VBoxContainer
	_roof_design_button = Button.new()
	_roof_design_button.name = "RoofDesignAction"
	_roof_design_button.text = "Roof design"
	_roof_design_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_roof_design_button.focus_mode = Control.FOCUS_ALL
	_roof_design_button.custom_minimum_size = Vector2(0, 34)
	_roof_design_button.pressed.connect(_open_roof_design_picker)
	box.add_child(_roof_design_button)
	var roof_colour: Button = null
	for button in _building_buttons:
		if button.text == "Roof colour": roof_colour = button; break
	if roof_colour:
		box.move_child(_roof_design_button, roof_colour.get_index() + 1)
		var roof_index: int = _building_buttons.find(roof_colour)
		_building_buttons.insert(roof_index + 1, _roof_design_button)
	else: _building_buttons.append(_roof_design_button)
	for button in _building_buttons: button.custom_minimum_size.y = 34
	box.add_theme_constant_override("separation", 2)

func _build_roof_design_picker() -> void:
	_roof_design_picker = _make_catalogue_panel("RoofDesignPicker", Vector2(500, 470))
	var box := _catalogue_box(_roof_design_picker)
	box.add_theme_constant_override("separation", 5)
	_add_catalogue_heading(box, "ROOF DESIGN", "Browse to preview • A apply • B cancel")
	for design in ROOF_DESIGNS:
		var button := Button.new(); button.text = "%s  •  %s" % [str(design["label"]), str(design["summary"])]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.custom_minimum_size = Vector2(450, 42); button.focus_mode = Control.FOCUS_ALL
		button.set_meta("roof_profile", str(design["id"])); button.focus_entered.connect(_preview_roof_design.bind(str(design["id"]))); button.pressed.connect(_commit_roof_design.bind(str(design["id"])))
		box.add_child(button); _roof_design_buttons.append(button)

func _input(event: InputEvent) -> void:
	if _roof_design_picker_open and not menu_open:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"): _cancel_roof_design_picker()
		elif event.is_action_pressed("m1_pause"): _cancel_roof_design_picker(); super._input(event)
		elif event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner(); if focus in _roof_design_buttons: (focus as Button).pressed.emit()
		elif event.is_action_pressed("m1_height_up") or event.is_action_pressed("ui_up"): _move_focus(_roof_design_buttons, -1)
		elif event.is_action_pressed("m1_height_down") or event.is_action_pressed("ui_down"): _move_focus(_roof_design_buttons, 1)
		get_viewport().set_input_as_handled(); return
	super._input(event)

func _open_roof_design_picker() -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty(): return
	_roof_design_original = str(view.get("roof_profile", "gentle_gable")); _roof_design_preview = _roof_design_original; _roof_design_picker_open = true; tools_open = true
	if _building_panel: _building_panel.visible = false
	_roof_design_picker.visible = true
	var focus_button: Button = null
	for button in _roof_design_buttons:
		if str(button.get_meta("roof_profile", "")) == _roof_design_original: focus_button = button; break
	if focus_button == null and not _roof_design_buttons.is_empty(): focus_button = _roof_design_buttons[0]
	if focus_button: focus_button.grab_focus()
	_apply_roof_design_preview(); _set_status("Choose roof design • browse to preview • A apply / B cancel"); _refresh_controller_hud()

func _preview_roof_design(profile: String) -> void:
	if not _roof_design_picker_open: return
	_roof_design_preview = profile; _apply_roof_design_preview(); _set_status("Roof preview: %s • A apply / B cancel" % _roof_label(profile))

func _apply_roof_design_preview() -> void:
	if not _roof_design_picker_open: return
	var presentation: Dictionary = building_world.get_building(selected_building_id)
	if presentation.is_empty(): return
	presentation["roof_profile"] = _roof_design_preview
	var revision: int = building_world.get_revision()
	for visual in _selected_visual_roots():
		if visual.has_method("request_revision"): visual.request_revision(revision)
		if visual.has_method("apply_building"): visual.apply_building(presentation, revision)
		_refresh_roof_overlay_for_visual(visual, presentation)
	_apply_all_house_accents()

func _commit_roof_design(profile: String) -> void:
	if not _roof_design_picker_open: return
	var changed: bool = _set_roof_profile(selected_building_id, profile)
	_close_roof_design_picker()
	if changed: _record_history("building")
	_presentation_key = ""; _update_presentation(); _set_status("Roof design updated" if changed else "Roof design unchanged")

func _cancel_roof_design_picker() -> void:
	if not _roof_design_picker_open: return
	_close_roof_design_picker(); _presentation_key = ""; _update_presentation(); _set_status("Roof design change cancelled")

func _close_roof_design_picker() -> void:
	_roof_design_picker_open = false; _roof_design_original = ""; _roof_design_preview = ""; tools_open = false
	if _roof_design_picker: _roof_design_picker.visible = false
	get_viewport().gui_release_focus(); _refresh_controller_hud()

func _set_roof_profile(building_id: String, profile: String) -> bool:
	if not _valid_roof_profile(profile): return false
	var index: int = building_world._building_index(building_id)
	if index < 0: return false
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[index]
	if str(building.get("roof_profile", "gentle_gable")) == profile: return false
	var before: Dictionary = building_world._copy(building_world._document)
	building["roof_profile"] = profile; buildings[index] = building
	return building_world._record_change(before)

func _valid_roof_profile(profile: String) -> bool:
	for design in ROOF_DESIGNS:
		if str(design["id"]) == profile: return true
	return false

func _roof_label(profile: String) -> String:
	for design in ROOF_DESIGNS:
		if str(design["id"]) == profile: return str(design["label"])
	return profile.replace("_", " ").capitalize()

func _update_presentation() -> void:
	super._update_presentation()
	if _roof_design_picker_open: _apply_roof_design_preview()
	else: _refresh_roof_overlays()

func _refresh_roof_overlays() -> void:
	var seen: Dictionary = {}
	for visual_value in cottage_visuals.values():
		if visual_value is Node3D and is_instance_valid(visual_value):
			var visual := visual_value as Node3D; seen[visual.get_instance_id()] = true
			var applied_value = visual.get("_applied_view")
			if applied_value is Dictionary: _refresh_roof_overlay_for_visual(visual, applied_value as Dictionary)
	if cottage_visual is Node3D and is_instance_valid(cottage_visual) and not seen.has((cottage_visual as Node3D).get_instance_id()):
		var selected_applied_value = (cottage_visual as Node3D).get("_applied_view")
		if selected_applied_value is Dictionary: _refresh_roof_overlay_for_visual(cottage_visual as Node3D, selected_applied_value as Dictionary)

func _refresh_roof_overlay_for_visual(visual: Node3D, view: Dictionary) -> void:
	var profile: String = str(view.get("roof_profile", "gentle_gable")); var custom: bool = profile in CUSTOM_ROOF_PROFILES
	for child in visual.get_children():
		if _is_base_roof_node(str(child.name)): (child as Node).set("visible", not custom)
	if not custom:
		_remove_roof_overlay(visual); _roof_overlay_signatures.erase(visual.get_instance_id()); return
	var signature: String = "%s|%s|%s|%s" % [profile, str(view.get("dimensions", Vector3.ZERO)), str(view.get("roof_material_id", "terracotta")), str(view.get("wall_material_id", "stone_plaster"))]
	var key: int = int(visual.get_instance_id()); var overlay := visual.get_node_or_null("M2RoofDesign") as Node3D
	if str(_roof_overlay_signatures.get(key, "")) == signature and overlay != null: return
	_roof_overlay_signatures[key] = signature; _remove_roof_overlay(visual); _build_custom_roof(visual, view, profile)

func _is_base_roof_node(node_name: String) -> bool:
	return node_name.begins_with("RoofTiles_") or node_name.begins_with("GableLeft_") or node_name.begins_with("GableRight_") or node_name in ["RidgeCourses", "RoofEdgeLip", "GableVent", "GableFinials"]

func _remove_roof_overlay(visual: Node3D) -> void:
	var existing := visual.get_node_or_null("M2RoofDesign")
	if existing: visual.remove_child(existing); existing.queue_free()

func _build_custom_roof(visual: Node3D, view: Dictionary, profile: String) -> void:
	var dimensions: Vector3 = view.get("dimensions", Vector3(15, 6, 12)); var roof_id: String = str(view.get("roof_material_id", "terracotta")); var wall_id: String = str(view.get("wall_material_id", "stone_plaster"))
	var roof_colour: Color = SURFACE_MATERIAL_COLOURS.get(roof_id, Color("#b9654c")); var wall_colour: Color = SURFACE_MATERIAL_COLOURS.get(wall_id, Color("#e7cfab"))
	var unit_value = visual.get("_detail_unit"); var unit: Vector3 = unit_value if unit_value is Vector3 else Vector3.ONE * 0.5
	var root := Node3D.new(); root.name = "M2RoofDesign"; visual.add_child(root)
	match profile:
		"hip": _build_hip_roof(root, dimensions, roof_colour, unit)
		"shed": _build_shed_roof(root, dimensions, roof_colour, wall_colour, unit)
		"saltbox": _build_saltbox_roof(root, dimensions, roof_colour, wall_colour, unit)
		"gambrel": _build_gambrel_roof(root, dimensions, roof_colour, wall_colour, unit)

func _build_hip_roof(root: Node3D, dimensions: Vector3, colour: Color, unit: Vector3) -> void:
	var half_x: float = dimensions.x * 0.5 + 0.5; var half_z: float = dimensions.z * 0.5 + 0.5; var run_step: float = maxf(unit.z * 2.0, 0.5); var height_step: float = maxf(unit.y, 0.25); var rows: int = maxi(2, ceili(half_z / run_step))
	for row in rows:
		var inset: float = minf(half_z - unit.z, float(row) * run_step); var size_x: float = maxf(unit.x * 2.0, (half_x - inset) * 2.0); var size_z: float = maxf(unit.z * 2.0, (half_z - inset) * 2.0)
		_add_roof_box(root, "Hip_%d" % row, Vector3(0, dimensions.y + (row + 0.5) * height_step, 0), Vector3(size_x, height_step, size_z), colour.lightened(float(row % 2) * 0.035), unit)

func _build_shed_roof(root: Node3D, dimensions: Vector3, colour: Color, wall_colour: Color, unit: Vector3) -> void:
	var half_z: float = dimensions.z * 0.5 + 0.5; var run_step: float = maxf(unit.z * 2.0, 0.5); var rows: int = maxi(2, ceili((half_z * 2.0) / run_step))
	for row in rows:
		var z: float = -half_z + (row + 0.5) * run_step; var height: float = dimensions.y + (row + 0.5) * unit.y * 0.55
		_add_roof_box(root, "Shed_%d" % row, Vector3(0, height, z), Vector3(dimensions.x + 1.0, unit.y, run_step + unit.z * 0.35), colour.lightened(float(row % 2) * 0.03), unit); _add_end_infill(root, "ShedFill", dimensions, z, height, run_step, wall_colour, unit)

func _build_saltbox_roof(root: Node3D, dimensions: Vector3, colour: Color, wall_colour: Color, unit: Vector3) -> void:
	var half_z: float = dimensions.z * 0.5 + 0.5; var ridge_z: float = -dimensions.z * 0.16; var rise: float = maxf(2.0, dimensions.y * 0.46)
	for side_value in [-1.0, 1.0]:
		var side: float = float(side_value); var run: float = (ridge_z + half_z) if side < 0.0 else (half_z - ridge_z); var run_step: float = maxf(unit.z * 2.0, 0.5); var rows: int = maxi(2, ceili(run / run_step))
		for row in rows:
			var distance: float = minf(run, (row + 0.5) * run_step); var z: float = ridge_z + side * distance; var height: float = dimensions.y + rise * (1.0 - distance / run)
			_add_roof_box(root, "Saltbox_%s_%d" % [side, row], Vector3(0, height, z), Vector3(dimensions.x + 1.0, unit.y, run_step + unit.z * 0.35), colour.lightened(float(row % 2) * 0.03), unit); _add_end_infill(root, "SaltboxFill", dimensions, z, height, run_step, wall_colour, unit)
	_add_roof_box(root, "SaltboxRidge", Vector3(0, dimensions.y + rise, ridge_z), Vector3(dimensions.x + 1.0, unit.y, unit.z * 2.0), colour.lightened(0.07), unit)

func _build_gambrel_roof(root: Node3D, dimensions: Vector3, colour: Color, wall_colour: Color, unit: Vector3) -> void:
	var half_z: float = dimensions.z * 0.5 + 0.5; var rise: float = maxf(2.4, dimensions.y * 0.52); var run_step: float = maxf(unit.z * 2.0, 0.5); var rows: int = maxi(3, ceili(half_z / run_step))
	for side_value in [-1.0, 1.0]:
		var side: float = float(side_value)
		for row in rows:
			var distance: float = minf(half_z, (row + 0.5) * run_step); var t: float = clampf(distance / half_z, 0.0, 1.0); var fraction: float = lerpf(1.0, 0.68, t / 0.45) if t <= 0.45 else lerpf(0.68, 0.0, (t - 0.45) / 0.55); var z: float = side * distance; var height: float = dimensions.y + rise * fraction
			_add_roof_box(root, "Gambrel_%s_%d" % [side, row], Vector3(0, height, z), Vector3(dimensions.x + 1.0, unit.y, run_step + unit.z * 0.35), colour.lightened(float(row % 2) * 0.03), unit); _add_end_infill(root, "GambrelFill", dimensions, z, height, run_step, wall_colour, unit)
	_add_roof_box(root, "GambrelRidge", Vector3(0, dimensions.y + rise, 0), Vector3(dimensions.x + 1.0, unit.y, unit.z * 2.0), colour.lightened(0.07), unit)

func _add_end_infill(root: Node3D, prefix: String, dimensions: Vector3, z: float, roof_height: float, depth: float, colour: Color, unit: Vector3) -> void:
	var fill_height: float = roof_height - dimensions.y
	if fill_height <= unit.y * 0.25: return
	for side_value in [-1.0, 1.0]:
		var side: float = float(side_value); _add_roof_box(root, "%s_%s_%s" % [prefix, side, str(z)], Vector3(side * dimensions.x * 0.5, dimensions.y + fill_height * 0.5, z), Vector3(unit.x, fill_height, depth), colour, unit)

func _add_roof_box(parent: Node3D, node_name: String, center: Vector3, size: Vector3, colour: Color, unit: Vector3) -> void:
	var quantized: Dictionary = RoofGrid.quantized_box(center, size, unit); var node := MeshInstance3D.new(); node.name = node_name; var mesh := BoxMesh.new(); mesh.size = quantized.get("size", size); node.mesh = mesh; var material := StandardMaterial3D.new(); material.albedo_color = colour; node.material_override = material; node.position = quantized.get("center", center); parent.add_child(node)

func _cancel_current_edit(reason: String) -> void:
	if _roof_design_picker_open:
		_roof_design_picker_open = false; _roof_design_original = ""; _roof_design_preview = ""; if _roof_design_picker: _roof_design_picker.visible = false
	super._cancel_current_edit(reason)

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if not _roof_design_picker: return
	_roof_design_picker.visible = _roof_design_picker_open and not menu_open
	if _roof_design_picker_open:
		if _building_panel: _building_panel.visible = false
		if _tool_card: _tool_card.visible = false
		_tool_name.text = "Roof design"; _tool_meta.text = _roof_label(_roof_design_preview); _set_prompts([["UP/DOWN", "Choose"], ["A", "Apply"], ["B", "Cancel"], ["RS", "Orbit"]])
