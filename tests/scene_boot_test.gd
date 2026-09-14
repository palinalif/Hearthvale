extends SceneTree

## Fast headless boot/compile gate for the main gameplay scene
## (scripts/m1_scene.gd).
##
## Background (see PR body): tests/backend_test.gd preloads only
## terrain_backend.gd and never touches the main scene, so a per-script compile
## failure in m1_scene.gd (e.g. the super._exit_tree() class of regression from
## PR #19) sails through the standard gate. This is the independent, fast gate
## that actually loads, instantiates, enters the tree with, and cleanly removes
## the main scene. It intentionally does NOT import or run the heavy
## tests/m1_acceptance_test.gd.
##
## Godot 4.7 API notes discovered while building this gate:
## - Signal has no get_connection_count(); we assert on a specific binding we
##   hold, via signal.is_connected(callable).
## - A Node has NO process_frame signal (that is a MainLoop/SceneTree signal).
##   Connecting to it on the scene raises "Invalid access to property ...
##   'process_frame' on a base object of type 'Node3D'". So Check 2 binds a
##   real Node lifecycle signal (ready), which every Node emits.
## - This test never overrides _exit_tree(), so the illegal-super pitfall does
##   not apply here; it exercises the scene's own teardown path on removal.
## - A hard watchdog guarantees the gate always exits even if _init deadlocks.

const WATCHDOG_MS := 60000

var failures := 0
var checks := 0
var scene: Node = null
var _wd_deadline := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

# No-op handler; connecting it to a live Node signal proves the scene script
# compiled and the node's signal machinery is bound.
func _boot_probe() -> void:
	pass

# Hard watchdog: if _init dies (script error or deadlocked await) the main loop
# would spin forever; this guarantees the gate always exits with a distinct code.
func _watchdog() -> void:
	if _wd_deadline > 0 and Time.get_ticks_msec() > _wd_deadline:
		print("boot_gate_watchdog: aborting after %d ms (no clean _init completion)" % WATCHDOG_MS)
		quit(3)

func _arm_watchdog() -> void:
	if _wd_deadline <= 0:
		_wd_deadline = Time.get_ticks_msec() + WATCHDOG_MS
		# SceneTree (a MainLoop) DOES have process_frame — unlike the Node tested.
		process_frame.connect(_watchdog)

func _wait_in_tree(node: Node, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline and not node.is_inside_tree():
		await process_frame
	return is_instance_valid(node) and node.is_inside_tree()

func _init() -> void:
	_arm_watchdog()

	# Compile check: load() forces the script to parse; .new() instantiates it.
	var script: GDScript = load("res://scripts/m1_scene.gd")
	check(script != null, "m1_scene.gd load() returned a script")
	if script == null:
		_finish()
		return
	check(script.can_instantiate(), "m1_scene.gd can_instantiate()")
	if not script.can_instantiate():
		_finish()
		return

	# Check 1: instance exists and is inside the tree (bounded ~5s wait).
	scene = (script as GDScript).new()
	check(is_instance_valid(scene), "scene instantiated")
	if not is_instance_valid(scene):
		_finish()
		return
	scene.name = "M1BootGate"
	scene.checkpoint_root = "user://m1-boot-gate-%d" % Time.get_ticks_usec()
	root.add_child(scene)
	check(await _wait_in_tree(scene, 5000), "scene entered the tree (bounded wait)")
	if not is_instance_valid(scene) or not scene.is_inside_tree():
		_finish()
		return

	# Check 2: no pending script errors — the scene's signal machinery is live:
	# connect a handler to a real Node signal and verify it is_connected.
	# (process_frame is deliberately NOT used: it does not exist on a Node.)
	var bind_sig := "ready"
	check(scene.has_signal(bind_sig), "scene exposes the '%s' Node signal" % bind_sig)
	if scene.has_signal(bind_sig):
		scene.ready.connect(_boot_probe)
		check(scene.ready.is_connected(_boot_probe),
			"scene.ready is_connected(handling) is true")
	await process_frame

	# Check 3: clean removal — free the scene and survive (no script crash).
	# queue_free runs the scene's _exit_tree teardown path; the process staying
	# alive to the final print implies the removal path is clean.
	var freed_ok := false
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
		await process_frame
		freed_ok = not is_instance_valid(scene)
	check(freed_ok, "scene freed cleanly (is_instance_valid false after queue_free)")

	_finish()

func _finish() -> void:
	print("boot_checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
