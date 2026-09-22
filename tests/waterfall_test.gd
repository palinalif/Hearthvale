extends SceneTree
## Locks the pure waterfall derivation: a higher authored body's edge that drops
## near-vertically into a lower authored body becomes a waterfall; anything that
## is not a clean head-drop (flat ground, equal levels, no lower body) does not.
## Headless, deterministic, no native module.

const Waterfall = preload("res://scripts/waterfall_geometry.gd")

var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _cliff_sampler() -> Callable:
	# Plateau top 4.0 for x <= 10, pool floor 1.0 for x > 10 (a step cliff at x=10).
	return func(p: Vector2) -> float:
		return 4.0 if p.x <= 10.0 else 1.0

func _flat_sampler(height: float) -> Callable:
	return func(_p: Vector2) -> float: return height

func _upper() -> Dictionary:
	return {"id": 1, "type": "lake", "level": 4.0, "points": [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]]}

func _lower(level: float = 1.0) -> Dictionary:
	return {"id": 2, "type": "lake", "level": level, "points": [[10.0, 0.0], [20.0, 0.0], [20.0, 10.0], [10.0, 10.0]]}

func _digest(falls: Array) -> String:
	var text := ""
	for f in falls:
		text += "%d-%d@%.2f,%.2f w%.2f h%.2f;" % [f["upper_id"], f["lower_id"], f["crown"][0], f["crown"][1], f["width"], f["head"]]
	return text

func _initialize() -> void:
	var cliff := _cliff_sampler()

	# stepped cliff: upper lake drops 3 m into a lower pool -> one waterfall at the edge
	var falls := Waterfall.derive([_upper(), _lower()], cliff)
	check(falls.size() == 1, "stepped cliff yields one waterfall (got %d)" % falls.size())
	if falls.size() == 1:
		var f: Dictionary = falls[0]
		check(int(f["upper_id"]) == 1 and int(f["lower_id"]) == 2, "falls link the upper and lower body")
		check(is_equal_approx(float(f["head"]), 3.0), "head is the level difference (3 m)")
		check(is_equal_approx(float(f["crown"][0]), 10.0), "crown sits on the cliff edge x=10 (got %s)" % str(f["crown"][0]))
		check(float(f["crown"][1]) >= 0.0 and float(f["crown"][1]) <= 10.0, "crown z lies on the bank")
		check(float(f["flow"][0]) > 0.0, "cascade flows toward the lower body")
		check(str(f["key"]) == "1-2", "stable pair key")

	# no lower body -> nothing to fall into
	check(Waterfall.derive([_upper()], cliff).is_empty(), "no lower body -> no waterfall")

	# flat ground (no drop) -> not a waterfall
	check(Waterfall.derive([_upper(), _lower()], _flat_sampler(4.0)).is_empty(), "flat ground is not a waterfall")

	check(Waterfall.derive([_upper(), _lower()], _flat_sampler(1.0)).is_empty(), "water suspended over low terrain is not a supported waterfall")

	# equal levels (head < 0.5) -> not a waterfall
	check(Waterfall.derive([_upper(), _lower(4.0)], cliff).is_empty(), "equal levels are not a waterfall")

	# stream upper dropping into a pool -> one waterfall at the stream's end
	var stream := {"id": 3, "type": "stream", "level": 4.0, "width": 1.5, "flow": [1.0, 0.0], "points": [[0.0, 5.0], [10.0, 5.0]]}
	var pool := {"id": 4, "type": "lake", "level": 1.0, "points": [[10.0, 0.0], [20.0, 0.0], [20.0, 10.0], [10.0, 10.0]]}
	var sfalls := Waterfall.derive([stream, pool], cliff)
	check(sfalls.size() == 1, "stream dropping into a pool yields one waterfall (got %d)" % sfalls.size())
	if sfalls.size() == 1:
		var sf: Dictionary = sfalls[0]
		check(is_equal_approx(float(sf["crown"][0]), 10.0), "stream crown at its cliff end x=10 (got %s)" % str(sf["crown"][0]))

	# rect scoping: only crowns inside the dirty rect are evaluated
	var near_cliff := Rect2(9.0, 0.0, 2.0, 10.0)  # contains the x=10 crown
	check(Waterfall.derive([_upper(), _lower()], cliff, near_cliff).size() == 1, "rect containing the crown yields the fall")
	var away_cliff := Rect2(0.0, 0.0, 5.0, 10.0)  # excludes the x=10 crown
	check(Waterfall.derive([_upper(), _lower()], cliff, away_cliff).is_empty(), "rect excluding the crown yields nothing")

	# a local edit grows by SAMPLE_MARGIN: a nearby edit (x=8) still catches the
	# crown; a far edit (x=2) does not — derivation never scans the whole map.
	var nearby := Rect2(8.0, 5.0, 0.0, 0.0).grow(Waterfall.SAMPLE_MARGIN)
	check(nearby.has_point(Vector2(10.0, 5.0)), "a nearby edit's grown rect reaches the crown")
	check(Waterfall.derive([_upper(), _lower()], cliff, nearby).size() == 1, "nearby edit re-derives the crown")
	var far := Rect2(2.0, 5.0, 0.0, 0.0).grow(Waterfall.SAMPLE_MARGIN)
	check(not far.has_point(Vector2(10.0, 5.0)), "a far edit's grown rect does not reach the crown")
	check(Waterfall.derive([_upper(), _lower()], cliff, far).is_empty(), "far edit leaves the crown untouched")

	# determinism
	check(_digest(Waterfall.derive([_upper(), _lower()], cliff)) == _digest(Waterfall.derive([_upper(), _lower()], cliff)), "derivation is deterministic")

	print("waterfall_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
