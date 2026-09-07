extends SceneTree
## Real continuously changing requests, not step-and-settle microbenchmarks.
## Coverage is diagnostic: zero current previews is NOT interaction acceptance.
const Native = preload("res://scripts/terrain_backend.gd")
const Job = preload("res://scripts/sculpt_preview_job.gd")
var checks := 0
var failures := 0
class SinkTool extends RefCounted:
	func paste(_origin: Vector3i, _buffer: Object, _mask: int) -> void: pass
class SinkTerrain extends Node:
	func get_voxel_tool() -> RefCounted: return SinkTool.new()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var source := Native.new()
	source.patch_size = Vector3i(384, 256, 384)
	source.voxel_scale = 0.125
	source.voxels = ClassDB.instantiate("VoxelBuffer")
	source.voxels.create(384, 256, 384)
	source.voxels.fill_area(2, Vector3i.ZERO, Vector3i(384, 80, 384), 0)
	source._backend_ready = true
	source.terrain = SinkTerrain.new()
	for radius in [2.0, 8.0]:
		for phase in ["continuous_aim", "continuous_hold"]:
			var job := Job.new()
			var center := Vector3(24, 10, 24)
			var settings := {"radius": radius, "strength": 2.0, "falloff": 0.45}
			if phase == "continuous_hold": source.begin_stroke("dig", center, settings)
			var current_frames := 0
			var services: Array[float] = []
			var key: Array = []
			for frame in 90:
				await process_frame
				if phase == "continuous_aim": center.x += 0.0125
				else: source.update_stroke(center, 1.0 / 60.0)
				key = [center, source._revision, source._stroke_mutations, source._stroke_active, settings]
				var started := Time.get_ticks_usec()
				var plan: Dictionary = job.update(source, "dig", center, settings, {}, key)
				services.append((Time.get_ticks_usec() - started) / 1000.0)
				if not plan.is_empty():
					current_frames += 1
					check(job._ready_key == key, "published plan matches current request exactly")
					check(not plan.has("changes") and plan.has("packed"), "only compact output crosses worker boundary")
			var stopped := Time.get_ticks_usec()
			var deadline := Time.get_ticks_msec() + 4000
			var settled: Dictionary = {}
			while settled.is_empty() and Time.get_ticks_msec() < deadline:
				await process_frame
				settled = job.update(source, "dig", center, settings, {}, key)
			check(not settled.is_empty(), "latest request recovers after motion stops")
			services.sort()
			print("PREVIEW_LIVE " + JSON.stringify({"radius": radius, "phase": phase, "frames": 90, "current_frames": current_frames, "current_fraction": float(current_frames) / 90.0, "service_p95_ms": services[85], "service_max_ms": services[89], "settle_ms": (Time.get_ticks_usec() - stopped) / 1000.0, "discarded": job.discarded_count, "requests": job.query_count, "interaction_acceptance": "NOT ESTABLISHED"}))
			job.close()
			if phase == "continuous_hold": source.cancel_stroke()
	source.terrain.free()
	source.free()
	print("sculpt_preview_live_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
