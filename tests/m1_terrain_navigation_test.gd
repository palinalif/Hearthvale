extends SceneTree
## Complete scene, real native Raise, held input, release, then leave the hill.
## Numeric camera assertions are not a physical Thor comfort/performance verdict.
var scene: Node
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)

func _button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func _top_at(x: float, z: float) -> float:
	var unit: float = scene.backend.voxel_scale
	var patch: Vector3i = scene.backend.patch_size
	for y in range(patch.y - 1, -1, -1):
		if scene.backend.voxel_at(Vector3i(floori(x / unit), y, floori(z / unit))) != 0:
			return float(y + 1) * unit
	return -1.0

func _tick(dt: float, sculpt: bool = false) -> void:
	scene._read_camera_and_cursor(dt)
	if sculpt: scene.backend.update_stroke(scene.cursor + scene.stroke_aim_offset, dt)
	scene._update_camera()

func _run() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://terrain-navigation-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "exported native scene ready")
	if not scene._player_restored: _finish(); return
	scene.set_process(false)
	var ground := _top_at(30.0, 28.0)
	check(ground > 0.0, "open field fixture has ground")
	check(scene.backend.apply_sphere(Vector3(30, ground + 2.0, 28), 3.0, false), "native hill fixture created")
	var peak := _top_at(30.0, 28.0)
	check(peak > ground + 4.0, "hill is much higher than adjacent ground")
	scene.cursor = Vector3(30, peak, 28)
	scene.terrain_cursor = scene.cursor
	scene.camera_yaw = 0.0
	scene.camera_pitch = 0.45
	scene.camera_distance = 15.0
	scene._free_camera_valid = false
	scene._update_camera()
	scene._set_sculpt_tool("raise")
	scene.brush_radius = 0.5
	scene.set_brush_strength_level(10)
	scene._update_brush_preview()
	check(scene._terrain_target_valid, "raised hill is actually targetable")
	var camera_start: Vector3 = scene.camera.position
	var history_before: int = scene._history_tags.size()
	await _button(JOY_BUTTON_A, true)
	check(scene.stroke_active, "physical A starts real Raise")
	var max_vertical_change := 0.0
	for i in 120:
		_tick(1.0 / 60.0, true)
		max_vertical_change = maxf(max_vertical_change, absf(scene.camera.position.y - camera_start.y))
	var grown := _top_at(30.0, 28.0)
	check(grown > peak + 0.5, "terrain really grows, rather than a frozen test fixture")
	check(max_vertical_change < 0.0001, "stationary held Raise does not move camera height")
	Input.action_press("m1_move_right", 1.0)
	for i in 8: _tick(1.0 / 60.0, true)
	Input.action_release("m1_move_right")
	check(scene.camera.position.x > camera_start.x + 0.5, "horizontal camera travel remains available during Raise")
	check(absf(scene.camera.position.y - camera_start.y) < 0.0001, "moving Raise retains its starting camera elevation")
	await _button(JOY_BUTTON_A, false)
	check(not scene.stroke_active and scene._history_tags.size() == history_before + 1, "release commits exactly one terrain edit")
	for i in 120:
		_tick(1.0 / 60.0)
		for repeated in 3: scene._update_camera()
	check(absf(scene.camera.position.y - camera_start.y) < 0.0001, "release and repeated camera updates never chase the new summit")

	Input.action_press("m1_move_right", 1.0)
	var max_step := 0.0
	for i in 36:
		var previous: float = scene.camera.position.y
		_tick(1.0 / 60.0)
		max_step = maxf(max_step, absf(scene.camera.position.y - previous))
	Input.action_release("m1_move_right")
	var lower := _top_at(scene.cursor.x, scene.cursor.z)
	check(lower < peak - 2.0, "controller travel leaves the hill for lower terrain")
	check(absf(scene.cursor.y - lower) < 0.0001, "aim follows ground on the new column, not the old high point")
	check(max_step <= 3.0 / 60.0 + 0.0001, "height navigation has a bounded speed on steep transitions")
	scene._update_brush_preview()
	check(scene._terrain_target_valid and absf(scene._terrain_target_point.y - lower) < 0.001, "preview reacquires lower ground without a mode toggle")
	check(Vector2(scene._terrain_target_point.x - scene.cursor.x, scene._terrain_target_point.z - scene.cursor.z).length() < 0.001, "preview does not snap sideways to a neighbouring peak")
	for i in 240: _tick(1.0 / 60.0)
	check(absf(scene._free_camera_y - (lower + 2.0)) < 0.05, "navigation camera settles down rather than remaining at summit height")

	# Camera changes never modify native terrain/history, or take over a wall aim.
	var revision: int = scene.backend.stats().revision
	var wall_y: float = scene.cursor.y + 1.0
	scene.reference_mode = "wall"
	scene.cursor.y = wall_y
	Input.action_press("m1_move_right", 0.3)
	_tick(0.1)
	Input.action_release("m1_move_right")
	check(is_equal_approx(scene.cursor.y, wall_y), "wall-reference navigation is not forced onto ground")
	check(scene.backend.stats().revision == revision, "camera/navigation does not edit terrain")
	scene.reference_mode = "ground"
	scene._set_view_context("building")
	var before_exit: Transform3D = scene.camera.global_transform
	scene._set_view_context("terrain")
	scene._update_camera()
	check(scene.camera.global_transform.is_equal_approx(before_exit), "accepted cottage exit still preserves the view")
	_finish()

func _finish() -> void:
	Input.action_release("m1_move_right")
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m1_terrain_navigation_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
