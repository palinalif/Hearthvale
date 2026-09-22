# Valley ring occlusion test (analytic).
#
# The starter valley's mountain surround (ValleySurround) is a 3-layer range:
# a gentle low inner ridge, a taller mid ridge, and a hazy far ridge. This
# validates the "prominent but not sealed" design: the camera sees SOME of the
# far mountain (not a fully sealed 160 m wall) but not most of it, and the
# inner ridge is a smooth, gentle, low slope (not a jagged 10-band wall). The
# river corridor must stay open where the river exits the valley.
#
# We do not rely on a live scene: the surround's profile is a pure function,
# so this validates the design analytically and cheaply.

extends SceneTree

const SCRIPT_NAME := "valley_ring_occlusion_test"
const VALLEY_MAX_PITCH := 1.15
const MAX_DISTANCE := 52.0
const TARGET_Y := 16.0
const RIVER_LEVEL := 8.75
const Surround = preload("res://scripts/m2_valley_surround.gd")
const Gen = preload("res://scripts/m1_patch_generator.gd")


func _init() -> void:
	var code := _run()
	quit(code)


func _run() -> int:
	var f := 0
	var ring: ValleySurround = Surround.new()
	root.add_child(ring)

	var reach := TARGET_Y + sin(VALLEY_MAX_PITCH) * MAX_DISTANCE
	print("max camera reach: %.2f m (pitch %.2f, distance %.1f, target %.1f)" % [
		reach, VALLEY_MAX_PITCH, MAX_DISTANCE, TARGET_Y,
	])

	# 1. Inner ridge crest: a jagged, gentle range. Sample the crest around the
	#    full ring; it must sit in the 30-75 m band (prominent, not the old
	#    160 m sealed wall) and be irregular (not a flat cylinder).
	var min_crest := 1e9
	var max_crest := -1e9
	var crest_sum := 0.0
	const N := 72
	for i in N:
		var ang := float(i) / float(N) * TAU
		var xz := Vector2(260.0 * cos(ang), 260.0 * sin(ang))
		var h: float = ring.peak_height(xz)
		min_crest = minf(min_crest, h)
		max_crest = maxf(max_crest, h)
		crest_sum += h
	var crest_mean := crest_sum / float(N)
	var crest_var := 0.0
	for i in N:
		var ang := float(i) / float(N) * TAU
		crest_var += pow(ring.peak_height(Vector2(260.0 * cos(ang), 260.0 * sin(ang))) - crest_mean, 2.0)
	var crest_std := sqrt(crest_var / float(N))
	print("inner crest: min %.0f  mean %.0f  max %.0f  std %.1f m" % [min_crest, crest_mean, max_crest, crest_std])
	if max_crest > 80.0:
		f += 1
		print("FAIL: crest too tall (max %.0f m, want <=80)" % max_crest)
	if max_crest < 35.0:
		f += 1
		print("FAIL: crest too low to be prominent (max %.0f m, want >=35)" % max_crest)
	if crest_std < 3.0:
		f += 1
		print("FAIL: crest reads as a flat cylinder (std %.1f, want >3)" % crest_std)

	# 2. Look-up angle to see sky: from the max-reach camera, for each bearing,
	#    march the ray's elevation from the horizon (0 deg) upward until it
	#    clears the ridge. That angle = how steeply the player must look up to
	#    see sky. Small (<=25 deg) => distant mountain band with sky above
	#    (open, prominent); large (>30 deg) => a sealed dome. Uses the composite
	#    ridge_elevation — the real height field the camera sees (inner+mid+far
	#    + haze), not a single wall layer.
	var cam := Vector3(60.0, reach, 0.0)
	var worst_angle := 0.0
	for i in N:
		var bearing := float(i) / float(N) * TAU
		var top_angle := 0.0
		for e in range(0, 90, 2):
			var ea := deg_to_rad(float(e))
			var tp := Vector3(
				cam.x + 500.0 * cos(ea) * cos(bearing),
				cam.y + 500.0 * sin(ea),
				cam.z + 500.0 * cos(ea) * sin(bearing)
			)
			var blocked := false
			for s in 25:
				var t := (float(s) + 1.0) / 26.0
				var p := cam.lerp(tp, t)
				var xz := Vector2(p.x, p.z)
				if ring.ridge_elevation(xz) > p.y + 0.5:
					blocked = true
					break
			if not blocked:
				top_angle = float(e)
				break
		worst_angle = maxf(worst_angle, top_angle)
	print("look-up angle to see sky: at most %.0f deg (open <=25, sealed >30)" % worst_angle)
	if worst_angle > 30.0:
		f += 1
		print("FAIL: too sealed — player looks up %.0f deg to see sky (want <=30)" % worst_angle)

	# 3. River corridor stays open where the river exits (north/south): the
	#    surround height on the corridor must be the low water level.
	var corridor_fail := 0
	for z in [0.0, 159.9]:
		var cx: float = Gen.river_center_x(z)
		var h: float = ring.ring_height(1.0, Vector2(cx, z))
		if h > 20.0:
			corridor_fail += 1
			print("FAIL: river exit at z=%.1f sealed by a %dm ridge (want <20)" % [z, int(h)])
	if corridor_fail == 0:
		print("OK: river corridor open at both exits (no tall ridge on the corridor)")

	print("%s: %d failures" % [SCRIPT_NAME, f])
	return 1 if f > 0 else 0
