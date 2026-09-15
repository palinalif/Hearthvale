# tools/probe_godot.gd — ask the ACTUAL installed engine for the valid properties
# of a class, instead of guessing from model memory. Godot 3 names (e.g.
# adjustment_gamma, ssao_deitter_enabled, ground_top_color, shadow_max_distance)
# are a recurring source of runtime crashes that the parser never flags.
#
# Usage:  godot --headless --script tools/probe_godot.gd -- <ClassName>
#         godot --headless --script tools/probe_godot.gd  (prints all of the common ones)
extends SceneTree

const CLASSES := {
	"Environment": "core",
	"ProceduralSkyMaterial": "core",
	"DirectionalLight3D": "node",
	"Sky": "core",
	"WorldEnvironment": "node",
}

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = CLASSES.keys()
	for name in args:
		if not CLASSES.has(name):
			print("probe: unknown class '%s' (known: %s)" % [name, str(CLASSES.keys())])
			continue
		var inst: Object = _make(name)
		if inst == null:
			print("probe: could not instantiate %s" % name)
			continue
		var props: Array[String] = []
		for p in inst.get_property_list():
			props.append(p["name"] as String)
		props.sort()
		print("== %s (%d props) ==" % [name, props.size()])
		print(", ".join(props))
		quit(0)
	# args.is_empty() is handled above; reaching here means all failed
	quit(1)

func _make(name: String) -> Object:
	match name:
		"Environment": return Environment.new()
		"ProceduralSkyMaterial": return ProceduralSkyMaterial.new()
		"DirectionalLight3D": return DirectionalLight3D.new()
		"Sky": return Sky.new()
		"WorldEnvironment": return WorldEnvironment.new()
	return null
