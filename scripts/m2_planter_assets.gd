extends RefCounted
class_name M2PlanterAssets

## Authored, baked MagicaVoxel presentation only. Saved composition records keep
## their existing style_id, footprint, identity, colour and rotation contracts.
const UNIT := 0.0625
const FOOTPRINT := Vector2(0.75, 0.75)
const STYLE_IDS: Array[String] = ["barrel_planter", "barrel_planter_herbs", "barrel_planter_light"]
const DEFINITIONS := {
	"barrel_planter": {"name": "Barrel planter", "size": FOOTPRINT, "summary": "Staved oak barrel with a full rose-and-cream flower arrangement"},
	"barrel_planter_herbs": {"name": "Herb barrel planter", "size": FOOTPRINT, "summary": "Layered leafy herbs in an iron-hooped wooden barrel"},
	"barrel_planter_light": {"name": "Lightly planted barrel", "size": FOOTPRINT, "summary": "A few fresh shoots and one cream flower above inset soil"},
}
const PATHS := {
	"barrel_planter": "res://assets/models/magicavoxel/hearthvale_planter_flowers.res",
	"barrel_planter_herbs": "res://assets/models/magicavoxel/hearthvale_planter_herbs.res",
	"barrel_planter_light": "res://assets/models/magicavoxel/hearthvale_planter_light.res",
}
const VOXEL_COUNTS := {"barrel_planter": 562, "barrel_planter_herbs": 544, "barrel_planter_light": 498}
const SWATCHES := [Color("#79563f"), Color("#4b514d"), Color("#638348"), Color("#df9a8b")]
const TINTS := preload("res://scripts/m2_composition_visual.gd").DETAIL_TINTS
static var _cache: Dictionary = {}

static func has_style(style_id: String) -> bool:
	return PATHS.has(style_id)

static func mesh_for(style_id: String, colour_id: String = "", preview: bool = false, valid: bool = true) -> ArrayMesh:
	if not has_style(style_id): return null
	var normalized_colour := colour_id if TINTS.has(colour_id) else ""
	var key := "%s|%s|%s|%s" % [style_id, normalized_colour, preview, valid if preview else true]
	if _cache.has(key): return _cache[key] as ArrayMesh
	var source := load(str(PATHS[style_id])) as ArrayMesh
	if source == null:
		push_error("Missing authored planter mesh: " + str(PATHS[style_id]))
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
		if not normalized_colour.is_empty(): material.albedo_color = material.albedo_color.lerp(TINTS[normalized_colour], 0.42)
		if preview:
			material.albedo_color = material.albedo_color.lerp(Color("#a7e0a0") if valid else Color("#ef8b78"), 0.56)
			material.albedo_color.a = 0.56
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		result.surface_set_material(index, material)
	_cache[key] = result
	return result
