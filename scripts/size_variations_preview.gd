extends Node3D

const Wind = preload("res://scripts/tree_wind.gd")
const ORIGINALS := ["orchard", "riverside", "wind"]
const VARIANTS := ["orchard_compact", "riverside_young", "wind_low"]
const LABELS := ["COMPACT ORCHARD", "YOUNG RIVERSIDE", "LOW WIND-SHAPED"]
var trees: Array[MeshInstance3D] = []
var winds: Array[TreeWind] = []
var context_winds: Array[TreeWind] = []
var rocks: Array[MeshInstance3D] = [] # Static mushroom patches use the shared preview-test contract.
var elapsed := 0.0
var wind_enabled := true
var paused := false
var automatic := true
var status: Label

func _ready() -> void:
	var ground := MeshInstance3D.new(); var plane := PlaneMesh.new()
	plane.size = Vector2(18, 10); ground.mesh = plane
	var ground_material := StandardMaterial3D.new(); ground_material.albedo_color = Color("#91aa68")
	ground.material_override = ground_material; add_child(ground)
	for i in 3:
		var x := (i - 1) * 5.25
		var original := MeshInstance3D.new()
		original.mesh = load("res://assets/models/magicavoxel/hearthvale_tree_" + ORIGINALS[i] + ".res")
		original.position = Vector3(x, 0, -1.55); add_child(original)
		context_winds.append(Wind.new(original, [0.0, 1.9, 4.1][i]))
		var compact := MeshInstance3D.new()
		compact.mesh = load("res://assets/models/magicavoxel/hearthvale_tree_" + VARIANTS[i] + ".res")
		compact.position = Vector3(x, 0, 2.15); add_child(compact)
		trees.append(compact); winds.append(Wind.new(compact, [0.45, 2.35, 4.55][i]))
	for i in 2:
		var mushrooms := MeshInstance3D.new()
		mushrooms.mesh = load("res://assets/models/magicavoxel/hearthvale_foliage_mushrooms_" + ["flat", "flat_scatter"][i] + ".res")
		mushrooms.position = Vector3([-2.0, 2.0][i], 0, 4.1); add_child(mushrooms); rocks.append(mushrooms)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, -30, 0); sun.shadow_enabled = true; add_child(sun)
	var world := WorldEnvironment.new(); var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR; environment.background_color = Color("#c3d2c5")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#c2d5e0"); environment.ambient_light_energy = 0.55
	world.environment = environment; add_child(world)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.5; camera.look_at_from_position(Vector3(3, 8.5, 19), Vector3(0, 2.6, 0.7))
	camera.current = true; add_child(camera)
	var overlay := CanvasLayer.new(); add_child(overlay)
	_label(overlay, "HEARTHVALE / TREE SIZE VARIATIONS & FLAT MUSHROOMS", Vector2(30, 24), 26)
	_label(overlay, "APPROVED FULL SIZE BEHIND  /  NEW COMPACT SIZE IN FRONT", Vector2(30, 58), 17)
	for i in 3:
		var point := camera.unproject_position(trees[i].position)
		_label(overlay, LABELS[i], Vector2(point.x - 105, 565), 18)
	_label(overlay, "LOW TRIO", Vector2(490, 630), 17)
	_label(overlay, "WIDE SCATTER", Vector2(685, 630), 17)
	status = _label(overlay, "", Vector2(30, 680), 17)
	set_time(0.0); _update_status()

func _label(parent: Node, text: String, position_2d: Vector2, size: int) -> Label:
	var label := Label.new(); label.text = text; label.position = position_2d
	label.add_theme_font_size_override("font_size", size); label.modulate = Color("#26392f")
	parent.add_child(label); return label

func _process(delta: float) -> void:
	if automatic: advance(delta)

func advance(delta: float) -> void:
	if not paused and wind_enabled: set_time(elapsed + delta)

func set_time(seconds: float) -> void:
	elapsed = fposmod(seconds, Wind.PERIOD)
	for wind in winds + context_winds:
		wind.strength = Wind.DEFAULT_STRENGTH if wind_enabled else 0.0
		wind.set_time(elapsed)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_SPACE: paused = not paused
	elif event.keycode == KEY_W:
		wind_enabled = not wind_enabled; set_time(elapsed)
	elif event.keycode == KEY_ESCAPE: get_tree().quit()
	_update_status()

func _update_status() -> void:
	status.text = "Gentle wind  /  " + ("Paused" if paused else ("On" if wind_enabled else "Off")) + "     •     Space: pause     W: wind on/off     Esc: close"
