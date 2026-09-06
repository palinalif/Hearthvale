extends Node3D

const TreeVariationScript := preload("res://dev/tree_variations/tree_variation.gd")
const BuildingWorldScript := preload("res://scripts/building_world.gd")
const CottageVisualScript := preload("res://scripts/cottage_visual.gd")

var capture_name := ""

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): capture_name = arg.get_slice("=", 1)
	_build_lighting()
	_build_ground()
	_build_trees()
	_build_cottage()
	_configure_camera()
	if not capture_name.is_empty(): call_deferred("_capture_after_frames")

func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "TrialSun"
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.light_color = Color("#fff0d5")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#c3d2c5")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#c2d5e0")
	environment.ambient_light_energy = 0.55
	environment.fog_enabled = false
	environment_node.environment = environment
	add_child(environment_node)

func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "ReviewGround"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(34, 0.24, 18)
	ground.mesh = mesh
	ground.position = Vector3(3, -0.12, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#849d61")
	material.roughness = 1.0
	ground.material_override = material
	add_child(ground)

func _build_trees() -> void:
	var placements := [
		["compact", Vector3(-8, 0, 0)],
		["tall", Vector3(-1, 0, 0)],
		["asymmetric", Vector3(6, 0, 0)]
	]
	for placement in placements:
		var kind: String = placement[0]
		var tree: Node3D = TreeVariationScript.build_variant(kind, 1042)
		tree.position = placement[1]
		add_child(tree)
		var stats: Dictionary = tree.get_meta("tree_stats")
		_add_label(str(stats["label"]), placement[1] + Vector3(0, float(stats["bounds_max_cell"].y) * TreeVariationScript.CELL_SIZE + 1.0, 0))

func _build_cottage() -> void:
	var world := BuildingWorldScript.new()
	var view: Dictionary = world.get_building("building-1")
	view["transform"] = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * BuildingWorldScript.MINIATURE_SCALE), Vector3(14, 0, 0))
	var cottage := CottageVisualScript.new()
	cottage.name = "CurrentProceduralCottage"
	add_child(cottage)
	cottage.request_revision(world.get_revision())
	cottage.apply_building(view, world.get_revision())
	_add_label("CURRENT COTTAGE", Vector3(14, 5.9, 0), Color("#fff0d5"))

func _add_label(text_value: String, position_value: Vector3, color := Color("#f5ead4")) -> void:
	var label := Label3D.new()
	label.text = text_value
	label.position = position_value
	label.font_size = 48
	label.modulate = color
	label.outline_size = 10
	label.fixed_size = false
	label.pixel_size = 0.004
	label.outline_modulate = Color("#3a4636")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)

func _configure_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "TrialCamera"
	camera.current = true
	camera.fov = 52.0
	var close := capture_name.contains("close")
	camera.position = Vector3(9, 13, 29) if not close else Vector3(2, 10, 21)
	var target := Vector3(3.0, 2.7, 0.0) if not close else Vector3(-1.0, 2.7, 0.0)
	add_child(camera)
	camera.look_at(target, Vector3.UP)

func _capture_after_frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	var image := get_viewport().get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var output := ProjectSettings.globalize_path("res://reports/screenshots/tree-trial/%s.png" % capture_name)
	var error := image.save_png(output)
	print(JSON.stringify({"ok": error == OK, "capture": output, "renderer": RenderingServer.get_current_rendering_method(), "size": "%sx%s" % [image.get_width(), image.get_height()]}))
	get_tree().quit(0 if error == OK else 1)
