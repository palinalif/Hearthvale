extends SceneTree

const HouseMassing = preload("res://scripts/m2_house_massing.gd")
const BASELINE_PATH := "res://tests/performance/m2_mobile_performance_baseline.json"
const WARMUP_FRAMES := 90
const SAMPLE_FRAMES := 120
const CATALOGUE_FRAMES := 90
const MOVING_SECTION_FRAMES := 60

var scene: Node
var checks := 0
var failures := 0
var _section_base := Vector3.ZERO
var _section_update_cpu_ms: Array[float] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var rendering := "--require-rendering" in OS.get_cmdline_user_args()
	check(rendering, "performance guard requires explicit rendering mode")
	if rendering:
		check(DisplayServer.get_name() != "headless", "real display server required")
		check(RenderingServer.get_current_rendering_method() == "mobile", "Mobile renderer required")
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var baseline := _load_baseline()
	check(not baseline.is_empty(), "performance baseline loads")
	if baseline.is_empty():
		_finish()
		return

	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-mobile-perf-%d" % Time.get_ticks_usec()
	root.add_child(scene)

	var deadline := Time.get_ticks_msec() + 120000
	while not scene._player_restored and Time.get_ticks_msec() < deadline:
		await process_frame
	check(scene._player_restored, "performance scene ready")
	if not scene._player_restored:
		await _finish()
		return

	scene._set_view_context("building")
	await _wait_frames(WARMUP_FRAMES)

	var idle := await _sample_frames(SAMPLE_FRAMES)
	var camera := await _sample_frames(SAMPLE_FRAMES, Callable(self, "_camera_step"))

	scene._open_build_browser("windows")
	await _wait_frames(12)
	check(scene._browser_open, "build catalogue opens for benchmark")
	var catalogue := await _sample_frames(CATALOGUE_FRAMES)
	scene._close_build_browser()
	await _wait_frames(12)

	scene._begin_portion_placement()
	check(scene.portion_placement_active, "section placement starts for benchmark")
	if not scene.portion_placement_active:
		await _finish()
		return
	_section_base = scene.portion_offset
	await _wait_frames(12)

	var section_stationary := await _sample_frames(SAMPLE_FRAMES)
	_section_update_cpu_ms.clear()
	var section_moving := await _sample_frames(MOVING_SECTION_FRAMES, Callable(self, "_section_move_step"))

	scene.portion_offset = _section_base
	scene._update_portion_preview()
	check(scene.portion_valid, "baseline section candidate remains valid")
	var commit_start := Time.get_ticks_usec()
	var committed: bool = scene._commit_portion_placement()
	var commit_ms := float(Time.get_ticks_usec() - commit_start) / 1000.0
	check(committed, "section benchmark commit succeeds")
	await _wait_frames(12)

	var idle_p95 := maxf(0.001, float(idle["p95_ms"]))
	var idle_median := maxf(0.001, float(idle["median_ms"]))
	var metrics := {
		"idle": idle,
		"camera": camera,
		"catalogue": catalogue,
		"section_stationary": section_stationary,
		"section_moving": section_moving,
		"section_update_cpu_p95_ms": _percentile(_section_update_cpu_ms, 0.95),
		"section_commit_ms": commit_ms,
	}
	var normalized := {
		"camera_p95_vs_idle": float(camera["p95_ms"]) / idle_p95,
		"catalogue_p95_vs_idle": float(catalogue["p95_ms"]) / idle_p95,
		"section_stationary_p95_vs_idle": float(section_stationary["p95_ms"]) / idle_p95,
		"section_moving_p95_vs_idle": float(section_moving["p95_ms"]) / idle_p95,
		"section_update_cpu_p95_vs_idle_median": _percentile(_section_update_cpu_ms, 0.95) / idle_median,
		"section_commit_vs_idle_median": commit_ms / idle_median,
	}

	var allowed := float(baseline.get("allowed_regression_fraction", 0.20))
	var budgets: Dictionary = baseline.get("normalized_budgets", {})
	for key in budgets:
		var observed := float(normalized.get(key, INF))
		var expected := float(budgets[key])
		var limit := expected * (1.0 + allowed)
		check(observed <= limit, "%s %.3fx <= %.3fx normalized budget" % [key, observed, limit])

	var result := {
		"ok": failures == 0,
		"checks": checks,
		"failures": failures,
		"renderer": RenderingServer.get_current_rendering_method(),
		"display": DisplayServer.get_name(),
		"resolution": root.get_visible_rect().size,
		"metrics": metrics,
		"normalized": normalized,
		"allowed_regression_fraction": allowed,
		"normalized_budgets": budgets,
	}
	DirAccess.make_dir_recursive_absolute(".tools/performance")
	var receipt := FileAccess.open(".tools/performance/m2-mobile-performance.json", FileAccess.WRITE)
	if receipt:
		receipt.store_string(JSON.stringify(result, "\t"))
		receipt.close()
	print("M2_PERFORMANCE_RESULT " + JSON.stringify(result))
	await _finish()

func _camera_step(_index: int) -> void:
	scene.camera_yaw += 0.012
	scene._update_camera()

func _section_move_step(index: int) -> void:
	var offset := HouseMassing.CELL if index % 2 == 0 else 0.0
	scene.portion_offset = _section_base + Vector3(0.0, 0.0, offset)
	var started := Time.get_ticks_usec()
	scene._update_portion_preview()
	_section_update_cpu_ms.append(float(Time.get_ticks_usec() - started) / 1000.0)

func _sample_frames(count: int, before_frame: Callable = Callable()) -> Dictionary:
	var times: Array[float] = []
	for i in count:
		var started := Time.get_ticks_usec()
		if before_frame.is_valid():
			before_frame.call(i)
		await RenderingServer.frame_post_draw
		times.append(float(Time.get_ticks_usec() - started) / 1000.0)
	return _stats(times)

func _wait_frames(count: int) -> void:
	for _i in count:
		await RenderingServer.frame_post_draw

func _stats(values: Array[float]) -> Dictionary:
	var median := _percentile(values, 0.50)
	var p95 := _percentile(values, 0.95)
	var p99 := _percentile(values, 0.99)
	return {
		"samples": values.size(),
		"median_ms": median,
		"p95_ms": p95,
		"p99_ms": p99,
		"median_fps": 1000.0 / maxf(0.001, median),
		"p95_fps_equivalent": 1000.0 / maxf(0.001, p95),
	}

func _percentile(values: Array[float], percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var ordered := values.duplicate()
	ordered.sort()
	var index := clampi(int(ceil(float(ordered.size()) * percentile)) - 1, 0, ordered.size() - 1)
	return float(ordered[index])

func _load_baseline() -> Dictionary:
	var text := FileAccess.get_file_as_string(BASELINE_PATH)
	if text.is_empty():
		push_error("FAIL: missing performance baseline at " + BASELINE_PATH)
		return {}
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("FAIL: invalid performance baseline JSON")
		return {}
	return parsed as Dictionary

func _finish() -> void:
	if is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m2_mobile_performance_guard checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
