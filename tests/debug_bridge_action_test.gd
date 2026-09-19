extends SceneTree

## Verifies the debug-only semantic action API (scene.debug_test_action) and the
## bridge's "action" protocol dispatch (the wire format tools/feature_perf.py
## speaks), headless. Strokes are NOT bypassed: the test only covers
## selection/query verbs; stroke steps in specs stay real InputMap events.
var failures := 0
var checks := 0
var scene: Node

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)

func _initialize() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.checkpoint_root = "user://debug-bridge-action-test-%s" % Time.get_ticks_usec()
	scene.test_mode = true
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 30000
	while (scene.backend == null or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(scene.backend != null and scene.backend.is_ready(), "native backend ready")
	if scene.backend == null or not scene.backend.is_ready():
		await _finish()
		return

	# --- direct verb semantics (same functions the real input handlers call) ---
	var st: Dictionary = scene.debug_test_action("state", [])
	_check(st.get("type") == "state" and st.get("tool") == "raise" and st.get("stroke_active") == false,
		"state reports default terrain tool")
	_check(scene.debug_test_action("select_tool", ["water"]).get("tool") == "water",
		"select_tool switches to water (virtual dispatch)")
	_check(scene.get("water_placement_active") == true, "water placement engaged by select_tool")
	_check(scene.debug_test_action("select_tool", ["raise"]).get("tool") == "raise", "select_tool back to raise")
	_check(scene.get("water_placement_active") == false, "water placement cancelled on tool switch")
	_check(scene.debug_test_action("select_tool", []).get("type") == "error", "select_tool without args is rejected")
	_check(scene.debug_test_action("nope", []).get("type") == "error", "unknown action is rejected")

	# --- bridge protocol dispatch (the feature_perf wire format) ---
	# The JSON protocol is exercised via _handle_command rather than a live socket:
	# in headless, same-process loopback TCP peers are unreliable (peers linger in
	# CONNECTING and client->server bytes can be dropped, with no game code
	# involved). The wire itself is a plain newline-delimited JSON TCP stream,
	# verified on the real device by the feature_perf run.
	var bridge := scene.get_node_or_null("virtual_controller_bridge")
	_check(bridge != null, "bridge node present in debug build")
	if bridge == null:
		await _finish()
		return
	_check(bridge._handle_command("{\"cmd\":\"ping\"}").get("type") == "pong", "protocol ping/pong")
	var sel: Dictionary = bridge._handle_command("{\"cmd\":\"action\",\"name\":\"select_tool\",\"args\":[\"water\"]}")
	_check(sel.get("type") == "ok" and sel.get("tool") == "water", "protocol action select_tool -> water")
	var st2: Dictionary = bridge._handle_command("{\"cmd\":\"action\",\"name\":\"state\",\"args\":[]}")
	_check(st2.get("type") == "state" and st2.get("tool") == "water" and st2.get("water_placement_active") == true,
		"protocol action state reflects water placement")
	_check(bridge._handle_command("{\"cmd\":\"telemetry\"}").get("type") == "telemetry", "protocol telemetry")
	_check(bridge._handle_command("not json").get("type") == "error", "protocol rejects bad json")
	_check(bridge._handle_command("{\"cmd\":\"nope\"}").get("type") == "error", "protocol rejects unknown cmd")
	await _finish()

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene.queue_free()
		await process_frame
		await process_frame
	print("debug_bridge_action_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
