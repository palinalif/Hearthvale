extends SceneTree
## Locks the derived-waterfall presentation (no simulation): a higher authored body
## overhanging a lower one renders a cascade; a dismissal hides it; and a local
## terrain edit re-derives only that area. Uses a cliff mock backend so the build
## pipeline is testable headless without the native voxel module.

const Visual = preload("res://scripts/water_visual.gd")
const Waterfall = preload("res://scripts/waterfall_geometry.gd")
const PremadeRiver = preload("res://scripts/premade_river.gd")

var checks := 0
var failures := 0

class CliffBackend:
	extends Node
	var voxel_scale := 0.125
	var patch_size := Vector3i(40, 48, 40)
	var filled := false   # true: the pool side rises to the plateau (the cliff fills in)
	var _rev := 0
	func is_ready() -> bool: return true
	func revision() -> int: return _rev
	func bump() -> void: _rev += 1
	func _col_surface(x: int) -> int:
		if x < 20: return 32
		return 32 if filled else 8
	func voxel_at(p: Vector3i) -> int:
		if p.x < 0 or p.z < 0 or p.x >= patch_size.x or p.z >= patch_size.z: return 0
		return 1 if p.y < _col_surface(p.x) else 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _upper() -> Dictionary:
	return {"id": 1, "type": "lake", "level": 4.0, "points": [[0.0, 0.0], [2.5, 0.0], [2.5, 5.0], [0.0, 5.0]]}

func _lower() -> Dictionary:
	return {"id": 2, "type": "lake", "level": 1.0, "points": [[2.5, 0.0], [5.0, 0.0], [5.0, 5.0], [2.5, 5.0]]}

func _make(backend: Node, regions: Array) -> Node:
	var visual: Node = Visual.new()
	root.add_child(visual)
	visual.attach_backend(backend)
	visual.set_regions(regions)
	return visual

func _initialize() -> void:
	# The shallow authored reservoir and pool must cover their warm voxel beds,
	# while player lakes keep the existing translucent stream material.
	var still := Visual.new()
	check(still._is_still_water(PremadeRiver.reservoir_region()), "starter reservoir uses still-water shading")
	check(still._is_still_water(PremadeRiver._reservoir_region_at_radius(PremadeRiver.PREVIOUS_RESERVOIR_RADIUS)), "legacy reservoir uses still-water shading")
	check(still._is_still_water(PremadeRiver.plunge_pool_region()), "plunge pool uses still-water shading")
	check(not still._is_still_water(_upper()), "unrelated lake stays translucent")
	check(still._region_material(Vector2.RIGHT, PremadeRiver.reservoir_region()).shader == still.POOL_WATER_SHADER, "reservoir receives the opaque shader")
	check(still._region_material(Vector2.DOWN, PremadeRiver.region()).shader == still.WATER_SHADER, "generated river keeps the stream material")
	check(still._region_material(Vector2.DOWN, {"type": "stream", "level": 5.0, "width": 2.0, "points": [[40.0, 20.0], [40.0, 30.0]], "flow": [0.0, -1.0]}).shader == still.WATER_SHADER, "player stream retains translucent material")
	# Only the starter reservoir fall follows the river corridor, including
	# older saved 4 m streams. The mesh, foam and particle width share the cap.
	var reservoir := PremadeRiver.reservoir_region()
	reservoir["id"] = 11
	var pool := PremadeRiver.plunge_pool_region()
	pool["id"] = 12
	var river := PremadeRiver.region()
	river["id"] = 13
	still._regions = [reservoir, pool, river]
	var starter_fall := {"upper_id": 11, "lower_id": 12, "crown": [82.0, 140.0], "flow": [0.0, -1.0], "top_level": 23.0, "bottom_level": 3.0, "crown_width": 12.0, "impact_width": 10.0, "lower_centroid": [82.0, 136.0]}
	var fall_node: MeshInstance3D = still._build_cascade(starter_fall)
	var curtain: PackedVector3Array = fall_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var visible_width: float = PremadeRiver.WIDTH * still.STARTER_FALL_WIDTH_RATIO
	check(is_equal_approx(absf(curtain[0].x - curtain[1].x), visible_width), "starter curtain crown leaves a narrow river margin")
	check(is_equal_approx(absf(curtain[2].x - curtain[3].x), visible_width), "starter curtain impact leaves a narrow river margin")
	var foam: PackedVector3Array = fall_node.mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX]
	check(is_equal_approx(absf(foam[1].x - foam[9].x), visible_width), "starter foam fits narrowed curtain")
	fall_node.free()
	river["width"] = PremadeRiver.PREVIOUS_WIDTH
	check(is_equal_approx(still._starter_fall_river_width(starter_fall), PremadeRiver.PREVIOUS_WIDTH), "legacy starter river retains its own fall width")
	still._regions = [reservoir, pool]
	check(is_zero_approx(still._starter_fall_river_width(starter_fall)), "unrelated falls retain terrain-derived width")
	still.free()
	# derivation: a stepped cliff yields one waterfall joining the two bodies
	var mock: Node = CliffBackend.new()
	root.add_child(mock)
	var visual := _make(mock, [_upper(), _lower()])
	visual.refresh_waterfalls(Waterfall.FULL_RECT)
	check(visual.waterfall_count() == 1, "stepped cliff yields one waterfall (got %d)" % visual.waterfall_count())
	check(visual.waterfall_keys() == ["1-2"], "fall key is the upper-lower pair")
	check(visual.waterfall_particle_node_count() == 2, "each fall has spray + mist emitters (got %d)" % visual.waterfall_particle_node_count())
	# dismissal hides the fall; un-dismissing brings it back
	visual.set_waterfall_suppressions(["1-2"])
	check(visual.waterfall_count() == 0, "a dismissed fall is hidden")
	visual.set_waterfall_suppressions([])
	check(visual.waterfall_count() == 1, "an un-dismissed fall returns")
	visual.queue_free(); mock.queue_free()

	# scoped terrain change: filling in the cliff removes only the affected fall
	var mock2: Node = CliffBackend.new()
	root.add_child(mock2)
	var visual2 := _make(mock2, [_upper(), _lower()])
	visual2.refresh_waterfalls(Waterfall.FULL_RECT)
	check(visual2.waterfall_count() == 1, "initial fall present")
	mock2.filled = true
	mock2.bump()
	var pool_rect := Rect2(2.5, 0.0, 2.5, 5.0).grow(Waterfall.SAMPLE_MARGIN)
	visual2.refresh_waterfalls(pool_rect)
	check(visual2.waterfall_count() == 0, "filling the cliff removes the fall")
	visual2.queue_free(); mock2.queue_free()

	print("waterfall_visual_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
