extends Node3D

const Wind = preload("res://scripts/tree_wind.gd")
const Flora = preload("res://scripts/vegetation_mesh.gd")
const NAMES := ["seedgrass", "cream", "mauve"]
const STRENGTHS := [0.04, 0.02, 0.035]
# Same preview contract as the tree study, allowing the shared GPU/reference gate.
var rocks: Array[MeshInstance3D] = []
var trees: Array[MeshInstance3D] = []
var winds: Array[TreeWind] = []
var context_winds: Array[TreeWind] = []
var context_strengths: Array[float] = []
var elapsed := 0.0
var wind_enabled := true
var paused := false
var automatic := true
var status: Label

func _ready() -> void:
	var context := "--context" in OS.get_cmdline_user_args()
	var ground := MeshInstance3D.new(); var plane := PlaneMesh.new()
	plane.size = Vector2(18, 8) if context else Vector2(6.5, 5.2); ground.mesh = plane
	var material := StandardMaterial3D.new(); material.albedo_color = Color("#91aa68")
	ground.material_override = material; add_child(ground)
	for i in 3:
		var plant := MeshInstance3D.new()
		plant.mesh = load("res://assets/models/magicavoxel/hearthvale_foliage_" + NAMES[i] + ".res")
		plant.position = Vector3((i - 1) * (5.25 if context else 1.9), 0, 1.4 if context else 1.2)
		add_child(plant); trees.append(plant); winds.append(Wind.new(plant, [0.3, 2.2, 4.4][i]))
		var rock := MeshInstance3D.new()
		rock.mesh = load("res://assets/models/magicavoxel/hearthvale_rock_" + ["slab", "split", "moss"][i] + ".res")
		rock.position = Vector3((i - 1) * (5.25 if context else 1.9) + (1.15 if context else 0.0), 0, -0.4 if context else -1.3)
		add_child(rock); rocks.append(rock)
		if context:
			var tree := MeshInstance3D.new()
			tree.mesh = load("res://assets/models/magicavoxel/hearthvale_tree_" + ["orchard", "riverside", "wind"][i] + ".res")
			tree.position.x = (i - 1) * 5.25; add_child(tree)
			context_winds.append(Wind.new(tree, [0.0, 1.9, 4.1][i])); context_strengths.append(Wind.DEFAULT_STRENGTH)
			for j in 2:
				var extra := MeshInstance3D.new()
				var variant := (i + j + 1) % 3
				extra.mesh = load("res://assets/models/magicavoxel/hearthvale_foliage_" + NAMES[variant] + ".res")
				extra.position = Vector3(tree.position.x + [-1.0, 1.15][j], 0, [0.65, 0.4][j])
				add_child(extra); context_winds.append(Wind.new(extra, i * 1.8 + j * 0.9))
				context_strengths.append(STRENGTHS[variant])
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true; add_child(sun)
	var world := WorldEnvironment.new(); var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR; environment.background_color = Color("#c3d2c5")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#c2d5e0"); environment.ambient_light_energy = 0.55
	world.environment = environment; add_child(world)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	if context:
		camera.size = 14.0; camera.look_at_from_position(Vector3(3, 7.5, 18), Vector3(0, 2.7, 0))
	else:
		camera.size = 4.1; camera.look_at_from_position(Vector3(0.8, 4, 6), Vector3(0, 0.2, 0))
	camera.current = true; add_child(camera)
	var overlay := CanvasLayer.new(); add_child(overlay)
	_label(overlay, "HEARTHVALE / " + ("MEADOW ADDITIONS / AT TREE SCALE" if context else "THREE NEW PLANTS & THREE NEW ROCKS"), Vector2(30, 24), 26)
	if not context:
		for i in 3:
			var old_point := camera.unproject_position(Vector3((i - 1) * 1.9, 0, -1.3))
			_label(overlay, ["FLAT STONE", "SPLIT BOULDER", "MOSSY CLUSTER"][i], old_point + Vector2(-65, 22), 16)
			var point := camera.unproject_position(trees[i].position)
			_label(overlay, ["SEED GRASS", "CREAM FLOWERS", "MAUVE SPIKES"][i], point + Vector2(-90, 32), 18)
	status = _label(overlay, "", Vector2(30, 668), 18)
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
	for i in winds.size():
		winds[i].strength = STRENGTHS[i] if wind_enabled else 0.0; winds[i].set_time(elapsed)
	for i in context_winds.size():
		context_winds[i].strength = context_strengths[i] if wind_enabled else 0.0; context_winds[i].set_time(elapsed)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_SPACE: paused = not paused
	elif event.keycode == KEY_W:
		wind_enabled = not wind_enabled; set_time(elapsed)
	elif event.keycode == KEY_ESCAPE: get_tree().quit()
	_update_status()

func _update_status() -> void:
	status.text = "Gentle wind  /  " + ("Paused" if paused else ("On" if wind_enabled else "Off")) + "     •     Space: pause     W: wind on/off     Esc: close"
