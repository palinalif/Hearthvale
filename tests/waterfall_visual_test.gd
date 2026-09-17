extends SceneTree
## Locks the derived-waterfall presentation (no simulation): a higher authored body
## overhanging a lower one renders a cascade; a dismissal hides it; and a local
## terrain edit re-derives only that area. Uses a cliff mock backend so the build
## pipeline is testable headless without the native voxel module.

const Visual = preload("res://scripts/water_visual.gd")
const Waterfall = preload("res://scripts/waterfall_geometry.gd")

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
	# derivation: a stepped cliff yields one waterfall joining the two bodies
	var mock: Node = CliffBackend.new()
	root.add_child(mock)
	var visual := _make(mock, [_upper(), _lower()])
	visual.refresh_waterfalls(Waterfall.FULL_RECT)
	check(visual.waterfall_count() == 1, "stepped cliff yields one waterfall (got %d)" % visual.waterfall_count())
	check(visual.waterfall_keys() == ["1-2"], "fall key is the upper-lower pair")
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
