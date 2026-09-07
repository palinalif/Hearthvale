extends SceneTree
const Native = preload("res://scripts/terrain_backend.gd")
const Snapshot = preload("res://scripts/sculpt_preview_snapshot.gd")
const Query = preload("res://scripts/sculpt_next_layer.gd")
const Job = preload("res://scripts/sculpt_preview_job.gd")
const Visual = preload("res://scripts/terrain_edit_preview.gd")
const Buffers = preload("res://scripts/terrain_preview_buffers.gd")
var checks := 0
var failures := 0

class SinkTool extends RefCounted:
	func paste(_origin: Vector3i, _buffer: Object, _mask: int) -> void: pass
class SinkTerrain extends Node:
	var sink := SinkTool.new()
	func get_voxel_tool() -> RefCounted: return sink

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var source := Native.new()
	source.patch_size = Vector3i(80, 64, 72)
	source.voxel_scale = 0.125
	source.voxels = ClassDB.instantiate("VoxelBuffer")
	source.voxels.create(80, 64, 72)
	source._backend_ready = true
	source.terrain = SinkTerrain.new()
	var query := Query.new()
	var visual := Visual.new()
	root.add_child(visual)
	for normal in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		for tool in ["raise", "dig", "level", "slope", "smooth"]:
			source.voxels.fill(0, 0)
			var center := Vector3(5, 4, 4.5)
			var axis: int = source._dominant_axis(normal) if tool in ["raise", "dig"] else 1
			var low := Vector3i.ZERO
			var high: Vector3i = source.patch_size
			if normal[axis] >= 0 or tool not in ["raise", "dig"]: high[axis] /= 2
			else: low[axis] = high[axis] / 2
			source.voxels.fill_area(65535, low, high, 0)
			var settings := {"radius": 0.5, "strength": 2.0, "falloff": 0.45, "surface_normal": normal}
			var plane := {"valid": true, "point": center, "normal": Vector3.UP, "slope_x": 0.25 if tool == "slope" else 0.0, "slope_z": 0.0}
			var expected: Dictionary = query.plan(source, tool, center, settings, plane)
			var frozen: RefCounted = Snapshot.capture(source, tool, center, settings, plane)
			check(frozen.copied_bytes < 80 * 64 * 72 * 2, "snapshot is brush local")
			var before: PackedByteArray = source.voxels.get_channel_as_byte_array(0)
			var actual: Dictionary = Job._compute(frozen, tool, center, settings, plane)
			check(actual.get("changes", []) == expected.changes, "snapshot parity %s %s" % [tool, normal])
			check(actual.get("rim", []) == expected.rim, "snapshot rim parity")
			check(frozen.voxels.out_of_bounds_reads == 0, "snapshot covers every integrator read")
			check(before == source.voxels.get_channel_as_byte_array(0), "worker input read-only")
			visual.show_plan(actual)
			var packed: Dictionary = actual["packed"]
			check(packed.cells.size() == expected.changes.size(), "packed cells complete")
			for i in expected.changes.size():
				var change: Dictionary = expected.changes[i]
				var layer: MultiMesh = visual.removals.multimesh if int(change.after) == 0 else visual.additions.multimesh
				# Every fixture here has only additions or only removals.
				if layer.visible_instance_count != expected.changes.size(): break
				var point := (Vector3(change.cell) + Vector3.ONE * 0.5) * 0.125
				if int(change.after) == 0: point += expected.normal * 0.125 * 0.515
				check(layer.get_instance_transform(i).origin.is_equal_approx(point), "bulk transform layout")
				check(layer.get_instance_color(i).a > 0.0, "bulk color layout")
	# Freeze an active brush, then mutate/cancel the live terrain. Worker
	# still sees the original snapshot and owns its own copied metadata.
	source.voxels.fill(0, 0)
	source.voxels.fill_area(2, Vector3i.ZERO, Vector3i(80, 32, 72), 0)
	var settings := {"radius": 0.5, "strength": 2.0, "falloff": 0.45}
	var center := Vector3(5, 4, 4.5)
	source.begin_stroke("dig", center, settings)
	source.update_stroke(center, 0.1)
	var expected: Dictionary = query.plan(source, "dig", center, settings)
	var frozen: RefCounted = Snapshot.capture(source, "dig", center, settings)
	source.update_stroke(center, 0.1)
	source.cancel_stroke()
	check(Job._compute(frozen, "dig", center, settings, {}).changes == expected.changes, "active snapshot independent after cancel")
	var job := Job.new()
	var key: Array = [1, "dig", center]
	check(job.update(source, "dig", center, settings, {}, key).is_empty(), "first request returns pending without waiting")
	var count: int = job.query_count
	for _i in 50: job.update(source, "dig", center, settings, {}, [2])
	check(job.query_count <= count + 1, "single-flight has no queued backlog")
	job.invalidate()
	await create_timer(0.1).timeout
	var result: Dictionary = {}
	var deadline := Time.get_ticks_msec() + 3000
	while result.is_empty() and Time.get_ticks_msec() < deadline:
		result = job.update(source, "dig", center, settings, {}, [3])
		await process_frame
	check(not result.is_empty(), "latest request eventually published")
	check(job.discarded_count > 0 and job._ready_key == [3], "stale aim/context generation discarded")
	count = job.query_count
	for _i in 10: job.update(source, "dig", center, settings, {}, [3])
	check(job.query_count == count, "idle exact result cached")
	job.close()
	visual.queue_free()
	query.free()
	source.terrain.free()
	source.free()
	await process_frame
	print("sculpt_preview_job_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
