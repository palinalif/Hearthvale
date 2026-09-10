extends SceneTree

const World = preload("res://scripts/building_world.gd")
const Visual = preload("res://scripts/cottage_visual.gd")
const Massing = preload("res://scripts/m2_house_massing.gd")
const MassingVisual = preload("res://scripts/m2_house_massing_visual.gd")

var checks := 0
var failures := 0
var stage: Node3D
var camera: Camera3D
var entries: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "mobile":
		print("M2_HOUSE_SHAPES_RENDER_UNAVAILABLE")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	stage = Node3D.new()
	root.add_child(stage)
	_build_stage()
	var world := World.new()
	var specs: Array[Dictionary] = [
		{"id": "rectangle", "label": "RECTANGLE", "position": Vector3(-5.2, 0.0, -3.3)},
		{"id": "l_shape", "label": "L SHAPE", "position": Vector3(5.2, 0.0, -3.3)},
		{"id": "t_shape", "label": "T SHAPE", "position": Vector3(-5.2, 0.0, 4.1)},
		{"id": "u_shape", "label": "U SHAPE", "position": Vector3(5.2, 0.0, 4.1)},
	]
	for index in specs.size():
		var spec: Dictionary = specs[index]
		var transform_value := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * World.MINIATURE_SCALE), spec["position"])
		var view: Dictionary = world.preview_home_design("riverside_cottage", transform_value)
		if str(spec["id"]) != "rectangle":
			view["massing_sections"] = _serialize_sections(Massing.preset_sections(view, str(spec["id"])))
			view["massing_preset"] = str(spec["id"])
		var visual := _make_visual(view, index)
		entries.append({"id": str(spec["id"]), "label": str(spec["label"]), "visual": visual, "position": spec["position"]})
		var label := Label3D.new()
		label.text = str(spec["label"])
		label.position = (spec["position"] as Vector3) + Vector3(0.0, 0.18, 3.5)
		label.font_size = 34
		label.modulate = Color("#33483d")
		label.outline_size = 5
		label.outline_modulate = Color("#dbe5d6")
		stage.add_child(label)

	var custom_view: Dictionary = world.preview_home_design("riverside_cottage", Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * World.MINIATURE_SCALE), Vector3.ZERO))
	var custom_sections: Array[Dictionary] = Massing.sections_for(custom_view)
	var dims: Vector3 = custom_view["dimensions"]
	var right_wing := {"id": "custom-right", "offset": Vector3(dims.x * 0.5 + 2.25, 0.0, -dims.z * 0.14), "size": Vector3(4.5, dims.y, 5.0)}
	var back_nook := {"id": "custom-back", "offset": Vector3(-dims.x * 0.22, 0.0, dims.z * 0.5 + 2.0), "size": Vector3(5.0, dims.y, 4.0)}
	if Massing.can_add_portion(custom_sections, right_wing): custom_sections.append(right_wing)
	if Massing.can_add_portion(custom_sections, back_nook): custom_sections.append(back_nook)
	custom_view["massing_sections"] = _serialize_sections(custom_sections)
	custom_view["massing_preset"] = "custom"
	var custom_visual := _make_visual(custom_view, 20)
	entries.append({"id": "custom", "label": "CUSTOM ADDED PORTIONS", "visual": custom_visual, "position": Vector3.ZERO})
	custom_visual.visible = false

	for unused in 18: await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("reports/screenshots/m2-house-shapes")
	var comparison := root.get_texture().get_image()
	check(not comparison.is_empty() and comparison.get_width() == 1280 and comparison.get_height() == 720, "actual Mobile comparison sheet rendered")
	check(comparison.save_png("reports/screenshots/m2-house-shapes/all-shapes.png") == OK, "Mobile Rectangle/L/T/U comparison saved")

	for entry in entries:
		for other in entries: (other["visual"] as Node3D).visible = other == entry
		for child in stage.get_children():
			if child is Label3D: child.visible = false
		var visual := entry["visual"] as Node3D
		var view_value: Dictionary = visual.get_meta("review_view", {})
		var bounds: Rect2 = Massing.union_bounds(Massing.sections_for(view_value))
		var target_local := Vector3(bounds.get_center().x, float(view_value.get("dimensions", Vector3(10, 6, 8)).y) * 0.58, bounds.get_center().y)
		var transform_value: Transform3D = view_value.get("transform", Transform3D.IDENTITY)
		var target := transform_value * target_local
		camera.size = maxf(7.4, maxf(bounds.size.x, bounds.size.y) * World.MINIATURE_SCALE * 1.52)
		camera.look_at_from_position(target + Vector3(8.5, 7.0, 10.5), target)
		for unused in 10: await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := "reports/screenshots/m2-house-shapes/%s.png" % str(entry["id"])
		check(image.save_png(path) == OK, "%s Mobile shape capture saved" % str(entry["label"]))

	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "renderer": RenderingServer.get_current_rendering_method(), "captures": ["reports/screenshots/m2-house-shapes/all-shapes.png", "reports/screenshots/m2-house-shapes/rectangle.png", "reports/screenshots/m2-house-shapes/l_shape.png", "reports/screenshots/m2-house-shapes/t_shape.png", "reports/screenshots/m2-house-shapes/u_shape.png", "reports/screenshots/m2-house-shapes/custom.png"]}))
	quit(1 if failures else 0)

func _build_stage() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(28, 20)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#91aa68")
	ground_material.roughness = 1.0
	ground.material_override = ground_material
	stage.add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -34, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#c3d2c5")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#c2d5e0")
	environment.ambient_light_energy = 0.62
	environment_node.environment = environment
	stage.add_child(environment_node)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18.0
	camera.position = Vector3(14, 13, 19)
	camera.look_at_from_position(camera.position, Vector3(0, 1.2, 0))
	camera.current = true
	stage.add_child(camera)
	var overlay := CanvasLayer.new()
	stage.add_child(overlay)
	var title := Label.new()
	title.text = "HEARTHVALE / JOINED HOUSE SHAPES / MOBILE REVIEW"
	title.position = Vector2(28, 20)
	title.add_theme_font_size_override("font_size", 25)
	title.modulate = Color("#26392f")
	overlay.add_child(title)
	var note := Label.new()
	note.text = "Townscaper-style massing • shared walls disappear • one joined roof field"
	note.position = Vector2(28, 54)
	note.add_theme_font_size_override("font_size", 17)
	note.modulate = Color("#3f594a")
	overlay.add_child(note)

func _make_visual(view: Dictionary, revision: int) -> Node3D:
	var visual := Visual.new()
	stage.add_child(visual)
	visual.apply_building(view, revision)
	visual.set_meta("review_view", view.duplicate(true))
	if Massing.sections_for(view).size() > 1:
		_hide_native_shell(visual)
		var joined := MassingVisual.new()
		joined.name = "M2JoinedMassing"
		visual.add_child(joined)
		joined.show_view(view, Color("#e7cfab"), [Color("#ae5f49"), Color("#bb6a50"), Color("#9d4f40")], Color("#8d4438"))
		check(joined.get_child_count() >= 4, "%s builds foundation/walls/eaves/joined roof" % str(view.get("massing_preset", "custom")))
	return visual

func _hide_native_shell(visual: Node3D) -> void:
	for child in visual.get_children():
		if not child is Node3D: continue
		var name_value := str(child.name)
		for prefix in ["Foundation", "Wall", "LogCourses", "Trim_", "Cornice_", "RoofTiles_", "GableLeft_", "GableRight_", "CornerQuoins", "Crafted", "GableVent", "LodgeLogEnds", "TudorWallFrame", "GableFinials", "RidgeCourses", "RoofEdgeLip", "M2RoofDesign"]:
			if name_value.begins_with(prefix):
				(child as Node3D).visible = false
				break

func _serialize_sections(sections: Array[Dictionary]) -> Array:
	var result: Array = []
	for section in sections:
		var offset: Vector3 = section["offset"]
		var size: Vector3 = section["size"]
		result.append({"id": str(section.get("id", "section")), "offset": [offset.x, offset.y, offset.z], "size": [size.x, size.y, size.z]})
	return result
