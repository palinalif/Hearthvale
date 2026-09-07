extends SceneTree
const Native = preload("res://scripts/terrain_backend.gd")
const Job = preload("res://scripts/sculpt_preview_job.gd")
const Visual = preload("res://scripts/terrain_edit_preview.gd")
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
	source.patch_size = Vector3i(384, 256, 384)
	source.voxel_scale = 0.125
	source.voxels = ClassDB.instantiate("VoxelBuffer")
	source.voxels.create(384, 256, 384)
	source.voxels.fill_area(2, Vector3i.ZERO, Vector3i(384, 80, 384), 0)
	source._backend_ready = true
	source.terrain = SinkTerrain.new()
	var visual := Visual.new()
	root.add_child(visual)
	for radius in [2.0, 8.0]:
		for phase in ["cold", "moving", "held"]:
			var job := Job.new()
			var capture_times: Array[float] = []
			var service_times: Array[float] = []
			var publish_times: Array[float] = []
			var latencies: Array[float] = []
			var worker_times: Array[float] = []
			var pack_times: Array[float] = []
			var settings := {"radius": radius, "strength": 2.0, "falloff": 0.45}
			var center := Vector3(24, 10, 24)
			if phase == "held": source.begin_stroke("dig", center, settings)
			var cell_count := 0
			for sample in 5:
				if phase == "cold": job.invalidate()
				if phase == "moving": center.x += 0.125
				if phase == "held": source.update_stroke(center, 1.0 / 16.0)
				var key: Array = [phase, sample, source._stroke_mutations]
				var wall_start := Time.get_ticks_usec()
				var call_start := wall_start
				var plan: Dictionary = job.update(source, "dig", center, settings, {}, key)
				capture_times.append((Time.get_ticks_usec() - call_start) / 1000.0)
				var deadline := Time.get_ticks_msec() + 4000
				while plan.is_empty() and Time.get_ticks_msec() < deadline:
					await process_frame
					call_start = Time.get_ticks_usec()
					plan = job.update(source, "dig", center, settings, {}, key)
					service_times.append((Time.get_ticks_usec() - call_start) / 1000.0)
				check(not plan.is_empty(), "preview service finishes bounded request")
				if plan.is_empty(): break
				latencies.append((Time.get_ticks_usec() - wall_start) / 1000.0)
				visual.show_plan(plan)
				publish_times.append(visual.last_build_ms)
				worker_times.append(job.last_query_ms)
				pack_times.append(job.last_pack_ms)
				cell_count = plan.packed.cells.size()
			check(cell_count > 9, "full fine-grid footprint retained")
			# Immediate live-frontier calls have no poll phase; zero is the correct
			# poll cost, not infinity. The first-call budget covers their complete
			# synchronous query+pack cost.
			var poll_p95 := 0.0 if service_times.is_empty() else _percentile(service_times, 0.95)
			check(_percentile(capture_times, 0.8) < 12.0, "first preview service stays below 12ms p80")
			check(poll_p95 < 2.0, "nonblocking async poll p95 below 2ms")
			check(_percentile(publish_times, 0.8) < 4.0, "bulk publication below 4ms p80")
			print("PREVIEW_PERF " + JSON.stringify({"radius": radius, "phase": phase, "samples": latencies.size(), "cells": cell_count, "snapshot_bytes": job.last_snapshot_bytes, "capture_ms": capture_times, "poll_p95_ms": poll_p95, "upload_ms": publish_times, "worker_query_ms": worker_times, "worker_pack_ms": pack_times, "response_ms": latencies}))
			job.close()
			if phase == "held": source.cancel_stroke()
	source.terrain.free()
	source.free()
	visual.queue_free()
	await process_frame
	print("sculpt_preview_performance_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _percentile(values: Array[float], percentile: float) -> float:
	if values.is_empty(): return 0.0
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[mini(ordered.size() - 1, int(float(ordered.size()) * percentile))]
