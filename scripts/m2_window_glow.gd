extends RefCounted
class_name M2WindowGlow

## Warm interior light for cottage window panes.
##
## A lit house is pure presentation: the pane's own material emits, so no
## light node, record, save field, anchor or authority is added. Frames,
## joinery, shutters, sills and walls stay unlit, which is what makes the
## window read as light *inside* the house rather than a glowing decal.
##
## Interior warmth varies per window by the same deterministic craft variant
## the joinery already uses, so a facade never reads as one uniform panel.
## Daylight is constant (the shipped world has no night cycle); a
## VisualLightingProfile retunes the strength for dusk/night captures.

## Interior light colours, indexed by the window's craft variant.
const INTERIOR_GLOW_COLOURS: Array[Color] = [
	Color(1.0, 0.58, 0.26),
	Color(1.0, 0.66, 0.36),
	Color(0.98, 0.52, 0.30),
]

## Daylight emissive strength. Deliberately below the lantern glass baseline:
## a house interior is a large soft source, not a lamp.
const DAYLIGHT_EMISSIVE_SCALE := 0.34

## Glass is a hard, slightly reflective surface; a matte pane reads as paint.
const GLASS_ROUGHNESS := 0.35

## Material metadata: the glow scale and the craft variant a pane carries, so
## a building caches one material per variant instead of one per window.
const GLOW_SCALE_META := &"m2_window_glow_scale"
const GLOW_VARIANT_META := &"m2_window_glow_variant"

## Pane material for one window. `variant` selects the interior warmth and is
## the existing deterministic craft variant, never a random draw.
static func make_material(base_colour: Color, variant: int, scale: float = DAYLIGHT_EMISSIVE_SCALE) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = base_colour
	material.roughness = GLASS_ROUGHNESS
	material.set_meta(GLOW_VARIANT_META, posmod(variant, INTERIOR_GLOW_COLOURS.size()))
	apply_scale(material, scale)
	return material

## True when a material is a glow-driven pane material.
static func is_glow_material(material: Material) -> bool:
	return material != null and material.has_meta(GLOW_SCALE_META)

## Current emissive strength of a pane material (0.0 when it does not glow).
static func emissive_scale(material: Material) -> float:
	if not is_glow_material(material): return 0.0
	return float(material.get_meta(GLOW_SCALE_META))

## Interior colour for a craft variant; an unknown variant falls back to the
## neutral warm amber so the look never depends on the variant count.
static func interior_glow_colour(variant: int) -> Color:
	if variant < 0: return INTERIOR_GLOW_COLOURS[0]
	return INTERIOR_GLOW_COLOURS[posmod(variant, INTERIOR_GLOW_COLOURS.size())]

## Set the emissive strength. A scale of 0.0 returns the pane to plain glass.
static func apply_scale(material: StandardMaterial3D, scale: float) -> void:
	if material == null: return
	var strength := maxf(0.0, scale)
	material.emission_enabled = strength > 0.0
	material.emission = interior_glow_colour(int(material.get_meta(GLOW_VARIANT_META, 0)))
	material.emission_energy_multiplier = strength
	material.set_meta(GLOW_SCALE_META, strength)

## Retune every pane material for a lighting profile (dusk/night). Null
## restores the constant daylight look the shipped world uses.
static func apply_profile(materials: Array, profile: Resource) -> void:
	var scale := DAYLIGHT_EMISSIVE_SCALE
	if profile != null: scale = float(profile.get("window_emissive_scale"))
	for value in materials:
		var material := value as StandardMaterial3D
		if is_glow_material(material): apply_scale(material, scale)
