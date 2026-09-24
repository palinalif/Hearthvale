extends SceneTree

## Locks the playable inner-valley boundary for the controller terrain
## cursor: deterministic circle at (80, 80), clear of the northern
## waterfall cliff (foot z135.5, x82) and the mountain range (~58 m out),
## with the village starter home (32, 60) kept inside, edge sliding,
## y retention and robust invalid-input handling.

const Boundary = preload("res://scripts/m2_playable_boundary.gd")
const EPSILON := 0.01

var checks := 0
var failures := 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)


func _initialize() -> void:
	_verify_center_and_interior()
	_verify_village_home_inside()
	_verify_waterfall_approach()
	_verify_edges_and_corners()
	_verify_y_retained()
	_verify_sliding_along_edge()
	_verify_invalid_input()
	print("m2_playable_boundary_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _verify_center_and_interior() -> void:
	check(Boundary.is_inside(Boundary.CENTER), "valley centre is playable")
	check(Boundary.is_inside(Vector3(80.0, 0.0, 80.0)), "centre at (80, z0, 80) is playable")
	var interior := Vector3(84.0, 3.2, 66.0)
	check(Boundary.is_inside(interior), "meadow point 18 m from centre is playable")
	check(Boundary.clamp_position(interior) == interior, "interior point is untouched by clamp")
	check(Boundary.RADIUS >= 50.0 and Boundary.RADIUS <= 52.0, "radius sits in the approved 50-52 m band")
	var river_edge := Vector3(80.0, 0.0, Boundary.CENTER.z + Boundary.RADIUS)
	check(is_equal_approx(river_edge.z, 132.0), "boundary reaches exactly z132 on the river line")


func _verify_village_home_inside() -> void:
	# Starter home footprint centre: (32, 60) in xz.
	var home := Vector3(32.0, 0.0, 60.0)
	check(Boundary.is_inside(home), "village house position stays inside the playable valley")
	check(Boundary.clamp_position(home) == home, "village house position is never clamped")


func _verify_waterfall_approach() -> void:
	# Cliff foot z135.5 with the waterfall at x82.
	var cliff_foot := Vector3(82.0, 0.0, 135.5)
	check(not Boundary.is_inside(cliff_foot), "cliff foot is outside the playable valley")
	var clamped := Boundary.clamp_position(cliff_foot)
	var radial := Vector2(clamped.x - Boundary.CENTER.x, clamped.z - Boundary.CENTER.z).length()
	check(radial <= Boundary.RADIUS + EPSILON, "cliff foot clamps onto the boundary circle")
	check(clamped.z < 135.5, "clamped point stays on the valley side of the cliff foot")
	check(135.5 - clamped.z >= 2.0, "clamped point keeps a couple of metres off the cliff")
	var riverline := Boundary.clamp_position(Vector3(80.0, 0.0, 140.0))
	check(riverline.z <= 132.0 + EPSILON, "river-line approach stops at z132")
	check(not Boundary.is_inside(Vector3(80.0, 0.0, 133.5)), "1 m short of the cliff is still excluded")


func _verify_edges_and_corners() -> void:
	for angle in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]:
		var radians := deg_to_rad(angle)
		var rim := Boundary.CENTER + Vector3(cos(radians), 0.0, sin(radians)) * Boundary.RADIUS
		check(Boundary.is_inside(rim), "rim point at %d deg counts as inside" % angle)
		check(
			(Boundary.clamp_position(rim) - rim).length() <= EPSILON,
			"rim point at %d deg is not dragged" % angle
		)
	for angle in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]:
		var radians := deg_to_rad(angle)
		var outside := Boundary.CENTER + Vector3(cos(radians), 0.0, sin(radians)) * (Boundary.RADIUS + 10.0)
		var clamped := Boundary.clamp_position(outside)
		var radial := Vector2(clamped.x - Boundary.CENTER.x, clamped.z - Boundary.CENTER.z).length()
		check(is_equal_approx(radial, Boundary.RADIUS), "point 10 m out at %d deg projects onto the circle" % angle)
		check(not Boundary.is_inside(outside), "point 10 m out at %d deg is outside" % angle)
	check(not Boundary.is_inside(Boundary.CENTER + Vector3(0.0, 0.0, Boundary.RADIUS + 0.5)), "half a metre past the rim is outside")


func _verify_y_retained() -> void:
	for y in [0.0, 7.3, -4.0, 60.0]:
		var point := Vector3(160.0, y, 80.0)
		var clamped := Boundary.clamp_position(point)
		check(is_equal_approx(clamped.y, y), "clamped point retains y=%s" % y)
		check(is_equal_approx(clamped.x, Boundary.CENTER.x + Boundary.RADIUS), "east exit lands on the east rim")


func _verify_sliding_along_edge() -> void:
	# Walk the cursor from deep inside toward the northern edge and keep
	# pushing: it must slide along the circle, staying on the boundary and
	# moving continuously (no teleports between successive positions).
	var previous: Vector3 = Vector3(Boundary.CENTER.x, 0.0, Boundary.CENTER.z - 40.0)
	var smooth := true
	var on_edge := 0
	for i in range(1, 61):
		var candidate := Vector3(Boundary.CENTER.x + float(i) * 2.0, 0.0, Boundary.CENTER.z - 40.0 + float(i) * 3.0)
		var clamped := Boundary.clamp_position(candidate)
		var radial := Vector2(clamped.x - Boundary.CENTER.x, clamped.z - Boundary.CENTER.z).length()
		check(radial <= Boundary.RADIUS + EPSILON, "slide step %d stays inside" % i)
		if radial > Boundary.RADIUS - 1.0:
			on_edge += 1
		if (clamped - previous).length_squared() > 36.0:
			smooth = false
		previous = clamped
	check(on_edge >= 25, "slide spends sustained time pressed against the boundary")
	check(smooth, "slide along the curved edge is continuous, no teleports")


func _verify_invalid_input() -> void:
	check(not Boundary.is_inside(Vector3(INF, 0.0, 0.0)), "infinite xz is not inside")
	check(not Boundary.is_inside(Vector3(NAN, 0.0, 0.0)), "nan xz is not inside")
	check(not Boundary.is_inside(Vector3(100.0, INF, 100.0)), "infinite y is rejected too")
	var recovered := Boundary.clamp_position(Vector3(NAN, 5.0, NAN))
	check(recovered.is_finite(), "non-finite input clamps to a finite result")
	check(Boundary.is_inside(recovered), "recovered position is inside the valley")
	check(is_equal_approx(recovered.x, Boundary.CENTER.x) and is_equal_approx(recovered.z, Boundary.CENTER.z), "non-finite input recovers at the valley centre")
	var restored := Boundary.clamp_position(Vector3(300.0, 12.0, -80.0))
	check(Boundary.is_inside(restored) and is_equal_approx(restored.y, 12.0), "far restored point clamps inside and keeps y")
