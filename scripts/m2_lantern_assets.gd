extends RefCounted
class_name M2LanternAssets

## Authored, baked MagicaVoxel presentation for the path lantern. Saved
## composition records keep their existing style_id, footprint, identity, colour
## and rotation contracts; only the geometry comes from the voxel source.
##
## The baked mesh is centred on the node origin in x/z and rests on y = 0, so
## placed and preview nodes use the same transform as every other prop.
const UNIT := 0.0625
const FOOTPRINT := Vector2(0.5, 0.5)
const STYLE_IDS: Array[String] = ["lantern"]
const DEFINITIONS := {
	"lantern": {"name": "Path lantern", "size": FOOTPRINT, "summary": "Iron post lamp with inset glass and a flame over a stone plinth"},
}
const PATHS := {
	"lantern": "res://assets/models/magicavoxel/hearthvale_prop_path_lantern.res",
}
const VOXEL_COUNTS := {"lantern": 316}
const SWATCHES := [Color("#454a47"), Color("#655344"), Color("#d7a85e"), Color("#8c765c")]
const TINTS := preload("res://scripts/m2_composition_visual.gd").DETAIL_TINTS
static var _cache: Dictionary = {}

static func has_style(style_id: String) -> bool:
	return STYLE_IDS.has(style_id)

static func mesh_for(style_id: String, colour_id: String = "", preview: bool = false, valid: bool = true) -> ArrayMesh:
	if not has_style(style_id): return null
	var normalized_colour := colour_id if TINTS.has(colour_id) else ""
	var key := "%s|%s|%s|%s" % [style_id, normalized_colour, preview, valid if preview else true]
	if _cache.has(key): return _cache[key] as ArrayMesh
	var source := load(str(PATHS[style_id])) as ArrayMesh
	if source == null:
		push_error("Missing authored lantern mesh: " + str(PATHS[style_id]))
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
