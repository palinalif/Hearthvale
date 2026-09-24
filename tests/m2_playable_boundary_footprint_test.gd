extends SceneTree

## Locks the footprint containment checks for circular and polygon/rectangle
## edits against the playable RADIUS=52 disk: inside/on-edge (EPSILON) vs
## crossing, rotated rectangles, finite/nonnegative validation, plus the
## pre-existing boundary invariants.

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
	_verify_circle_inside()
	_verify_circle_on_edge_and_crossing()
	_verify_circle_validation()
	_verify_rectangle_inside()
	_verify_rectangle_on_edge_and_crossing()
	_verify_rotated_rectangle()
	_verify_polygon_validation()
	_verify_prior_invariants()
	print("m2_playable_boundary_footprint_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _rectangle_corners(center: Vector3, half_x: float, half_z: float, angle_deg: float) -> Array[Vector3]:
	var corners: Array[Vector3] = []
	var c := cos(deg_to_rad(angle_deg))
	var s := sin(deg_to_rad(angle_deg))
	for dx in [half_x, -half_x]:
		for dz in [half_z, -half_z]:
			corners.append(center + Vector3(dx * c - dz * s, 0.0, dx * s + dz * c))
	return corners


func _verify_circle_inside() -> void:
	check(Boundary.is_circle_footprint_inside(Boundary.CENTER, 10.0), "10 m circle at the valley centre fits")
	check(Boundary.is_circle_footprint_inside(Boundary.CENTER + Vector3(0.0, 0.0, 20.0), 10.0), "10 m circle 20 m from centre fits")
	var near_rim := Boundary.CENTER + Vector3(0.0, 0.0, 40.0)
	check(Boundary.is_circle_footprint_inside(near_rim, 5.0), "5 m circle 40 m from centre fits with 7 m to spare")
	var elevated := Boundary.CENTER + Vector3(0.0, 40.0, 20.0)
	check(Boundary.is_circle_footprint_inside(elevated, 10.0), "finite y is ignored for containment")


func _verify_circle_on_edge_and_crossing() -> void:
	var near_rim := Boundary.CENTER + Vector3(0.0, 0.0, 40.0)
	check(Boundary.is_circle_footprint_inside(near_rim, 12.0), "circle whose rim touches the boundary exactly counts as inside")
	check(not Boundary.is_circle_footprint_inside(near_rim, 12.5), "circle crossing the boundary is not inside")
	check(Boundary.is_circle_footprint_inside(Boundary.CENTER, Boundary.RADIUS), "circle exactly the playable size at the centre is inside")
	check(not Boundary.is_circle_footprint_inside(Boundary.CENTER, Boundary.RADIUS + 0.5), "circle bigger than the playable disk is not inside")


func _verify_circle_validation() -> void:
	check(Boundary.is_circle_footprint_inside(Boundary.CENTER, 0.0), "zero-radius footprint at the centre is inside")
	check(not Boundary.is_circle_footprint_inside(Boundary.CENTER + Vector3(0.0, 0.0, 60.0), 0.0), "zero-radius footprint past the rim is not inside")
	check(not Boundary.is_circle_footprint_inside(Boundary.CENTER, -1.0), "negative radius is rejected")
	check(not Boundary.is_circle_footprint_inside(Boundary.CENTER, -0.0005), "negative radius below epsilon is rejected")
	check(not Boundary.is_circle_footprint_inside(Vector3(NAN, 0.0, 80.0), 10.0), "nan centre is rejected")
	check(not Boundary.is_circle_footprint_inside(Vector3(80.0, INF, 80.0), 10.0), "infinite centre y is rejected")
	check(not Boundary.is_circle_footprint_inside(Boundary.CENTER, INF), "infinite radius is rejected")
	check(not Boundary.is_circle_footprint_inside(Boundary.CENTER, NAN), "nan radius is rejected")


func _verify_rectangle_inside() -> void:
	var rect := _rectangle_corners(Boundary.CENTER, 20.0, 10.0, 0.0)
	check(Boundary.is_polygon_footprint_inside(rect), "40x20 rectangle at the centre fits")
	var shifted := _rectangle_corners(Boundary.CENTER + Vector3(15.0, 0.0, -10.0), 20.0, 10.0, 0.0)
	check(Boundary.is_polygon_footprint_inside(shifted), "40x20 rectangle 18 m from centre fits")
	var tri: Array[Vector3] = [
		Boundary.CENTER + Vector3(10.0, 0.0, 0.0),
		Boundary.CENTER + Vector3(-10.0, 0.0, 10.0),
		Boundary.CENTER + Vector3(-10.0, 0.0, -10.0),
	]
	check(Boundary.is_polygon_footprint_inside(tri), "small triangle at the centre fits")


func _verify_rectangle_on_edge_and_crossing() -> void:
	# 96x40 rectangle centred on the valley: corners at (48, 20) sit exactly
	# 52 m out, i.e. on the rim.
	var on_edge := _rectangle_corners(Boundary.CENTER, 48.0, 20.0, 0.0)
	check(Boundary.is_polygon_footprint_inside(on_edge), "rectangle with corners exactly on the rim counts as inside")
	# Shifted 2 m toward the rim: the near corners cross the boundary.
	var crossing := _rectangle_corners(Boundary.CENTER + Vector3(0.0, 0.0, 2.0), 48.0, 20.0, 0.0)
	check(not Boundary.is_polygon_footprint_inside(crossing), "same rectangle shifted 2 m outward is not inside")


func _verify_rotated_rectangle() -> void:
	# 20x20 square 40 m from the centre: axis-aligned its far corners reach
	# ~50.99 m (inside); rotated 45 deg the same square reaches ~54.14 m
	# (crossing), so rotation is genuinely accounted for.
	var straight := _rectangle_corners(Boundary.CENTER + Vector3(0.0, 0.0, 40.0), 10.0, 10.0, 0.0)
	check(Boundary.is_polygon_footprint_inside(straight), "axis-aligned 20x20 square 40 m from centre fits")
	var rotated := _rectangle_corners(Boundary.CENTER + Vector3(0.0, 0.0, 40.0), 10.0, 10.0, 45.0)
	check(not Boundary.is_polygon_footprint_inside(rotated), "same square rotated 45 deg crosses the rim")
	var safe_rotated := _rectangle_corners(Boundary.CENTER, 20.0, 10.0, 37.0)
	check(Boundary.is_polygon_footprint_inside(safe_rotated), "rotated 40x20 rectangle at the centre still fits")


func _verify_polygon_validation() -> void:
	var empty: Array[Vector3] = []
	check(not Boundary.is_polygon_footprint_inside(empty), "no corners is rejected")
	var two: Array[Vector3] = [Boundary.CENTER, Boundary.CENTER + Vector3(10.0, 0.0, 0.0)]
	check(not Boundary.is_polygon_footprint_inside(two), "two corners is rejected")
	var nan_corner: Array[Vector3] = [
		Boundary.CENTER + Vector3(10.0, 0.0, 0.0),
		Vector3(NAN, 0.0, 0.0),
		Boundary.CENTER + Vector3(0.0, 0.0, 10.0),
	]
	check(not Boundary.is_polygon_footprint_inside(nan_corner), "polygon with a nan corner is rejected")
	var inf_corner: Array[Vector3] = [
		Boundary.CENTER + Vector3(10.0, 0.0, 0.0),
		Vector3(80.0, INF, 80.0),
		Boundary.CENTER + Vector3(0.0, 0.0, 10.0),
	]
	check(not Boundary.is_polygon_footprint_inside(inf_corner), "polygon with an infinite y corner is rejected")
	var far_corner := _rectangle_corners(Boundary.CENTER + Vector3(0.0, 0.0, 4.0), 48.0, 20.0, 0.0)
	check(not Boundary.is_polygon_footprint_inside(far_corner), "one corner past the rim is enough to fail")


func _verify_prior_invariants() -> void:
	check(Boundary.RADIUS == 52.0, "playable radius is still exactly 52 m")
	check(Boundary.is_inside(Boundary.CENTER), "valley centre is playable")
	check(Boundary.is_inside(Vector3(32.0, 0.0, 60.0)), "village starter home stays inside")
	check(Boundary.clamp_position(Vector3(32.0, 0.0, 60.0)) == Vector3(32.0, 0.0, 60.0), "village starter home is never clamped")
	var rim := Boundary.CENTER + Vector3(1.0, 0.0, 0.0) * Boundary.RADIUS
	check(Boundary.is_inside(rim), "rim point counts as inside")
	check(not Boundary.is_inside(Vector3(82.0, 0.0, 135.5)), "waterfall cliff foot is outside")
	var recovered := Boundary.clamp_position(Vector3(NAN, 0.0, NAN))
	check(recovered == Boundary.CENTER, "non-finite point recovers at the valley centre")
	check(not Boundary.is_inside(Boundary.CENTER + Vector3(0.0, 0.0, Boundary.RADIUS + 0.5)), "half a metre past the rim is outside")
