extends SceneTree

## The tree brush draws its variant from RNG seeded as next_id * 7919 (see
## m1_scene.gd::_paint_plant_sample), and m1_landscape_test asserts that draw
## lands in the expanded compact-variant set (seed >= 3 of 6 authored trees).
## This probe reports, for a range of landscape sizes, which next_id values
## satisfy that authored expectation so the scene's scatter can be sized
## without touching the test.
##
##   godot --headless --path . --script tools/bob_seed_probe.gd -- 200 400

const TREE_VARIANTS := 6

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var low := int(args[0]) if args.size() > 0 else 200
	var high := int(args[1]) if args.size() > 1 else 400
	var good: Array[int] = []
	for next_id in range(low, high + 1):
		var rng := RandomNumberGenerator.new()
		rng.seed = next_id * 7919
		rng.randf_range(0.0, TAU)
		var variant := rng.randi_range(0, TREE_VARIANTS - 1)
		if variant >= 3: good.append(next_id)
	print("SEED_PROBE next_id values whose first tree-brush draw is a compact variant (>=3):")
	print("  " + str(good))
	quit(0)