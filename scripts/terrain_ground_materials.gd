extends RefCounted
class_name GroundMaterials

## Ground material library for the starter valley art pass (stage 3).
##
## Material ids in the voxel channel:
##   0  air          1  stone (subsurface)      2  grass (exact GrassTone)
##   3  dirt         4  sand (riverbed)         5  gravel (upper banks)
##   6  moss         7  rock face (ring crest)  8  dry grass (sunny field)
##   9  dense grass  (forest ring)
##
## The grass family (2/8/9) shares one shader so the field has continuous
## shading; 8 and 9 re-tint the GrassTone palette toward a sunny olive and a
## dark forest green respectively. 2 keeps the exact GrassTone values (the
## tuft renderer and determinism tests rely on that single source of truth).
## Everything else is a flat StandardMaterial3D with vertex colours on, so
## the VoxelBlocky vertex tinting keeps the painterly variety.
##
## The channel is saved as 8-bit (see CheckpointStore), so all ids are < 256
## and old saves (0/1/2) migrate unchanged.
const GRASS := 2
const DIRT := 3
const SAND := 4
const GRAVEL := 5
const MOSS := 6
const ROCK_FACE := 7
const DRY_GRASS := 8
const DENSE_GRASS := 9
const STONE := 1
const NAMES: Dictionary = {
	1: "stone", 2: "grass", 3: "dirt", 4: "sand", 5: "gravel",
	6: "moss", 7: "rock_face", 8: "dry_grass", 9: "dense_grass",
}
const GRASS_SHADER := preload("res://scripts/terrain_grass.gdshader")
const GrassTone = preload("res://scripts/grass_tone.gd")

## Sunny-olive anchor for dry grass; dark-forest anchor for dense grass.
const DRY_TINT := Color("#a89a5f")
const DENSE_TINT := Color("#3f5a38")

static func name(id: int) -> String:
	return NAMES.get(id, "air")

## variant 0 = exact GrassTone (native model 2); 1 = dry; 2 = dense.
static func grass_material(variant: int = 0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GRASS_SHADER
	var uniforms := GrassTone.shader_uniforms()
	for parameter: String in uniforms:
		var value: Variant = uniforms[parameter]
		if variant == 1 and value is Color:
			value = _tint(value as Color, DRY_TINT, 0.5)
		elif variant == 2 and value is Color:
			value = _tint(value as Color, DENSE_TINT, 0.45)
		material.set_shader_parameter(parameter, value)
	return material

static func _tint(source: Color, target: Color, amount: float) -> Color:
	return source.lerp(target, amount)

static func standard(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	return material

static func material_for(id: int) -> Material:
	match id:
		1: return standard(Color("#ac9677"))
		2: return grass_material(0)
		3: return standard(Color("#8a6a4b"))
		4: return standard(Color("#c9b184"))
		5: return standard(Color("#8e8a84"))
		6: return standard(Color("#5d7d46"))
		7: return standard(Color("#75706a"))
		8: return grass_material(1)
		9: return grass_material(2)
	return standard(Color.WHITE)

## Builds the 10-model VoxelBlocky library (index 0 = empty). Callers apply
## the beveled geometry afterwards (TerrainBackend).
static func build_library() -> Object:
	var library: Object = ClassDB.instantiate("VoxelBlockyLibrary")
	var empty: Object = ClassDB.instantiate("VoxelBlockyModelEmpty")
	library.add_model(empty)
	for id in range(1, 10):
		var cube: Object = ClassDB.instantiate("VoxelBlockyModelCube")
		cube.set_material_override(0, material_for(id))
		library.add_model(cube)
	library.bake()
	return library
