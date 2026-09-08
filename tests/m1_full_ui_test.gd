extends SceneTree

var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scripts/m1_scene_full_ui.gd").new()
	scene.checkpoint_root = "user://m1-full-ui-test-%s" % Time.get_ticks_usec()
	scene.test_mode = true
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 15000
	while (scene.backend == null or not scene.backend.is_ready() or not scene._player_restored) and Time.get_ticks_msec() < deadline:
		await process_frame
	if scene.backend == null or not scene.backend.is_ready(): _fail("backend ready"); _finish(); return

	scene._set_view_context("building", "UI test")
	_check(scene._building_panel != null and scene._building_buttons.size() >= 5, "compact cottage shell menu exists")
	scene._open_building_panel()
	_check(scene.tools_open and scene._building_panel.visible, "shell X menu opens")
	_check(not scene.tools_panel.visible, "legacy cottage action dump stays hidden for shell")
	var labels: Array[String] = []
	for button in scene._building_buttons: labels.append(button.text)
	_check("Duplicate / place cottage" in labels and "Add flower box" in labels and "Add shutter" in labels, "shell menu exposes cottage placement and detail placement")
	scene._close_building_panel()

	scene._set_menu(true)
	_check(scene._modern_pause.visible and not scene.pause_panel.visible, "modern pause replaces prototype pause panel")
	var pause_labels := _pause_labels()
	_check("Resume" in pause_labels and "Settings" in pause_labels and "Save" in pause_labels, "pause presents primary actions")
	scene._open_settings()
	var settings_labels := _pause_labels()
	_check(settings_labels.any(func(v): return v.begins_with("Context hints:")), "settings exposes context hint toggle")
	scene._close_settings()
	scene._set_menu(false)
	_check(not scene._modern_pause.visible, "resume closes pause surface")
	_finish()

func _pause_labels() -> Array[String]:
	var result: Array[String] = []
	for child in scene._pause_stack.get_children():
		if child is Button: result.append((child as Button).text)
	return result

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1; print("FAIL: %s" % label)
func _fail(label: String) -> void:
	failures += 1; print("FAIL: %s" % label)
func _finish() -> void:
	if scene and is_instance_valid(scene): scene.queue_free(); await process_frame; await process_frame
	print(JSON.stringify({"ok": failures == 0, "failures": failures, "full_ui": failures == 0}))
	quit(1 if failures > 0 else 0)
