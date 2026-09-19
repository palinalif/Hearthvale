extends SceneTree
## Headless, deterministic tests for the authored-water record model
## (LandscapeState) and its pure geometry (WaterRegionGeometry). No native voxel
## module, no scene, no RNG: pure logic only.
const State = preload("res://scripts/landscape_state.gd")
const Geometry = preload("res://scripts/water_region_geometry.gd")

var failures := 0
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _square(cx: float, cz: float, half: float) -> Array:
	var a := half
	return [[cx - a, cz - a], [cx + a, cz - a], [cx + a, cz + a], [cx - a, cz + a]]

func _initialize() -> void:
	_run()
	print("water_region_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _run() -> void:
	var state = State.new()

	# --- add a lake -----------------------------------------------------------
	var lake_id := state.add_water("lake", 3.0, _square(32.0, 32.0, 2.0))
	check(lake_id >= 1, "lake add returns a valid id")
	check(state.water.size() == 1, "lake stored")

	# --- add a stream ---------------------------------------------------------
	var stream_points := [[10.0, 10.0], [20.0, 10.0], [30.0, 14.0]]
	var stream_id := state.add_water("stream", 2.5, stream_points, 1.5, [1.0, 0.0])
	check(stream_id >= 1 and stream_id != lake_id, "stream add returns a distinct id")
	check(state.water.size() == 2, "stream stored")

	# --- round trip: document / validate / restore ----------------------------
	var doc := state.document()
	check(doc.has("water") and (doc["water"] as Array).size() == 2, "document carries water")
	check(State.validate(doc), "document validates")
	var restored = State.new()
	check(restored.restore(doc), "restore accepts the document")
	check((restored.water as Array).size() == 2, "restore keeps both regions")
	check(float((restored.water[0] as Dictionary)["level"]) == 3.0, "lake level survives round trip")
	check(float((restored.water[1] as Dictionary)["width"]) == 1.5, "stream width survives round trip")
	check(int((restored.water[1] as Dictionary)["id"]) == stream_id, "stream id survives round trip")

	# --- rejection: invalid inputs -------------------------------------------
	var s2 = State.new()
	check(s2.add_water("ocean", 3.0, _square(10.0, 10.0, 1.0)) == -1, "unknown type rejected")
	check(s2.add_water("lake", 99.0, _square(10.0, 10.0, 1.0)) == -1, "level above max rejected")
	check(s2.add_water("lake", 3.0, [[10.0, 10.0], [11.0, 10.0]]) == -1, "lake with 2 points rejected")
	check(s2.add_water("stream", 3.0, [[10.0, 10.0]]) == -1, "stream with 1 point rejected")
	check(s2.add_water("lake", 3.0, [[-1.0, 10.0], [11.0, 10.0], [11.0, 12.0]]) == -1, "out-of-world point rejected")
	check(s2.add_water("stream", 3.0, [[10.0, 10.0], [20.0, 10.0]], 1.5, [0.0, 0.0]) == -1, "zero flow rejected")
	check(s2.water.is_empty(), "rejected adds leave state empty")

	# --- region limit ---------------------------------------------------------
	var s3 = State.new()
	var accepted := 0
	for i in range(State.WATER_LIMIT + 1):
		var offset := 1.0 + float(i) * 2.0
		if s3.add_water("lake", 3.0, _square(1.0 + offset, 1.0 + offset, 0.5)) >= 1:
			accepted += 1
	check(accepted == State.WATER_LIMIT, "region limit enforced (%d)" % accepted)

	# --- erase ----------------------------------------------------------------
	check(state.erase_water(lake_id), "erase lake returns true")
	check(state.water.size() == 1, "lake removed")
	check(not state.erase_water(lake_id), "erase unknown returns false")

	# --- waterfall suppressions (the only authoritative waterfall state) ----
	var s4 = State.new()
	check(not s4.document().has("waterfall_suppressions"), "document omits suppressions when empty")
	check(s4.suppress_waterfall("1-2"), "suppress a derived fall")
	check(not s4.suppress_waterfall("1-2"), "duplicate suppress rejected")
	check(s4.suppress_waterfall("3-4"), "second fall suppressed")
	check(not s4.suppress_waterfall(""), "empty key rejected")
	check((s4.document()["waterfall_suppressions"] as Array).size() == 2, "document carries suppressions")
	var s4b = State.new()
	check(s4b.restore(s4.document()), "restore accepts suppressions")
	check(s4b.waterfall_suppressions.has("1-2") and s4b.waterfall_suppressions.has("3-4"), "suppressions survive round trip")
	check(s4b.unsuppress_waterfall("1-2"), "unsuppress removes")
	check(not s4b.waterfall_suppressions.has("1-2"), "suppression gone after unsuppress")
	check(not s4b.unsuppress_waterfall("1-2"), "unsuppress unknown rejected")
	check(State.validate(s4b.document()), "document with suppressions validates")

	# --- geometry: lake containment ------------------------------------------
	var lake := {"type": "lake", "level": 3.0, "points": _square(32.0, 32.0, 2.0)}
	check(Geometry.contains(lake, Vector2(32.0, 32.0)), "lake centre inside")
	check(Geometry.contains(lake, Vector2(33.0, 31.0)), "lake interior inside")
	check(not Geometry.contains(lake, Vector2(35.0, 32.0)), "lake outside rejected")
	check(not Geometry.contains(lake, Vector2(29.0, 29.0)), "lake corner-outside rejected")
	check(is_equal_approx(Geometry.surface_level(lake), 3.0), "lake surface level")
	check(Geometry.is_submerged(lake, Vector2(32.0, 32.0), 2.0), "terrain below level is submerged")
	check(not Geometry.is_submerged(lake, Vector2(32.0, 32.0), 4.0), "terrain above level is not submerged")
	check(not Geometry.is_submerged(lake, Vector2(40.0, 40.0), 1.0), "outside region not submerged")

	# --- geometry: stream containment ----------------------------------------
	var stream := {"type": "stream", "level": 2.5, "width": 1.5, "flow": [1.0, 0.0], "points": [[10.0, 10.0], [30.0, 10.0]]}
	check(Geometry.contains(stream, Vector2(20.0, 10.0)), "stream on centreline inside")
	check(Geometry.contains(stream, Vector2(20.0, 10.7)), "stream within half-width inside")
	check(not Geometry.contains(stream, Vector2(20.0, 12.0)), "stream beyond half-width outside")
	check(not Geometry.contains(stream, Vector2(5.0, 10.0)), "stream off the line outside")
	check(is_equal_approx(Geometry.surface_level(stream), 2.5), "stream surface level")

	# --- geometry: footprint cells -------------------------------------------
	var lake_cells := Geometry.footprint_cells(lake, 64.0)
	check(lake_cells.size() > 0, "lake footprint non-empty")
	var stream_cells := Geometry.footprint_cells(stream, 64.0)
	check(stream_cells.size() > 0, "stream footprint non-empty")
	check(stream_cells.size() > lake_cells.size(), "long stream covers more cells than small lake")

	# --- determinism ----------------------------------------------------------
	var lake_cells_b := Geometry.footprint_cells(lake, 64.0)
	check(_digest(lake_cells) == _digest(lake_cells_b), "lake footprint deterministic")
	var stream_cells_b := Geometry.footprint_cells(stream, 64.0)
	check(_digest(stream_cells) == _digest(stream_cells_b), "stream footprint deterministic")

	# --- polygon area / polyline helpers -------------------------------------
	var area := State._water_polygon_area(_square(32.0, 32.0, 2.0))
	check(is_equal_approx(area, 16.0), "square polygon area = 16 (got %.3f)" % area)
	var length := State._water_polyline_length([[0.0, 0.0], [3.0, 4.0]])
	check(is_equal_approx(length, 5.0), "polyline length = 5")

func _digest(cells: Array) -> String:
	var text := ""
	for cell: Vector2i in cells:
		text += "%d,%d;" % [cell.x, cell.y]
	return text
