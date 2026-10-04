extends SceneTree
const VisualLightingProfile = preload("res://scripts/visual_lighting_profile.gd")

## Verifies that a placed path lantern carries a warm glow: the authored glass
## and flame surfaces emit (flame hotter than glass), nothing else does, the
## flame light sits in the authored flame volume, a lighting profile retunes
## both, and detaching leaves the prop exactly as it was.

const LanternGlow = preload("res://scripts/m2_lantern_glow.gd")
const LANTERN_POSITION := Vector2(19.0, 24.25)
const LANTERN_YAW_DEGREES := 0.0

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	var visual := M2HamletVisual.new() as Node
	root.add_child(visual)
	await process_frame
	_place_lantern(visual)
	await process_frame
	_check_authored_authority()
	_check_glow(visual)
	_check_profile(visual)
	await _check_detach(visual)
	_finish()

func _profile(scale: float, energy: float) -> Resource:
	var resource := VisualLightingProfile.new()
	resource.lamp_emissive_scale = scale
	resource.lamp_light_energy = energy
	return resource

func _place_lantern(visual: Node) -> void:
	var records: Array = [{
		"kind": "furniture",
		"id": 1,
		"style_id": "lantern",
		"position": [LANTERN_POSITION.x, LANTERN_POSITION.y],
		"size": [0.5, 0.5],
		"yaw_degrees": LANTERN_YAW_DEGREES,
	}]
	visual.rebuild_furniture(records)

func _lantern(visual: Node) -> MeshInstance3D:
	for node_value in visual._furniture_nodes:
		var node := node_value as MeshInstance3D
		if node == null: continue
		if String(node.get_meta("authored_asset", "")).contains("path_lantern"): return node
	return null


func _effective_material(node: MeshInstance3D, index: int) -> StandardMaterial3D:
	var override := node.get_surface_override_material(index) as StandardMaterial3D
	if override != null: return override
	return node.mesh.surface_get_material(index) as StandardMaterial3D


func _colour_distance(a: Color, b: Color) -> float:
	var dr := a.r - b.r
	var dg := a.g - b.g
	var db := a.b - b.b
	return sqrt(dr * dr + dg * dg + db * db)

## The authored asset record is the authority for which palettes emit; the
## runtime glow must target exactly those roles.
func _check_authored_authority() -> void:
	var file := FileAccess.open("res://assets/models/magicavoxel/hearthvale_prop_path_lantern.asset.json", FileAccess.READ)
	if file == null:
		# The authored lantern asset record is M2 authored-prop work. Where this
		# source predates that layer there is nothing to glow, so skip cleanly.
		print("M2 lantern glow checks SKIPPED (authored lantern asset record not in this source)")
		quit(0)
		return
	var record: Variant = JSON.parse_string(file.get_as_text())
	file = null
	if not (record is Dictionary):
		_fail("authored lantern asset record is not a dictionary")
		return
	var indices: Array = (record as Dictionary).get("emissive_palette_indices", [])
	# JSON numbers arrive as floats, so compare on integers.
	var declared: Array[int] = []
	for index in indices: declared.append(int(index))
	if declared.size() != 2: _fail("authored lantern declares %d emissive palettes" % declared.size())
	if not declared.has(M2LanternGlow.GLASS_PALETTE_INDEX):
		_fail("authored lantern glass palette %d is not declared emissive" % M2LanternGlow.GLASS_PALETTE_INDEX)
	if not declared.has(M2LanternGlow.FLAME_PALETTE_INDEX):
		_fail("authored lantern flame palette %d is not declared emissive" % M2LanternGlow.FLAME_PALETTE_INDEX)
	for index in declared:
		if int(index) == M2LanternGlow.GLASS_PALETTE_INDEX: continue
		if int(index) == M2LanternGlow.FLAME_PALETTE_INDEX: continue
		_fail("authored lantern declares palette %d emissive with no runtime role" % int(index))
	_ok("authored emissive palettes match the runtime glass and flame roles")

func _check_glow(visual: Node) -> void:
	var glow_nodes: Array = []
	for node_value in visual._furniture_nodes:
		var node := node_value as MeshInstance3D
		if node == null: continue
		for child in node.get_children():
			if child is M2LanternGlow: glow_nodes.append(child)
	if glow_nodes.size() != 1:
		_fail("expected one lantern glow, got %d" % glow_nodes.size())
		return
	var glow: Node = glow_nodes[0]
	var lantern := _lantern(visual)
	if lantern == null:
		_fail("no authored lantern furniture node found")
		return
	var mesh := lantern.mesh as ArrayMesh
	var roles: Dictionary = M2LanternGlow.emissive_surface_indices(mesh)
	var glass_index := int(roles["glass"])
	var flame_index := int(roles["flame"])
	if glass_index < 0: _fail("authored lantern has no glass surface to glow")
	if flame_index < 0: _fail("authored lantern has no flame surface to glow")
	var glass := _effective_material(lantern, glass_index) as StandardMaterial3D
	var flame := _effective_material(lantern, flame_index) as StandardMaterial3D
	if glass == null or not glass.emission_enabled:
		_fail("lantern glass surface does not emit")
	if flame == null or not flame.emission_enabled:
		_fail("lantern flame surface does not emit")
	if glass.emission_energy_multiplier <= 0.0:
		_fail("lantern glass emission energy is not positive")
	if flame.emission_energy_multiplier <= 0.0:
		_fail("lantern flame emission energy is not positive")
	# The flame is the emitter, so it must read hotter than the glass it lights.
	if flame.emission_energy_multiplier <= glass.emission_energy_multiplier:
		_fail("lantern flame does not read hotter than its glass")
	if _colour_distance(glass.emission, glass.albedo_color) > 0.01:
		_fail("lantern glass glows in a colour that is not its own glass colour")
	if _colour_distance(flame.emission, flame.albedo_color) > 0.01:
		_fail("lantern flame glows in a colour that is not its own flame colour")
	# Only the authored emissive roles glow: timber and the stone base stay dark.
	for index in mesh.get_surface_count():
		if index == glass_index or index == flame_index: continue
		var shell := _effective_material(lantern, index) as StandardMaterial3D
		if shell != null and shell.emission_enabled:
			_fail("lantern surface %d (%s) glows but is not an authored emissive role" % [index, shell.resource_name])
	var light := _flame_light(lantern)
	if light == null:
		_fail("lantern has no flame light")
		return
	if light.light_energy <= 0.0:
		_fail("flame light energy is not positive")
	if light.omni_range <= 0.0:
		_fail("flame light has no range")
	# The flame must sit in the lamp, not at the prop's origin.
	var origin := lantern.global_transform.origin
	if light.global_position.distance_to(origin) < 0.5:
		_fail("flame light sits at the prop origin instead of in the lamp")
	var bounds := _world_bounds(lantern)
	if not bounds.has_point(light.global_position):
		_fail("flame light is outside the lantern's own bounds")
	# The light must be seated in the authored flame volume, not at a stale
	# constant that only fits the old procedural proportions.
	var flame_centroid := lantern.global_transform * M2LanternGlow.surface_centroid(mesh, flame_index, Vector3.ZERO)
	if light.global_position.distance_to(flame_centroid) > 0.25:
		_fail("flame light is not seated in the authored flame volume")

func _check_profile(visual: Node) -> void:
	var glow := _glow_of(visual)
	if glow == null:
		_fail("no glow to retune")
		return
	var daylight_scale := float(glow.emissive_scale)
	var daylight_energy := float(glow.light_energy)
	glow.apply_profile(_profile(0.9, 1.8))
	if not is_equal_approx(float(glow.emissive_scale), 0.9) or not is_equal_approx(float(glow.light_energy), 1.8):
		_fail("profile did not retune the glow")
	var lantern := _lantern(visual)
	var roles: Dictionary = M2LanternGlow.emissive_surface_indices(lantern.mesh)
	var glass := _effective_material(lantern, int(roles["glass"])) as StandardMaterial3D
	var flame := _effective_material(lantern, int(roles["flame"])) as StandardMaterial3D
	if glass.emission_energy_multiplier <= daylight_scale:
		_fail("glass emission did not brighten under the night profile")
	if flame.emission_energy_multiplier <= daylight_scale:
		_fail("flame emission did not brighten under the night profile")
	var light := _flame_light(lantern)
	if light == null or light.light_energy <= daylight_energy:
		_fail("flame light did not brighten under the night profile")
	glow.apply_profile(null)
	if not is_equal_approx(float(glow.emissive_scale), daylight_scale) or not is_equal_approx(float(glow.light_energy), daylight_energy):
		_fail("null profile did not restore the daylight glow")

func _check_detach(visual: Node) -> void:
	var glow := _glow_of(visual)
	if glow == null:
		_fail("no glow to detach")
		return
	var lantern := _lantern(visual)
	var roles: Dictionary = M2LanternGlow.emissive_surface_indices(lantern.mesh)
	var glass_index := int(roles["glass"])
	var flame_index := int(roles["flame"])
	# The authored asset materials are the baseline: the glow must never change them.
	var authored_glass := lantern.mesh.surface_get_material(glass_index) as StandardMaterial3D
	var authored_flame := lantern.mesh.surface_get_material(flame_index) as StandardMaterial3D
	var light := _flame_light(lantern)
	if light == null:
		_fail("no flame light to detach")
		return
	glow.detach()
	await process_frame
	await process_frame
	var glass := _effective_material(lantern, glass_index) as StandardMaterial3D
	var flame := _effective_material(lantern, flame_index) as StandardMaterial3D
	if glass.emission_enabled:
		_fail("detach left the glass emitting")
	if flame.emission_enabled:
		_fail("detach left the flame emitting")
	if glass != authored_glass or flame != authored_flame:
		_fail("detach left material overrides on the lantern")
	if not is_equal_approx(glass.emission_energy_multiplier, authored_glass.emission_energy_multiplier) \
			or not is_equal_approx(flame.emission_energy_multiplier, authored_flame.emission_energy_multiplier):
		_fail("detach did not restore the authored emission energies")
	if light != null and is_instance_valid(light):
		_fail("detach left the flame light in the tree")
	if _glow_of(visual) != null:
		_fail("detach left the glow node in the tree")

func _glow_of(visual: Node) -> Node:
	for node_value in visual._furniture_nodes:
		var node := node_value as MeshInstance3D
		if node == null: continue
		for child in node.get_children():
			if child is M2LanternGlow: return child
	return null

func _flame_light(lantern: MeshInstance3D) -> OmniLight3D:
	for child in lantern.get_children():
		if child is OmniLight3D: return child as OmniLight3D
	return null

func _world_bounds(lantern: MeshInstance3D) -> AABB:
	var mesh := lantern.mesh as ArrayMesh
	if mesh == null: return AABB()
	var local := mesh.get_aabb()
	return lantern.global_transform * local

func _ok(message: String) -> void:
	checks += 1
	print("PASS: ", message)

func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL: ", message)

func _finish() -> void:
	if failures.is_empty(): print("M2 lantern glow checks passed")
	else: print("M2 lantern glow checks FAILED: ", ", ".join(failures))
	quit(0 if failures.is_empty() else 1)
