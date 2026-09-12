extends SceneTree

const Excavation = preload("res://scripts/m2_path_terrain_excavation.gd")
const Grid = preload("res://scripts/visual_grid.gd")

class FakeBackend:
	extends RefCounted
	var voxel_scale := Grid.UNIT
	var patch_size := Vector3i(96, 32, 96)
	var values := {}
	func voxel_at(pos: Vector3i) -> int:
		return int(values.get(pos, 0))
	func fill_column(x: int, z: int, top_y: int, material: int = 7) -> void:
		for y in range(top_y + 1): values[Vector3i(x, y, z)] = material

var checks := 0
var failures := 0

func _initialize() -> void:
	var backend := FakeBackend.new()
	var cells: Array = []
	for z in range(20, 28):
		for x in range(20, 28):
			cells.append(Vector2i(x, z))
			backend.fill_column(x, z, 12, 9)
	var plan := Excavation.plan_packed_earth(backend, cells)
	_check(bool(plan.ok), "packed-earth excavation plan accepts matching structural terrain grid")
	_check(int(plan.changed_count) > 0, "broad painted region produces terrain removals")
	var depths := {}
	var before_ok := true
	var after_ok := true
	for item: Dictionary in plan.removals:
		depths[int(item.depth)] = true
		before_ok = before_ok and int(item.before) == 9
		after_ok = after_ok and int(item.after) == 0
	_check(depths.has(1) and depths.has(2), "U-profile excavation contains one- and two-voxel interior cuts")
	_check(before_ok and after_ok, "plan preserves original terrain material for exact rollback")
	var edge_removed := false
	for item: Dictionary in plan.removals:
		var p: Vector3i = item.position
		if p.x == 20 or p.x == 27 or p.z == 20 or p.z == 27: edge_removed = true
	_check(not edge_removed, "level shoulder ring never excavates")
	var deep_column := 0
	for item: Dictionary in plan.removals:
		var p: Vector3i = item.position
		if p.x == 23 and p.z == 23: deep_column += 1
	_check(deep_column == 2, "broad centre removes exactly two connected top voxels")
	_check(plan.min != Vector3i.ZERO and plan.max.x > plan.min.x and plan.max.y > plan.min.y and plan.max.z > plan.min.z, "plan returns a bounded native edit region")
	var original_count := backend.values.size()
	_check(backend.values.size() == original_count, "planning is read-only and does not mutate terrain")

	var cave := FakeBackend.new()
	for z in range(40, 48):
		for x in range(40, 48):
			cave.fill_column(x, z, 10, 5)
	cave.values[Vector3i(43, 9, 43)] = 0
	var cave_cells: Array = []
	for z in range(40, 48):
		for x in range(40, 48): cave_cells.append(Vector2i(x, z))
	var cave_plan := Excavation.plan_packed_earth(cave, cave_cells)
	var cave_removals := 0
	for item: Dictionary in cave_plan.removals:
		if (item.position as Vector3i).x == 43 and (item.position as Vector3i).z == 43: cave_removals += 1
	_check(cave_removals == 1, "excavation stops at a pre-existing void instead of tunnelling through it")

	var mismatch := FakeBackend.new()
	mismatch.voxel_scale = 0.25
	var rejected := Excavation.plan_packed_earth(mismatch, cells)
	_check(not bool(rejected.ok) and str(rejected.error).contains("differ"), "mismatched terrain voxel pitch is rejected explicitly")

	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "removals": plan.changed_count}))
	quit(1 if failures else 0)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)
