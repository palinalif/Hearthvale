extends SceneTree

var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scripts/m1_scene_ui_overhaul.gd").new()
	scene.checkpoint_root = "user://m1-ui-overhaul-test-%s" % Time.get_ticks_usec()
	scene.test_mode = true
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 15000
	while (scene.backend == null or not scene.backend.is_ready() or not scene._player_restored) and Time.get_ticks_msec() < deadline:
		await process_frame
	if scene.backend == null or not scene.backend.is_ready():
		_fail("M1 backend becomes ready")
		_finish(); return

	_check(InputMap.has_action("m1_mode_switch"), "dedicated mode switch action exists")
	var has_dpad_up := false
	for event in InputMap.action_get_events("m1_mode_switch"):
		if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_DPAD_UP: has_dpad_up = true
	_check(has_dpad_up, "D-pad Up is bound to mode switch")
	_check(scene.view_context == "terrain", "starts in terrain mode")
	var switch := InputEventAction.new(); switch.action = "m1_mode_switch"; switch.pressed = true
	scene._input(switch)
	_check(scene.view_context == "building", "D-pad Up action enters building mode")
	scene._input(switch)
	_check(scene.view_context == "terrain", "D-pad Up action returns to terrain mode")

	_check(scene._mode_label != null and scene._tool_card != null and scene._prompt_bar != null, "controller HUD surfaces exist")
	scene._refresh_controller_hud()
	_check(scene._mode_label.text.contains("TERRAIN"), "mode pill names current context")
	_check(scene._tool_meta.text.contains("Strength"), "terrain card exposes strength without opening action list")
	_check(scene._tool_icon != null and scene._tool_icon.symbol == scene.sculpt_tool, "active terrain tool has matching graphical icon")
	_check(scene._tool_card.theme == scene._hud_theme, "HUD inherits its presentation theme")
	var terrain_prompt := _prompt_text()
	_check(terrain_prompt.contains("Sculpt") and terrain_prompt.contains("Tools") and terrain_prompt.contains("Building"), "terrain prompts show only current primary actions")

	scene._set_view_context("building", "UI test")
	scene._refresh_controller_hud()
	_check(scene._mode_label.text.contains("BUILDING"), "building mode pill updates")
	var building_prompt := _prompt_text()
	_check(building_prompt.contains("Orbit") and building_prompt.contains("Terrain"), "building prompts keep camera and mode switch visible")
	_check(scene._tool_icon.symbol == "cottage", "building context updates graphical icon")
	# Changing prompts repeatedly in one frame must not leave obsolete actions
	# occupying the row until deferred deletion runs.
	scene._set_prompts([["A", "Place"], ["B", "Restore"]])
	scene._set_prompts([["A", "Apply"]])
	_check(scene._prompt_row.get_child_count() == 1 and not _prompt_text().contains("Restore"), "prompt transitions immediately retire obsolete actions")
	var glyph_row: Control = scene._prompt_row.get_child(0).get_child(0)
	_check(glyph_row.get_meta("controller_key", "") == "A" and glyph_row.get_child(0) is TextureRect and glyph_row.get_child(0).texture != null, "action prompt renders the admitted controller texture")
	for key in ["A", "B", "X", "Y", "D-PAD", "UP/DOWN", "LEFT/RIGHT", "LS", "RS", "L3", "R3", "LB", "RB", "LT/RT"]:
		var control: Control = scene.InputGlyph.control(key)
		_check(control.get_child_count() > 0 and control.get_child(0).texture != null, "controller glyph resolves: " + key)
		control.free()
	scene._set_prompts([["LS", "Drag handle"], ["B", "Finish resizing"]])
	_check(_prompt_text() == "Drag Done", "inherited prompts retain action meaning with short labels")

	_finish()

func _prompt_text() -> String:
	var parts: Array[String] = []
	for group in scene._prompt_row.get_children():
		for child in group.get_children():
			if child is Label: parts.append((child as Label).text)
	return " ".join(parts)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: %s" % label)

func _fail(label: String) -> void:
	failures += 1
	print("FAIL: %s" % label)

func _finish() -> void:
	if scene and is_instance_valid(scene): scene.queue_free(); await process_frame; await process_frame
	print(JSON.stringify({"ok": failures == 0, "failures": failures, "ui_overhaul": failures == 0}))
	quit(1 if failures > 0 else 0)
