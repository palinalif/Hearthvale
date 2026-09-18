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
	_server = TCPServer.new()
	var err := _server.listen(DEFAULT_PORT, "127.0.0.1")  # loopback only
	if err != OK:
		enabled = false
		set_process(false)
		push_warning("VirtualControllerBridge: listen on 127.0.0.1:%d failed (%s)" % [DEFAULT_PORT, error_string(err)])
		return

func _process(_delta: float) -> void:
	if not enabled: return
	_pump_socket()
	_inject_virtual_input()

func _exit_tree() -> void:
	if _client != null: _client.disconnect_from_host()
	_client = null
	_server = null

func _pump_socket() -> void:
	if _client == null and _server.is_connection_available():
		_client = _server.take_connection()
	if _client == null:
		return
	if _client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		var avail := _client.get_available_bytes()
		if avail > 0:
			var bytes: PackedByteArray = _client.get_data(avail)
			_buffer += bytes.get_string_from_utf8()
		var idx := _buffer.find("\n")
		while idx >= 0:
			var line := _buffer.left(idx).strip_edges()
			_buffer = _buffer.substr(idx + 1)
			if line.length() > 0:
				_handle_command(line)
			idx = _buffer.find("\n")
	elif _client.get_status() == StreamPeerTCP.STATUS_ERROR:
		_client = null
		_buffer = ""

func _handle_command(line: String) -> void:
	var json := JSON.new()
	if json.parse(line) != OK:
		_reply({"type": "error", "message": "bad json"})
		return
	var cmd: Dictionary = json.data
	match String(cmd.get("cmd", "")):
		"ping":
			_reply({"type": "pong", "ts": Time.get_ticks_msec()})
		"set_stick":
			var stick := String(cmd.get("stick", "left"))
			var x := float(cmd.get("x", 0.0)); var y := float(cmd.get("y", 0.0))
			if stick == "left":
				_axes[JOY_AXIS_LEFT_X] = x; _axes[JOY_AXIS_LEFT_Y] = y
			else:
				_axes[JOY_AXIS_RIGHT_X] = x; _axes[JOY_AXIS_RIGHT_Y] = y
			_reply({"type": "ok", "stick": stick, "x": x, "y": y})
		"set_axis":
			var name := String(cmd.get("axis", ""))
			if AXIS_MAP.has(name):
				_axes[AXIS_MAP[name]] = float(cmd.get("value", 0.0))
				_reply({"type": "ok", "axis": name})
			else:
				_reply({"type": "error", "message": "unknown axis"})
		"button":
			var name := String(cmd.get("button", ""))
			if BUTTON_MAP.has(name):
				var pressed := bool(cmd.get("pressed", true))
				_buttons[BUTTON_MAP[name]] = pressed
				_reply({"type": "ok", "button": name, "pressed": pressed})
			else:
				_reply({"type": "error", "message": "unknown button"})
		"reset_input":
			_axes.clear(); _buttons.clear()
			_reply({"type": "ok", "reset": true})
		"telemetry":
			_reply(_telemetry())
		"mark":
			_reply({"type": "ok", "mark": String(cmd.get("name", ""))})
		_:
			_reply({"type": "error", "message": "unknown cmd"})

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
	}

func _reply(dict: Dictionary) -> void:
	if _client == null:
		return
	_client.put_data((JSON.stringify(dict) + "\n").to_utf8_buffer())

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
