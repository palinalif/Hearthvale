extends SceneTree
const Runs = preload("res://scripts/sculpt_occupancy_runs.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures <= 12: push_error("FAIL: " + label)

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 72901
	var dimensions := Vector3i(11, 9, 13)
	var origin := Vector3i(17, 23, 31)
	for depth in [0, 1]:
		for fixture in 4:
			var buffer: Object = ClassDB.instantiate("VoxelBuffer")
			buffer.set_channel_depth(0, depth)
			buffer.create(dimensions.x, dimensions.y, dimensions.z)
			for x in dimensions.x:
				for y in dimensions.y:
					for z in dimensions.z:
						var value := 0
						if fixture == 1: value = 255 if depth == 0 else 65535
						elif fixture == 2 and (x + y + z) % 3 == 0: value = rng.randi_range(1, 255 if depth == 0 else 65535)
						elif fixture == 3 and (y < 3 or y > 6): value = 2 if depth == 0 else 256
						buffer.set_voxel(value, x, y, z, 0)
			var before: PackedByteArray = buffer.get_channel_as_byte_array(0)
			for axis in 3:
				var runs := Runs.new()
				check(runs.build(buffer, origin, axis), "occupancy builds")
				check(before == buffer.get_channel_as_byte_array(0), "occupancy leaves material bytes intact")
				for _sample in 160:
					var cell := Vector3i(rng.randi_range(0, dimensions.x - 1), rng.randi_range(0, dimensions.y - 1), rng.randi_range(0, dimensions.z - 1))
					var reach := rng.randi_range(0, 20)
					for direction in [-1, 1]:
						for occupied in [false, true]:
							var expected := -1
							for distance in reach + 1:
								var p := cell
								p[axis] += distance * direction
								if p[axis] < 0 or p[axis] >= dimensions[axis]: break
								if (int(buffer.get_voxel(p.x, p.y, p.z, 0)) != 0) == occupied:
									expected = p[axis] + origin[axis]
									break
							check(runs.first(cell + origin, direction, reach, occupied) == expected, "native run parity depth=%d fixture=%d axis=%d" % [depth, fixture, axis])
	print("sculpt_occupancy_runs_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
