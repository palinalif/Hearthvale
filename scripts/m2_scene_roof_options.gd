extends "res://scripts/m2_scene_roof_accessories.gd"

## Integration layer for the growing house roof controls. Keep the main Home
## options readable at 720p while leaving the dedicated roof pickers roomy.
## The legacy gable ridge is authored one structural voxel above the roof
## planes, so M2 lowers only that ridge assembly after each visual refresh.
func _ready() -> void:
	super._ready()
	_compact_home_options_for_roof_controls()
	_align_base_roof_ridges()

func _compact_home_options_for_roof_controls() -> void:
	if not _building_panel: return
	_building_panel.position = Vector2(28, 122)
	var margin := _building_panel.get_child(0) as MarginContainer
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	var box := margin.get_child(0) as VBoxContainer
	box.add_theme_constant_override("separation", 1)
	for button in _building_buttons:
		button.custom_minimum_size.y = 31

func _update_presentation() -> void:
	super._update_presentation()
	_align_base_roof_ridges()

func _align_base_roof_ridges() -> void:
	var seen: Dictionary = {}
	for visual_value in cottage_visuals.values():
		if visual_value is Node3D and is_instance_valid(visual_value):
			var visual := visual_value as Node3D
			seen[visual.get_instance_id()] = true
			_lower_ridge_one_voxel(visual)
	if cottage_visual is Node3D and is_instance_valid(cottage_visual) and not seen.has((cottage_visual as Node3D).get_instance_id()):
		_lower_ridge_one_voxel(cottage_visual as Node3D)
	if building_placement_ghost is Node3D and is_instance_valid(building_placement_ghost):
		_lower_ridge_one_voxel(building_placement_ghost as Node3D)

func _lower_ridge_one_voxel(visual: Node3D) -> void:
	var ridge := visual.get_node_or_null("RidgeCourses") as Node3D
	if not ridge or bool(ridge.get_meta("m2_ridge_lowered", false)): return
	var unit_value = visual.get("_unit")
	if not unit_value is Vector3: return
	var unit: Vector3 = unit_value
	ridge.position.y -= unit.y
	ridge.set_meta("m2_ridge_lowered", true)
