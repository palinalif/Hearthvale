extends SceneTree

const Scene = preload("res://scripts/m1_scene.gd")
var scene: Node
var results: Dictionary = {}

func _initialize() -> void:
	scene = Scene.new(); scene.test_mode = true
	scene.checkpoint_root = "user://m1-profile-%d" % Time.get_ticks_usec()
	root.add_child(scene)
	while scene.backend == null or not scene.backend.is_ready(): await process_frame
	for i in 120: await process_frame
	await _sample("idle", 180)
	scene._begin_stroke()
	await _sample("sculpt", 180)
	scene._end_stroke()
	scene._set_view_context("building")
	scene._begin_resize()
	await _sample("resize", 120)
	scene._cancel_resize()
	results["renderer"] = ProjectSettings.get_setting("rendering/renderer/rendering_method")
	results["adapter"] = RenderingServer.get_video_adapter_name()
	results["resolution"] = str(root.size)
	results["physical_thor"] = "not run"
	print(JSON.stringify(results))
	scene._quit_cleanly()

func _sample(label: String, frames: int) -> void:
	var elapsed: Array[float] = []
	var rebuild: Array[float] = []
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
	elapsed.sort(); rebuild.sort()
	results[label] = {"samples": frames, "frame_ms_p50": elapsed[frames / 2], "frame_ms_p95": elapsed[int(frames * 0.95)], "frame_ms_max": elapsed[-1], "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "godot_static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC)}
	if not rebuild.is_empty(): results[label]["presentation_cpu_ms_p95"] = rebuild[int(rebuild.size() * 0.95)]
