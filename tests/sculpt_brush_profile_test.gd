extends SceneTree

const Backend = preload("res://scripts/terrain_backend.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _init() -> void:
	for falloff in [0.0, 0.25, 0.45, 0.75, 1.0]:
		check(is_equal_approx(Backend.sculpt_front_influence(0.0, falloff), 1.0), "centre stays full strength %.2f" % falloff)
		check(is_equal_approx(Backend.sculpt_front_influence(1.0, falloff), 0.0), "edge reaches zero %.2f" % falloff)
		var previous := 1.0
		for step in range(1, 21):
			var current := Backend.sculpt_front_influence(float(step) / 20.0, falloff)
			check(current <= previous + 0.000001, "profile monotonic %.2f/%d" % [falloff, step])
			previous = current
	# Low falloff is intentionally a broad plateau: half-radius edits should
	# advance at the same rate as the centre instead of forming a cone.
	check(is_equal_approx(Backend.sculpt_front_influence(0.5, 0.0), 1.0), "low falloff has broad plateau")
	# Default M1 setting should remain essentially flat through the inner half.
	check(Backend.sculpt_front_influence(0.5, 0.45) > 0.98, "default falloff is not cone-shaped")
	# High falloff is the rounded option and therefore attenuates by half radius.
	check(Backend.sculpt_front_influence(0.5, 1.0) < 0.75, "high falloff produces rounded hill")
	check(Backend.sculpt_front_influence(0.5, 0.0) > Backend.sculpt_front_influence(0.5, 1.0), "falloff exposes distinct shapes")
	check(Backend.sculpt_front_influence(NAN, 0.5) == 0.0, "invalid distance rejected")
	print("sculpt_brush_profile_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
