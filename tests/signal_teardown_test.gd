extends SceneTree

## Signal teardown test for scripts/m1_scene.gd (task/signal-teardown).
##
## Verifies the scene's signal bookkeeping (track/disconnect/_exit_tree) and —
## concretely — that a scene's connection to the Input singleton is removed when
## the scene exits the tree, so Input does not accumulate stale scene callbacks.
## Follows the check() idiom of tests/backend_test.gd.
##
## Headless coverage limits:
## - No rendering / no real controller: joy wiring is verified at the
##   signal-connection level only.
## - Godot 4 has no public Signal.get_connection_count(), so we assert on a
##   specific binding we hold (the scene's own joy handler callable).
## - One full scene boot (ready -> exit tree) bounds this file; heavier lifecycle
##   scenarios belong in the in-tree GUI tests.

const M1Scene = preload("res://scripts/m1_scene.gd")
var failures := 0
var checks := 0
var scene: Node = null
var scene_joy_cb: Callable = Callable()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _boot_scene() -> Node:
	var s: Node = M1Scene.new()
	s.name = "M1SignalTest"
	s.checkpoint_root = "user://m1-signal-teardown-test-%d" % Time.get_ticks_usec()
	root.add_child(s)
	# _ready() runs synchronously on add_child; the tracked connections (which
	# include the Input binding) are established by then. Backend readiness is
	# irrelevant to signal bookkeeping, so no wait loop.
	await process_frame
	return s

func _joy_connected() -> bool:
	if not Input.has_signal("joy_connection_changed"):
		return false
	return Input.joy_connection_changed.is_connected(scene_joy_cb)

func _init() -> void:
	# --- Bookkeeping exists ---------------------------------------------
	scene = await _boot_scene()
	check(is_instance_valid(scene), "scene booted")
	if not is_instance_valid(scene):
		_finish()
		return
	check(scene.has_method("_track_connect"), "_track_connect exists")
	check(scene.has_method("_disconnect_tracked_signals"), "_disconnect_tracked_signals exists")
	check(scene.has_method("_exit_tree"), "_exit_tree exists")
	var tv: Variant = scene.get("_signal_teardown")
	check(tv is Array, "scene exposes the _signal_teardown array")
	var tracked: Array = tv if tv is Array else []
	check(tracked.size() >= 4, "scene tracked 4+ connections after _ready (found %d)" % tracked.size())

	# --- Concrete Input binding present while alive -----------------------
	scene_joy_cb = scene._on_joy_connection_changed if scene.has_method("_on_joy_connection_changed") else Callable()
	check(not scene_joy_cb.is_null(), "scene exposes the joy handler callable")
	check(Input.has_signal("joy_connection_changed"), "Input.joy_connection_changed exists")
	check(_joy_connected(), "scene's joy handler connected to Input while alive")

	# --- Exit tree tears the connection down -----------------------------
	scene._exit_tree()
	await process_frame
	var tv2: Variant = scene.get("_signal_teardown")
	check(not (tv2 is Array) or (tv2 as Array).is_empty(), "_signal_teardown cleared after _exit_tree")
	check(not _joy_connected(), "scene's joy handler DISCONNECTED from Input after _exit_tree")

	_finish()

func _finish() -> void:
	if failures > 0:
		print("FAIL checks=%d failures=%d" % [checks, failures])
		quit(1)
	print("PASS checks=%d failures=0" % checks)
	quit(0)
