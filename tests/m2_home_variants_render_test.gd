extends SceneTree

const World = preload("res://scripts/building_world.gd")
const Visual = preload("res://scripts/cottage_visual.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "mobile":
		print("M2_HOME_VARIANTS_RENDER_UNAVAILABLE")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new(); root.add_child(stage)
	var ground := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(28, 15); ground.mesh = plane
	var ground_material := StandardMaterial3D.new(); ground_material.albedo_color = Color("#91aa68"); ground.material_override = ground_material; stage.add_child(ground)
	var world := World.new()
	var specs := [
		["riverside_cottage", Vector3(-7.0, 0.0, 0.0)],
		["woodland_lodge", Vector3(0.0, 0.0, 0.0)],
		["village_gable", Vector3(7.0, 0.0, 0.0)],
	]
	var visuals: Array[Node3D] = []
	for index in specs.size():
		var spec: Array = specs[index]
		var transform_value := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * World.MINIATURE_SCALE), spec[1])
		var view := world.preview_home_design(spec[0], transform_value)
		var visual := Visual.new(); stage.add_child(visual); visual.apply_building(view, index); visuals.append(visual)
		var label := Label3D.new(); label.text = str(view["name"]); label.position = spec[1] + Vector3(0, 0.15, 3.4); label.font_size = 38; label.modulate = Color("#33483d"); stage.add_child(label)
	check(visuals[0].get_node_or_null("CornerQuoins") != null, "riverside recipe renders masonry corner language")
	check(visuals[1].get_node_or_null("LodgeTimberFrame") != null and visuals[1].get_node_or_null("CornerQuoins") == null, "woodland lodge renders a distinct low timber language")
	check(visuals[2].get_node_or_null("GableFinials") != null, "village gable renders distinct steep-roof accents")
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, -30, 0); sun.shadow_enabled = true; stage.add_child(sun)
	var environment_node := WorldEnvironment.new(); var environment := Environment.new(); environment.background_mode = Environment.BG_COLOR; environment.background_color = Color("#c3d2c5"); environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color = Color("#c2d5e0"); environment.ambient_light_energy = 0.58; environment_node.environment = environment; stage.add_child(environment_node)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 15.0; camera.position = Vector3(13, 11, 18); camera.look_at_from_position(camera.position, Vector3(0, 1.4, 0)); camera.current = true; stage.add_child(camera)
	var overlay := CanvasLayer.new(); stage.add_child(overlay)
	var title := Label.new(); title.text = "HEARTHVALE / M2 RESIDENTIAL CATALOGUE / MOBILE REVIEW"; title.position = Vector2(28, 20); title.add_theme_font_size_override("font_size", 25); title.modulate = Color("#26392f"); overlay.add_child(title)
	var note := Label.new(); note.text = "classic riverside  •  low timber lodge  •  tall village gable  •  independent roofs"; note.position = Vector2(28, 54); note.add_theme_font_size_override("font_size", 17); note.modulate = Color("#3f594a"); overlay.add_child(note)
	for unused in 20: await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(not image.is_empty() and image.get_width() == 1280, "actual Mobile catalogue image rendered")
	DirAccess.make_dir_recursive_absolute("reports/screenshots/m2-home-catalogue")
	check(image.save_png("reports/screenshots/m2-home-catalogue/three-home-recipes.png") == OK, "three-home Mobile comparison saved")
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "renderer": RenderingServer.get_current_rendering_method(), "capture": "reports/screenshots/m2-home-catalogue/three-home-recipes.png"}))
	quit(1 if failures else 0)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)
