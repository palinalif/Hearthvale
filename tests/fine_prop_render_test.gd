extends SceneTree

const Flora = preload("res://scripts/vegetation_mesh.gd")

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
	for variant in Flora.variant_count("tree"):
		_add_parts(scene, "tree", variant, Vector3(-9.0 + variant * 3.6, 0, 2.3))
	for variant in Flora.variant_count("foliage"):
		_add_parts(scene, "foliage", variant, Vector3(-9.0 + (variant % 6) * 3.6, 0, -2.0 - (variant / 6) * 1.8))
	for variant in Flora.variant_count("rock"):
		_add_parts(scene, "rock", variant, Vector3(-3.6 + variant * 3.6, 0, -5.1))
	var terrain_reference := MeshInstance3D.new(); var cube := BoxMesh.new(); cube.size = Vector3.ONE * 0.125; terrain_reference.mesh = cube; terrain_reference.position = Vector3(-9.0, 0.0625, -5.1)
	var terrain_material := StandardMaterial3D.new(); terrain_material.albedo_color = Color("#7d9957"); terrain_reference.material_override = terrain_material; scene.add_child(terrain_reference)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, -30, 0); sun.shadow_enabled = true; scene.add_child(sun)
	var world := WorldEnvironment.new(); var environment := Environment.new(); environment.background_mode = Environment.BG_COLOR; environment.background_color = Color("#c3d2c5"); environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color = Color("#c2d5e0"); environment.ambient_light_energy = 0.55; world.environment = environment; scene.add_child(world)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 15.5; camera.position = Vector3(8, 10, 18); camera.look_at_from_position(camera.position, Vector3(0, 2.0, -1.0)); camera.current = true; scene.add_child(camera)
	var overlay := CanvasLayer.new(); scene.add_child(overlay)
	var title := Label.new(); title.text = "HEARTHVALE / 0.0625 PROP GRID / MOBILE REVIEW"; title.position = Vector2(28, 20); title.add_theme_font_size_override("font_size", 25); title.modulate = Color("#26392f"); overlay.add_child(title)
	for unused in 20: await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(not image.is_empty() and image.get_width() == 1280, "actual Mobile image rendered")
	DirAccess.make_dir_recursive_absolute("reports/screenshots")
	_check(image.save_png("reports/screenshots/fine-prop-grid.png") == OK, "fine prop comparison saved")
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "renderer": RenderingServer.get_current_rendering_method(), "capture": "reports/screenshots/fine-prop-grid.png"}))
	quit(1 if failures else 0)

func _add_parts(parent: Node3D, kind: String, variant: int, position: Vector3) -> void:
	for mesh: Mesh in Flora.meshes(kind, variant):
		var part := MeshInstance3D.new(); part.mesh = mesh; part.position = position; parent.add_child(part)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)
