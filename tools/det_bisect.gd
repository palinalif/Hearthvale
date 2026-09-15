extends SceneTree
## Determinism bisection harness (scene-side diagnosis, NOT a graded gate test).
## Boots the REAL m1.tscn once (Mobile renderer, Xvfb display required), reuses
## the EXACT capture pipeline of the failing gate test (4x frame_post_draw +
## root.get_texture().get_image()), and re-captures the SAME recipe N times
## while mutating the LIVE WorldEnvironment's environment properties.
##
## For every variant: IDENTICAL if second and third capture are byte-equal.
## A variant whose env props still produce a diff = determinism breaker.
##
## Usage (render test env, NOT headless):
##   DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 <engine> --max-fps 60 --renderer mobile \
##     --path . --script tools/det_bisect.gd
## Prints: BIS_VARIANT <id> IDENTICAL|DIFF changed=<px>  and  DONE

var scene: Node

func _initialize() -> void:
	call_deferred("_run")

func _capture() -> Image:
	for i in 4: await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _changed(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size():
		return a.get_width() * a.get_height()
	var ad := a.get_data()
	var bd := b.get_data()
	var changed := 0
	for offset in range(0, ad.size(), 4):
		if ad[offset] != bd[offset] or ad[offset+1] != bd[offset+1] \
				or ad[offset+2] != bd[offset+2] or ad[offset+3] != bd[offset+3]:
			changed += 1
	return changed

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("BISECT_UNAVAILABLE headless")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://det-bisect-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 120000
	while (not scene._player_restored or not scene.backend or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline:
		await process_frame
	print("BISECT_BOOT ready=%s method=%s" % [str(scene._player_restored and scene.backend.is_ready()), RenderingServer.get_current_rendering_method()])
	if not (scene._player_restored and scene.backend and scene.backend.is_ready()):
		_finish()
		return
	scene.set_process(false)
	scene._set_view_context("building")
	scene._update_presentation()
	if scene.hud: scene.hud.visible = false
	scene.camera_yaw = PI * 0.6
	scene.camera_pitch = 0.35
	scene.camera_distance = 14.0
	scene._update_camera()
	await _capture()

	var envs := scene.find_children("", "WorldEnvironment", true, false)
	if envs.is_empty():
		print("BISECT_NO_ENV")
		_finish()
		return
	# Deterministic mutation path: grab the environment reference up front.
	var env: Environment = (envs[0] as WorldEnvironment).environment
	if env == null:
		print("BISECT_NO_ENV_RES")
		_finish()
		return
	var golden_sky = env.sky
	var golden_fog := [env.fog_light_color, env.fog_density, env.fog_sky_affect, env.fog_depth_begin, env.fog_depth_end]
	var golden_glow := [env.glow_enabled, env.glow_intensity, env.glow_bloom, env.glow_blend_mode]
	print("BISECT_GOLDEN fog_density=%f fog_begin=%.1f fog_end=%.1f glow=%f/%f" % [
		golden_fog[1], golden_fog[3], golden_fog[4], golden_glow[1], golden_glow[2]])

	# --- Run the matrix -------------------------------------------------------
	# Each row: id | fog | tone | glow | sky | grade  (1 = golden value, 0 = off/default)
	var rows: Array = [
		["A_baseline_all_on", 1, 1, 1, 1, 1],
		["B_no_fog", 0, 1, 1, 1, 1],
		["J_all_off", 0, 0, 0, 0, 0],
	]
	for row in rows:
		var rid: String = row[0]
		var fog_on: bool = (row[1] == 1)
		var tone_on: bool = (row[2] == 1)
		var glow_on: bool = (row[3] == 1)
		var sky_on: bool = (row[4] == 1)
		var grade_on: bool = (row[5] == 1)
		# Apply environment state.
		env.sky = golden_sky if sky_on else null
		env.background_mode = Environment.BG_SKY if sky_on else Environment.BG_COLOR
		env.background_color = Color("#f2d9a4")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if sky_on else Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("#cbbd9a")
		env.ambient_light_energy = 1.0
		env.ambient_light_sky_contribution = 1.0
		env.fog_enabled = fog_on
		env.fog_light_color = golden_fog[0]
		env.fog_density = golden_fog[1]
		env.fog_sky_affect = golden_fog[2]
		env.fog_depth_begin = golden_fog[3]
		env.fog_depth_end = golden_fog[4]
		env.glow_enabled = glow_on
		env.glow_intensity = golden_glow[1]
		env.glow_bloom = golden_glow[2]
		env.glow_blend_mode = golden_glow[3]
		env.tonemap_mode = Environment.TONE_MAPPER_ACES if tone_on else Environment.TONE_MAPPER_LINEAR
		env.tonemap_exposure = 1.05 if tone_on else 1.0
		env.tonemap_white = 1.35 if tone_on else 1.0
		env.adjustment_enabled = grade_on
		env.adjustment_saturation = 1.06 if grade_on else 1.0
		env.adjustment_contrast = 1.04 if grade_on else 1.0
		env.adjustment_brightness = 1.02 if grade_on else 1.0
		await _capture()
		var img1 := await _capture()
		var img2 := await _capture()
		var diff := _changed(img1, img2)
		var verdict := "IDENTICAL" if diff == 0 else "DIFF"
		print("BISECT %s %s changed=%d" % [rid, verdict, diff])

	# Leave the env at baseline for any downstream reads.
	_finish()

func _finish() -> void:
	print("BISECT DONE")
	quit(0)
