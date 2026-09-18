extends Node
## E2E host for the debug TCP bridge: a minimal stub game that exposes
## debug_test_action (the same contract scripts/m1_scene.gd implements) and
## loads the REAL res://scripts/m1_debug_bridge.gd as its child.
##
## Run as a separate process so an external Python socket client can exercise
## the actual wire:  godot --headless --path . .probe/bridge_e2e.tscn
##
## This file is a throwaway test host (untracked under .probe/), never shipped.

var sculpt_tool := "raise"
var bridge_ready := false

func _ready() -> void:
	var bridge: Node = load("res://scripts/m1_debug_bridge.gd").new()
	bridge.name = "virtual_controller_bridge"
	add_child(bridge)
	bridge_ready = bridge.get("enabled") == true
	print("E2E_HOST_READY bridge_enabled=", bridge_ready)

## Mirror of m1_scene.debug_test_action contract (subset: state/select_tool).
func debug_test_action(action: String, args: Array) -> Dictionary:
	match action:
		"state":
			return {"type": "state", "tool": sculpt_tool, "menu_open": false}
		"select_tool":
			if args.size() < 1:
				return {"type": "error", "message": "select_tool needs a tool"}
			var tool := String(args[0])
			const TOOLS := ["raise", "dig", "smooth", "level", "slope", "water", "foliage", "tree"]
			if TOOLS.has(tool):
				sculpt_tool = tool
			return {"type": "ok", "tool": sculpt_tool}
		_:
			return {"type": "error", "message": "unknown action: " + action}
