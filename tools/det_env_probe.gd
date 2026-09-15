extends SceneTree
## Render-determinism probe: one environment flag at a time, same scene each run.
## Usage (after --): any of  --glow --tonemap --fog --sky --ambient-sky
var flags: Array = []
var environment := Environment.new()
var world := Node3D.new()

func _apply_flags() -> void:
	for f in flags:
		if f == "glow":
			environment.glow_enabled = true
			environment.glow_intensity = 0.5
			environment.glow_bloom = 0.14
			environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		elif f == "tonemap":
			environment.tonemap_mode = Environment.TONE_MAPPER_ACES
			environment.tonemap_exposure = 1.05
			environment.tonemap_white = 1.35
		elif f == "fog":
			environment.fog_enabled = true
			environment.fog_light_color = Color("#ead7b3")
			environment.fog_density = 0.0038
			environment.fog_sky_affect = 0.8
			environment.fog_depth_begin = 18.0
			environment.fog_depth_end = 150.0
		elif f == "sky":
			var sky_mat := ProceduralSkyMaterial.new()
			sky_mat.sky_top_color = Color("#d8e1e5")
			sky_mat.sky_horizon_color = Color("#f2d9a4")
			sky_mat.ground_bottom_color = Color("#c3b795")
			sky_mat.ground_horizon_color = Color("#e0d3b2")
			sky_mat.sky_energy_multiplier = 0.55
			sky_mat.ground_energy_multiplier = 0.35
			var sky := Sky.new()
			sky.sky_material = sky_mat
			environment.sky = sky
			environment.background_mode = Environment.BG_SKY
		elif f == "ambient-sky":
			environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			environment.ambient_light_sky_contribution = 1.0

func _build_scene() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-33, -46, 0)
	sun.light_color = Color("#ffd9a0")
	sun.light_energy = 1.72
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	world.add_child(sun)
	for i in 8:
		var cube := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.0 + 0.25 * (i % 3), 1.2, 1.0)
		cube.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.6 + 0.05 * i, 0.4, 0.3)
		cube.material_override = mat
		cube.position = Vector3(-4.0 + i * 1.6, 0.6, -2.0 - (i % 3) * 1.5)
		world.add_child(cube)
	var ground := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(30.0, 0.4, 20.0)
	ground.mesh = slab
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.35, 0.55, 0.3)
	ground.material_override = gmat
	ground.position = Vector3(0, -0.2, 0)
	world.add_child(ground)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 4, 14)
	camera.rotation_degrees = Vector3(-14, 0, 0)
	world.add_child(camera)
	var env_node := WorldEnvironment.new()
	env_node.environment = environment
	world.add_child(env_node)
	current_scene = world
	get_root().add_child(world)

func _grab() -> PackedByteArray:
	for i in 8:
		await RenderingServer.frame_post_draw
	return get_root().get_texture().get_image().get_data()

func _drift(a: PackedByteArray, b: PackedByteArray) -> int:
	if a.size() != b.size():
		return -1
	var changed := 0
	for off in range(0, a.size(), 4):
		if a[off] != b[off] or a[off + 1] != b[off + 1] or a[off + 2] != b[off + 2] or a[off + 3] != b[off + 3]:
			changed += 1
	return changed

func ready() -> void:
	for arg in OS.get_cmdline_user_args():
		flags.append(arg.trim_prefix("--"))
	_apply_flags()
	_build_scene()
	await process_frame
	await process_frame
	await process_frame
	var data_a := await _grab()
	var data_b := await _grab()
	print("DETPROBE flags=[%s] drift_pixels=%d" % [flags.join(","), _drift(data_a, data_b)])
	quit(0)
