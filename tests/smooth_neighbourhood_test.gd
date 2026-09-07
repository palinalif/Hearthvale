extends SceneTree

const Kernel = preload("res://scripts/smooth_neighbourhood.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _init() -> void:
	var columns: Array[Vector3i] = []
	check(Kernel.means(columns, {}).is_empty(), "empty footprint")
	var surfaces := {}
	for x in range(-7, 8):
		for z in range(-7, 8):
			surfaces[Vector3i(x, 0, z)] = float(24 + x + z)
	for x in range(-3, 4):
		for z in range(-3, 4):
			if x * x + z * z <= 9: columns.append(Vector3i(x, 0, z))
	var means: PackedFloat64Array = Kernel.means(columns, surfaces)
	for i in columns.size():
		check(is_equal_approx(means[i], float(surfaces[columns[i]])), "halo preserves planar slope %d" % i)
	var rng := RandomNumberGenerator.new()
	rng.seed = 379217
	for trial in 12:
		for position in surfaces:
			surfaces[position] = -1.0 if rng.randf() < 0.2 else float(rng.randi_range(0, 255))
		var radius := trial % 4
		means = Kernel.means(columns, surfaces, radius)
		for i in columns.size():
			var total := 0.0
			var count := 0
			for dx in range(-radius, radius + 1):
				for dz in range(-radius, radius + 1):
					var value := float(surfaces.get(columns[i] + Vector3i(dx, 0, dz), -1.0))
					if value >= 0.0:
						total += value
						count += 1
			var current := float(surfaces.get(columns[i], -1.0))
			var expected := -1.0
			if count > 0:
				expected = current - 1.0 if radius > 0 and count == 1 and current >= 0.0 else total / float(count)
			check(is_equal_approx(means[i], expected), "summed-area matches robust reference %d/%d" % [trial, i])
	var isolated := {Vector3i.ZERO: 11.0}
	var isolated_columns: Array[Vector3i] = [Vector3i.ZERO]
	check(Kernel.means(isolated_columns, isolated, 2)[0] == 10.0, "isolated cap erodes one cell")
	check(Kernel.means(isolated_columns, isolated, 0)[0] == 11.0, "zero radius remains exact")
	means = Kernel.means(columns, {})
	for value in means: check(value == -1.0, "missing columns stay invalid")
	check(Kernel.means(columns, surfaces, -1).is_empty(), "invalid neighbourhood rejected")
	print("smooth_neighbourhood_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
