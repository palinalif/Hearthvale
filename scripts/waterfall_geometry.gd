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
# A stream's lip needs a bigger head than a lake's: the ~2 m step where the
# starter river plunges into the pool is the tail of the cliff cascade that
# feeds that pool, not its own fall, so a stream's small step reads as a
# riffle (rock) rather than a second sheet. Lakes keep MIN_HEAD.
const MIN_STREAM_HEAD := 2.5
const MAX_LIP_DEPTH := 1.0  # includes the standard 0.75 m excavated lake bed
const LIP_TOL := 0.5        # crown terrain may sit this close to / below the upper level
const DROP_REACH := 2.0     # how far beyond the crown to sample the cliff base
const DROP_TOL := 0.25      # base must drop to within this of the lower level
const LANDING_REACH := 2.0  # crown must be this close to the lower body
const CASCADE_WIDTH := 1.5  # default cascade width (metres)
# The cascade sheet spans the submerged run of each body: terrain is scanned
# perpendicular to the flow from the crown (lip) and the impact point
# (plunge) until it rises above the water surface. On a flat plateau the scan
# runs out at the cap and the region's own width is used instead (so a 200 m
# lake does not produce a 48 m sheet). The sheet is a trapezoid, wider at the
# plunge, so a narrow lip flares out into the full river bed at the pool.
const MAX_SPAN_SCAN := 24.0
# Two falls sharing the same source and nearly the same lip (e.g. a river and
# the plunge pool beneath it) would render the same sheet twice; keep only
# the best-scored one per lip.
const CROWN_DEDUP := 2.0

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
			var min_head := MIN_STREAM_HEAD if str(upper.get("type", "")) == "stream" else MIN_HEAD
			if head < min_head:
				continue
			var fall := _best_crown(upper, lower, up_level, lo_level, sample, dirty_rect)
			if fall.is_empty():
				continue
			var crown := Vector2(float(fall["crown"][0]), float(fall["crown"][1]))
			var flow := Vector2(float(fall["flow"][0]), float(fall["flow"][1]))
			var perp := flow.rotated(PI / 2.0)
			var impact := crown + flow * cascade_run(float(fall["head"]))
			fall["crown_width"] = _submerged_span(sample, crown, perp, up_level, LIP_TOL, upper)
			fall["impact_width"] = _submerged_span(sample, impact, perp, lo_level, DROP_TOL, lower)
			falls.append(fall)
	falls = _dedupe_same_lip(falls)
	falls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["upper_id"]) < int(b["upper_id"]))
	return falls

## Horizontal run of the sheet from the lip to the plunge, derived from the
## head so a taller fall lands a little farther out (matching the cliff's
## slight overhang). Shared by the mesh, splash and spray so they agree.
static func cascade_run(head: float) -> float:
	return clampf(head * 0.25, 0.5, 8.0)

## Total submerged span around `p` along `dir` (both directions). The scan
## stops where the terrain rises above `level + tol`; when both sides run out
## at the cap (flat plateau) the region-based fallback is used instead.
static func _submerged_span(sample: Callable, p: Vector2, dir: Vector2, level: float,
		tol: float, region: Dictionary) -> float:
	var a: float = _scan_span(sample, p, dir, level + tol)
	var b: float = _scan_span(sample, p, -dir, level + tol)
	if Geometry.is_lake(region):
		# The water body is polygon-clipped: a scan that runs out at the cap
		# is terrain, not water, so it falls back to the polygon chord.
		var pts := Geometry.points(region)
		if a >= MAX_SPAN_SCAN:
			a = _chord_to(pts, p, dir)
		if b >= MAX_SPAN_SCAN:
			b = _chord_to(pts, p, -dir)
	else:
		# A stream's polygon is a centerline; the scan is the channel, but a
		# dry bed inside the corridor must still count as the corridor width.
		var corridor := float(region.get("width", CASCADE_WIDTH))
		if a + b < corridor:
			a += (corridor - a - b)
	return maxf(a + b, CASCADE_WIDTH)

static func _scan_span(sample: Callable, p: Vector2, dir: Vector2, above: float) -> float:
	var d := 0.0
	for _i in 192: # 24 m at 0.125 m
		d += 0.125
		if d >= MAX_SPAN_SCAN:
			return MAX_SPAN_SCAN
		var h: float = sample.call(p + dir * d)
		if not is_nan(h) and h > above:
			return d
	return MAX_SPAN_SCAN

## Region-based width fallback: a stream is a fixed corridor; a lake is the
## polygon chord through `p` along `dir`.
static func _chord_to(pts: PackedVector2Array, p: Vector2, dir: Vector2) -> float:
	if pts.size() < 3:
		return 0.0
	var d := 0.0
	for _i in 192:
		d += 0.125
		if d >= MAX_SPAN_SCAN:
			return MAX_SPAN_SCAN
		if not Geometry.point_in_polygon(pts, p + dir * d):
			return d
	return MAX_SPAN_SCAN

## Keep one fall per (source, lip): the best-scored wins, mirroring the
## _best_crown score (head minus landing reach).
static func _dedupe_same_lip(falls: Array) -> Array:
	var kept: Array = []
	for fall: Dictionary in falls:
		var dropped := false
		var best_index := -1
		for i in kept.size():
			var other: Dictionary = kept[i]
			if int(other["upper_id"]) != int(fall["upper_id"]):
				continue
			var oc := Vector2(float(other["crown"][0]), float(other["crown"][1]))
			var fc := Vector2(float(fall["crown"][0]), float(fall["crown"][1]))
			if oc.distance_to(fc) > CROWN_DEDUP:
				continue
			if _fall_score(fall) > _fall_score(other):
				best_index = i
				dropped = true
			break
		if dropped and best_index >= 0:
			kept[best_index] = fall
		elif not dropped:
			kept.append(fall)
	return kept

## The _best_crown score, recomputed without the region list (landing reach is
## within ~2 m of the shared lip for both candidates, so the head decides).
static func _fall_score(fall: Dictionary) -> float:
	return float(fall["head"])

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
