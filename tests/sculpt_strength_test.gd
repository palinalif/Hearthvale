extends SceneTree
const Scale = preload("res://scripts/sculpt_strength.gd")
const Scene = preload("res://scripts/m1_scene_terrain_ux.gd")
var checks := 0
var failures := 0

class StrokeCapture extends Node:
	var settings: Dictionary = {}
	func begin_stroke(_tool, _center: Vector3, value: Dictionary, _reference: Dictionary) -> bool:
		settings = value.duplicate(true)
		return true
	func sample_surface_plane(center: Vector3, _normal: Vector3, _radius: float) -> Dictionary:
		return {"valid": true, "point": center, "normal": Vector3.UP}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _init() -> void:
	check(is_equal_approx(Scale.rate(1), 1.0), "gentle anchor")
	check(is_equal_approx(Scale.rate(5), 2.0), "default is one third of 6")
	check(is_equal_approx(Scale.rate(10), 4.0), "maximum is twice default")
	check(Scale.rate(-50) == Scale.rate(1), "lower clamp")
	check(Scale.rate(50) == Scale.rate(10), "upper clamp")
	for level in range(1, 10):
		check(Scale.rate(level + 1) > Scale.rate(level), "monotonic %d" % level)
		check(Scale.rate(level + 1) / Scale.rate(level) < 1.2, "gradual step %d" % level)
	var scene := Scene.new()
	var capture := StrokeCapture.new()
	scene.backend = capture
	scene._terrain_target_valid = true
	scene._terrain_target_point = Vector3(24, 10, 24)
	check(scene.brush_strength_level == 5 and is_equal_approx(scene.brush_strength, 2.0), "fresh M1 default")
	for tool in ["raise", "dig", "level", "slope", "smooth"]:
		for precision in [false, true]:
			scene.stroke_active = false
			scene.sculpt_tool = tool
			scene.precision_mode = precision
			scene._begin_stroke()
			check(is_equal_approx(float(capture.settings.get("strength", -1.0)), 0.5 if precision else 2.0), "live stroke rate %s precision=%s" % [tool, precision])
	scene.stroke_active = false
	for _i in 20: scene._tool_choice("Strength +")
	check(scene.brush_strength_level == 10 and is_equal_approx(scene.brush_strength, 4.0), "controller upper clamp")
	for _i in 20: scene._tool_choice("Strength -")
	check(scene.brush_strength_level == 1 and is_equal_approx(scene.brush_strength, 1.0), "controller lower clamp")
	check(scene.landscape_state.records.is_empty(), "strength does not plant or change density")
	scene.free()
	capture.free()
	print("sculpt_strength_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
