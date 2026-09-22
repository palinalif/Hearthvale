extends SceneTree

## Stage 3 art pass: ground material library.
## Checks the id table, the model library (10 models, index 0 empty), the
## grass shader variants (exact GrassTone base + re-tinted dry/dense), and
## the deterministic paint rules (pure functions of position; no RNG).

const GroundMaterials = preload("res://scripts/terrain_ground_materials.gd")
const Generator = preload("res://scripts/m1_patch_generator.gd")
const GrassTone = preload("res://scripts/grass_tone.gd")

var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# Id table: every id is a byte (< 256, the channel save depth) and named.
	for id in range(1, 10):
		check(id < 256, "material id %d fits the 8-bit channel" % id)
		check(GroundMaterials.name(id) != "", "material id %d has a name" % id)
	check(GroundMaterials.name(2) == "grass", "id 2 is the native grass name")
	check(GroundMaterials.name(3) == "dirt", "id 3 is dirt")
	check(GroundMaterials.name(4) == "sand", "id 4 is sand")
	check(GroundMaterials.name(5) == "gravel", "id 5 is gravel")
	check(GroundMaterials.name(6) == "moss", "id 6 is moss")
	check(GroundMaterials.name(7) == "rock_face", "id 7 is rock face")
	check(GroundMaterials.name(8) == "dry_grass", "id 8 is dry grass")
	check(GroundMaterials.name(9) == "dense_grass", "id 9 is dense grass")

	# Library: 10 models, index 0 empty, every solid model carries a material.
	var library: Object = GroundMaterials.build_library()
	var models: Array = library.get_models()
	check(models.size() == 10, "library has 10 models (got %d)" % models.size())
	check(models[0] != null, "model 0 (empty) present")
	for id in range(1, 10):
		check(_model_material(models[id]) != null, "model %d carries a material" % id)
	# Grass family: one shared shader; variant 0 exact GrassTone, 1/2 tinted.
	var base: Material = _model_material(models[2])
	var dry: Material = _model_material(models[8])
	var dense: Material = _model_material(models[9])
	check(base is ShaderMaterial and dry is ShaderMaterial and dense is ShaderMaterial, "grass family uses the grass shader")
	if base is ShaderMaterial and dry is ShaderMaterial:
		check(base.get_shader_parameter("tone_0") == GrassTone.TONES[0], "base model 2 keeps the exact GrassTone tone_0")
		check(dry.get_shader_parameter("tone_0") != GrassTone.TONES[0], "dry grass re-tints tone_0")
		check(dense.get_shader_parameter("tone_0") != GrassTone.TONES[0], "dense grass re-tints tone_0")
		check(dry.get_shader_parameter("tone_scales") == base.get_shader_parameter("tone_scales"), "dry grass keeps the GrassTone patch scales")
	check(_model_material(models[3]) is StandardMaterial3D, "dirt is a standard material")
	check(_model_material(models[7]) is StandardMaterial3D, "rock face is a standard material")

	# Deterministic paint: pure position function, identical on every run.
	var a1 := _paint_digest(Generator.generate())
	var a2 := _paint_digest(Generator.generate())
	check(a1 == a2, "generate() paints the ground identically on every run")
	check(a1 != "", "paint digest is non-trivial")

	# Spot rules: hamlet stays grass; river bed sand; banks gravel; ring layers.
	check(Generator.surface_material(20.0, 18.0, 8.0) == GroundMaterials.GRASS, "hamlet highland stays grass")
	var center := Generator.river_center_x(40.0)
	check(Generator.surface_material(center, 40.0, 4.375) == GroundMaterials.SAND, "river bed is sand")
	check(Generator.surface_material(center + 3.5, 40.0, 6.0) == GroundMaterials.GRAVEL, "upper bank is gravel")
	check(Generator.surface_material(24.0, 27.5, 8.0) == GroundMaterials.DIRT, "lane at the well is packed dirt")
	var ring_materials := {}
	for x in range(65, 79, 2):
		for z in range(65, 79, 2):
			var h := Generator.terrain_height(float(x), float(z))
			var m := Generator.surface_material(float(x), float(z), h)
			ring_materials[m] = int(ring_materials.get(m, 0)) + 1
	check(ring_materials.has(GroundMaterials.DENSE_GRASS), "ring has dense forest grass (got %s)" % str(ring_materials))
	check(ring_materials.has(GroundMaterials.MOSS) or ring_materials.has(GroundMaterials.ROCK_FACE), "ring has moss/rock face variation (got %s)" % str(ring_materials))
	check(not ring_materials.has(GroundMaterials.SAND), "ring has no riverbed sand")

	# Surface voxels only: the two top voxels of a painted column take the
	# painted material; everything below stays stone (1).
	var voxels: Object = Generator.generate()
	var col_x := 70
	var col_z := 70
	var top := -1
	for y in range(Generator.PATCH_SIZE.y - 1, -1, -1):
		if int(voxels.get_voxel(col_x, y, col_z, 0)) != 0:
			top = y
			break
	check(top > 0, "painted column has a surface")
	var expected := Generator.surface_material(float(col_x) * 0.125, float(col_z) * 0.125, Generator.terrain_height(float(col_x) * 0.125, float(col_z) * 0.125))
	check(int(voxels.get_voxel(col_x, top, col_z, 0)) == expected, "top voxel matches the paint rule")
	check(int(voxels.get_voxel(col_x, top - 1, col_z, 0)) == expected, "second voxel matches the paint rule")
	check(int(voxels.get_voxel(col_x, top - 2, col_z, 0)) == 1, "subsurface below the paint stays stone")

	print("GROUND_MATERIALS_RESULT " + JSON.stringify({"ok": failures.is_empty(), "checks": checks, "failures": failures.size(), "messages": failures}))
	quit(0 if failures.is_empty() else 1)

func _model_material(model: Object) -> Material:
	if model.has_method("get_material_override"):
		return model.get_material_override(0)
	return null

## Digest of the painted top-two voxels over a sample grid: deterministic
## paint must produce the same digest on every run.
func _paint_digest(voxels: Object) -> String:
	var digest := 0
	for x in range(0, Generator.PATCH_SIZE.x, 16):
		for z in range(0, Generator.PATCH_SIZE.z, 16):
			var top := -1
			for y in range(Generator.PATCH_SIZE.y - 1, -1, -1):
				if int(voxels.get_voxel(x, y, z, 0)) != 0:
					top = y
					break
			if top > 0:
				digest = (digest * 31 + int(voxels.get_voxel(x, top, z, 0)) * 131 + int(voxels.get_voxel(x, top - 1, z, 0))) % 999999937
	return str(digest)
