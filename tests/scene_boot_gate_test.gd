# tests/scene_boot_gate_test.gd — COMMIT BLOCKER.
# Instantiates the real gameplay scene the way the render tests do, and hard-fails
# if _build_world() ever aborts (a runtime property crash leaves no WorldEnvironment
# child — that is exactly how the Godot-3-named golden-hour code survived 4 runs).
# Runs headless with the Mobile renderer: no display, no Xvfb, no screenshot.
extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "mobile":
		push_error("scene boot gate requires the actual Mobile renderer")
		quit(2)
		return
	var scene: Node = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://boot-gate-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline:
		await process_frame
	check(scene._player_restored, "gameplay scene ready (no _build_world abort)")
	if not scene._player_restored:
		print("checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	var world_envs: Array = scene.find_children("", "WorldEnvironment", true, false)
	check(world_envs.size() >= 1, "WorldEnvironment live in scene tree")
	if world_envs.size() >= 1:
		var env: Environment = (world_envs[0] as WorldEnvironment).environment
		if env != null:
			check(env.background_mode == Environment.BG_SKY, "background = sky")
			check(env.sky != null and env.sky.sky_material != null, "sky material attached")
		else:
			check(false, "WorldEnvironment.environment set")
	print("checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
