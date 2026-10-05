extends SceneTree
## Window glow contract: a cottage's window panes are self-emissive, so a lit
## interior reads from outside, and the lighting profile's bloom turns that
## emission into visible glow.
##
## Presentation only. This asserts no light node, no world input change, no
## save/authority field, and no change to non-window cottage geometry.
const World = preload("res://scripts/building_world.gd")
const CottageVisual = preload("res://scripts/cottage_visual.gd")
const Profile = preload("res://scripts/visual_lighting_profile.gd")
const WINDOW_KIND := "window"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := World.new()
	world.add_detail("building-1", WINDOW_KIND, "wall-front", Vector3(0, 1.5, -7.02), "window_cottage_diamond")
	world.add_detail("building-1", WINDOW_KIND, "wall-back", Vector3(0, 1.5, 7.02), "window_cottage_diamond")
	world.add_detail("building-1", "flower_box", "wall-front", Vector3(0, 0.9, -7.02), "flower_box_wood")
	world.add_detail("building-1", "shutter", "wall-back", Vector3(0, 3.4, 7.02), "shutter_wood")
	var visual := CottageVisual.new()
	root.add_child(visual)
	_check(visual.apply_building(world.get_building("building-1"), 0), "cottage builds with windows")

	var panes := _emissive_window_panes(visual)
	_check(panes.size() >= 2, "every placed window pane is self-emissive", "found %d" % panes.size())
	var warm := true
	for pane in panes:
		var mat: StandardMaterial3D = pane
		if mat.emission.g <= mat.emission.r and mat.emission.b >= mat.emission.g:
			warm = false
	_check(warm, "the pane glow is warm, not cool")
	_check(panes.size() > 0 and float(panes[0].emission_energy_multiplier) > 0.0, "the pane glow carries energy")

	# Only windows glow: frames, sills, mullions, walls and roofs stay unlit.
	var lit_non_window := 0
	for node in _mesh_instances(visual):
		var mat: StandardMaterial3D = node.material_override
		if mat == null or not mat.emission_enabled: continue
		if str(node.name).begins_with("Detail_" + WINDOW_KIND): continue
		lit_non_window += 1
	_check(lit_non_window == 0, "non-window cottage geometry stays unlit", "%d lit non-window pieces" % lit_non_window)

	# The glow is visible: the lighting profile must propagate glow to the live
	# environment when a profile turns it on. (The shipped gameplay scene already
	# enables glow in m1_scene; this asserts the profile seam carries it.)
	var sun := DirectionalLight3D.new()
	var world_env := WorldEnvironment.new()
	world_env.environment = Environment.new()
	root.add_child(sun)
	root.add_child(world_env)
	var profile: Resource = Profile.new()
	profile.set("glow_enabled", true)
	_check(profile.call("apply_to", sun, world_env), "the lighting profile applies")
	var env := world_env.environment
	_check(env.glow_enabled, "a glow-enabled profile leaves glow enabled on the environment")
	_check(env.glow_intensity > 0.0, "glow carries intensity")
	_check(env.glow_bloom < 0.5, "glow bloom stays modest so unlit geometry is not washed out")
	_check(env.background_mode != Environment.BG_COLOR, "the profile keeps the world sky, not a flat colour")
	_check(env.glow_strength > 0.0 and env.glow_bloom > 0.0, "glow strength and bloom are both live")

	# Glow off stays off: the profile must not light a scene that did not ask for it.
	var plain: Resource = Profile.new()
	var world_env2 := WorldEnvironment.new()
	world_env2.environment = Environment.new()
	root.add_child(world_env2)
	_check(plain.call("apply_to", sun, world_env2) and not world_env2.environment.glow_enabled, "a glow-disabled profile leaves the scene unlit")

	print("M2 WINDOW GLOW %s: %d/%d checks" % ["PASS" if failures == 0 else "FAIL", checks - failures, checks])
	quit(0 if failures == 0 else 1)

func _mesh_instances(visual: Node) -> Array:
	var found: Array = []
	var stack: Array = [visual]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is MeshInstance3D:
			found.append(node)
	return found

func _emissive_window_panes(visual: Node) -> Array:
	var found: Array = []
	for node in _mesh_instances(visual):
		if not str(node.name).begins_with("Detail_" + WINDOW_KIND): continue
		var mat: StandardMaterial3D = node.material_override
		if mat != null and mat.emission_enabled: found.append(mat)
	return found

func _check(condition: bool, label: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: %s %s" % [label, detail])
