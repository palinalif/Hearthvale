extends SceneTree
## Fresh native terrain field; saved voxel buffers remain authoritative.
const Generator = preload("res://scripts/m1_patch_generator.gd")
const PremadeRiver = preload("res://scripts/premade_river.gd")
const STEP := 0.125
var failures := 0
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _initialize() -> void:
	_test_profile()
	_test_lip_and_pool()
	_test_inlet()
	print("waterfall_cliff_shape_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _test_profile() -> void:
	for side in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		var previous := Generator._cliff_profile(Generator.SOURCE_LIP_Z, side)
		check(is_equal_approx(previous, 22.25), "spill edge at side %f" % side)
		for i in range(1, 37):
			var z := Generator.SOURCE_LIP_Z - float(i) * STEP
			var h := Generator._cliff_profile(z, side)
			check(h <= previous + 1e-4, "face descends at z=%f side=%f" % [z, side])
			previous = h
		check(is_equal_approx(Generator._cliff_profile(136.5, side), 4.75), "talus start")
		check(is_equal_approx(Generator._cliff_profile(135.5, side), 4.5), "talus toe")
	check(Generator._cliff_profile(140.0, 0.0) - Generator._cliff_profile(139.0, 0.0) > Generator._cliff_profile(137.0, 0.0) - Generator._cliff_profile(136.5, 0.0), "face eases into talus")
	# The flanks must drop straight from the lip: no flat rock cap under the
	# lip, no projecting bench, and the whole mass stays contained by the
	# banks (never above the 22.25 lip, never below the 4.75 talus start).
	for side in [4.0, 8.0, -4.0, -8.0]:
		check(Generator._cliff_profile(Generator.SOURCE_LIP_Z - STEP, side) < 22.25, "no rock cap under lip, side=%f" % side)
		check(Generator._cliff_profile(139.5, side) < 22.25 - 1.5, "cliff drops within 0.5 m, side=%f" % side)
		var z := Generator.SOURCE_LIP_Z - STEP
		while z > 136.5:
			var h := Generator._cliff_profile(z, side)
			check(h < 22.25 + 0.03125 and h > 4.75 - 0.5, "cliff contained z=%f side=%f" % [z, side])
			check(Generator._cliff_profile(z + STEP, side) - h >= -0.0001, "cliff never rises toward the toe z=%f side=%f" % [z, side])
			z -= STEP
	for x in [77.5, 82.0, 86.5]:
		check(is_equal_approx(Generator._cliff_face_height(x, Generator.SOURCE_LIP_Z), 22.25), "full-width structural lip")
		check(is_equal_approx(Generator._cliff_face_height(x, 135.5), 4.5), "full-width toe")
		check(Generator._cliff_face_weight(x, 139.5) == 1.0, "cascade supported by rock")
	check(Generator._cliff_face_height(90.0, 138.0) < Generator._cliff_face_height(74.0, 138.0), "staggered face")

func _test_lip_and_pool() -> void:
	check(is_equal_approx(Generator.terrain_height(82.0, 140.0), 22.25), "reservoir lip")
	check(Generator.terrain_height(82.0, 139.5) < 21.0, "no exposed shelf below spill")
	check(is_equal_approx(Generator.terrain_height(82.0, 136.0), Generator.POOL_FLOOR), "plunge floor")
	var z := 130.0
	var bed := 4.375 + snappedf(sin(z * 0.145) * 0.125, STEP)
	check(is_equal_approx(Generator.terrain_height(Generator.river_center_x(z), z), bed), "downstream river bed")
	for raw_point in PremadeRiver.reservoir_region()["points"]:
		var p := Vector2(float(raw_point[0]), float(raw_point[1]))
		for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var inside := Generator.SOURCE_CENTER.lerp(p, fraction)
			check(Generator.terrain_height(inside.x, inside.y) < Generator.SOURCE_LEVEL, "submerged polygon %s" % inside)

func _test_inlet() -> void:
	check(Generator._waterfall_inlet_weight(82.0, 126.0) == 0.0, "downstream untouched")
	check(Generator._waterfall_inlet_weight(82.0, 143.0) == 1.0, "inlet feeds lake")
	for z in [141.0, 145.0, 150.0, 156.0, 160.0]:
		for x in [64.0, 65.0, 100.0, 102.0]:
			check(Generator._waterfall_inlet_weight(x, z) == 0.0, "native hills outside inlet x=%f z=%f" % [x, z])
		# Sample actual terrain at voxel pitch across the cut and its banks.
		# A weight-only test misses a vertical wall at the lake boundary.
		var previous := Generator.terrain_height(72.0, z)
		for i in range(1, 193):
			var x := 72.0 + float(i) * STEP
			var h := Generator.terrain_height(x, z)
			check(is_finite(h) and absf(h - previous) < 0.6, "lateral terrain step x=%f z=%f" % [x, z])
			previous = h
	# Transects from the submerged lake across the north/east/west bank.
	for angle in [0.0, PI * 0.25, PI * 0.5, PI * 0.75, PI]:
		var direction := Vector2(cos(angle), sin(angle))
		var previous := Generator.terrain_height(Generator.SOURCE_CENTER.x + direction.x * 3.0, Generator.SOURCE_CENTER.y + direction.y * 3.0)
		for i in range(1, 65):
			var distance := 3.0 + float(i) * STEP
			var p := Generator.SOURCE_CENTER + direction * distance
			var h := Generator.terrain_height(p.x, p.y)
			check(is_finite(h) and absf(h - previous) < 0.6, "lake bank terrain step %s" % p)
			previous = h
	check(Generator.terrain_height(82.0, 152.0) > Generator.SOURCE_LEVEL, "north bank rises above pond")
	check(Generator.terrain_height(64.0, 159.0) > Generator.terrain_height(64.0, 125.0) + 8.0, "west ridge backs cliff")
	var cap := -INF
	for z in range(140, 161):
		for x in range(56, 109, 2):
			cap = maxf(cap, Generator.terrain_height(float(x), float(z)))
	check(cap < 32.0, "rear terrain below 32 m (%f)" % cap)
