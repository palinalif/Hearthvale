extends SceneTree

const Courses = preload("res://scripts/roof_course_layout.gd")
const Grid = preload("res://scripts/visual_grid.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	for row in range(-7, 8):
		var strips := Courses.spans(-31, 73, row, 19)
		var next := -31
		for strip in strips:
			check(int(strip["first"]) == next and int(strip["count"]) > 0, "course spans are positive and contiguous")
			next += int(strip["count"])
		check(next == 42, "course spans cover both negative and positive cell addresses")
		check(strips == Courses.spans(-31, 73, row, 19), "unchanged recipe has deterministic courses")
	check(Courses.address(0, 0)["seam"] and not Courses.address(0, 3)["seam"], "alternate courses move the end seam")
	check(Courses.address(3, 3)["seam"] and not Courses.address(3, 0)["seam"], "half-bond phase is exactly three cells")
	for material in ["terracotta", "moss_tile", "slate", "wood_shake"]:
		check(Courses.supports(material), "tile/shake material has a course finish")
	for material in ["thatch", "standing_seam", "green_roof"]:
		check(not Courses.supports(material), "non-tile material is not turned into masonry")
	for scale_value in [0.25, 0.5, 1.0]:
		var unit := Vector3.ONE * Grid.COTTAGE_DETAIL_UNIT / float(scale_value)
		for dimensions in [Vector3(18, 7, 14), Vector3(23, 8, 12)]:
			for ratio in [0.30, 0.42, 0.62]:
				_check_gable(dimensions, unit, ratio)
		for size in [Vector3(19, unit.y, 0.5), Vector3(17, unit.y * 2, 13), Vector3(1, unit.y, 1)]:
			var centre := Vector3(-1, 10, -0.5)
			var parts := Courses.box_pieces(centre, size, unit, 73)
			var q := Grid.quantized_box(centre, size, unit)
			var expected := AABB(q["center"] - q["size"] * 0.5, q["size"])
			var volume := 0.0
			var all_on_grid := true
			var all_inside := true
			for part in parts:
				var box := AABB(part["center"] - part["size"] * 0.5, part["size"])
				volume += box.get_volume()
				all_on_grid = all_on_grid and _on_grid(part, unit)
				all_inside = all_inside and expected.grow(0.00001).encloses(box)
			check(all_inside and all_on_grid, "custom roof pieces remain inside the exact original grid envelope")
			check(is_equal_approx(volume, expected.get_volume()), "custom roof partition retains the complete solid volume")
			check(parts == Courses.box_pieces(centre, size, unit, 73), "custom roof subdivision is stable")
	print("roof_course_layout_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _on_grid(part: Dictionary, unit: Vector3) -> bool:
	var low: Vector3 = part["center"] - part["size"] * 0.5
	var high: Vector3 = part["center"] + part["size"] * 0.5
	return low.is_equal_approx(low.snapped(unit)) and high.is_equal_approx(high.snapped(unit)) and (part["size"] as Vector3).is_finite() and (part["size"] as Vector3).x > 0 and (part["size"] as Vector3).y > 0 and (part["size"] as Vector3).z > 0

func _check_gable(dimensions: Vector3, unit: Vector3, ratio: float) -> void:
	var pieces := Courses.gable(dimensions, unit, ratio, 37)
	var span := dimensions.x + 0.75
	var first := roundi(-snappedf(span * 0.5, unit.x) / unit.x)
	var columns := ceili(span / (unit.x * 2)) * 2
	var rows := ceili((dimensions.z * 0.5 + 0.5) / unit.z)
	var base_count := 0
	var top_cells := 0
	var on_grid := true
	var in_envelope := true
	for bucket in pieces:
		for part in bucket:
			var centre: Vector3 = part["center"]
			var size: Vector3 = part["size"]
			on_grid = on_grid and _on_grid(part, unit)
			var row := floori(absf(centre.z) / unit.z)
			var source_z := (row + 0.5) * unit.z
			var source_y := snappedf(dimensions.y + dimensions.y * ratio * (1 - source_z / (dimensions.z * 0.5 + 0.5)), unit.y)
			in_envelope = in_envelope and centre.x - size.x * 0.5 >= first * unit.x - 0.00001 and centre.x + size.x * 0.5 <= (first + columns) * unit.x + 0.00001 and row >= 0 and row < rows and centre.y - size.y * 0.5 >= source_y - unit.y - 0.00001 and centre.y + size.y * 0.5 <= source_y + unit.y + 0.00001
			if is_equal_approx(centre.y, source_y - unit.y * 0.5):
				check(is_equal_approx(size.x, columns * unit.x), "under-course skin closes the entire roof width")
				base_count += 1
			else: top_cells += roundi(size.x / unit.x)
	check(base_count == rows * 2, "every roof row on both slopes retains solid backing")
	check(top_cells > 0 and top_cells < rows * 2 * columns, "top layer has real recessed end seams")
	check(in_envelope and on_grid, "gable finish preserves source roof extent and cubic world-cell tier")
	check(pieces == Courses.gable(dimensions, unit, ratio, 37), "resize/profile regeneration does not shuffle a fixed recipe")
