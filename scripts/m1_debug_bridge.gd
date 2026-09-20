extends Node
## Debug-only virtual-controller + telemetry bridge.
##
## A localhost-only TCP server (debug builds only) that injects virtual joypad
## input into the Godot InputMap — the same abstraction the physical controller
## uses — and returns machine-readable perf telemetry. The game reads the
## InputMap, not raw events, so virtual and physical input are indistinguishable
## and exercise the full real gameplay path. The physical controller keeps
## working: parse_input_event *adds* events, it never replaces the real ones.
##
## Transport: `adb forward tcp:<port> tcp:<port>`, then newline-delimited JSON.
## Binds loopback only (127.0.0.1), is gated behind OS.is_debug_build(), and is
## a self-contained leaf node that can be removed/compiled out cleanly.
##
## Protocol (one JSON object per line):
##   {"cmd":"ping"}                                  -> {"type":"pong"}
##   {"cmd":"set_stick","stick":"right","x":1,"y":0} -> {"type":"ok"}
##   {"cmd":"set_axis","axis":"right_x","value":0.8} -> {"type":"ok"}
##   {"cmd":"button","button":"a","pressed":true}    -> {"type":"ok"}
##   {"cmd":"reset_input"}                           -> {"type":"ok","reset":true}
##   {"cmd":"telemetry"}                             -> {"type":"telemetry",...}
##   {"cmd":"mark","name":"x"}                       -> {"type":"ok","mark":"x"}
##   {"cmd":"action","name":"select_tool","args":["water"]}
##                                                     -> {"type":"ok","tool":"water"}
##     "action" forwards a semantic verb to the scene's debug_test_action():
##     state | composition_dump | select_tool [tool] | view_context [terrain|building]
##     | cancel | undo | redo | world_stats | mesh_survey | perf | tune [target key value [index]]
##     | probe_nodes [class:X|name:Y, hide|show|disable|enable].
##     "tune" is also accepted as a top-level cmd (same args). Strokes themselves stay real
##     InputMap events (button "a" + stick), so the gameplay path is exercised, not bypassed.

const DEFAULT_PORT := 47123

# axis name -> JoyAxis
const AXIS_MAP := {
	"left_x": JOY_AXIS_LEFT_X, "left_y": JOY_AXIS_LEFT_Y,
	"right_x": JOY_AXIS_RIGHT_X, "right_y": JOY_AXIS_RIGHT_Y,
	"trigger_left": JOY_AXIS_TRIGGER_LEFT, "trigger_right": JOY_AXIS_TRIGGER_RIGHT,
}
# button name -> JoyButton
const BUTTON_MAP := {
	"a": JOY_BUTTON_A, "b": JOY_BUTTON_B, "x": JOY_BUTTON_X, "y": JOY_BUTTON_Y,
	"lb": JOY_BUTTON_LEFT_SHOULDER, "rb": JOY_BUTTON_RIGHT_SHOULDER,
	"lt": JOY_AXIS_TRIGGER_LEFT, "rt": JOY_AXIS_TRIGGER_RIGHT,
	"back": JOY_BUTTON_BACK, "start": JOY_BUTTON_START,
	"dpad_up": JOY_BUTTON_DPAD_UP, "dpad_down": JOY_BUTTON_DPAD_DOWN,
	"dpad_left": JOY_BUTTON_DPAD_LEFT, "dpad_right": JOY_BUTTON_DPAD_RIGHT,
}

var _server: TCPServer
var _client: StreamPeerTCP
var _buffer := ""
var _client_since_ms := 0
var _client_got_data := false
var _ready_ms := 0
var _world_stats_reported := false

# Virtual joypad state.
var _axes := {}   # JoyAxis -> float
var _buttons := {} # JoyButton -> bool
var enabled := false

func _ready() -> void:
	if not OS.is_debug_build():
		# Release builds: no server, no processing. Fully inert.
		set_process(false)
		return
	enabled = true
	var err: Error = ERR_UNAVAILABLE
	var attempt := 0
	# Bounded retry: a just force-stopped previous instance can hold 127.0.0.1:47123
	# for a few seconds, and a failed one-shot listen left the bridge dead for the
	# whole session (silent game, no telemetry) — seen on the Thor, 2026-07-19.
	while attempt < 15:
		var srv := TCPServer.new()
		err = srv.listen(DEFAULT_PORT, "127.0.0.1")  # loopback only
		if err == OK:
			_server = srv
			break
		attempt += 1
		await get_tree().create_timer(0.7).timeout
	if err != OK:
		enabled = false
		set_process(false)
		push_warning("VirtualControllerBridge: listen on 127.0.0.1:%d failed after %d tries (%s)" % [DEFAULT_PORT, attempt, error_string(err)])
		return
	# Explicitly enable the per-frame pump. (A script-defined _process usually
	# enables itself on ready; this makes it explicit and covers any future
	# change to that default.)
	set_process(true)
	_ready_ms = Time.get_ticks_msec()
	print("BRIDGE_LISTENING port=", DEFAULT_PORT)

func _process(_delta: float) -> void:
	if not enabled: return
	# One-shot, ~25 s after the scene is up (terrain meshing is done by then): a
	# world-stats snapshot in the launch log, so "why is my world slow?" never
	# depends on someone remembering to run a query. Stale dense forest worlds
	# (1.5M+ tris across thousands of tree meshes) vs the ~158k-class starter
	# valley are instantly distinguishable in logcat.
	if not _world_stats_reported and Time.get_ticks_msec() - _ready_ms > 25000:
		_world_stats_reported = true
		var parent := get_parent()
		if parent != null and parent.has_method("debug_test_action"):
			var stats: Variant = parent.call("debug_test_action", "world_stats", [])
			print("WORLD_STATS ", JSON.stringify(stats))
	_pump_socket()
	_inject_virtual_input()

func _exit_tree() -> void:
	if _client != null: _client.disconnect_from_host()
	_client = null
	_server = null

func _pump_socket() -> void:
	# _server is null until listen succeeds (and during the post-failure
	# window); a null-deref here spams a script error every frame and costs
	# real time on an already frame-starved device.
	if _server == null:
		return
	if _client == null and _server.is_connection_available():
		_client = _server.take_connection()
		_client_since_ms = Time.get_ticks_msec()
		_client_got_data = false
	if _client == null:
		return
	# Pump first: 4.7.2 StreamPeerSocket statuses are 0=none 1=connecting
	# 2=connected 3=error, and is_open() no longer exists. A freshly accepted
	# peer can report NONE before its first poll, so only a hard ERROR is
	# fatal here; dead-but-silent peers are recycled by the no-data grace
	# window below. (The read is gated on available bytes, not status, because
	# headless same-process loopback can linger in CONNECTING while data
	# flows; on device the status is CONNECTED and it reads identically.)
	_client.poll()
	var client_status := _client.get_status()
	if client_status == StreamPeerTCP.STATUS_ERROR:
		_client = null
		_buffer = ""
		return
	# Query the byte count only while the socket is open: on a closed one,
	# get_available_bytes() logs `Condition "!is_open()"` and returns -1,
	# spamming the log (logcat) every frame while a dead peer is recycled.
	var avail := 0
	if client_status == StreamPeerTCP.STATUS_CONNECTED:
		avail = _client.get_available_bytes()
	if avail > 0:
		# Godot 4.7: get_data() returns [Error, PackedByteArray], not a bare buffer.
		var res: Array = _client.get_data(avail)
		if res.size() == 2 and int(res[0]) == OK:
			var bytes: PackedByteArray = res[1]
			_client_got_data = true
			_buffer += bytes.get_string_from_utf8()
			var idx := _buffer.find("\n")
			while idx >= 0:
				var line := _buffer.left(idx).strip_edges()
				_buffer = _buffer.substr(idx + 1)
				if line.length() > 0:
					_reply(_handle_command(line))
				idx = _buffer.find("\n")
	elif _client_got_data and client_status == StreamPeerTCP.STATUS_NONE:
		# Real EOF (client closed after a live session).
		_client = null
		_buffer = ""
	elif not _client_got_data and Time.get_ticks_msec() - _client_since_ms > 3000:
		# Connected and went silent: recycle the slot.
		_client = null
		_buffer = ""

## Dispatch one protocol line; returns the reply dict (the socket layer sends
## it). Returned directly so headless tests can exercise the protocol without a
## live socket (same-process headless TCP peers are unreliable).
func _handle_command(line: String) -> Dictionary:
	var json := JSON.new()
	# Reject non-object JSON (arrays, numbers...) before typing, or the
	# `Dictionary` assignment aborts the frame with a script error and the
	# client gets no reply at all.
	if json.parse(line) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"type": "error", "message": "bad json"}
	var cmd: Dictionary = json.data
	match String(cmd.get("cmd", "")):
		"ping":
			return {"type": "pong", "ts": Time.get_ticks_msec()}
		"set_stick":
			var stick := String(cmd.get("stick", "left"))
			var x := float(cmd.get("x", 0.0)); var y := float(cmd.get("y", 0.0))
			if stick == "left":
				_axes[JOY_AXIS_LEFT_X] = x; _axes[JOY_AXIS_LEFT_Y] = y
			else:
				_axes[JOY_AXIS_RIGHT_X] = x; _axes[JOY_AXIS_RIGHT_Y] = y
			return {"type": "ok", "stick": stick, "x": x, "y": y}
		"set_axis":
			var name := String(cmd.get("axis", ""))
			if AXIS_MAP.has(name):
				_axes[AXIS_MAP[name]] = float(cmd.get("value", 0.0))
				return {"type": "ok", "axis": name}
			return {"type": "error", "message": "unknown axis"}
		"button":
			var name := String(cmd.get("button", ""))
			if BUTTON_MAP.has(name):
				var pressed := bool(cmd.get("pressed", true))
				_buttons[BUTTON_MAP[name]] = pressed
				return {"type": "ok", "button": name, "pressed": pressed}
			return {"type": "error", "message": "unknown button"}
		"reset_input":
			_axes.clear(); _buttons.clear()
			return {"type": "ok", "reset": true}
		"action":
			var game := get_parent()
			var args: Variant = cmd.get("args", [])
			if not (args is Array):
				args = []
			if game != null and game.has_method("debug_test_action"):
				var res: Variant = game.debug_test_action(String(cmd.get("name", "")), args)
				return res if res is Dictionary else {"type": "error", "message": "action failed"}
			return {"type": "error", "message": "no debug action host"}
		"frame_clock":
			return _frame_clock()
		"tune":
			# Top-level sugar for action/name=tune (keeps feature-perf scripts terse).
			var tune_game := get_parent()
			var tune_args: Variant = cmd.get("args", [])
			if not (tune_args is Array):
				tune_args = []
			if tune_game != null and tune_game.has_method("debug_test_action"):
				var tune_res: Variant = tune_game.debug_test_action("tune", tune_args)
				return tune_res if tune_res is Dictionary else {"type": "error", "message": "tune failed"}
			return {"type": "error", "message": "no debug action host"}
		"telemetry":
			return _telemetry()
		"mark":
			return {"type": "ok", "mark": String(cmd.get("name", ""))}
		_:
			return {"type": "error", "message": "unknown cmd"}

func _telemetry() -> Dictionary:
	return {
		"type": "telemetry",
		"fps": Engine.get_frames_per_second(),
		"frame_ms": 1000.0 / max(Engine.get_frames_per_second(), 0.001),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"memory_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1024.0 / 1024.0,
		# The scene's own per-phase timers (camera/focus/preview/presentation/...),
		# so a feature-perf run shows which scene phase eats CPU on device.
		"scene_costs": _scene_costs(),
	}

func _scene_costs() -> Dictionary:
	var p := get_parent()
	if p != null and p.get("last_frame_costs") is Dictionary:
		return (p.get("last_frame_costs") as Dictionary).duplicate(true)
	return {}

## Main-loop phase breakdown (ms) from the root-window probe
## (frame_clock_probe.gd, added by m1_scene): pre = engine/input + nodes before
## the gameplay scene's _process; scene = the scene chain's _process itself;
## post = nodes after the scene + physics + render hand-off + vsync wait.
## Rolling 300-frame window averages; `samples` = frames since the probe's last
## 300-frame reset (small while the window is filling).
func _frame_clock() -> Dictionary:
	var p := get_parent()
	if p == null:
		return {"type": "error", "message": "no scene"}
	var fc: Variant = p.get("_frame_clock_probe")
	if fc == null:
		return {"type": "error", "message": "no frame clock (release build?)"}
	var out: Dictionary = fc.read()
	out["type"] = "frame_clock"
	return out

func _reply(dict: Dictionary) -> void:
	if _client == null:
		return
	if _client.put_data((JSON.stringify(dict) + "\n").to_utf8_buffer()) != OK:
		# Write failed (peer gone); drop so the slot recycles.
		_client = null
		_buffer = ""

## Inject the current virtual joypad state as InputMap events. Called once per
## frame in _process; the game's next _input reads the updated axis/button state.
func _inject_virtual_input() -> void:
	for axis in _axes:
		var value := float(_axes[axis])
		var ev := InputEventJoypadMotion.new()
		ev.axis = axis
		ev.axis_value = value
		Input.parse_input_event(ev)
	for button in _buttons:
		var pressed := bool(_buttons[button])
		var bev := InputEventJoypadButton.new()
		bev.button_index = button
		bev.pressed = pressed
		Input.parse_input_event(bev)
