# Valley ring occlusion test (analytic).
#
# The valley ring (ValleySurround) must keep the skybox hidden from every
# reachable camera pose in the starter valley. Two contracts:
#   1. Max camera reach: the starter scene caps orbit pitch at 1.15 rad and
#      the building camera distance at 52 m, so the highest camera position
#      is target_y + sin(1.15) * 52 ≈ 63.5 m above the 16 m target below.
#      Ring peaks (112–140 m) must sit above that from the
#      player's vantage region.
#   2. River exits: the ring must stay open (water level 8.75 m) where the
#      river leaves the map, so the world still reads as a valley with a
#      river flowing out, not a sealed box.
#
# We do not rely on a live scene: the surround's profile is a pure function,
# so this validates the design analytically and cheaply.

extends SceneTree

const SCRIPT_NAME := "valley_ring_occlusion_test"
const VALLEY_MAX_PITCH := 1.15
const MAX_DISTANCE := 52.0
const TARGET_Y := 16.0
const RIVER_LEVEL := 8.75
const Ring = preload("res://scripts/m2_valley_surround.gd")
const Gen = preload("res://scripts/m1_patch_generator.gd")


func _init() -> void:
	var code := _run()
	quit(code)


func _run() -> int:
	var f := 0
	var ring: ValleySurround = Ring.new()
	root.add_child(ring)

	# Highest reachable camera position.
	var reach := TARGET_Y + sin(VALLEY_MAX_PITCH) * MAX_DISTANCE
	print("max camera reach: %.2f m (pitch %.2f, distance %.1f, target %.1f)" % [
		reach, VALLEY_MAX_PITCH, MAX_DISTANCE, TARGET_Y,
	])

	# 1. Peaks must clear the max camera reach everywhere around the ring.
	var worst := 0.0
	for i in 720:
		var ang := float(i) / 720.0 * 6.28318530718
		var xz := Vector2(
			80.0 + 80.0 * cos(ang),
			80.0 + 80.0 * sin(ang)
		)
		var peak := ring.peak_height(xz)
		worst = maxf(worst, reach - peak)
	if worst > 0.0:
		f += 1
		print("FAIL: camera clears a ring peak by %.2f m at some bearing" % worst)
	else:
		print("OK: all ring peaks sit above the max camera reach (worst gap %.2f m)" % worst)

	# 2. The wall must rise monotonically from the edge to the peak band so
	#    no intermediate pose sees over it: at every radial sample the height
	#    at the peak band must exceed the height closer to the edge.
	var wall_fail := 0
	for i in 36:
		var ang := float(i) / 36.0 * 6.28318530718
		var xz := Vector2(
			80.0 + 90.0 * cos(ang),
			80.0 + 90.0 * sin(ang)
		)
		var edge_h := ring.ring_height(0.25, xz)
		var wall_h := ring.ring_height(10.0, xz)
		var peak_h := ring.ring_height(28.0, xz)
		if wall_h < edge_h - 0.01 or peak_h < wall_h - 0.01:
			wall_fail += 1
	if wall_fail > 0:
		f += 1
		print("FAIL: wall profile not monotonic at %d/36 bearings" % wall_fail)
	else:
		print("OK: wall profile rises monotonically at all 36 bearings")

	# 3. River exits stay open at the corridor, both directions.
	var corridor_fail := 0
	for z in [0.0, 159.9]:
		var cx: float = Gen.river_center_x(z)
		# At the north/south edges the corridor must drop to water level.
		var h: float = ring.ring_height(60.0, Vector2(cx, z))
		if absf(h - RIVER_LEVEL) > 1.0:
			corridor_fail += 1
			print("FAIL: river exit at z=%.1f not at water level (got %.2f)" % [z, h])
	if corridor_fail == 0:
		print("OK: river corridor open at both exits (water level %.3f)" % RIVER_LEVEL)

	# 4. Off-corridor ring must never collapse to water level.
	var sealed_fail := 0
	for i in 12:
		var ang := float(i) / 12.0 * 6.28318530718
		var xz := Vector2(
			80.0 + 90.0 * cos(ang),
			80.0 + 90.0 * sin(ang)
		)
		if absf(xz.x - Gen.river_center_x(xz.y)) < Gen.river_half_width(xz.y) + 3.0:
			continue # skip corridor samples
		var h: float = ring.ring_height(60.0, xz)
		if h < 40.0:
			sealed_fail += 1
	if sealed_fail > 0:
		f += 1
		print("FAIL: %d/12 off-corridor ring samples below 40 m" % sealed_fail)
	else:
		print("OK: off-corridor ring stays high (>= 40 m) at all samples")

	print("%s: %d failures" % [SCRIPT_NAME, f])
	return 1 if f > 0 else 0
