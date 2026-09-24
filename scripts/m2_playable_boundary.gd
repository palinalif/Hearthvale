extends RefCounted
class_name M2PlayableBoundary

## Rounded playable inner valley for the controller terrain cursor.
##
## The M2 starter valley is a circular basin centred at (80, 80). The mountain
## range begins at a radial distance of ~58 m, and the northern waterfall
## stands at x82 with its cliff foot at z135.5 (~55.5 m from centre). The
## playable radius keeps the cursor at least a few metres from both:
##
##   - at the river line (x=80) the boundary reaches z=132, i.e. 3.5 m shy of
##     the cliff foot at z135.5;
##   - the village starter home at (32, 60) sits exactly 52 m from centre, so
##     it remains inside (on the rim, never clamped).
##
## The geometry is a pure function of (x, z): deterministic, no terrain
## sampling per frame. Movement "slides" along the curved edge because an
## outside candidate is projected back onto the boundary circle. Finite Y is
## retained so restored/saved positions keep their altitude.

## Valley centre (xz plane). Y is irrelevant; the boundary is a vertical wall.
const CENTER := Vector3(80.0, 0.0, 80.0)

## Playable radius in metres. See the class comment for the cliff/mountain
## margins this value buys.
const RADIUS := 52.0

## Tolerance for boundary comparisons; keeps points on the rim "inside"
## instead of jittering them by floating-point noise.
const EPSILON := 0.001


## True when `point` is finite and at or inside the playable boundary
## (xz radial distance <= RADIUS + EPSILON). Finite Y does not affect distance.
static func is_inside(point: Vector3) -> bool:
	if not point.is_finite():
		return false
	return _radial_distance(point) <= RADIUS + EPSILON


## Robustly clamp `point` into the playable valley.
##
## - Finite inside points (and points on the rim) are returned unchanged.
## - Finite outside points are projected onto the boundary circle in the
##   xz plane, so a controller moving against the edge slides along it.
## - Non-finite input (NaN/Inf from a bad restore, for example) falls back
##   to the valley centre.
## - Finite input retains Y; non-finite input uses the finite centre.
static func clamp_position(point: Vector3) -> Vector3:
	if not point.is_finite():
		return CENTER
	var distance := _radial_distance(point)
	if distance <= RADIUS + EPSILON:
		return point
	var direction := Vector3(point.x - CENTER.x, 0.0, point.z - CENTER.z)
	var edge := CENTER + direction / distance * RADIUS
	return Vector3(edge.x, point.y, edge.z)


## True when a circular edit footprint of `radius` metres centred on
## `center` lies entirely inside the playable disk, with EPSILON edge
## tolerance. The footprint is the disk of points whose xz distance from
## `center` is <= `radius`, so it fits only when the centre is finite, the
## radius is finite and nonnegative, and the centre's radial distance plus
## the radius does not exceed RADIUS + EPSILON.
static func is_circle_footprint_inside(center: Vector3, radius: float) -> bool:
	if not center.is_finite() or is_nan(radius) or is_inf(radius) or radius < 0.0:
		return false
	return _radial_distance(center) + radius <= RADIUS + EPSILON


## True when a polygon/rectangle edit footprint (its corners, in any order) lies
## entirely inside the playable disk, with EPSILON edge tolerance. The playable
## disk is convex, so if every corner is at or inside the rim the whole
## convex hull (the footprint) is too. Requires at least 3 corners, all
## finite, each within RADIUS + EPSILON.
static func is_polygon_footprint_inside(corners: Array[Vector3]) -> bool:
	if corners.size() < 3:
		return false
	for corner in corners:
		if not corner.is_finite() or _radial_distance(corner) > RADIUS + EPSILON:
			return false
	return true


## Radial (xz-plane) distance from the valley centre.
static func _radial_distance(point: Vector3) -> float:
	return Vector2(point.x - CENTER.x, point.z - CENTER.z).length()
