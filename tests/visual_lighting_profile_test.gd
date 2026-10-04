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
	var sky_depth := load("res://resources/visual_profiles/sky_depth.tres") as Profile
	var sky_soft := load("res://resources/visual_profiles/sky_soft.tres") as Profile
	var warm := load("res://resources/visual_profiles/warm_daylight.tres") as Profile
	check(sky_fill != null and sky_depth != null and sky_soft != null, "sky-fill tuning profiles load")
	if sky_fill and sky_depth and sky_soft:
		check(sky_depth.sun_rotation_degrees == sky_fill.sun_rotation_degrees and sky_soft.sun_rotation_degrees == sky_fill.sun_rotation_degrees, "tuning candidates keep the approved sky-fill sun direction")
		check(sky_depth.ambient_energy < sky_fill.ambient_energy and sky_depth.sun_energy > sky_fill.sun_energy, "depth candidate makes only a restrained contrast adjustment")
		check(sky_soft.ambient_energy > sky_fill.ambient_energy and sky_soft.sun_energy < sky_fill.sun_energy, "soft candidate increases shaded-side fill without moving the sun")
	for profile in [baseline, sky_fill, sky_depth, sky_soft, warm]:
		world.environment = source
		check(profile != null and profile.apply_to(sun, world), "valid lighting profile applies")
		check(world.environment != source, "application uses a private environment")
		check(source.sky == null and source.ambient_light_source == Environment.AMBIENT_SOURCE_BG, "source environment is unchanged")
		check(world.environment.tonemap_exposure == source.tonemap_exposure and world.environment.background_color == source.background_color, "exposure and background remain unchanged")
		check(sun.shadow_enabled, "lighting selection does not disable cast shadows")
		check(not world.environment.fog_enabled and not world.environment.glow_enabled, "comparison does not hide detail with post effects")
		if profile.use_sky_fill:
			var material := world.environment.sky.sky_material as ProceduralSkyMaterial
			check(is_equal_approx(material.sky_energy_multiplier, profile.sky_energy) and is_equal_approx(material.ground_energy_multiplier, profile.sky_energy), "sky fill uses effective radiance controls")
			check(is_equal_approx(world.environment.ambient_light_sky_contribution, profile.sky_contribution), "sky and constant fill use the requested blend")
		else:
			check(world.environment.sky == null and world.environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR, "baseline uses constant fill")
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
	invalid.sun_colour = Color.WHITE
	invalid.sky_contribution = 1.1
	check(not invalid.apply_to(sun, world) and world.environment == before, "out-of-range sky blend is atomically rejected")
	check(not baseline.apply_to(null, world), "missing light is rejected")
	check(baseline.apply_to(sun, world) and world.environment.sky == null, "switching back removes the candidate sky")
	# Night look. Ambient is derived from the profile's own sun strength, so no
	# scene hand-authors it, and it must stay a dim warm dusk rather than the
	# old flat grey that made every lamp look unlit.
	var night_profile := Profile.new()
	night_profile.profile_id = &"night_probe"
	night_profile.sun_energy = 0.0
	world.environment = source
	check(night_profile.night_factor() == 1.0, "night factor saturates with no sun")
	var day_profile := Profile.new()
	check(day_profile.night_factor() == 0.0, "night factor is zero at full sun")
	check(night_profile.apply_to(sun, world), "night profile applies")
	check(world.environment.ambient_light_color.is_equal_approx(Profile.NIGHT_AMBIENT), "night uses the lifted dusk ambient")
	check(is_equal_approx(world.environment.ambient_light_energy, Profile.NIGHT_AMBIENT_ENERGY), "night uses the lifted dusk energy")
	var old_flat := Color(0.03, 0.04, 0.06)
	check(world.environment.ambient_light_color.get_luminance() > old_flat.get_luminance() * 0.35, "night ambient is brighter than the retired flat grey")
	check(world.environment.ambient_light_energy < 0.6, "night ambient stays dim enough for lamps to read")
	world.environment = source
	check(day_profile.apply_to(sun, world), "daylight profile applies")
	check(world.environment.ambient_light_color.is_equal_approx(day_profile.ambient_colour) and is_equal_approx(world.environment.ambient_light_energy, day_profile.ambient_energy), "daylight ambient is untouched by the night lift")
	sun.free()
	world.free()
	print("visual_lighting_profile_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
