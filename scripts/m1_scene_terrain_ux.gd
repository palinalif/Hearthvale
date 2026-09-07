extends "res://scripts/m1_scene_placement.gd"
## M1 terrain UI layer; retain the playtested sculpting and placement paths.
const StrengthScale = preload("res://scripts/sculpt_strength.gd")
var brush_strength_level := StrengthScale.DEFAULT_LEVEL

func _init() -> void:
	brush_strength = StrengthScale.rate(brush_strength_level)

func set_brush_strength_level(level: int) -> void:
	brush_strength_level = clampi(level, StrengthScale.MIN_LEVEL, StrengthScale.MAX_LEVEL)
	brush_strength = StrengthScale.rate(brush_strength_level)
	_preview_key = ""

func _tool_choice(choice: String) -> void:
	if view_context == "terrain" and choice in ["Strength +", "Strength -"]:
		set_brush_strength_level(brush_strength_level + (1 if choice == "Strength +" else -1))
		tools_open = false
		detail_open = false
		if tools_panel: tools_panel.visible = false
		_set_status("Strength %d/10%s • L3 precision is one-quarter speed" % [brush_strength_level, " (default)" if brush_strength_level == 5 else ""])
		_update_presentation()
		return
	super._tool_choice(choice)

func _update_action_buttons() -> void:
	super._update_action_buttons()
	for label in ["Strength +", "Strength -"]:
		if not _tool_buttons.has(label): continue
		var button: Button = _tool_buttons[label]
		button.text = "%s (%d/10)" % [label, brush_strength_level]
		button.disabled = not button.visible or sculpt_tool in ["foliage", "tree", "clear_planting"] or (brush_strength_level == 10 if label == "Strength +" else brush_strength_level == 1)

func _update_presentation() -> void:
	if not building_world: return
	super._update_presentation()
	if target_label and view_context == "terrain":
		target_label.text = target_label.text.replace("str %.1f" % brush_strength, "strength %d/10" % brush_strength_level)
