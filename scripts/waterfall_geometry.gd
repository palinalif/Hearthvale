class_name WaterfallGeometry
extends RefCounted
## Pure, deterministic waterfall derivation from authored water regions + terrain.
##
## A waterfall is NOT simulated. It is derived, at edit time, wherever a higher
## authored body's edge drops near-vertically into a lower authored body: the
## crown sits on the upper body's lip, the cliff drops to (or below) the lower
## body's level, and the cascade base lands in the lower body. The same regions +
## terrain always yield the same falls. No state, no RNG, no per-frame work —
## presentation and the editor both consume this, and only the *suppressions* the
## player chooses are stored as authoritative state (see LandscapeState).
const Geometry = preload("res://scripts/water_region_geometry.gd")
const Grid = preload("res://scripts/visual_grid.gd")

const MIN_HEAD := 0.5       # minimum fall height (metres) to count as a waterfall
const MAX_LIP_DEPTH := 1.0  # includes the standard 0.75 m excavated lake bed
const LIP_TOL := 0.5        # crown terrain may sit this close to / below the upper level
const DROP_REACH := 2.0     # how far beyond the crown to sample the cliff base
const DROP_TOL := 0.25      # base must drop to within this of the lower level
const LANDING_REACH := 2.0  # crown must be this close to the lower body
const CASCADE_WIDTH := 1.5  # default cascade width (metres)

## How far beyond a crown the derivation samples (cliff base + landing reach). The
## caller grows a dirty rect by this before a partial re-derive so every sample a
## crown makes stays inside the rect — derivation never touches the whole map.
const SAMPLE_MARGIN := DROP_REACH + LANDING_REACH

## A rect that matches every world point, i.e. "re-derive the whole map" (initial
## load only; discrete water-body edits pass a scoped rect instead).
const FULL_RECT := Rect2(-1.0e6, -1.0e6, 2.0e6, 2.0e6)

## derive(regions, sample, dirty_rect) -> Array of waterfall dicts. "sample" returns
## the terrain-top world Y for an XZ point (NAN when empty). Only crown candidates
## inside dirty_rect are evaluated, so a partial re-derive after a local terrain
## edit samples only that area. FULL_RECT re-derives everything.
static func derive(regions: Array, sample: Callable, dirty_rect: Rect2 = FULL_RECT) -> Array:
	var bodies := _bodies(regions)
	var falls: Array = []
	for upper in bodies:
		var up_level := Geometry.surface_level(upper)
		for lower in bodies:
			if int(lower.get("id", -1)) == int(upper.get("id", -1)):
				continue
			var lo_level := Geometry.surface_level(lower)
			var head := up_level - lo_level
			if head < MIN_HEAD:
				continue
			var fall := _best_crown(upper, lower, up_level, lo_level, sample, dirty_rect)
			if not fall.is_empty():
				falls.append(fall)
	falls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["upper_id"]) < int(b["upper_id"]))
	return falls

static func _bodies(regions: Array) -> Array:
	var result: Array = []
	for value in regions:
		if value is Dictionary and str((value as Dictionary).get("type", "")) in ["lake", "stream"]:
			result.append(value)
	return result

static func _best_crown(upper: Dictionary, lower: Dictionary, up_level: float, lo_level: float, sample: Callable, dirty_rect: Rect2 = FULL_RECT) -> Dictionary:
	var candidates := _candidate_points(upper)
	if candidates.is_empty():
		return {}
	var lower_centroid := _centroid(lower)
	var best_point := Vector2(NAN, NAN)
	var best_score := -INF
	var best_flow := Vector2(1.0, 0.0)
	for p in candidates:
		if not p.is_finite() or not dirty_rect.has_point(p):
			continue
		var top: float = sample.call(p)
		if is_nan(top) or top > up_level + LIP_TOL or top < up_level - MAX_LIP_DEPTH:
			continue
		var out_dir := lower_centroid - p
		if out_dir.length() < 0.000001:
			out_dir = Vector2(1.0, 0.0)
		out_dir = out_dir.normalized()
		var base_top: float = sample.call(p + out_dir * DROP_REACH)
		if not (is_nan(base_top) or base_top <= lo_level + DROP_TOL):
			continue
		var dist := _min_distance_to_region(lower, p)
		if dist > LANDING_REACH:
			continue
		var score := (up_level - lo_level) - 0.5 * dist
		if score > best_score:
			best_score = score
			best_point = p
			best_flow = out_dir
	if not best_point.is_finite():
		return {}
	var crown := Vector2(snappedf(best_point.x, Grid.UNIT), snappedf(best_point.y, Grid.UNIT))
	return {
		"key": "%d-%d" % [int(upper.get("id", 0)), int(lower.get("id", 0))],
		"upper_id": int(upper.get("id", 0)),
		"lower_id": int(lower.get("id", 0)),
		"crown": [crown.x, crown.y],
		"width": CASCADE_WIDTH,
		"flow": [snappedf(best_flow.x, 0.001), snappedf(best_flow.y, 0.001)],
		"head": up_level - lo_level,
		"top_level": up_level,
		"bottom_level": lo_level,
	}

## Crown candidates: the authored points, plus lake edge midpoints (so a fall can
## hang from the middle of a bank, not only a corner).
static func _candidate_points(region: Dictionary) -> PackedVector2Array:
	var pts := Geometry.points(region)
	var result := PackedVector2Array()
	for p in pts:
		result.append(p)
	if Geometry.is_lake(region) and pts.size() >= 3:
		for i in range(pts.size()):
			result.append((pts[i] + pts[(i + 1) % pts.size()]) * 0.5)
	return result

static func _centroid(region: Dictionary) -> Vector2:
	var pts := Geometry.points(region)
	if pts.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in pts:
		sum += p
	return sum / float(pts.size())

## Distance from a point to a region's body (0 when inside the footprint).
static func _min_distance_to_region(region: Dictionary, p: Vector2) -> float:
	var pts := Geometry.points(region)
	if pts.is_empty():
		return INF
	if Geometry.is_lake(region):
		if Geometry.point_in_polygon(pts, p):
			return 0.0
		return _min_distance_to_polygon(pts, p)
	return maxf(0.0, Geometry.min_distance_to_polyline(pts, p) - Geometry.stream_radius(region))

static func _min_distance_to_polygon(pts: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	var n := pts.size()
	for i in range(n):
		best = minf(best, Geometry.segment_closest_point(pts[i], pts[(i + 1) % n], p).distance_to(p))
	return best
