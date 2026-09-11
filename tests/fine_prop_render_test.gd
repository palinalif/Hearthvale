extends SceneTree

const Flora = preload("res://scripts/vegetation_mesh.gd")
const Garden = preload("res://scripts/m1_garden_visual.gd")
const MATERIAL_CAPTURE_DIR := "reports/screenshots/m2-hamlet/vegetation-materials"

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "mobile":
		print("FINE_PROP_RENDER_UNAVAILABLE")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var scene := Node3D.new(); root.add_child(scene)
	var ground := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(24, 14); ground.mesh = plane
	var ground_material := StandardMaterial3D.new(); ground_material.albedo_color = Color("#91aa68"); ground.material_override = ground_material; scene.add_child(ground)
	# Use the gameplay batching/override path, not bare imported mesh materials.
	var records: Array = []
	for variant in Flora.variant_count("tree"):
		records.append({"id": records.size() + 1, "kind": "tree", "seed": variant, "position": [-9.0 + variant * 3.6, 0.0, 2.3]})
	for variant in Flora.variant_count("foliage"):
		records.append({"id": records.size() + 1, "kind": "foliage", "seed": variant, "position": [-9.0 + (variant % 6) * 3.6, 0.0, -2.0 - (variant / 6) * 1.8]})
	for variant in Flora.variant_count("rock"):
		records.append({"id": records.size() + 1, "kind": "rock", "seed": variant, "position": [-3.6 + variant * 3.6, 0.0, -5.1]})
	var garden := Garden.new(); scene.add_child(garden)
	garden.set_wind_enabled(false) # Both captures use the identical rest pose.
	garden.apply_records(records)
	var terrain_reference := MeshInstance3D.new(); var cube := BoxMesh.new(); cube.size = Vector3.ONE * 0.125; terrain_reference.mesh = cube; terrain_reference.position = Vector3(-9.0, 0.0625, -5.1)
	var terrain_material := StandardMaterial3D.new(); terrain_material.albedo_color = Color("#7d9957"); terrain_reference.material_override = terrain_material; scene.add_child(terrain_reference)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, -30, 0); sun.shadow_enabled = true; scene.add_child(sun)
	var world := WorldEnvironment.new(); var environment := Environment.new(); environment.background_mode = Environment.BG_COLOR; environment.background_color = Color("#c3d2c5"); environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color = Color("#c2d5e0"); environment.ambient_light_energy = 0.55; world.environment = environment; scene.add_child(world)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 15.5; camera.position = Vector3(8, 10, 18); camera.look_at_from_position(camera.position, Vector3(0, 2.0, -1.0)); camera.current = true; scene.add_child(camera)
	var overlay := CanvasLayer.new(); scene.add_child(overlay)
	var title := Label.new(); title.text = "HEARTHVALE / GAMEPLAY PROP MATERIALS / MOBILE REVIEW"; title.position = Vector2(28, 20); title.add_theme_font_size_override("font_size", 25); title.modulate = Color("#26392f"); overlay.add_child(title)
	_check(DirAccess.make_dir_recursive_absolute(MATERIAL_CAPTURE_DIR) == OK, "material comparison directory available")
	var overrides: Array[Dictionary] = []
	for node: MultiMeshInstance3D in garden._groups.values():
		var material := node.material_override as ShaderMaterial
		_check(material != null and material.shader != null, "comparison uses a gameplay material override")
		if material == null or material.shader == null: continue
		# Reconstruct only the old alpha output on a private material copy. This
		# is a controlled legacy-shader ablation, not an old-build screenshot.
		var legacy := material.duplicate() as ShaderMaterial
		var legacy_shader := Shader.new()
		legacy_shader.code = material.shader.code.replace("void fragment() {", "void fragment() {\n\tALPHA = base_color.a * COLOR.a;")
		legacy.shader = legacy_shader
		# Explicitly preserve all uniforms across the shader replacement.
		legacy.set_shader_parameter("base_color", material.get_shader_parameter("base_color"))
		if material.shader == Garden.VEGETATION_WIND_SHADER:
			legacy.set_shader_parameter("wind_strength", 0.0)
			legacy.set_shader_parameter("mesh_height", material.get_shader_parameter("mesh_height"))
		overrides.append({"node": node, "original": material, "legacy": legacy})
	for view in ["normal", "reverse"]:
		if view == "reverse":
			camera.look_at_from_position(Vector3(-8, 10, -20), Vector3(0, 2.0, -1.0))
		for pair: Dictionary in overrides: (pair["node"] as MultiMeshInstance3D).material_override = pair["legacy"]
		await _capture("%s/%s-legacy-alpha.png" % [MATERIAL_CAPTURE_DIR, view])
		for pair: Dictionary in overrides: (pair["node"] as MultiMeshInstance3D).material_override = pair["original"]
		await _capture("%s/%s-opaque.png" % [MATERIAL_CAPTURE_DIR, view])
		if view == "normal":
			_check(root.get_texture().get_image().save_png("reports/screenshots/fine-prop-grid.png") == OK, "existing fine prop capture now shows gameplay materials")
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "renderer": RenderingServer.get_current_rendering_method(), "capture": "reports/screenshots/fine-prop-grid.png", "material_comparisons": MATERIAL_CAPTURE_DIR, "baseline": "reconstructed legacy alpha output", "wind_enabled": false}))
	quit(1 if failures else 0)

func _capture(path: String) -> void:
	for unused in 20: await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(not image.is_empty() and image.get_width() == 1280 and image.get_height() == 720, "actual Mobile image rendered: " + path)
	_check(image.save_png(path) == OK, "material comparison saved: " + path)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)
