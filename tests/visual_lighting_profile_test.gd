extends SceneTree

const Profile = preload("res://scripts/visual_lighting_profile.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	var sun := DirectionalLight3D.new()
	var world := WorldEnvironment.new()
	var source := Environment.new()
	source.tonemap_exposure = 0.85
	source.background_color = Color("#c3d2c5")
	world.environment = source
	sun.shadow_enabled = true
	var baseline := load("res://resources/visual_profiles/baseline.tres") as Profile
	var sky_fill := load("res://resources/visual_profiles/sky_fill.tres") as Profile
	var warm := load("res://resources/visual_profiles/warm_daylight.tres") as Profile
	for profile in [baseline, sky_fill, warm]:
		world.environment = source
		check(profile.apply_to(sun, world), "valid lighting profile applies")
		check(world.environment != source, "application uses a private environment")
		check(source.sky == null and source.ambient_light_source == Environment.AMBIENT_SOURCE_BG, "source environment is unchanged")
		check(world.environment.tonemap_exposure == 0.85 and world.environment.background_color == source.background_color, "exposure and background remain unchanged")
		check(sun.shadow_enabled, "lighting selection does not disable cast shadows")
		check(not world.environment.fog_enabled and not world.environment.glow_enabled, "comparison does not hide detail with post effects")
		if profile.use_sky_fill:
			var material := world.environment.sky.sky_material as ProceduralSkyMaterial
			check(material.sky_energy_multiplier == profile.sky_energy and material.ground_energy_multiplier == profile.sky_energy, "sky fill uses effective radiance controls")
		else:
			check(world.environment.sky == null and world.environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR, "baseline restores constant fill")
	var first := world.environment
	check(warm.apply_to(sun, world) and world.environment != first and world.environment.sky != first.sky, "reapplication owns a fresh sky resource")
	var before := world.environment
	var transform_before := sun.transform
	var invalid := Profile.new()
	invalid.sky_energy = NAN
	check(not invalid.apply_to(sun, world), "nonfinite profile is rejected")
	check(world.environment == before and sun.transform == transform_before, "invalid profile is atomic")
	invalid.sky_energy = 0.5
	invalid.sun_colour = Color(NAN, 1, 1)
	check(not invalid.apply_to(sun, world), "nonfinite colour is rejected")
	check(not baseline.apply_to(null, world), "missing light is rejected")
	check(baseline.apply_to(sun, world) and world.environment.sky == null, "switching back removes the candidate sky")
	sun.free()
	world.free()
	print("visual_lighting_profile_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
