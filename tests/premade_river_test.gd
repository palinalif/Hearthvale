extends SceneTree
## Headless, deterministic tests for the premade starter river expressed as a
## water region (PremadeRiver) plus its mountain reservoir. Pure logic only --
## no native voxel module and no scene -- so it locks in the "river shares the
## player-water path" invariant: the derived region is a valid stream that
## add_water accepts, follows the generated centerline, and the idempotency
## guard prevents duplicate adds. The river runs from the plain edge (z=0) up
## the generated corridor into the mountains (z=LENGTH) and the reservoir sits
## at its head, feeding the waterfall that WaterfallGeometry derives.
const State = preload("res://scripts/landscape_state.gd")
const PremadeRiver = preload("res://scripts/premade_river.gd")
const Generator = preload("res://scripts/m1_patch_generator.gd")
const WaterfallGeometry = preload("res://scripts/waterfall_geometry.gd")

var failures := 0
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _initialize() -> void:
	_run()
	print("premade_river_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _run() -> void:
	var region: Dictionary = PremadeRiver.region()

	# --- well-formed region --------------------------------------------------
	check(str(region.get("type", "")) == "stream", "premade river is a stream")
	check(absf(float(region["level"]) - 5.0) < 0.0001, "premade river level is 5.0")
	check(float(region["width"]) > 0.0 and float(region["width"]) <= State.WATER_MAX_WIDTH, "width within bounds")
	var points: Array = region["points"]
	check(points.size() >= 2, "has at least two points")
	check(points.size() <= State.WATER_MAX_POINTS, "point count within the water limit")
	check(absf(float(points[0][0]) - Generator.river_center_x(0.0)) < 0.125, "starts on the generated centerline")
	check(absf(float(points[0][1]) - 0.0) < 0.0001, "starts at z=0")
	check(absf(float(points[-1][1]) - PremadeRiver.LENGTH) < 0.125, "ends at z=LENGTH in the mountains")
	check(absf(float(points[-1][0]) - Generator.river_center_x(PremadeRiver.LENGTH)) < 0.125, "ends on the generated centerline")
	var flow: Array = region["flow"]
	check(flow.size() == 2 and absf(Vector2(flow[0], flow[1]).length() - 1.0) < 0.001, "flow is a unit vector")

	# --- add_water accepts it, document stays valid --------------------------
	var state = State.new()
	var id: int = state.add_water("stream", region["level"], region["points"], region["width"], region["flow"])
	check(id > 0, "add_water accepts the premade river")
	check(state.water.size() == 1, "exactly one water region")
	check(state.validate(state.document()), "document validates with the premade river")

	# --- idempotency: the stored region matches, and a re-derive is recognised
	var stored: Dictionary = state.water[0]
	check(PremadeRiver.matches(stored, region), "stored region matches the derived river")
	var again: Dictionary = PremadeRiver.region()
	check(PremadeRiver.matches(stored, again), "re-derivation is deterministic and recognised")

	# --- idempotency guard: a distinct player stream is NOT the premade river
	var other: Dictionary = {"type": "stream", "level": 8.0, "width": 1.0, "flow": [1.0, 0.0],
		"points": [[10.0, 10.0], [12.0, 10.0], [14.0, 10.0]]}
	check(not PremadeRiver.matches(other, region), "a player stream is not mistaken for the premade river")

	# --- the mountain reservoir at the river's head ---------------------------
	var reservoir: Dictionary = PremadeRiver.reservoir_region()
	check(str(reservoir.get("type", "")) == "lake", "reservoir is a lake")
	check(absf(float(reservoir["level"]) - 10.0) < 0.0001, "reservoir level is 10.0")
	var rpoints: Array = reservoir["points"]
	check(rpoints.size() >= 3, "reservoir has a closed polygon")
	for point: Array in rpoints:
		check(absf(fmod(float(point[0]), 0.125)) < 0.0001 and absf(fmod(float(point[1]), 0.125)) < 0.0001,
			"reservoir points are grid-snapped")
	# The reservoir is at the head of the river, not at the plain edge.
	check(float(rpoints[0][1]) > 90.0, "reservoir sits in the mountains (z > 90)")
	check(PremadeRiver.matches_reservoir(reservoir, PremadeRiver.reservoir_region()), "reservoir re-derivation is recognised")
	# The reservoir must fit the document's water budget alongside the river.
	var reservoir_id: int = state.add_water("lake", reservoir["level"], reservoir["points"])
	check(reservoir_id > 0, "add_water accepts the reservoir alongside the river")
	check(state.validate(state.document()), "document validates with the reservoir")

	# --- the waterfall derives from the reservoir + river + generated cliff ---
	var sample := func(p: Vector2) -> float: return Generator.terrain_height(p.x, p.y)
	var falls: Array = WaterfallGeometry.derive(state.water, sample)
	check(falls.size() == 1, "exactly one waterfall derives (reservoir to river)")
	if falls.size() == 1:
		var fall: Dictionary = falls[0]
		check(int(fall["upper_id"]) == reservoir_id, "waterfall upper body is the reservoir")
		check(int(fall["lower_id"]) == id, "waterfall lower body is the river")
		check(absf(float(fall["head"]) - 5.0) < 0.0001, "waterfall head is 5 m")
		var flow_dir := Vector2(float(fall["flow"][0]), float(fall["flow"][1]))
		check(flow_dir.y < -0.5, "waterfall flows downhill toward the plain (flow z < 0)")
		# The crown sits on the reservoir's edge (the mountain rim), not in the river.
		var crown := Vector2(float(fall["crown"][0]), float(fall["crown"][1]))
		check(crown.distance_to(PremadeRiver.RESERVOIR_CENTER) <= PremadeRiver.RESERVOIR_RADIUS + 1.5,
			"waterfall crown is at the reservoir edge")
