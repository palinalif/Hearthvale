extends SceneTree

const Region = preload("res://scripts/m2_painted_path_region.gd")
const Grid = preload("res://scripts/visual_grid.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	var tiny := Region.brush_cells(Vector2(8.0, 8.0), Grid.UNIT * 0.5)
	_check(not tiny.is_empty(), "tiny brush always paints at least one structural cell")
	_check(tiny == Region.brush_cells(Vector2(8.0, 8.0), Grid.UNIT * 0.5), "brush rasterization is deterministic")

	var small := Region.brush_cells(Vector2(8.0, 8.0), 0.25)
	var plaza := Region.brush_cells(Vector2(8.0, 8.0), 1.0)
	_check(plaza.size() > small.size() and small.size() > tiny.size(), "brush radius scales from tiny trail to plaza")
	var circular := true
	for cell: Vector2i in plaza:
		circular = circular and Region.cell_center(cell).distance_to(Vector2(8.0, 8.0)) <= 1.000001
	_check(circular, "circular brush contains only cell centres inside its radius")

	var normalized := Region.normalize_cells([
		Vector2i(4, 5), [4, 5], Vector2(6, 5), [-1, 2], [9999, 2], [5, 5]
	])
	_check(normalized == [Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5)], "normalization deduplicates, bounds and sorts authoritative cells")
	_check(Region.encode_cells(normalized) == [[4, 5], [5, 5], [6, 5]], "encoded cells are compact and deterministic")

	var joined := Region.union_cells([Vector2i(4, 5), Vector2i(5, 5)], [Vector2i(5, 5), Vector2i(6, 5)])
	_check(joined == [Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5)], "paint strokes merge by cell union without junction geometry")
	_check(Region.union_cells(joined, [Vector2i(5, 5)]) == joined, "painting the same cell is idempotent")
	_check(Region.erase_cells(joined, [Vector2i(5, 5)]) == [Vector2i(4, 5), Vector2i(6, 5)], "erase removes only covered cells")

	var sweep_from := Vector2(4.0, 4.0)
	var sweep_to := Vector2(6.0, 4.0)
	var sweep := Region.stroke_cells(sweep_from, sweep_to, Grid.UNIT * 0.5)
	_check(sweep == Region.stroke_cells(sweep_to, sweep_from, Grid.UNIT * 0.5), "stroke rasterization is direction independent")
	var columns := {}
	for cell: Vector2i in sweep: columns[cell.x] = true
	var first_column := floori(sweep_from.x / Grid.UNIT)
	var last_column := floori(sweep_to.x / Grid.UNIT)
	var continuous := true
	for x in range(first_column, last_column + 1): continuous = continuous and columns.has(x)
	_check(continuous, "fast brush sweep leaves no skipped structural columns")
	var wide_sweep := Region.stroke_cells(sweep_from, sweep_to, Grid.UNIT * 2.0)
	_check(wide_sweep.size() > sweep.size(), "stroke radius controls painted width while preserving continuity")

	var three := _block(20, 20, 3, 3)
	var three_field := Region.distance_field(three)
	_check(int(three_field[Vector2i(21, 21)]) == 1, "three-cell trail has one-voxel-deep centre ring")
	_check(Region.packed_earth_depth_steps(int(three_field[Vector2i(21, 21)])) == 1, "normal trail centre packs down one voxel")
	_check(Region.packed_earth_depth_steps(int(three_field[Vector2i(20, 20)])) == 0, "packed-earth shoulder stays at lawn grade")

	var six := _block(40, 40, 6, 6)
	var six_field := Region.distance_field(six)
	_check(int(six_field[Vector2i(42, 42)]) == 2, "six-cell path develops two interior erosion rings")
	_check(Region.packed_earth_depth_steps(int(six_field[Vector2i(42, 42)])) == 1, "six-cell path remains a shallow one-voxel trough")

	var eight := _block(60, 60, 8, 8)
	var eight_field := Region.distance_field(eight)
	_check(int(eight_field[Vector2i(63, 63)]) == 3, "broad painted area develops a deep interior ring")
	_check(Region.packed_earth_depth_steps(int(eight_field[Vector2i(63, 63)])) == 2, "broad road or plaza packs down two voxels")
	_check(is_equal_approx(Region.packed_earth_depth_offset(3), -Grid.UNIT * 2.0), "two-step depression uses structural voxel height")

	var profile := Region.packed_earth_profile(eight)
	var edge_zero := true
	var has_one := false
	var has_two := false
	for cell in profile:
		var depth := int(profile[cell])
		has_one = has_one or depth == 1
		has_two = has_two or depth == 2
		if cell.x == 60 or cell.x == 67 or cell.y == 60 or cell.y == 67:
			edge_zero = edge_zero and depth == 0
	_check(edge_zero and has_one and has_two, "packed-earth profile forms a voxel U with level shoulders and stepped centre")

	var clipped := Region.brush_cells(Vector2(0.02, 0.02), 0.5)
	var in_world := true
	for cell: Vector2i in clipped:
		in_world = in_world and cell.x >= 0 and cell.y >= 0
	_check(in_world, "brush clips cleanly at editable-world edge")

	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "unit": Grid.UNIT, "tiny_cells": tiny.size(), "small_cells": small.size(), "plaza_cells": plaza.size(), "sweep_cells": sweep.size()}))
	quit(1 if failures else 0)

func _block(x0: int, y0: int, width: int, height: int) -> Array:
	var result: Array = []
	for y in range(y0, y0 + height):
		for x in range(x0, x0 + width):
			result.append(Vector2i(x, y))
	return result

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)
