extends SceneTree
const Index = preload("res://scripts/sculpt_column_index.gd")
const Native = preload("res://scripts/terrain_backend.gd")
const Query = preload("res://scripts/sculpt_next_layer.gd")
const Visual = preload("res://scripts/terrain_edit_preview.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _init() -> void:
	var dimensions := Vector3i(12, 16, 20)
	var source: Object = ClassDB.instantiate("VoxelBuffer")
	source.create(dimensions.x, dimensions.y, dimensions.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = 739151
	for depth in [0, 1]:
		source.set_channel_depth(0, depth)
		for x in dimensions.x:
			for y in dimensions.y:
				for z in dimensions.z:
					source.set_voxel(0 if rng.randf() < 0.72 else (1 if depth == 0 else 256), x, y, z, 0)
		var original: PackedByteArray = source.get_channel_as_byte_array(0)
		for axis in [0, 1, 2]:
			var index := Index.new()
			check(index.capture(source, dimensions, Vector3(6, 8, 10), 3.0, axis), "capture %d/%d" % [depth, axis])
			check(source.get_channel_as_byte_array(0) == original, "snapshot never changes source")
			for _i in 100:
				var cell := index.origin + Vector3i(rng.randi_range(0, index.size.x - 1), rng.randi_range(0, index.size.y - 1), rng.randi_range(0, index.size.z - 1))
				var reach := rng.randi_range(0, 25)
				for direction in [-1, 1]:
					for occupied in [false, true]:
						var expected := -1
						for step in reach + 1:
							var probe := cell
							probe[axis] += direction * step
							if probe[axis] < 0 or probe[axis] >= dimensions[axis]: break
							if (int(source.get_voxel(probe.x, probe.y, probe.z, 0)) != 0) == occupied:
								expected = probe[axis]
								break
						check(index.first(cell, direction, reach, occupied) == expected, "native occupancy run parity axis=%d" % axis)
	# Verify fast seeding itself, including all-air, long solid masses,
	# disconnected roofs and rays that hit the patch boundaries.
	var backend := Native.new()
	backend.patch_size = dimensions
	backend.voxels = source
	backend._backend_ready = true
	var query := Query.new()
	query.patch_size = dimensions
	query.voxels = source
	query._backend_ready = true
	query._index_center = Vector3(6, 8, 10)
	query._index_radius = 3.0
	for fixture in [0, 1, 2]:
		if fixture < 2: source.fill(0 if fixture == 0 else 2, 0)
		for axis in [0, 1, 2]:
			for direction in [-1, 1]:
				for tool in ["raise", "dig"]:
					backend._stroke_settings = {"radius": 3.0}
					query._stroke_settings = backend._stroke_settings.duplicate()
					backend._stroke_tool = tool
					query._stroke_tool = tool
					backend._stroke_front_axis = axis
					query._stroke_front_axis = axis
					backend._stroke_front_sign = direction
					query._stroke_front_sign = direction
					query._column_index = null
					for _i in 20:
						var center := Vector3(6, 8, 10)
						center[axis] = float(rng.randi_range(0, dimensions[axis] - 1)) + 0.25
						var column := Vector3i(center.floor())
						column[axis] = 0
						backend._stroke_fronts.clear()
						query._stroke_fronts.clear()
						backend._ensure_front(column, center)
						query._ensure_front(column, center)
						check(query._stroke_fronts == backend._stroke_fronts, "seeding parity fixture=%d axis=%d sign=%d tool=%s" % [fixture, axis, direction, tool])
		if fixture == 1:
			source.fill(0, 0)
			for _i in 1000:
				source.set_voxel(256, rng.randi_range(0, dimensions.x - 1), rng.randi_range(0, dimensions.y - 1), rng.randi_range(0, dimensions.z - 1), 0)
	# Actual fine-grid query/build costs, cold and cached. These are desktop
	# CPU diagnostics, not Thor timing or shader/rendering evidence.
	backend.voxels = ClassDB.instantiate("VoxelBuffer")
	backend.patch_size = Vector3i(160, 96, 160)
	backend.voxel_scale = 0.125
	backend.voxels.create(160, 96, 160)
	backend.voxels.fill_area(2, Vector3i.ZERO, Vector3i(160, 48, 160), 0)
	backend._stroke_active = false
	for radius in [2.0, 8.0]:
		var settings := {"radius": radius, "strength": 2.0, "falloff": 0.45}
		var plan: Dictionary = query.plan(backend, "dig", Vector3(10, 6, 10), settings)
		var cold := query.last_query_ms
		check(query.last_snapshot_bytes < 16 * 1024 * 1024, "bounded snapshot never full world")
		var snapshot_bytes := query.last_snapshot_bytes
		var visual := Visual.new()
		visual.show_plan(plan)
		var build := visual.last_build_ms
		plan = query.plan(backend, "dig", Vector3(10, 6, 10), settings)
		check(query.last_snapshot_bytes == 0, "cached columns need no snapshot")
		print("PREVIEW_COST radius=%.1f cells=%d cold_ms=%.3f warm_ms=%.3f build_ms=%.3f snapshot_bytes=%d" % [radius, plan.changes.size(), cold, query.last_query_ms, build, snapshot_bytes])
		visual.free()
	backend.free()
	query.free()
	print("sculpt_column_index_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
