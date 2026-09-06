extends Node

## Small, self-contained native Voxel Tools availability and data-access probe.
## It intentionally avoids static references so the script still parses without
## the extension installed.

const PROBE_SIZE := Vector3i(16, 16, 16)
const CHANNEL_TYPE_FALLBACK := 0

@onready var status_label: Label = $Label

func _ready() -> void:
	var result := _run_probe()
	var probe_mode := "--probe" in OS.get_cmdline_user_args() or "--probe" in OS.get_cmdline_args()
	if probe_mode:
		print(JSON.stringify(result))
		get_tree().quit(0 if bool(result.get("ok", false)) else 1)
	else:
		status_label.text = ("Native backend loaded\nGodot %s" % result.get("engine_version", "unknown")) if result.get("ok", false) else ("Native backend unavailable\n%s" % result.get("error", "unknown error"))

func _run_probe() -> Dictionary:
	var result := {
		"ok": false,
		"engine_version": str(Engine.get_version_info().get("string", "unknown")),
		"classes": {},
		"channel_type": CHANNEL_TYPE_FALLBACK,
		"samples": {},
	}
	var required := ["VoxelBuffer", "VoxelTerrain", "VoxelMesherBlocky"]
	for class_id in required:
		result["classes"][class_id] = ClassDB.class_exists(class_id)
		if not result["classes"][class_id]:
			result["error"] = "Missing native class: %s" % class_id
			return result

	var buffer: Object = ClassDB.instantiate("VoxelBuffer")
	if buffer == null:
		result["error"] = "ClassDB could not instantiate VoxelBuffer"
		return result
	var channel := _channel_type()
	result["channel_type"] = channel
	buffer.create(PROBE_SIZE.x, PROBE_SIZE.y, PROBE_SIZE.z)
	var lower := Vector3i(3, 2, 4)
	var upper := Vector3i(3, 9, 4)
	buffer.set_voxel(11, lower.x, lower.y, lower.z, channel)
	buffer.set_voxel(22, upper.x, upper.y, upper.z, channel)
	var lower_value := int(buffer.get_voxel(lower.x, lower.y, lower.z, channel))
	var upper_value := int(buffer.get_voxel(upper.x, upper.y, upper.z, channel))
	result["samples"] = {"lower": lower_value, "upper": upper_value}
	result["ok"] = lower_value == 11 and upper_value == 22 and lower_value != upper_value
	if not result["ok"]:
		result["error"] = "VoxelBuffer CHANNEL_TYPE set/get mismatch"
	return result

func _channel_type() -> int:
	# Voxel Tools declares CHANNEL_TYPE in its Channel enum (value 0). Resolve
	# the named constant when available, while retaining a parse-safe fallback.
	if ClassDB.has_method("class_get_integer_constant"):
		var resolved: int = ClassDB.class_get_integer_constant("VoxelBuffer", "CHANNEL_TYPE")
		if resolved >= 0:
			return resolved
	return CHANNEL_TYPE_FALLBACK
