extends SceneTree

var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scripts/m1_scene_tool_ui.gd").new()
	scene.checkpoint_root = "user://m1-tool-ui-test-%s" % Time.get_ticks_usec()
	scene.test_mode = true
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 15000
	while (scene.backend == null or not scene.backend.is_ready() or not scene._player_restored) and Time.get_ticks_msec() < deadline:
		await process_frame
	if scene.backend == null or not scene.backend.is_ready():
		_fail("backend ready"); _finish(); return

	var starting_tool: String = scene.sculpt_tool
	var cycle := InputEventAction.new(); cycle.action = "m1_cycle_right"; cycle.pressed = true
	scene._input(cycle)
	_check(scene.sculpt_tool != starting_tool, "D-pad right changes terrain tool directly")
	_check(not scene.tools_open, "direct tool cycle does not open overlay")

	var open := InputEventAction.new(); open.action = "m1_tools"; open.pressed = true
	scene._input(open)
	_check(scene.tools_open and scene._terrain_panel.visible, "X opens compact terrain settings")
	_check(not scene.tools_panel.visible, "legacy action dump stays hidden")
	_check(scene._terrain_ui_buttons.size() <= 16, "terrain surface stays compact")

	var radius_before: float = scene.brush_radius
	scene._change_radius(1)
	_check(scene.brush_radius > radius_before, "radius setting changes existing sculpt radius")
	var strength_before: int = scene.brush_strength_level
	scene._change_strength(1)
	_check(scene.brush_strength_level == min(10, strength_before + 1), "strength setting uses 1-10 scale")

	scene._close_terrain_settings()
	_check(not scene.tools_open and not scene._terrain_panel.visible, "B/X style close returns to world")
	_finish()

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: %s" % label)

func _fail(label: String) -> void:
	failures += 1
	print("FAIL: %s" % label)

func _finish() -> void:
	if scene and is_instance_valid(scene): scene.queue_free(); await process_frame; await process_frame
	print(JSON.stringify({"ok": failures == 0, "failures": failures, "tool_ui": failures == 0}))
	quit(1 if failures > 0 else 0)
