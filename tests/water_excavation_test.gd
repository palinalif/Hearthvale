extends SceneTree
## Locks the water bed/bank excavator (river 4b carve logic): the native voxel
## changes a commit applies. Headless, deterministic, mock backend — no native
## module. Bed cells are lowered to the bed level, bank cells to the water
## level, deep cells are left, and voids/caves are never tunelled through.

const Excavation = preload("res://scripts/water_terrain_excavation.gd")

var checks := 0
var failures := 0

class MockBackend:
	extends Node
	var voxel_scale := 0.125
	var patch_size := Vector3i(40, 16, 40)
	var surface := 8
	var voids := {}
	func is_ready() -> bool: return true
	func voxel_at(p: Vector3i) -> int:
		if p.x < 0 or p.z < 0 or p.x >= patch_size.x or p.z >= patch_size.z: return 0
		if voids.has(p): return 0
		return 1 if p.y < surface else 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _whole_lake(level: float) -> Dictionary:
	return {"id": 1, "type": "lake", "level": level, "points": [[0.0, 0.0], [5.0, 0.0], [5.0, 5.0], [0.0, 5.0]]}

func _top_after(mock: Node, changes: Array, cell: Vector2i) -> float:
	var removed := {}
	for change: Dictionary in changes:
		var p: Vector3i = change["position"]
		if p.x == cell.x and p.z == cell.y: removed[p.y] = true
	var scale := 0.125
	var surface: int = mock.surface
	var patch_y: int = mock.patch_size.y
	var voids: Dictionary = mock.voids
	for y in range(patch_y - 1, -1, -1):
		var solid: bool = (y < surface) and (not removed.has(y))
		if solid and not voids.has(Vector3i(cell.x, y, cell.y)):
			return float(y + 1) * scale
	return NAN

func _initialize() -> void:
	var world := 64.0

	# flat floor at 1.0 m, lake level 1.5 -> bed level 0.75. Bed cells carved to 0.75.
	var mock: Node = MockBackend.new()
	mock.surface = 8  # top face 1.0
	var plan := Excavation.plan_bed(mock, _whole_lake(1.5), world)
	check(bool(plan["ok"]), "plan ok")
	check(int(plan["changed_count"]) > 0, "floor above bed is carved (changes=%d)" % plan["changed_count"])
	var center := Vector2i(20, 20)
	var top := _top_after(mock, plan["changes"], center)
	check(not is_nan(top) and is_equal_approx(top, 0.75), "bed cell top lowered to 0.75 (got %s)" % str(top))

	# floor already deep (0.2 m) below the bed: nothing carved.
	var deep: Node = MockBackend.new()
	deep.surface = 2  # top face 0.25 < 0.75
	var plan_deep := Excavation.plan_bed(deep, _whole_lake(1.5), world)
	check(int(plan_deep["changed_count"]) == 0, "deep floor is not re-carved (changes=%d)" % plan_deep["changed_count"])

	# high floor (2.0 m) with a 3 m lake: bed to 0.75 and the shore ring to 1.5.
	var high: Node = MockBackend.new()
	high.surface = 16  # top face 2.0
	var small_lake := {"id": 5, "type": "lake", "level": 1.5, "points": [[1.0, 1.0], [4.0, 1.0], [4.0, 4.0], [1.0, 4.0]]}
	var plan_high := Excavation.plan_bed(high, small_lake, world)
	var bed_top := _top_after(high, plan_high["changes"], Vector2i(20, 20))
	check(is_equal_approx(bed_top, 0.75), "high floor bed to 0.75 (got %s)" % str(bed_top))
	# (7,20) is the one-cell shore ring just outside the 3 m polygon (centre x=0.94 < 1).
	var shore := _top_after(high, plan_high["changes"], Vector2i(7, 20))
	check(not is_nan(shore) and is_equal_approx(shore, 1.5), "bank cell lowered to the water level (got %s)" % str(shore))

	# never tunnel through a pre-existing void/cave.
	var cave: Node = MockBackend.new()
	cave.surface = 16
	var void_pos := Vector3i(20, 5, 20)
	cave.voids[void_pos] = true
	var plan_cave := Excavation.plan_bed(cave, _whole_lake(1.5), world)
	var touched_void := false
	for change: Dictionary in plan_cave["changes"]:
		if (change["position"] as Vector3i) == void_pos: touched_void = true
	check(not touched_void, "void voxel is never removed")

	# determinism.
	var a := Excavation.plan_bed(mock, _whole_lake(1.5), world)
	var b := Excavation.plan_bed(mock, _whole_lake(1.5), world)
	check(_digest(a["changes"]) == _digest(b["changes"]), "excavation is deterministic")

	print("water_excavation_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _digest(changes: Array) -> String:
	var text := ""
	for change: Dictionary in changes:
		var p: Vector3i = change["position"]
		text += "%d,%d,%d;" % [p.x, p.y, p.z]
	return text
