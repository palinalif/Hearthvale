extends SceneTree
## Headless, deterministic tests for the premade starter river expressed as a
## water region (PremadeRiver). Pure logic only -- no native voxel module and no
## scene -- so it locks in the "river shares the player-water path" invariant:
## the derived region is a valid stream that add_water accepts, follows the
## generated centerline, and the idempotency guard prevents duplicate adds.
const State = preload("res://scripts/landscape_state.gd")
const PremadeRiver = preload("res://scripts/premade_river.gd")
const Generator = preload("res://scripts/m1_patch_generator.gd")
const Bounds = preload("res://scripts/m2_world_bounds.gd")

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
	check(absf(float(points[0][0]) - Generator.river_center_x(0.0)) < 0.125, "starts on the generated centerline")
	check(absf(float(points[0][1]) - 0.0) < 0.0001, "starts at z=0")
	check(absf(float(points[-1][1]) - Bounds.SIZE) < 0.125, "ends at the world edge z=SIZE")
	check(absf(float(points[-1][0]) - Generator.river_center_x(Bounds.SIZE)) < 0.125, "ends on the generated centerline")
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
