extends "res://scripts/m2_scene_roof_design.gd"

## Integration layer for the growing house roof controls. Keep the main Home
## options readable at 720p while leaving the dedicated roof pickers roomy.
func _ready() -> void:
	super._ready()
	_compact_home_options_for_roof_controls()

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
