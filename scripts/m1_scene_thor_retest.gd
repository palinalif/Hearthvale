extends "res://scripts/m1_scene_playtest_repair.gd"
## Follow-up to the physically tested ca5185dc candidate. Preserve its accepted
## cottage interaction and keep these two remaining navigation fixes isolated.

func _move_focus(values: Array, direction: int) -> void:
	var buttons: Array[Button] = []
	for value in values:
		if value is Button and is_instance_valid(value):
			var button := value as Button
			if not button.is_queued_for_deletion() and button.is_visible_in_tree() and not button.disabled and button.focus_mode != Control.FOCUS_NONE:
				buttons.append(button)
	# Needs placement was appended to this array but inserted BEFORE Close in
	# the actual VBox. Use the same order the player sees (and the stick uses).
	if values == _building_buttons:
		buttons.sort_custom(func(a: Button, b: Button) -> bool: return a.get_index() < b.get_index())
	if buttons.is_empty(): return
	var index := buttons.find(get_viewport().gui_get_focus_owner())
	if index < 0: index = 0 if direction >= 0 else buttons.size() - 1
	else: index = posmod(index + direction, buttons.size())
	buttons[index].grab_focus()
