@tool
extends Node3D

func _ready() -> void:
	print("HEARTHVALE_MCP_SMOKE_READY")
	if not Engine.is_editor_hint():
		return
	var es := EditorInterface.get_editor_settings()
	es.set_setting("godot_ai/mcp_client_scope", "project")
	var command := McpClientConfigurator.manual_command("codex")
	print("HEARTHVALE_MCP_MANUAL_COMMAND")
	print(command)
