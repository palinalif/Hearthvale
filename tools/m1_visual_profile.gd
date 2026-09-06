extends SceneTree

const Scene = preload("res://scripts/m1_scene.gd")
var scene: Node
var results: Dictionary = {}

func _initialize() -> void:
	scene = Scene.new(); scene.test_mode = true
	scene.checkpoint_root = "user://m1-profile-%d" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 20000
	while (scene.backend == null or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline: await process_frame
	if scene.backend == null or not scene.backend.is_ready():
		print("PROFILE NOT READY " + str(scene.backend.stats() if scene.backend else {})); quit(1); return
	print("PROFILE ready")
	for i in 30: await process_frame
	await _sample("idle", 60)
	var sculpt_revision: int = scene.backend.stats()["revision"]
	scene._begin_stroke()
	results["sculpt_began"] = scene.stroke_active
	print("PROFILE sculpt_began=%s" % scene.stroke_active)
	await _sample("sculpt", 60)
	results["sculpt_changed_cells"] = scene.backend.get_stroke_state()["changed_count"]
	scene._end_stroke()
	results["sculpt_committed"] = scene.backend.stats()["revision"] > sculpt_revision
	scene._set_view_context("building")
	scene._begin_resize()
	await _sample("resize", 30)
	scene._cancel_resize()
	results["renderer"] = ProjectSettings.get_setting("rendering/renderer/rendering_method")
	results["adapter"] = RenderingServer.get_video_adapter_name()
	results["resolution"] = str(root.size)
	results["physical_thor"] = "not run"
	print(JSON.stringify(results))
	scene._quit_cleanly()

func _sample(label: String, frames: int) -> void:
	print("PROFILE phase=" + label)
	var elapsed: Array[float] = []
	var rebuild: Array[float] = []
	var sculpt_cpu: Array[float] = []
	var preview_cpu: Array[float] = []
	for i in frames:
		var start := Time.get_ticks_usec()
		if label == "resize":
			scene.resize_preview_dimensions.x = 18.0 + float(i % 12) * 0.5
			var before := Time.get_ticks_usec()
			scene._update_presentation()
			rebuild.append(float(Time.get_ticks_usec() - before) / 1000.0)
		if label == "sculpt": scene.cursor.x += 0.008
		await process_frame
		elapsed.append(float(Time.get_ticks_usec() - start) / 1000.0)
		sculpt_cpu.append(float(scene.last_frame_costs.get("sculpt_ms", 0)))
		preview_cpu.append(float(scene.last_frame_costs.get("preview_ms", 0)))
	print("PROFILE completed=" + label)
	elapsed.sort(); rebuild.sort(); sculpt_cpu.sort(); preview_cpu.sort()
	results[label] = {"samples": frames, "sculpt_cpu_ms_p95": sculpt_cpu[int(frames * 0.95)], "preview_cpu_ms_p95": preview_cpu[int(frames * 0.95)], "frame_ms_p50": elapsed[frames / 2], "frame_ms_p95": elapsed[int(frames * 0.95)], "frame_ms_max": elapsed[-1], "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "godot_static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC)}
	if not rebuild.is_empty(): results[label]["presentation_cpu_ms_p95"] = rebuild[int(rebuild.size() * 0.95)]
