extends Resource
class_name VisualLightingProfile

## Shared presentation-only look-development data. Each application creates a
## private Environment; it never edits an imported/shared environment resource,
## changes camera framing, or touches saved building/landscape authority.
@export var profile_id: StringName = &"baseline"
@export var sun_rotation_degrees := Vector3(-52.0, -28.0, 0.0)
@export var sun_colour := Color("#fff0d5")
@export_range(0.0, 8.0, 0.01) var sun_energy := 1.25
@export var ambient_colour := Color("#c2d5e0")
@export_range(0.0, 2.0, 0.01) var ambient_energy := 0.55
@export var use_sky_fill := false
@export var sky_top := Color("#7895b1")
@export var sky_horizon := Color("#c4d1d5")
@export var ground_bottom := Color("#505847")
@export var ground_horizon := Color("#a8b6ac")

func apply_to(sun: DirectionalLight3D, world: WorldEnvironment) -> bool:
	if not is_instance_valid(sun) or not is_instance_valid(world): return false
	if not sun_rotation_degrees.is_finite() or not is_finite(sun_energy) or not is_finite(ambient_energy): return false
	if sun_energy < 0.0 or ambient_energy < 0.0: return false
	var environment: Environment = world.environment.duplicate(true) if world.environment else Environment.new()
	sun.rotation_degrees = sun_rotation_degrees
	sun.light_color = sun_colour
	sun.light_energy = sun_energy
	environment.ambient_light_color = ambient_colour
	environment.ambient_light_energy = ambient_energy
	if use_sky_fill:
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = sky_top
		sky_material.sky_horizon_color = sky_horizon
		sky_material.ground_bottom_color = ground_bottom
		sky_material.ground_horizon_color = ground_horizon
		var sky := Sky.new()
		sky.sky_material = sky_material
		environment.sky = sky
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_sky_contribution = 1.0
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	else:
		environment.sky = null
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	# Preserve the gameplay background, tonemapping/exposure and shadow setup.
	# This first comparison isolates light/fill; no fog, bloom or blur rescue.
	environment.fog_enabled = false
	environment.glow_enabled = false
	world.environment = environment
	return true
