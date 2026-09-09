extends SceneTree

const Flora = preload("res://scripts/vegetation_mesh.gd")
const GardenVisual = preload("res://scripts/m1_garden_visual.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "mobile":
		print("FOLIAGE_HALFSIZE_RENDER_UNAVAILABLE")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var scene := Node3D.new(); root.add_child(scene)
	var ground := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(11, 7); ground.mesh = plane
	var ground_material := StandardMaterial3D.new(); ground_material.albedo_color = Color("#91aa68"); ground.material_override = ground_material; scene.add_child(ground)
	var records: Array = []
	for variant in Flora.variant_count("foliage"):
		var row := 0 if variant < 6 else 1
		var column := variant if row == 0 else variant - 6
		var position := Vector3(-3.75 + column * 1.5, 0, 1.25 - row * 2.1)
		records.append({"id": variant + 1, "kind": "foliage", "position": [position.x, position.y, position.z], "seed": variant})
		if variant >= 8:
			for extra in 2:
				var extra_position := position + Vector3(0.28 * float(extra + 1), 0, -0.22 * float(extra + 1))
				records.append({"id": 20 + variant * 2 + extra, "kind": "foliage", "position": [extra_position.x, extra_position.y, extra_position.z], "seed": variant})
	for variant in Flora.variant_count("rock"):
		for extra in 3:
			var rock_position := Vector3(0.7 + variant * 1.45 + extra * 0.32, 0, 2.75 - extra * 0.2)
			records.append({"id": 100 + variant * 3 + extra, "kind": "rock", "position": [rock_position.x, rock_position.y, rock_position.z], "seed": variant})
	var garden := GardenVisual.new(); scene.add_child(garden); garden.apply_records(records)
	var terrain_reference := MeshInstance3D.new(); var cube := BoxMesh.new(); cube.size = Vector3.ONE * 0.125; terrain_reference.mesh = cube; terrain_reference.position = Vector3(4.3, 0.0625, -0.85); scene.add_child(terrain_reference)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, -30, 0); sun.shadow_enabled = true; scene.add_child(sun)
	var world := WorldEnvironment.new(); var environment := Environment.new(); environment.background_mode = Environment.BG_COLOR; environment.background_color = Color("#c3d2c5"); environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color = Color("#c2d5e0"); environment.ambient_light_energy = 0.55; world.environment = environment; scene.add_child(world)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 6.5; camera.position = Vector3(6.5, 6.5, 10); camera.look_at_from_position(camera.position, Vector3(0, 0.35, 0)); camera.current = true; scene.add_child(camera)
	var overlay := CanvasLayer.new(); scene.add_child(overlay)
	var title := Label.new(); title.text = "HEARTHVALE / ROTATED + TINTED PLANTING / MOBILE REVIEW"; title.position = Vector2(28, 20); title.add_theme_font_size_override("font_size", 25); title.modulate = Color("#26392f"); overlay.add_child(title)
	var note := Label.new(); note.text = "tree 15° steps  •  foliage quarter turns  •  foliage/rock hue + value variety  •  warm mushroom caps"; note.position = Vector2(28, 54); note.add_theme_font_size_override("font_size", 17); note.modulate = Color("#3f594a"); overlay.add_child(note)
	for unused in 20: await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(not image.is_empty() and image.get_width() == 1280, "actual Mobile image rendered")
	DirAccess.make_dir_recursive_absolute("reports/screenshots")
	_check(image.save_png("reports/screenshots/foliage-halfsize.png") == OK, "half-size foliage comparison saved")
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "renderer": RenderingServer.get_current_rendering_method(), "capture": "reports/screenshots/foliage-halfsize.png"}))
	quit(1 if failures else 0)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)
