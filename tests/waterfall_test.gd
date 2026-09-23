extends SceneTree
## Headless, deterministic tests for the shared waterfall geometry. The
## renderer is scene-based (M1WaterVisual) and the derivation itself is
## pure logic over water regions + a terrain-top sampler, so this test
## drives the same code path with a small fixture: a flat reservoir
## shelf above a river, with the terrain dropping in one cell so the
## wedge rule finds exactly one candidate. The digest proves the derived
## fall is stable across runs and that the cascade widths (crown_width /
## impact_width) track the submerged channel, not a fixed 1.5 m pole.
const State = preload("res://scripts/landscape_state.gd")
const Waterfall = preload("res://scripts/waterfall_geometry.gd")

var failures := 0
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _initialize() -> void:
	_run()
	print("waterfall_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _run() -> void:
	var state = State.new()
	# The reservoir: a wide lake (8 m) at level 20 on a shelf at 21, its
	# south edge on the shelf line z=0.
	var reservoir_id: int = state.add_water("lake", 20.0, [
		[7.0, 40.0], [15.0, 40.0], [15.0, 48.0], [7.0, 48.0]])
	check(reservoir_id > 0, "reservoir region added")
	# The river: a wider lake (18 m) at level 10 below the shelf.
	var river_id: int = state.add_water("lake", 10.0, [
		[2.0, 28.0], [20.0, 28.0], [20.0, 40.0], [2.0, 40.0]])
	check(river_id > 0, "river region added")

	# Terrain: a carved bowl just below the reservoir level (19.8) along the
	# reservoir's south line, a higher shelf (21) beyond it, and the river at
	# 9.5 below the drop -- the lip rule finds the bowl edge, not a hole.
	var sample := func(p: Vector2) -> float:
		if p.y >= 40.0 and p.x >= 7.0 and p.x <= 15.0:
			return 19.8
		if p.y > 40.0:
			return 21.0
		return 9.5

	var falls: Array = Waterfall.derive(state.water, sample)
	check(falls.size() == 1, "exactly one waterfall derives")
	if falls.size() == 1:
		var fall: Dictionary = falls[0]
		check(int(fall["upper_id"]) == reservoir_id, "upper body is the reservoir")
		check(int(fall["lower_id"]) == river_id, "lower body is the river")
		check(is_equal_approx(float(fall["head"]), 10.0), "head is the 10 m drop")
		# The cascade tilts over a horizontal run proportional to the head.
		check(is_equal_approx(Waterfall.cascade_run(10.0), 2.5), "cascade run scales with head")
		check(is_equal_approx(Waterfall.cascade_run(200.0), 8.0), "cascade run is capped")
		check(is_equal_approx(Waterfall.cascade_run(1.0), 0.5), "cascade run has a floor")
		var flow_dir := Vector2(float(fall["flow"][0]), float(fall["flow"][1]))
		check(flow_dir.y < -0.5, "waterfall flows downhill (flow z < 0)")
		# The crown sits on the reservoir lip: the carved bowl floor, at level.
		var crown := Vector2(float(fall["crown"][0]), float(fall["crown"][1]))
		var crown_top: float = sample.call(crown)
		check(crown_top >= 19.0 and crown_top <= 20.5, "crown sits on the reservoir lip")
		# The widths track the submerged channel, not a fixed 1.5 m pole:
		# the crown spans the bowl and the impact spans the river bed.
		check(float(fall["crown_width"]) > 3.0, "crown width spans the reservoir bowl")
		check(float(fall["impact_width"]) > 3.0, "impact width spans the river bed")
		check(float(fall["impact_width"]) > float(fall["crown_width"]), "cascade flares from lip to river")
		# The render aims the sheet's impact at the lower body's centroid so a
		# fall into a pool lands in the pool's centre, not a fixed run past lip.
		check((fall["lower_centroid"] as Array).size() == 2, "fall carries its lower centroid")

		# Determinism: a second derive must produce the identical digest.
		var again: Array = Waterfall.derive(state.water, sample)
		check(again.size() == falls.size(), "second derive has the same count")
		check(_digest(again) == _digest(falls), "second derive is byte-identical")

func _digest(falls: Array) -> String:
	var parts: Array = []
	for fall: Dictionary in falls:
		parts.append("%d/%d/%.3f/%.3f/%.3f,%.3f/%.3f/%.3f" % [
			int(fall["upper_id"]), int(fall["lower_id"]),
			float(fall["top_level"]), float(fall["bottom_level"]),
			float(fall["flow"][0]), float(fall["flow"][1]),
			float(fall["crown_width"]), float(fall["impact_width"])])
	return "|".join(parts)
