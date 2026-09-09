extends Node3D

const Wind = preload("res://scripts/tree_wind.gd")
const NAMES := ["orchard", "riverside", "wind"]
var trees: Array[MeshInstance3D] = []
var winds: Array[TreeWind] = []
var elapsed := 0.0
var wind_enabled := true
var paused := false
var automatic := true
var status: Label

func _ready() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new(); plane.size = Vector2(18, 8); ground.mesh = plane
	var material := StandardMaterial3D.new(); material.albedo_color = Color("#91aa68")
	ground.material_override = material; add_child(ground)
	for i in 3:
		var tree := MeshInstance3D.new()
		tree.mesh = load("res://assets/models/magicavoxel/hearthvale_tree_" + NAMES[i] + ".res")
		tree.position.x = (i - 1) * 5.25
		add_child(tree); trees.append(tree)
		winds.append(Wind.new(tree, [0.0, 1.9, 4.1][i]))
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true; add_child(sun)
	var world := WorldEnvironment.new(); var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR; environment.background_color = Color("#c3d2c5")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#c2d5e0"); environment.ambient_light_energy = 0.55
	world.environment = environment; add_child(world)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.0; camera.look_at_from_position(Vector3(3, 7.5, 18), Vector3(0, 2.7, 0))
	camera.current = true; add_child(camera)
	var overlay := CanvasLayer.new(); add_child(overlay)
	_label(overlay, "HEARTHVALE / A LITTLE BREEZE", Vector2(30, 24), 26)
	for i in 3:
		var point := camera.unproject_position(trees[i].position)
		_label(overlay, ["BROAD ORCHARD", "TALL RIVERSIDE", "WIND-SHAPED"][i], Vector2(point.x - 100, 604), 20)
	status = _label(overlay, "", Vector2(30, 668), 18)
	_update_status()

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
	for wind in winds:
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
