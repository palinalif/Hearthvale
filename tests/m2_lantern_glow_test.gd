extends SceneTree

## Headless contract test for the starter-hamlet lantern glow.
##
## Asserts that a lantern built through the real furniture seam carries an
## emissive glass surface, that non-glow furniture stays unlit, and that the
## glow is nominated per style rather than applied globally.

const ROOT_ID := 1
const WORLD_ORIGIN := Vector3i(128, 0, 128)
const WORLD_SIZE := Vector3i(48, 24, 48)

const LANTERN_ID := 901
const SIGNPOST_ID := 902

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	var game := load("res://scripts/m1_scene.gd").new()
	game.ready.connect(_on_ready)
	root.add_child(game)


func _fail(message: String) -> void:
	failures.append(message)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		_fail(label)


func _mesh_of(visual: Node, node_name: String) -> Mesh:
	for node in visual.call("find_children", node_name, "*", true):
		return node.get("mesh") as Mesh
	return null


func _emissive_surfaces(mesh: Mesh) -> int:
	var lit := 0
	for index in mesh.call("get_surface_count"):
		var material: StandardMaterial3D = mesh.call("surface_get_material", index) as StandardMaterial3D
		if material != null and bool(material.get("emission_enabled")):
			lit += 1
	return lit


func _on_ready() -> void:
	var game: Node = root.get_node("m1_scene")
	root.process_mode = Node.PROCESS_MODE_DISABLED
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.set_physics_process(false)
	if game.get("voxel_world") == null:
		_fail("Voxel world was not created.")
		_finish()
		return
	var voxel_world: Node = game.get("voxel_world")
	var generator := M2StarterValleyGenerator.new()
	var world_request := generator.build(WORLD_ORIGIN, WORLD_SIZE, 20260727)
	var world: M2GeneratedWorldData = world_request.get_meta("m2_starter_valley")
	voxel_world.set("world", world)
	voxel_world.call("generate")
	var hamlet: Node = game.get("m2_hamlet")
	hamlet.set("generation_enabled", false)
	hamlet.set("generation_bounds", Rect2i(Vector2i.ZERO, Vector2i(0, 0)))
	hamlet.call("build")
	var visual: Node = hamlet.get("m2_hamlet_visual")
	visual.call("apply_records", [
		{"id": LANTERN_ID, "style_id": "lantern", "position": [128, 128], "yaw_quarters": 0},
		{"id": SIGNPOST_ID, "style_id": "signpost", "position": [130, 128], "yaw_quarters": 0},
	])
	_check(int(visual.call("stats")["furniture_count"]) == 2, "Both furniture records were built.")

	var lantern := _mesh_of(visual, "Furniture_%d" % LANTERN_ID)
	var signpost := _mesh_of(visual, "Furniture_%d" % SIGNPOST_ID)
	_check(lantern != null, "A lantern mesh was built through the furniture seam.")
	_check(signpost != null, "A signpost mesh was built through the furniture seam.")
	if lantern == null:
		_finish()
		return

	var glass: StandardMaterial3D = lantern.call("surface_get_material", 2) as StandardMaterial3D
	_check(glass != null, "The lantern glass surface has a material.")
	if glass != null:
		_check(bool(glass.get("emission_enabled")), "Lantern glass emission is enabled.")
		var emission: Color = glass.get("emission")
		_check(emission.r > 0.9 and emission.g > 0.4 and emission.b < emission.g, "Lantern glass emission reads as a warm ember, not a cool white.")
		_check(float(glass.get("emission_energy_multiplier")) > 1.0, "Lantern glass emission is bright enough to bloom.")
		_check(int(glass.get("shading_mode")) == BaseMaterial3D.SHADING_MODE_UNSHADED, "Lantern glass is unshaded so it reads as lit glass.")
	_check(_emissive_surfaces(lantern) == 1, "Only the lantern glass glows, not the whole lamp.")

	# Glow is nominated per style, so unrelated furniture stays unlit.
	_check(_emissive_surfaces(signpost) == 0, "Non-glow furniture stays unlit.")

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("M2_LANTERN_GLOW_TEST_PASS checks=%d" % checks)
		quit(0)
		return
	for failure in failures:
		print("M2_LANTERN_GLOW_TEST_FAIL: %s" % failure)
	quit(1)
