extends SceneTree
## Actual main-scene cold start, native Mobile captures and a real border edit.
## Uses a unique checkpoint root; player saves and the live scene are untouched.
const OUTPUT := "res://reports/screenshots/detailed-mountains"
var failures: Array[String] = []
var captures: Array[String] = []
# Phase timing: this shard sets the delivery run's wall time, and its cost was
# being read off the job wall alone. Record where the seconds actually go so
# the next optimization targets a measured phase rather than a guess.
var phase_ms := {}
var _phase_name := "boot"
var _phase_start_ms := 0

func _mark_phase(name: String) -> void:
	var now := Time.get_ticks_msec()
	phase_ms[_phase_name] = int(phase_ms.get(_phase_name, 0)) + (now - _phase_start_ms)
	_phase_name = name
	_phase_start_ms = now

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		if "--starter-render-child" in OS.get_cmdline_user_args():
			push_error("Real rendering was unavailable")
			quit(1)
			return
		var output: Array = []
		var result := OS.execute(OS.get_executable_path(), ["--path", ProjectSettings.globalize_path("res://"), "--rendering-method", "mobile", "--disable-vsync", "--max-fps", "60", "--script", "res://tests/m2_starter_render_test.gd", "--", "--starter-render-child"], output, true)
		for text in output: print(text)
		quit(result)
		return
	if RenderingServer.get_current_rendering_method() != "mobile":
		push_error("Capture did not use Mobile")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var scene = load("res://scenes/m1.tscn").instantiate()
	# Do not opt into a test-only starter: exercise the shipped default itself.
	scene.checkpoint_root = "user://m2-starter-render-%d" % Time.get_ticks_usec()
	root.add_child(scene)
	var boot_started := Time.get_ticks_msec()
	_phase_start_ms = boot_started
	var deadline := boot_started + 120000
	while not scene._player_restored and Time.get_ticks_msec() < deadline:
		await process_frame
		if scene.backend and not str(scene.backend.stats().get("error", "")).is_empty(): break
	print("STARTER_BOOT " + JSON.stringify({"elapsed_ms":Time.get_ticks_msec() - boot_started, "restored":scene._player_restored, "backend":scene.backend.stats() if scene.backend else {}}))
	_mark_phase("mesh")
	check(scene._player_restored, "Production main scene reached ready")
	if not scene._player_restored:
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		quit(1)
		return
	check(scene._starter_seeded, "Production cold start seeds the hamlet")
	check(scene.building_world.get_buildings().size() == 3, "Production cold start has three homes")
	# Native startup initially meshes only a small focus box. A panorama must
	# wait for the expanded viewer, otherwise captures contain floating water.
	# Full-valley meshing is time-sliced per rendered frame, and hosted Mobile
	# review runners sit at 1-2 fps, so this budget is wall-clock, not frames.
	# A hosted run exhausted 300s with the valley still unmeshed while all 11
	# captures themselves succeeded.
	# The product meshes a focus box around the camera and streams outward as the
	# camera moves: terrain_backend.startup_mesh_area uses startup_mesh_radius_world
	# = 12.0 with a 90s budget, then update_visual_focus keeps the streaming viewer
	# centred on the camera. It never promises a fully meshed 1280x256x1280 volume
	# at startup. Demanding that here made eleven captures pay for meshing the
	# entire world - about 1000s of a 1108s job - to assert a property the game
	# deliberately does not provide. Each capture now waits for the terrain its own
	# camera frames, which is the evidence the captures actually need: terrain in
	# frame, meshed. Full-world meshing is measured in the performance shard, where
	# it happens concurrently with the scenarios instead of gating every capture.
	_mark_phase("settle")
	await settle_frames(1500)
	scene.set_process(false)
	_mark_phase("capture")
	# The first two captures use the real initial camera without moving it.
	for home: Dictionary in scene.building_world.get_buildings():
		var transform_value: Transform3D = home["transform"]
		var point := transform_value.origin + Vector3.UP
		check(not scene.camera.is_position_behind(point), "Starter home faces the initial camera")
		check(Rect2(Vector2.ZERO, Vector2(root.size)).has_point(scene.camera.unproject_position(point)), "Starter home is framed at cold launch")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	await capture(scene, "opening-ui")
	scene.hud.visible = false
	for name in ["brush_preview", "cursor_reticle", "reference_plane", "terrain_hit_marker", "terrain_edit_preview"]:
		var node = scene.get(name)
		if node != null: node.visible = false
	await capture(scene, "normal")
	frame_scene(scene, Vector3(47.0, 9.25, 56.0), -1.9, 0.70, 15.0)
	await capture(scene, "commons-close")
	frame_scene(scene, Vector3(32.0, 8.75, 60.0), -2.6, 0.75, 9.0)
	await capture(scene, "woodcutters-close")
	frame_scene(scene, Vector3(54.0, 10.0, 56.0), 0.70, 0.78, 37.0)
	await capture(scene, "reverse")
	# Wide scene view and close source view exercise the actual Mobile renderer.
	scene.camera.attributes = null
	scene.camera.position = Vector3(175, 165, -65)
	scene.camera.look_at(Vector3(80, 8, 80))
	await capture(scene, "basin-overview")
	scene.camera.position = Vector3(98, 36, 111)
	scene.camera.look_at(Vector3(82, 16, 141))
	await capture(scene, "waterfall")
	scene.camera.position = Vector3(95, 28, 65)
	scene.camera.look_at(Vector3(80, 64, 175))
	await capture(scene, "mountain-detail")
	scene.camera.position = Vector3(132, 34, 111)
	scene.camera.look_at(Vector3(147, 27, 124))
	await capture(scene, "voxel-transition")
	frame_scene(scene, Vector3(155.0, 25.0, 80.0), -0.85, 0.74, 22.0)
	await capture(scene, "edge-before")
	var point := Vector3(158.0, 25.0, 80.0)
	var sample: Dictionary = scene.backend.sample_surface_plane(point + Vector3.UP * 4.0, Vector3.UP, 8.0)
	check(bool(sample.get("valid", false)), "Border terrain can be targeted")
	if bool(sample.get("valid", false)):
		point.y = (sample["point"] as Vector3).y
		var old_surround: Mesh = scene._valley_surround.mesh
		check(scene.backend.begin_stroke("dig", point, {"radius":1.5, "strength":2.0, "falloff":0.6}), "Border dig begins")
		for tick in 12: scene.backend.update_stroke(point, 1.0 / 30.0)
		check(scene.backend.end_stroke(), "Border dig commits through native terrain")
		check(scene._surround_refresh_pending, "Border edit schedules a scenery refresh")
		# Scene processing is frozen only for clean captures; run its normal
		# coalesced surround refresh once after the completed stroke.
		scene._process(1.0 / 60.0)
		check(not scene._surround_refresh_pending, "Border scenery refresh is consumed after the stroke")
		check(scene._valley_surround.mesh != old_surround, "Border scenery is rebuilt from the edited native boundary")
		frame_scene(scene, Vector3(155.0, 25.0, 80.0), -0.85, 0.74, 22.0)
		for name in ["brush_preview", "cursor_reticle", "reference_plane", "terrain_hit_marker", "terrain_edit_preview"]:
			var node = scene.get(name)
			if node != null: node.visible = false
		await capture(scene, "edge-edited")
	_mark_phase("shutdown")
	var receipt := {"ok":failures.is_empty(), "failures":failures.size(), "messages":failures, "renderer":RenderingServer.get_current_rendering_method(), "size":"1280x720", "production_start":true, "captures":captures, "phase_ms":phase_ms}
	var file := FileAccess.open(OUTPUT + "/receipt.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(receipt, "\t"))
		file.close()
	else: check(false, "Capture receipt could not be saved")
	print("STARTER_MOBILE_CAPTURE " + JSON.stringify(receipt))
	scene._shutting_down = true
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func frame_scene(scene: Node, target: Vector3, yaw: float, pitch: float, distance: float) -> void:
	scene.view_context = "terrain"
	scene.cursor = target - Vector3.UP * 2.0
	scene._free_camera_y = target.y
	scene._terrain_camera_goal_y = target.y
	scene._free_camera_valid = true
	scene.camera_yaw = yaw
	scene.camera_pitch = pitch
	scene.camera_distance = distance
	scene._update_camera()

func capture(scene: Node, label: String) -> void:
	await settle_frames(500)
	await _mesh_framed_area(scene, label)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := OUTPUT + "/" + label + ".png"
	check(not image.is_empty() and image.save_png(path) == OK, "Saved " + label + " capture")
	captures.append(path)

## Ground region the live camera can frame, in native cell coordinates.
## Height spans the full column so a cliff face counts as framed terrain.
##
## The region MUST stay inside the visual viewer's streaming volume, which is
## a SPHERE of _whole_world_view_distance around the camera. A box clamped to
## the patch has corners at radius*sqrt(2) from the camera, i.e. outside that
## sphere, and is_area_meshed() then never completes - each capture burns its
## whole deadline and the shard times out. Bounding the box's half-diagonal by
## radius/sqrt(2) keeps every corner inside the sphere.
func _framed_area(scene: Node) -> AABB:
	var cam: Camera3D = scene.camera
	var origin := cam.global_position
	var forward := -cam.global_transform.basis.z.normalized()
	var reach := clampf(cam.far, 32.0, 128.0)
	var lateral := reach * tan(deg_to_rad(cam.fov) * 0.5) + 8.0
	var radius := _view_radius_world(scene)
	var safe := radius / sqrt(2.0)
	var ground := Vector3(origin.x, 0.0, origin.z)
	var flat := Vector3(forward.x, 0.0, forward.z)
	var offset := minf(reach * 0.5, safe * 0.5)
	var centre := ground + (flat.normalized() if flat.length() > 0.01 else Vector3.ZERO) * offset
	var half := maxf(minf(lateral, safe - offset), 4.0)
	var scale_value := float(scene.backend.voxel_scale)
	# patch_size is in NATIVE CELLS; every clamp below is in WORLD METRES.
	var patch := Vector3(scene.backend.patch_size) * scale_value
	var lo := Vector3(clampf(centre.x - half, 0.0, patch.x), 0.0, clampf(centre.z - half, 0.0, patch.z))
	var hi := Vector3(clampf(centre.x + half, 0.0, patch.x), patch.y, clampf(centre.z + half, 0.0, patch.z))
	return AABB(lo / scale_value, (hi - lo) / scale_value)

## Streaming radius the visual viewer actually uses, mirroring
## TerrainBackend._whole_world_view_distance(RUNTIME_VIEW_DISTANCE_WORLD_FLOOR).
func _view_radius_world(scene: Node) -> float:
	var world := Vector3(scene.backend.patch_size) * float(scene.backend.voxel_scale)
	return ceilf(maxf(TerrainBackend.RUNTIME_VIEW_DISTANCE_WORLD_FLOOR, world.length() * 0.5))

func _mesh_framed_area(scene: Node, label: String) -> void:
	var area := _framed_area(scene)
	var started := Time.get_ticks_msec()
	var deadline := started + 60000
	while not scene.backend.terrain.is_area_meshed(area) and Time.get_ticks_msec() < deadline:
		await process_frame
	var waited_ms := float(Time.get_ticks_msec() - started)
	print("STARTER_MESH_WAIT ", JSON.stringify({"label": label, "area_cells": [int(area.size.x), int(area.size.y), int(area.size.z)], "meshed": scene.backend.terrain.is_area_meshed(area), "wait_ms": waited_ms}))
	check(scene.backend.terrain.is_area_meshed(area), label + " frames meshed native terrain")

func settle_frames(milliseconds: int) -> void:
	# WARP is a software renderer. A fixed 180-frame delay can consume minutes
	# without adding evidence; allow real rendered frames and bounded settling
	# time instead. Readiness still requires the full native production scene.
	var deadline := Time.get_ticks_msec() + milliseconds
	var frames := 0
	while frames < 3 or Time.get_ticks_msec() < deadline:
		await process_frame
		frames += 1
