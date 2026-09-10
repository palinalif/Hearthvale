extends SceneTree

const Flora = preload("res://scripts/vegetation_mesh.gd")
const Garden = preload("res://scripts/m1_garden_visual.gd")
const TREE_NAMES := ["orchard", "riverside", "wind", "orchard_compact", "riverside_young", "wind_low"]
const FOLIAGE_NAMES := ["grass", "wildflowers", "leafy", "seedgrass", "cream", "mauve", "reeds", "fern", "mushrooms", "mushrooms_flat", "mushrooms_flat_scatter"]
const ROCK_NAMES := ["slab", "split", "moss"]

var checks := 0
var failures := 0

func _initialize() -> void:
	for kind in ["tree", "foliage", "rock"]:
		var names: Array = TREE_NAMES if kind == "tree" else (FOLIAGE_NAMES if kind == "foliage" else ROCK_NAMES)
		_check(Flora.variant_count(kind) == names.size(), "%s exposes every authored variant" % kind)
		for variant in names.size():
			var expected := load("res://assets/models/magicavoxel/hearthvale_%s_%s.res" % [kind, names[variant]]) as Mesh
			var actual: Array = Flora.meshes(kind, variant)
			_check(actual.size() == expected.get_surface_count(), "%s variant %d keeps every authored palette surface" % [kind, variant])
			for surface in expected.get_surface_count():
				var source_arrays: Array = expected.surface_get_arrays(surface)
				var part_arrays: Array = actual[surface].surface_get_arrays(0)
				_check(part_arrays[Mesh.ARRAY_VERTEX] == source_arrays[Mesh.ARRAY_VERTEX] and part_arrays[Mesh.ARRAY_INDEX] == source_arrays[Mesh.ARRAY_INDEX], "%s variant %d surface %d uses authored geometry" % [kind, variant, surface])

	var garden := Garden.new()
	root.add_child(garden)
	var records: Array = []
	for variant in TREE_NAMES.size():
		records.append({"id": variant + 1, "kind": "tree", "seed": variant, "position": [4.0 + variant * 6.0, 8.0, 8.0]})
	for variant in FOLIAGE_NAMES.size():
		records.append({"id": variant + 4, "kind": "foliage", "seed": variant, "position": [4.0 + variant * 2.0, 8.0, 14.0]})
	for variant in ROCK_NAMES.size():
		records.append({"id": variant + 32, "kind": "rock", "seed": variant, "position": [8.0 + variant * 3.0, 8.0, 18.0]})
	garden.apply_records(records)
	await process_frame
	var expected_groups := 0
	for kind in ["tree", "foliage", "rock"]:
		for variant in Flora.variant_count(kind): expected_groups += Flora.meshes(kind, variant).size()
	_check(garden._groups.size() == expected_groups, "world batches every authored tree and foliage palette surface")
	var phases_by_asset := {}
	for key in garden._groups:
		var node: MultiMeshInstance3D = garden._groups[key]
		var kind := str(key).get_slice("_", 0)
		var variant := int(str(key).get_slice("_", 1))
		var surface := int(str(key).get_slice("_", 2))
		var expected: Mesh = Flora.meshes(kind, variant)[surface]
		_check(node.multimesh.mesh == expected and node.multimesh.instance_count == 1, "%s batch renders authored variant %d surface %d" % [kind, variant, surface])
		var source_material := expected.surface_get_material(0) as StandardMaterial3D
		var effective_material := node.material_override as ShaderMaterial
		_check(source_material != null and effective_material != null and (effective_material.get_shader_parameter("base_color") as Color).is_equal_approx(source_material.albedo_color), "%s variant %d surface %d preserves its authored palette color" % [kind, variant, surface])
		var animated := Garden.wind_strength(kind, variant) > 0.0
		_check(node.multimesh.use_custom_data == animated, "%s variant %d uses per-instance wind data only when animated" % [kind, variant])
		if animated:
			var material := node.material_override as ShaderMaterial
			_check(material != null and material.shader == Garden.VEGETATION_WIND_SHADER, "%s variant %d uses gameplay wind shader" % [kind, variant])
			_check(is_equal_approx(float(material.get_shader_parameter("wind_strength")), Garden.wind_strength(kind, variant)), "%s variant %d preserves approved sway strength" % [kind, variant])
			_check(float(material.get_shader_parameter("mesh_height")) >= 0.0625, "%s variant %d normalizes sway to the complete asset height" % [kind, variant])
			_check(node.extra_cull_margin + 0.0001 >= Garden.MAX_WIND_STRENGTH, "%s variant %d expands culling for maximum sway (%.3f)" % [kind, variant, node.extra_cull_margin])
			_check(node.multimesh.get_instance_custom_data(0).r >= 0.0 and node.multimesh.get_instance_custom_data(0).r < 1.0, "%s variant %d stores a valid stable phase" % [kind, variant])
			var asset_key := "%s_%d" % [kind, variant]
			var phase := node.multimesh.get_instance_custom_data(0).r
			if phases_by_asset.has(asset_key): _check(is_equal_approx(float(phases_by_asset[asset_key]), phase), "%s variant %d keeps palette surfaces seam-synchronized" % [kind, variant])
			else: phases_by_asset[asset_key] = phase
		elif kind == "rock" or variant >= 8:
			_check(not node.multimesh.use_custom_data, "%s variant %d remains intentionally static" % [kind, variant])
	for variant in 8:
		_check(Garden.wind_strength("foliage", variant) >= 0.04, "small foliage variant %d has visible gameplay wind strength" % variant)
	for variant in range(8, FOLIAGE_NAMES.size()):
		_check(is_zero_approx(Garden.wind_strength("foliage", variant)), "mushroom variant %d remains intentionally static" % variant)
	_check(Garden.TREE_WIND_STRENGTH > 0.16 and Garden.MAX_WIND_STRENGTH >= Garden.TREE_WIND_STRENGTH, "tree wind is slightly stronger with matching cull margin")
	var phase_a := Garden.wind_phase({"id": 1, "kind": "tree", "seed": 0, "position": [4.0, 8.0, 8.0]})
	var phase_b := Garden.wind_phase({"id": 2, "kind": "treee", "seed": 0, "position": [10.0, 8.0, 8.0]})
	_check(not is_equal_approx(phase_a, phase_b), "separate plantings receive independent deterministic wind phases")
	garden.set_wind_enabled(false)
	var all_paused := true
	for key: String in garden._groups:
		var node: MultiMeshInstance3D = garden._groups[key]
		if node.multimesh.use_custom_data: all_paused = all_paused and is_zero_approx(float((node.material_override as ShaderMaterial).get_shader_parameter("wind_strength")))
	_check(all_paused, "wind can be frozen for deterministic full-scene captures")
	garden.set_wind_enabled(true)
	var all_resumed := true
	for key: String in garden._groups:
		var node: MultiMeshInstance3D = garden._groups[key]
		if node.multimesh.use_custom_data:
			var kind := key.get_slice("_", 0); var variant := int(key.get_slice("_", 1))
			all_resumed = all_resumed and is_equal_approx(float((node.material_override as ShaderMaterial).get_shader_parameter("wind_strength")), Garden.wind_strength(kind, variant))
	_check(all_resumed, "wind resumes at each family's approved strength")
	garden.queue_free()
	await process_frame
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures}))
	quit(1 if failures else 0)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)
