extends RefCounted
# Authored voxel props that the hamlet places as furniture.
#
# These are the baked MagicaVoxel meshes for the starter props and the signpost:
# the village well, the chopping block, the log stack and the bench. They used to
# be rebuilt from primitives on every furniture rebuild, which meant the authored
# art in assets/source/magicavoxel was never what the player saw.
#
# This module mirrors the interface the other authored-asset modules expose
# (has_style / mesh_for / PATHS / VOXEL_COUNTS), so the furniture builder treats
# an authored prop exactly like an authored planter: one mesh instance per placed
# object, tinted by the record's colour, ghosted for placement previews.
#
# The baked meshes are authored on the 0.125 structural grid; the bench and
# signpost are presentation assets on the 0.0625 grid. Each style declares which.

const CompositionVisual = preload("res://scripts/m2_composition_visual.gd")

const STRUCTURAL_UNIT := 0.125
const PRESENTATION_UNIT := 0.0625

## style_id -> baked mesh path, the grid it was authored on, and the voxel count
## its bake receipt reports. Footprints stay with the placement catalogue, which
## owns them; this module only supplies geometry.
const ASSETS := {
	"well": {"path": "res://assets/models/magicavoxel/hearthvale_prop_village_well.res", "unit": STRUCTURAL_UNIT, "voxels": 3141},
	"chopping_block": {"path": "res://assets/models/magicavoxel/hearthvale_prop_chopping_block.res", "unit": STRUCTURAL_UNIT, "voxels": 404},
	"log_stack": {"path": "res://assets/models/magicavoxel/hearthvale_prop_log_stack.res", "unit": STRUCTURAL_UNIT, "voxels": 542},
	"bench": {"path": "res://assets/models/magicavoxel/hearthvale_furniture_bench.res", "unit": PRESENTATION_UNIT, "voxels": 685},
	"signpost": {"path": "res://assets/models/magicavoxel/hearthvale_furniture_signpost.res", "unit": PRESENTATION_UNIT, "voxels": 420},
}

const STYLE_IDS: Array[String] = ["well", "chopping_block", "log_stack", "bench", "signpost"]
const PATHS := {
	"well": "res://assets/models/magicavoxel/hearthvale_prop_village_well.res",
	"chopping_block": "res://assets/models/magicavoxel/hearthvale_prop_chopping_block.res",
	"log_stack": "res://assets/models/magicavoxel/hearthvale_prop_log_stack.res",
	"bench": "res://assets/models/magicavoxel/hearthvale_furniture_bench.res",
	"signpost": "res://assets/models/magicavoxel/hearthvale_furniture_signpost.res",
}
const VOXEL_COUNTS := {"well": 3141, "chopping_block": 404, "log_stack": 542, "bench": 685, "signpost": 420}
const TINTS := CompositionVisual.DETAIL_TINTS

const PREVIEW_VALID_TINT := Color("#a7e0a0")
const PREVIEW_INVALID_TINT := Color("#ef8b78")
const TINT_STRENGTH := 0.42
const PREVIEW_ALPHA := 0.56

static var _cache: Dictionary[String, ArrayMesh] = {}

static func has_style(style_id: String) -> bool:
	return ASSETS.has(style_id)

static func path_for(style_id: String) -> String:
	return str(PATHS.get(style_id, ""))

static func unit_for(style_id: String) -> float:
	return float(ASSETS.get(style_id, {}).get("unit", STRUCTURAL_UNIT))

## The runtime mesh for a placed prop, matching the other authored modules:
## uncoloured placements reuse the cached canonical mesh, tinted placements copy
## the palette materials, and previews are the same geometry ghosted translucent.
static func mesh_for(style_id: String, colour_id: String = "", preview: bool = false, valid: bool = true) -> ArrayMesh:
	if not has_style(style_id): return null
	var normalized_colour := colour_id if TINTS.has(colour_id) else ""
	var key := "%s|%s|%s|%s" % [style_id, normalized_colour, preview, valid if preview else true]
	if _cache.has(key): return _cache[key] as ArrayMesh
	var source := load(path_for(style_id)) as ArrayMesh
	if source == null:
		push_error("Missing authored prop mesh: " + path_for(style_id))
		return null
	if normalized_colour.is_empty() and not preview:
		_cache[key] = source
		return source
	# Copy palette materials, never the cached canonical asset. Preview and placed
	# geometry are exactly the same; only existing tint/ghost treatment differs.
	var result := ArrayMesh.new()
	for index in source.get_surface_count():
		result.add_surface_from_arrays(source.surface_get_primitive_type(index), source.surface_get_arrays(index))
		var material := source.surface_get_material(index).duplicate() as StandardMaterial3D
		if not normalized_colour.is_empty(): material.albedo_color = material.albedo_color.lerp(TINTS[normalized_colour], TINT_STRENGTH)
		if preview:
			material.albedo_color = material.albedo_color.lerp(PREVIEW_VALID_TINT if valid else PREVIEW_INVALID_TINT, 0.56)
			material.albedo_color.a = PREVIEW_ALPHA
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		result.surface_set_material(index, material)
	_cache[key] = result
	return result

## Drop the derived meshes (canonical, tinted and preview variants). The baked
## sources on disk are untouched.
static func invalidate_cache() -> void:
	_cache.clear()
