extends SceneTree

## Signal teardown test for scripts/m1_scene.gd (task/signal-teardown).
##
## Verifies that the scene's signal bookkeeping exists and that leaving the
## tree disconnects the connections made in _ready() and _build_*_panel() so
## they do not accumulate on singletons such as Input. Follows the check()
## idiom of tests/backend_test.gd.
##
## Headless coverage limits:
## - No rendering output is asserted; visual behavior is covered by the
##   other in-tree tests.
## - No physical joypad is present: Input.joy_connection_changed wiring is
##   verified at the signal-connection level only, not via a real controller
##   attach/detach cycle.
## - Two full scene boots (ready -> exit tree) are the ceiling for this
##   file; heavier lifecycle scenarios belong in the in-tree GUI tests.

const M1Scene = preload("res://scripts/m1_scene.gd")
var failures := 0
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _joy_signal_count() -> int:
	if not Input.has_signal("joy_connection_changed"):
		return -1
	return Input.joy_connection_changed.get_connection_count()

func _boot_scene(tag: String) -> Node:
	var scene: Node = M1Scene.new()
	scene.name = "M1SignalTest" + tag
	scene.checkpoint_root = "user://m1-signal-teardown-test-%s-%s" % [tag, Time.get_ticks_usec()]
	scene.test_mode = true
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 60000
	while (scene.backend == null or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline:
		await process_frame
	return scene

func _init() -> void:
	var joy_base: int = _joy_signal_count()
	check(joy_base >= 0, "Input.joy_connection_changed signal exists")
	var scene_1: Node = await _boot_scene("a")
	check(scene_1 != null, "scene A booted")
	if scene_1 == null:
		_finish(); return
	check(scene_1.backend != null and scene_1.backend.is_ready(), "scene A backend ready")
	check(scene_1.has_method("_disconnect_tracked_signals"), "_disconnect_tracked_signals exists")
	check(scene_1.has_method("_exit_tree"), "_exit_tree exists")
	var tracked_variant: Variant = scene_1.get("_signal_teardown")
	check(tracked_variant is Array, "scene A exposes the _signal_teardown array")
	var tracked: Array = tracked_variant if tracked_variant is Array else []
	check(tracked.size() >= 6, "scene A tracks 6+ connections before exit (found %d)" % tracked.size())
	var joy_with_a: int = _joy_signal_count()
	check(joy_with_a == joy_base + 1, "scene A added exactly one Input.joy_connection_changed connection")
	scene_1.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(scene_1), "scene A freed")
	check(tracked.is_empty(), "scene A tracked list cleared on exit tree")
	check(_joy_signal_count() == joy_base, "no Input signal accumulation after scene A exit")
	var scene_2: Node = await _boot_scene("b")
	check(scene_2 != null and is_instance_valid(scene_2), "scene B booted after scene A freed")
	var joy_with_b: int = _joy_signal_count()
	check(joy_with_b == joy_base + 1, "scene B tracked its own Input connection")
	var tracked_2_variant: Variant = scene_2.get("_signal_teardown") if scene_2 and is_instance_valid(scene_2) else null
	check(tracked_2_variant is Array and tracked_2_variant.size() >= 6, "scene B tracks its own connections before exit")
	var tracked_2: Array = tracked_2_variant if tracked_2_variant is Array else []
	scene_2.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(scene_2), "scene B freed")
	check(tracked_2.is_empty(), "scene B tracked list cleared on exit tree")
	check(_joy_signal_count() == joy_base, "no Input signal accumulation after scene B exit")
	_finish()

func _finish() -> void:
	if failures > 0:
		print("FAIL checks=%d failures=%d" % [checks, failures])
		quit(1)
	print("PASS checks=%d failures=0" % checks)
	quit(0)
