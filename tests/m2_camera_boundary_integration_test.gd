extends SceneTree
## Actual shipping scene and native backend; never reads or writes player saves.
var failures := 0
var checks := 0
var scene: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	scene = load("res://scenes/m1.tscn").instantiate()
	scene.checkpoint_root = "user://m2-camera-boundary-integration-%s" % Time.get_ticks_usec()
	scene.test_mode = true
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 60000
	while (scene.backend == null or not scene.backend.is_ready() or not scene._player_restored) and Time.get_ticks_msec() < deadline:
		await process_frame
	if scene.backend == null or not scene.backend.is_ready() or not scene._player_restored:
		_check(false, "native scene becomes ready in isolated test root")
		await _finish()
		return
	scene.set_process(false)
	var before_buildings := JSON.stringify(scene.building_world.get_document())
	var before_landscape := JSON.stringify(scene.landscape_state.document())
	scene.view_context = "building"
	scene.camera_yaw = -PI * 0.5
	scene.camera_pitch = 0.08
	scene.camera_distance = 28.0
	scene._update_camera()
	var target: Vector3 = scene._selected_building_camera_target()
	_check((scene._bounded_camera_focus as Vector3).is_equal_approx(target), "native house remains camera focus")
	_check(scene.camera.position.distance_to(target) < 27.99, "fixture actually reaches a clamped camera edge")
	_check(scene._set_view_context("terrain", "camera boundary integration"), "leave house editing at boundary")
	scene._update_camera()
	_check((scene._bounded_camera_focus as Vector3).is_equal_approx(target), "mode switch retains real focus rather than extrapolating zoom")
	_check(is_equal_approx(float(scene.camera_distance), 28.0), "mode switch retains desired zoom")
	_check(is_equal_approx(float(scene.camera_yaw), -PI * 0.5) and is_equal_approx(float(scene.camera_pitch), 0.08), "mode switch retains requested orbit")
	var extent: Vector3 = scene.backend.world_size()
	_check(_in_bounds(scene.camera.position, extent), "camera stays in bounds after mode switch")
	_check(_in_bounds(scene.cursor, extent), "cursor stays in bounds after mode switch")
	# The border remains safe for a straight-down clamped view; no degenerate
	# look_at or non-finite transform is allowed at the exact inset corner.
	scene._position_bounded_camera(Vector3(0.25, 10, 0.25), Vector3(-10, 8, -10))
	_check(scene.camera.global_basis.is_finite(), "exact inset corner has finite camera orientation")
	_check((-scene.camera.global_basis.z).normalized().dot(Vector3.DOWN) > 0.999, "exact inset corner still looks at its subject")
	_check(JSON.stringify(scene.building_world.get_document()) == before_buildings, "camera leaves building authority unchanged")
	_check(JSON.stringify(scene.landscape_state.document()) == before_landscape, "camera leaves landscape authority unchanged")
	await _finish()

func _in_bounds(point: Vector3, extent: Vector3) -> bool:
	return point.is_finite() and point.x >= 0.0 and point.x <= extent.x and point.z >= 0.0 and point.z <= extent.z

func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	print("FAIL: " + label)

func _finish() -> void:
	if is_instance_valid(scene): scene.queue_free()
	await process_frame
	await process_frame
	print(JSON.stringify({"ok": failures == 0, "failures": failures, "checks": checks, "native_camera_boundary": true}))
	quit(1 if failures else 0)
