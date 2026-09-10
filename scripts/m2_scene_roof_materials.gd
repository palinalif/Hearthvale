extends "res://scripts/m2_scene_roof_options.gd"

## Additional roof finishes layered over the existing roof systems. These are
## presentation/material choices only; the authoritative building recipe keeps
## the selected roof_material_id exactly like the original four materials.
const EXTRA_ROOF_MATERIALS: Array[String] = ["wood_shake", "standing_seam", "green_roof"]
const EXTRA_ROOF_SWATCHES := {
	"wood_shake": Color("#76523f"),
	"standing_seam": Color("#67777b"),
	"green_roof": Color("#6e8050"),
}
const EXTRA_ROOF_PALETTES := {
	"wood_shake": [Color("#76523f"), Color("#86604a"), Color("#694638")],
	"standing_seam": [Color("#67777b"), Color("#74858a"), Color("#596a6e")],
	"green_roof": [Color("#6e8050"), Color("#7f925d"), Color("#5d7044")],
}

var _extra_roof_material_buttons: Array[Button] = []

func _ready() -> void:
	super._ready()
	_install_extra_roof_materials()
	_apply_extra_roof_materials()

func _roof_material_choices() -> Array[String]:
	var result: Array[String] = []
	result.append_array(ROOF_MATERIALS)
	result.append_array(EXTRA_ROOF_MATERIALS)
	return result

func _install_extra_roof_materials() -> void:
	if not _surface_material_picker_panel: return
	var box: VBoxContainer = _catalogue_box(_surface_material_picker_panel)
	for material_id in EXTRA_ROOF_MATERIALS:
		var button := Button.new()
		button.text = material_id.replace("_", " ").capitalize()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(380, 44)
		button.focus_mode = Control.FOCUS_ALL
		button.icon = _colour_swatch(EXTRA_ROOF_SWATCHES[material_id])
		button.set_meta("material_id", material_id)
		button.focus_entered.connect(_preview_surface_material.bind(material_id))
		button.pressed.connect(_commit_surface_material.bind(material_id))
		button.visible = false
		box.add_child(button)
		_surface_material_picker_buttons.append(button)
		_extra_roof_material_buttons.append(button)

func _surface_material_candidates() -> Array:
	var result: Array = super._surface_material_candidates()
	if _surface_material_picker_kind != "roof": return result
	for button in _extra_roof_material_buttons:
		if button not in result: result.append(button)
	return result

func _cycle_catalogue_material(kind: String, direction: int) -> void:
	if kind != "roof":
		super._cycle_catalogue_material(kind, direction)
		return
	var design_id: String = _focused_design_id()
	if design_id.is_empty(): return
	var choices: Array[String] = _roof_material_choices()
	var current: String = str(_catalogue_roof_choices[design_id])
	_catalogue_roof_choices[design_id] = choices[posmod(choices.find(current) + direction, choices.size())]
	_refresh_catalogue_button(design_id)
	_set_status("%s roof: %s" % [str(_catalogue_designs[design_id]["name"]), str(_catalogue_roof_choices[design_id]).replace("_", " ").capitalize()])

func _palette_for_seed(seed: int, design_id: String) -> Dictionary:
	var palette: Dictionary = super._palette_for_seed(seed, design_id)
	var style_offset: int = int(HOME_PALETTE_STYLE_OFFSET.get(design_id, 0))
	var choices: Array[String] = _roof_material_choices()
	var roof_index: int = posmod(seed * 11 + style_offset * 5 + 1, choices.size())
	palette["roof"] = choices[roof_index]
	return palette

func _begin_new_building_placement(design_id: String, wall_material_id: String = "", roof_material_id: String = "") -> void:
	super._begin_new_building_placement(design_id, wall_material_id, roof_material_id)
	_apply_extra_roof_material_to_placement_ghost()

func _apply_surface_material_preview() -> void:
	super._apply_surface_material_preview()
	_apply_extra_roof_materials()

func _update_presentation() -> void:
	super._update_presentation()
	_apply_extra_roof_materials()

func _apply_extra_roof_materials() -> void:
	if not building_world: return
	var seen: Dictionary = {}
	for building_id_value in cottage_visuals.keys():
		var building_id: String = str(building_id_value)
		var visual: Node3D = cottage_visuals.get(building_id, null) as Node3D
		if not visual or not is_instance_valid(visual): continue
		seen[visual.get_instance_id()] = true
		var view: Dictionary = building_world.get_building(building_id)
		if view.is_empty(): continue
		var material_id: String = str(view.get("roof_material_id", "terracotta"))
		if _surface_material_picker_open and _surface_material_picker_kind == "roof" and building_id == selected_building_id:
			material_id = _surface_material_picker_preview
		_apply_extra_roof_material_to_visual(visual, material_id)
	if cottage_visual is Node3D and is_instance_valid(cottage_visual) and not seen.has((cottage_visual as Node3D).get_instance_id()):
		var view: Dictionary = building_world.get_building(selected_building_id)
		if not view.is_empty():
			var material_id: String = str(view.get("roof_material_id", "terracotta"))
			if _surface_material_picker_open and _surface_material_picker_kind == "roof": material_id = _surface_material_picker_preview
			_apply_extra_roof_material_to_visual(cottage_visual as Node3D, material_id)
	_apply_extra_roof_material_to_placement_ghost()

func _apply_extra_roof_material_to_placement_ghost() -> void:
	if not building_placement_active or not building_placement_ghost or not building_placement_ghost.visible: return
	var material_id: String = ""
	if building_placement_operation == "new":
		material_id = building_placement_roof_material_id
	elif not building_placement_source_id.is_empty():
		var source: Dictionary = building_world.get_building(building_placement_source_id)
		material_id = str(source.get("roof_material_id", ""))
	_apply_extra_roof_material_to_visual(building_placement_ghost, material_id)

func _apply_extra_roof_material_to_visual(visual: Node3D, material_id: String) -> void:
	if material_id not in EXTRA_ROOF_MATERIALS: return
	var palette: Array = EXTRA_ROOF_PALETTES[material_id]
	_recolour_roof_tree(visual, material_id, palette, false)

func _recolour_roof_tree(node: Node, material_id: String, palette: Array, inside_custom_roof: bool) -> void:
	if str(node.name) == "M2RoofAccessories": return
	var custom: bool = inside_custom_roof or str(node.name) == "M2RoofDesign"
	if node is GeometryInstance3D:
		var node_name: String = str(node.name)
		var is_roof_piece: bool = node_name.begins_with("RoofTiles_") or node_name in ["RidgeCourses", "RoofEdgeLip"]
		if custom and not node_name.contains("Fill"): is_roof_piece = true
		if is_roof_piece:
			var shade: int = posmod(node_name.hash(), 3)
			if node_name.begins_with("RoofTiles_"): shade = clampi(int(node_name.trim_prefix("RoofTiles_")), 0, 2)
			elif node_name == "RidgeCourses": shade = 2
			elif node_name == "RoofEdgeLip": shade = 0
			_apply_roof_finish(node as GeometryInstance3D, material_id, palette[shade] as Color)
	for child in node.get_children():
		_recolour_roof_tree(child, material_id, palette, custom)

func _apply_roof_finish(geometry: GeometryInstance3D, material_id: String, colour: Color) -> void:
	var material: StandardMaterial3D = geometry.material_override as StandardMaterial3D
	if material == null:
		material = StandardMaterial3D.new()
		geometry.material_override = material
	material.albedo_color = colour
	material.metallic = 0.58 if material_id == "standing_seam" else 0.0
	material.roughness = 0.48 if material_id == "standing_seam" else 0.92 if material_id == "wood_shake" else 1.0
