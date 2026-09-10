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
		print("M2_MULTI_FLOOR_RENDER_UNAVAILABLE")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	stage = Node3D.new()
	root.add_child(stage)
	_build_stage()
	var world := World.new()
	var specs: Array[Dictionary] = [
		{"id": "two_storey", "label": "FULL 2 STOREY", "position": Vector3(-5.1, 0.0, -3.1)},
		{"id": "stepped", "label": "STEPPED 2 STOREY", "position": Vector3(5.1, 0.0, -3.1)},
		{"id": "upper_l", "label": "L-SHAPED UPPER", "position": Vector3(-5.1, 0.0, 4.1)},
		{"id": "tower", "label": "3 STOREY TOWER", "position": Vector3(5.1, 0.0, 4.1)},
	]
	for index in specs.size():
		var spec: Dictionary = specs[index]
		var transform_value := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * World.MINIATURE_SCALE), spec["position"])
		var view: Dictionary = world.preview_home_design("riverside_cottage", transform_value)
		view["massing_sections"] = _sections_for_example(view, str(spec["id"]))
		view["massing_preset"] = "custom"
		var visual := _make_visual(view, index)
		entries.append({"id": str(spec["id"]), "label": str(spec["label"]), "visual": visual, "view": view})
		var label := Label3D.new()
		label.text = str(spec["label"])
		label.position = (spec["position"] as Vector3) + Vector3(0.0, 0.18, 3.7)
		label.font_size = 31
		label.modulate = Color("#33483d")
		label.outline_size = 5
		label.outline_modulate = Color("#dbe5d6")
		stage.add_child(label)

	for unused in 18: await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("reports/screenshots/m2-multi-floor")
	var comparison := root.get_texture().get_image()
	check(not comparison.is_empty() and comparison.get_width() == 1280 and comparison.get_height() == 720, "actual Mobile multi-floor comparison rendered")
	check(comparison.save_png("reports/screenshots/m2-multi-floor/all-floors.png") == OK, "Mobile multi-floor comparison saved")

	for entry in entries:
		for other in entries: (other["visual"] as Node3D).visible = other == entry
		for child in stage.get_children():
			if child is Label3D: child.visible = false
		var view: Dictionary = entry["view"]
		var bounds: Rect2 = Massing.union_bounds(Massing.sections_for(view))
		var top := 0.0
		for section in Massing.sections_for(view): top = maxf(top, Massing.section_top(section))
		var transform_value: Transform3D = view.get("transform", Transform3D.IDENTITY)
		var target := transform_value * Vector3(bounds.get_center().x, top * 0.48, bounds.get_center().y)
		camera.size = maxf(7.8, maxf(maxf(bounds.size.x, bounds.size.y), top * 0.78) * World.MINIATURE_SCALE * 1.50)
		camera.look_at_from_position(target + Vector3(8.7, 7.4, 10.7), target)
		for unused in 10: await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := "reports/screenshots/m2-multi-floor/%s.png" % str(entry["id"])
		check(image.save_png(path) == OK, "%s Mobile capture saved" % str(entry["label"]))

	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "renderer": RenderingServer.get_current_rendering_method(), "capture": "reports/screenshots/m2-multi-floor/all-floors.png"}))
	quit(1 if failures else 0)

func _sections_for_example(view: Dictionary, example_id: String) -> Array[Dictionary]:
	var dims: Vector3 = view["dimensions"]
	var core: Dictionary = Massing.core_section(view)
	var sections: Array[Dictionary] = [core]
	match example_id:
		"two_storey":
			sections.append({"id": "floor2", "level": 1, "offset": Vector3(0, dims.y, 0), "size": dims})
		"stepped":
			sections.append({"id": "floor2-small", "level": 1, "offset": Vector3(-dims.x * 0.12, dims.y, 0), "size": Vector3(dims.x * 0.62, dims.y, dims.z * 0.60)})
		"upper_l":
			sections.append({"id": "floor2-main", "level": 1, "offset": Vector3(-dims.x * 0.12, dims.y, -dims.z * 0.08), "size": Vector3(dims.x * 0.62, dims.y, dims.z * 0.58)})
			sections.append({"id": "floor2-wing", "level": 1, "offset": Vector3(dims.x * 0.22, dims.y, dims.z * 0.20), "size": Vector3(dims.x * 0.34, dims.y, dims.z * 0.42)})
		"tower":
			sections.append({"id": "floor2", "level": 1, "offset": Vector3(0, dims.y, 0), "size": Vector3(dims.x * 0.68, dims.y, dims.z * 0.68)})
			sections.append({"id": "floor3", "level": 2, "offset": Vector3(0, dims.y * 2.0, 0), "size": Vector3(dims.x * 0.38, dims.y, dims.z * 0.40)})
	return sections

func _build_stage() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(29, 21)
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
	camera.size = 19.0
	camera.position = Vector3(14, 14, 20)
	camera.look_at_from_position(camera.position, Vector3(0, 2.0, 0))
	camera.current = true
	stage.add_child(camera)
	var overlay := CanvasLayer.new()
	stage.add_child(overlay)
	var title := Label.new()
	title.text = "HEARTHVALE / STACKED HOUSE MASSING / MOBILE REVIEW"
	title.position = Vector2(28, 20)
	title.add_theme_font_size_override("font_size", 25)
	title.modulate = Color("#26392f")
	overlay.add_child(title)
	var note := Label.new()
	note.text = "same portion workflow vertically • supported upper floors • roofs only on exposed tops"
	note.position = Vector2(28, 54)
	note.add_theme_font_size_override("font_size", 17)
	note.modulate = Color("#3f594a")
	overlay.add_child(note)

func _make_visual(view: Dictionary, revision: int) -> Node3D:
	var visual := Visual.new()
	stage.add_child(visual)
	visual.apply_building(view, revision)
	_hide_native_shell(visual)
	var joined := MassingVisual.new()
	joined.name = "M2JoinedMassing"
	visual.add_child(joined)
	joined.show_view(view, Color("#e7cfab"), [Color("#ae5f49"), Color("#bb6a50"), Color("#9d4f40")], Color("#8d4438"))
	check(joined.get_node_or_null("JoinedFloorBands") != null, "%s renders visible storey bands" % str(view.get("massing_preset", "custom")))
	return visual

func _hide_native_shell(visual: Node3D) -> void:
	for child in visual.get_children():
		if not child is Node3D: continue
		var name_value := str(child.name)
		for prefix in ["Foundation", "Wall", "LogCourses", "Trim_", "Cornice_", "RoofTiles_", "GableLeft_", "GableRight_", "CornerQuoins", "Crafted", "GableVent", "LodgeLogEnds", "TudorWallFrame", "GableFinials", "RidgeCourses", "RoofEdgeLip", "EaveJoinery", "M2RoofDesign"]:
			if name_value.begins_with(prefix):
				(child as Node3D).visible = false
				break
