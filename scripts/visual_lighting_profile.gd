extends Resource
class_name VisualLightingProfile
const WindowGlow = preload("res://scripts/m2_window_glow.gd")

## Opt-in look-development data; application never changes camera framing,
## shared source environments, meshes, or saved building/terrain records.
@export var profile_id: StringName = &"baseline"
@export var sun_rotation_degrees := Vector3(-52.0, -28.0, 0.0)
@export var sun_colour := Color("#fff0d5")
@export_range(0.0, 8.0, 0.01) var sun_energy := 1.25
@export var ambient_colour := Color("#c2d5e0")
@export_range(0.0, 2.0, 0.01) var ambient_energy := 0.55
@export var use_sky_fill := false
@export_range(0.0, 4.0, 0.01) var sky_energy := 1.0
@export_range(0.0, 1.0, 0.01) var sky_contribution := 0.5
@export var sky_top := Color("#7895b1")
@export var sky_horizon := Color("#c4d1d5")
@export var ground_bottom := Color("#505847")
@export var ground_horizon := Color("#a8b6ac")
## Emissive scale for placed lantern glass under this profile. Matches the
## M2LanternGlow daylight baseline so the shipped look is unchanged.
@export_range(0.0, 4.0, 0.01) var lamp_emissive_scale := 0.55
## Flame light energy for placed lanterns under this profile.
@export_range(0.0, 4.0, 0.01) var lamp_light_energy := 0.45
## Lit-window strength for this look, applied through WindowGlow. Defaults
## to the constant daylight value, so existing profiles keep the shipped
## interior glow; dusk/night looks raise it.
@export_range(0.0, 4.0, 0.01) var window_emissive_scale := WindowGlow.DAYLIGHT_EMISSIVE_SCALE

## Night look. The old night ambient (0.03,0.04,0.06) at energy 0.35 rendered
## the world as flat grey, which made every lamp look unlit. Night is lifted to
## a low warm dusk and given a warm ground albedo so shaded volumes keep shape
## and lamplight reads as warm against it.
const NIGHT_AMBIENT := Color(0.10, 0.12, 0.18)
const NIGHT_AMBIENT_ENERGY := 0.45
const NIGHT_GROUND_ALBEDO := Color(0.34, 0.24, 0.13)

func night_factor() -> float:
	# Derived from the profile's own sun strength, never hand-authored per scene:
	# full sun (1.25) is day, no sun is night.
	return clampf(1.0 - sun_energy / 1.25, 0.0, 1.0)

# Bloom.  Godot 4.7 exposes glow as a fixed set of Environment properties; it
# has no glow buses, so the look is tuned through these rather than per-bus.
@export var glow_enabled := false
@export_range(0.0, 8.0, 0.001) var glow_intensity := 0.8
@export_range(0.0, 8.0, 0.001) var glow_strength := 1.0
@export_range(0.0, 1.0, 0.001) var glow_bloom := 0.15
@export_range(0.0, 1.0, 0.001) var glow_mix := 0.15
@export_range(0.0, 16.0, 0.001) var glow_hdr_threshold := 1.5
@export_range(0.0, 16.0, 0.001) var glow_hdr_scale := 1.0
@export var glow_normalized := false
# Godot GlowBlendMode: 0 = ADD, 1 = SCREEN, 2 = SOFTLIGHT.
@export_range(0, 2, 1) var glow_blend_mode := 0
# Level weights 1..7; index 0 is unused by Godot.
@export var glow_levels: Array[float] = [0.0, 0.0, 0.8, 0.4, 0.1, 0.0, 0.0, 0.0]

func apply_to(sun: DirectionalLight3D, world: WorldEnvironment) -> bool:
	if not is_instance_valid(sun) or not is_instance_valid(world): return false
	if not sun_rotation_degrees.is_finite(): return false
	for energy in [sun_energy, ambient_energy, sky_energy]:
		if not is_finite(energy) or energy < 0.0: return false
	if not is_finite(sky_contribution) or sky_contribution < 0.0 or sky_contribution > 1.0: return false
	for colour in [sun_colour, ambient_colour, sky_top, sky_horizon, ground_bottom, ground_horizon]:
		if not _colour_finite(colour): return false
	var environment: Environment = world.environment.duplicate(true) if world.environment else Environment.new()
	sun.rotation_degrees = sun_rotation_degrees
	sun.light_color = sun_colour
	sun.light_energy = sun_energy
	var night := night_factor()
	environment.ambient_light_color = ambient_colour.lerp(NIGHT_AMBIENT, night)
	environment.ambient_light_energy = lerpf(ambient_energy, NIGHT_AMBIENT_ENERGY, night)
	if use_sky_fill:
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = sky_top
		sky_material.sky_horizon_color = sky_horizon
		sky_material.ground_bottom_color = ground_bottom.lerp(NIGHT_GROUND_ALBEDO, night)
		sky_material.ground_horizon_color = ground_horizon.lerp(NIGHT_GROUND_ALBEDO, night)
		# Radiance and blend are separate controls. Retain a little constant
		# fill so canopy interiors and shaded facades remain readable.
		sky_material.sky_energy_multiplier = sky_energy
		sky_material.ground_energy_multiplier = sky_energy
		var sky := Sky.new()
		sky.sky_material = sky_material
		environment.sky = sky
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_sky_contribution = sky_contribution
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	else:
		environment.sky = null
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_sky_contribution = 0.0
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	# Isolate light/fill first. Exposure, tonemapper, background and shadow
	# quality are retained; fog stays off.
	environment.fog_enabled = false
	environment.glow_enabled = glow_enabled
	if glow_enabled:
		# Measured on the real Mobile pipeline: a wide, low-contrast bloom keeps
		# lamp filaments readable instead of turning them into white blobs.
		environment.glow_intensity = glow_intensity
		environment.glow_strength = glow_strength
		environment.glow_bloom = glow_bloom
		environment.glow_mix = glow_mix
		environment.glow_blend_mode = glow_blend_mode
		environment.glow_normalized = glow_normalized
		environment.glow_hdr_threshold = glow_hdr_threshold
		environment.glow_hdr_scale = glow_hdr_scale
		for level in range(1, 8):
			if level < glow_levels.size():
				environment.set("glow_levels/%d" % level, glow_levels[level])
	world.environment = environment
	return true

func _colour_finite(colour: Color) -> bool:
	return is_finite(colour.r) and is_finite(colour.g) and is_finite(colour.b) and is_finite(colour.a)
