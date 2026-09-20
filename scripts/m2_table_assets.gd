extends RefCounted
class_name M2TableAssets

## Authored, baked MagicaVoxel street furniture. Saved composition records keep
## their existing style_id, footprint, identity and orientation contracts.
const UNIT := 0.0625
const STYLE_IDS: Array[String] = [
	"village_table",
	"clothesline",
	"potted_trio",
	"market_crate",
	"bird_feeder",
	"mailbox",
	"topiary_pair",
	"beehive",
	"wheelbarrow",
	"flower_arch",
	"garden_gnome",
	"garden_gnome_small",
	"garden_gnome_tall",
]
const PATHS := {
	"village_table": "res://assets/models/magicavoxel/hearthvale_table_gathering.res",
	"clothesline": "res://assets/models/magicavoxel/hearthvale_clothesline.res",
	"potted_trio": "res://assets/models/magicavoxel/hearthvale_potted_trio.res",
	"market_crate": "res://assets/models/magicavoxel/hearthvale_market_crate.res",
	"bird_feeder": "res://assets/models/magicavoxel/hearthvale_bird_feeder.res",
	"mailbox": "res://assets/models/magicavoxel/hearthvale_mailbox.res",
	"topiary_pair": "res://assets/models/magicavoxel/hearthvale_topiary_pair.res",
	"beehive": "res://assets/models/magicavoxel/hearthvale_beehive.res",
	"wheelbarrow": "res://assets/models/magicavoxel/hearthvale_wheelbarrow.res",
	"flower_arch": "res://assets/models/magicavoxel/hearthvale_flower_arch.res",
	"garden_gnome": "res://assets/models/magicavoxel/hearthvale_garden_gnome.res",
	"garden_gnome_small": "res://assets/models/magicavoxel/hearthvale_garden_gnome_small.res",
	"garden_gnome_tall": "res://assets/models/magicavoxel/hearthvale_garden_gnome_tall.res",
}
const VOXEL_COUNTS := {
	"village_table": 1178,
	"clothesline": 310,
	"potted_trio": 224,
	"market_crate": 310,
	"bird_feeder": 229,
	"mailbox": 180,
	"topiary_pair": 363,
	"beehive": 174,
	"wheelbarrow": 148,
	"flower_arch": 18663,
	"garden_gnome": 182,
	"garden_gnome_small": 102,
	"garden_gnome_tall": 190,
}
const SWATCHES := [Color("#c9a878"), Color("#7d5b43"), Color("#594337")]
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
		push_error("Missing authored table mesh: " + str(PATHS[style_id]))
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
