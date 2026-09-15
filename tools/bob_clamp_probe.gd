extends SceneTree
## Measures the EFFECTIVE live camera pitch clamp of the real M1/M2 scene chain.
## Run:
##   timeout 600 /opt/data/tools/godot/Godot_v4.7.2-stable_linux.x86_64 \
##     --headless --max-fps 60 --path . --script tools/bob_clamp_probe.gd
##
## It drives the live input path exactly like the pad does
## (`_read_camera_and_cursor`, the most-derived override on the live chain, which
## cascades through every per-file clamp via super) while holding the orbit
## action, then reports the pitch the camera settles at. Those settled values ARE
## the effective clamp the player can reach — not the per-file literals.

const HOLD_FRAMES := 240
const STEP := 0.1

var scene: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://clamp-probe-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline: int = Time.get_ticks_msec() + 90000
	while (not scene._player_restored or not scene.backend or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not scene._player_restored:
		print("CLAMP_PROBE scene not ready")
		quit(2)
		return
	scene.set_process(false)
	print("CLAMP_PROBE start_pitch=%.4f yaw=%.4f distance=%.2f" % [scene.camera_pitch, scene.camera_yaw, scene.camera_distance])

	# Orbit "up" (stick up) reduces pitch: this is the direction that reveals sky.
	Input.action_press("m1_orbit_up", 1.0)
	for _i in HOLD_FRAMES:
		scene._read_camera_and_cursor(STEP)
	Input.action_release("m1_orbit_up")
	var lowest: float = scene.camera_pitch
	print("CLAMP_PROBE min_pitch=%.4f (%s)" % [lowest, "orbit_up held %d frames" % HOLD_FRAMES])

	# Orbit "down" raises pitch: the downward limit stays as it was.
	Input.action_press("m1_orbit_down", 1.0)
	for _i in HOLD_FRAMES:
		scene._read_camera_and_cursor(STEP)
	Input.action_release("m1_orbit_down")
	var highest: float = scene.camera_pitch
	print("CLAMP_PROBE max_pitch=%.4f" % highest)

	# Mouse orbit path (PC input) uses its own clamp: drag the mouse up.
	for _i in 80:
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(0, -2000)
		scene._input(motion)
	print("CLAMP_PROBE mouse_up_pitch=%.4f" % scene.camera_pitch)
	print("CLAMP_PROBE attributes=%s" % str(scene.camera.attributes))
	if scene.camera.attributes is CameraAttributesPractical:
		var practical: CameraAttributesPractical = scene.camera.attributes
		print("CLAMP_PROBE dof near_enabled=%s near_dist=%.2f near_trans=%.2f far_enabled=%s far_dist=%.2f far_trans=%.2f amount=%.3f" % [
			str(practical.dof_blur_near_enabled), practical.dof_blur_near_distance, practical.dof_blur_near_transition,
			str(practical.dof_blur_far_enabled), practical.dof_blur_far_distance, practical.dof_blur_far_transition, practical.dof_blur_amount])
	print("CLAMP_PROBE done")
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	quit(0)
