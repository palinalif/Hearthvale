extends "res://scripts/m2_scene_multi_floor.gd"

## The house editor has accumulated material, roof, decor, shape and storey
## actions. Keep the controller-first 720p panel clear of the persistent prompt
## bar without changing the contents or ordering of those actions.
func _ready() -> void:
	super._ready()
	_compact_home_options_for_storeys()

func _compact_home_options_for_storeys() -> void:
	if not _building_panel: return
	var margin: MarginContainer = _building_panel.get_child(0) as MarginContainer
	var box: VBoxContainer = margin.get_child(0) as VBoxContainer
	for button in _building_buttons:
		button.custom_minimum_size.y = 27
	box.add_theme_constant_override("separation", 0)
