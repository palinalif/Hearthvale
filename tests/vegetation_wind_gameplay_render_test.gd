extends SceneTree

const Flora = preload("res://scripts/vegetation_mesh.gd")
const GardenVisual = preload("res://scripts/m1_garden_visual.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "mobile":
		print("VEGETATION_WIND_GAMEPLAY_RENDER_UNAVAILABLE")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var scene := Node3D.new(); root.add_child(scene)
	var ground := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(24, 14); ground.mesh = plane
	var ground_material := StandardMaterial3D.new(); ground_material.albedo_color = Color("#91aa68"); ground.material_override = ground_material; scene.add_child(ground)
	var records: Array = []
	for variant in Flora.variant_count("tree"):
		records.append({"id": variant + 1, "kind": "tree", "position": [-9.0 + variant * 3.6, 0.0, 2.3], "seed": variant})
	for variant in Flora.variant_count("foliage"):
		records.append({"id": 20 + variant, "kind": "foliage", "position": [-9.0 + (variant % 6) * 3.6, 0.0, -2.0 - (variant / 6) * 1.8], "seed": variant})
	for variant in Flora.variant_count("rock"):
		records.append({"id": 40 + variant, "kind": "rock", "position": [-3.6 + variant * 3.6, 0.0, -5.1], "seed": variant})
	var garden := GardenVisual.new(); scene.add_child(garden); garden.apply_records(records)
	var phase_signatures := {}
	var distinct_phases := {}
	var palette_surfaces_synchronized := true
	for key: String in garden._groups:
		var node: MultiMeshInstance3D = garden._groups[key]
		if not node.multimesh.use_custom_data: continue
		var signature := ""
		for instance in node.multimesh.instance_count:
			var phase := node.multimesh.get_instance_custom_data(instance).r
			signature += "%.6f," % phase
			distinct_phases["%.6f" % phase] = true
		var asset_key := key.get_slice("_", 0) + "_" + key.get_slice("_", 1)
		if phase_signatures.has(asset_key): palette_surfaces_synchronized = palette_surfaces_synchronized and phase_signatures[asset_key] == signature
		else: phase_signatures[asset_key] = signature
	_check(distinct_phases.size() >= 4, "actual Mobile MultiMesh retains independent planting phases")
	_check(palette_surfaces_synchronized, "actual Mobile palette surfaces share each asset's phase sequence")
	var terrain_reference := MeshInstance3D.new(); var cube := BoxMesh.new(); cube.size = Vector3.ONE * 0.125; terrain_reference.mesh = cube; terrain_reference.position = Vector3(-9.0, 0.0625, -5.1)
	var terrain_material := StandardMaterial3D.new(); terrain_material.albedo_color = Color("#7d9957"); terrain_reference.material_override = terrain_material; scene.add_child(terrain_reference)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, -30, 0); sun.shadow_enabled = true; scene.add_child(sun)
	var world := WorldEnvironment.new(); var environment := Environment.new(); environment.background_mode = Environment.BG_COLOR; environment.background_color = Color("#c3d2c5"); environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color = Color("#c2d5e0"); environment.ambient_light_energy = 0.55; world.environment = environment; scene.add_child(world)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 15.5; camera.position = Vector3(8, 10, 18); camera.look_at_from_position(camera.position, Vector3(0, 2.0, -1.0)); camera.current = true; scene.add_child(camera)
	var overlay := CanvasLayer.new(); scene.add_child(overlay)
	var title := Label.new(); title.text = "HEARTHVALE / GAMEPLAY VEGETATION WIND / MOBILE REVIEW"; title.position = Vector2(28, 20); title.add_theme_font_size_override("font_size", 25); title.modulate = Color("#26392f"); overlay.add_child(title)
	var note := Label.new(); note.text = "independent tree + foliage sway  •  fixed roots  •  static mushrooms + rocks"; note.position = Vector2(28, 54); note.add_theme_font_size_override("font_size", 17); note.modulate = Color("#3f594a"); overlay.add_child(note)
	for unused in 20: await RenderingServer.frame_post_draw
	var first_image := root.get_texture().get_image()
	for unused in 75: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(not image.is_empty() and image.get_width() == 1280, "actual Mobile image rendered")
	_check(_difference(first_image, image) > 0.000001, "gameplay-batched trees and foliage visibly sway over time")
	DirAccess.make_dir_recursive_absolute("reports/screenshots")
	_check(image.save_png("reports/screenshots/vegetation-wind-gameplay.png") == OK, "gameplay wind review capture saved")
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "renderer": RenderingServer.get_current_rendering_method(), "phase_count": distinct_phases.size(), "capture": "reports/screenshots/vegetation-wind-gameplay.png"}))
	quit(1 if failures else 0)

func _difference(a: Image, b: Image) -> float:
	var bytes_a := a.get_data(); var bytes_b := b.get_data()
	if bytes_a == bytes_b: return 0.0
	var total := 0.0
	for i in bytes_a.size(): total += abs(int(bytes_a[i]) - int(bytes_b[i]))
	return total / (bytes_a.size() * 255.0)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)
