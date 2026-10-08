extends SceneTree
## Actual main-scene cold start, native Mobile captures and a real border edit.
## Uses a unique checkpoint root; player saves and the live scene are untouched.
const OUTPUT := "res://reports/screenshots/detailed-mountains"
# Wall-clock budget for the up-front streaming gate. Streaming follows the
# camera and re-pointing the focus discards in-flight block loads, so the gate
# parks the camera at one stable vantage and lets the viewer finish. A hosted
# software Mobile runner needs a few minutes for that. The gate only bounds the
# shard's time - the invariant is asserted by the per-capture framed gates.
const STREAMING_SWEEP_CAP_MS := 300000
# A framed region is already meshed once the valley has streamed, so this only
# has to absorb the last in-flight cells for the region a camera frames. The
# cap is generous because a gate that finds its region unmeshed must stream a
# fresh 48 m box on a software Mobile runner, and a warm edge-region gate
# already measured 29 s hosted (run 37811836652).
const FRAMED_MESH_CAP_MS := 60000
# Every framing the capture phase uses, in capture order. The up-front streaming
# gate is computed from this list and the captures are driven from it, so the
# gate can never demand terrain the captures do not frame. The last entry is
# captured after the border dig.
const CAPTURE_PLAN: Array[Dictionary] = [
	{"label": "opening-ui", "mode": "initial"},
	{"label": "normal", "mode": "initial"},
	{"label": "commons-close", "mode": "orbit", "target": Vector3(47.0, 9.25, 56.0), "yaw": -1.9, "pitch": 0.70, "distance": 15.0},
	{"label": "woodcutters-close", "mode": "orbit", "target": Vector3(32.0, 8.75, 60.0), "yaw": -2.6, "pitch": 0.75, "distance": 9.0},
	{"label": "reverse", "mode": "orbit", "target": Vector3(54.0, 10.0, 56.0), "yaw": 0.70, "pitch": 0.78, "distance": 37.0},
	{"label": "basin-overview", "mode": "panorama", "from": Vector3(175, 165, -65), "look": Vector3(80, 8, 80)},
	{"label": "waterfall", "mode": "panorama", "from": Vector3(98, 36, 111), "look": Vector3(82, 16, 141)},
	{"label": "mountain-detail", "mode": "panorama", "from": Vector3(95, 28, 65), "look": Vector3(80, 64, 175)},
	{"label": "voxel-transition", "mode": "panorama", "from": Vector3(132, 34, 111), "look": Vector3(147, 27, 124)},
	{"label": "edge-before", "mode": "orbit", "target": Vector3(155.0, 25.0, 80.0), "yaw": -0.85, "pitch": 0.74, "distance": 22.0},
	{"label": "edge-edited", "mode": "orbit", "target": Vector3(155.0, 25.0, 80.0), "yaw": -0.85, "pitch": 0.74, "distance": 22.0},
]
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
	# Streaming demand follows the camera, so a static camera streams slowly:
	# gating every capture separately paid for the same work up to eleven times
	# (seven labels burned 60-63 s each and still captured unmeshed terrain), and
	# demanding the whole map from the cold-launch camera exhausted 425 s without
	# finishing it. The wide panorama capture, which parks the camera high above
	# the map, finished its meshing in 57 s - so drive the camera over the region
	# the captures frame, once, up front, then restore it and let each capture
	# assert the terrain it frames, which is instant once that region has streamed.
	scene.set_process(false)
	await _stream_capture_region(scene)
	_mark_phase("settle")
	await settle_frames(1500)
	_mark_phase("capture")
	# The first two captures use the real initial camera without moving it.
	for home: Dictionary in scene.building_world.get_buildings():
		var transform_value: Transform3D = home["transform"]
		var point := transform_value.origin + Vector3.UP
		check(not scene.camera.is_position_behind(point), "Starter home faces the initial camera")
		check(Rect2(Vector2.ZERO, Vector2(root.size)).has_point(scene.camera.unproject_position(point)), "Starter home is framed at cold launch")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for index in CAPTURE_PLAN.size() - 1:
		var entry: Dictionary = CAPTURE_PLAN[index]
		var label := String(entry["label"])
		_apply_framing(scene, entry)
		await capture(scene, label)
		if label == "opening-ui":
			scene.hud.visible = false
			_hide_terrain_overlays(scene)
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
		_hide_terrain_overlays(scene)
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
## a SPHERE of _whole_world_view_distance around the camera, and it must be
## small enough for meshing throughput on a software Mobile runner. Meshing
## streams outward from the camera-centred viewer, so the region is centred on
## the camera and capped at 24 m half-extent.
func _framed_area(scene: Node) -> AABB:
	return _framed_area_around(scene, scene.cursor)

func _framed_area_around(scene: Node, cursor: Vector3) -> AABB:
	var cam: Camera3D = scene.camera
	var reach := clampf(cam.far, 32.0, 128.0)
	var lateral := reach * tan(deg_to_rad(cam.fov) * 0.5) + 8.0
	var safe := _view_radius_world(scene) / sqrt(2.0)
	# Centre on the ORBIT TARGET (scene.cursor), not on the camera.
	# _update_camera places the camera at cursor + offset with camera_distance
	# clamped to 8-52 m, and the viewer streams around camera.global_position at
	# a 128 m radius - so the target is always inside the map and always within
	# the streaming sphere. The camera is the thing that leaves the map: a
	# camera-centred region collapses against the patch edge for pulled-back
	# cameras (basin-overview produced a 72x256x0 zero-depth box), landing far
	# from the camera and outside the volume that streams.
	# Half-extent is capped because meshing throughput is the binding cost on a
	# software Mobile runner. The gate asserts the terrain each capture frames;
	# whole-world meshing is asserted by the performance shard, where it is
	# measured as a metric rather than gating screenshots.
	var focus := Vector3(cursor.x, 0.0, cursor.z)
	var half := maxf(minf(lateral, 24.0), 4.0)
	half = minf(half, safe)
	var centre := focus
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

## The terrain the capture phase frames, as one region: the union of every
## framing in CAPTURE_PLAN, in NATIVE CELLS like the framed areas it is built
## from. A panorama frames what its camera looks at, so its centre is the look
## target; an orbit frames its target; the two cold-launch captures frame the
## scene's own cursor. Height spans the full native column.
func _capture_region(scene: Node) -> AABB:
	var union: AABB
	var first := true
	for entry: Dictionary in CAPTURE_PLAN:
		var centre: Vector3 = entry.get("look", entry.get("target", scene.cursor))
		var framed := _framed_area_around(scene, centre)
		union = framed if first else union.merge(framed)
		first = false
	return AABB(Vector3(union.position.x, 0.0, union.position.z), Vector3(union.size.x, float(scene.backend.patch_size.y), union.size.z))

func _apply_framing(scene: Node, entry: Dictionary) -> void:
	match String(entry.get("mode", "")):
		"orbit":
			frame_scene(scene, entry["target"], float(entry["yaw"]), float(entry["pitch"]), float(entry["distance"]))
		"panorama":
			scene.camera.attributes = null
			scene.camera.position = entry["from"]
			scene.camera.look_at(entry["look"])
		_:
			pass

func _hide_terrain_overlays(scene: Node) -> void:
	for name in ["brush_preview", "cursor_reticle", "reference_plane", "terrain_hit_marker", "terrain_edit_preview"]:
		var node = scene.get(name)
		if node != null: node.visible = false

## Stream the terrain the captures frame, once, before any capture runs. The
## live scene re-points the streaming focus at the camera every frame, so the
## test drives that focus directly with the scene's own process disabled; the
## voxel streaming itself keeps running on frames.
##
## CI run 37795933012 demanded the whole 1280x256x1280 patch from the
## cold-launch camera, exhausted the 420 s cap with meshed:false, and still
## passed every per-capture framed gate. So the sweep is a time bound and a
## reported metric, not an assertion: the invariant - every capture frames
## meshed terrain - is asserted by the framed gates, which fail with the label
## of the capture that could not stream. The camera is restored from the scene's
## orbit state afterwards, which is the same call the live scene makes, so the
## cold-launch captures are unchanged.
func _stream_capture_region(scene: Node) -> void:
	var region := _capture_region(scene)
	# The region is in native cells; the camera and the streaming focus are in
	# world metres, so everything handed to the scene is converted first.
	var scale_value := float(scene.backend.voxel_scale)
	var patch := Vector3(scene.backend.patch_size) * scale_value
	# ONE stable focus, ABOVE the terrain. The viewer streams the blocks it can
	# see from the camera, so a camera inside the voxel column streams almost
	# nothing: CI run 37807523731 held a stable focus at the map centre at mid
	# height (80, 16, 80 - inside a 32 m column) for 303 s, never meshed the
	# region, and ten of eleven framed gates failed. The five-vantage sweep that
	# did pass every framed gate (run 37795933012) sat at y = 40 m, above the
	# column, looking down at the valley; the panorama capture that meshed in
	# 5.8 s was parked far above the map too. Height above the terrain is what
	# made the difference, and re-pointing the focus mid-stream discards the
	# blocks already in flight, so hold one high vantage and let it finish.
	var focus := Vector3(patch.x * 0.5, patch.y + 8.0, patch.z * 0.5)
	var reach := _view_radius_world(scene)
	var worst := 0.0
	for x in [region.position.x, region.end.x]:
		for z in [region.position.z, region.end.z]:
			for y in [0.0, float(region.size.y)]:
				worst = maxf(worst, (Vector3(x, y, z) * scale_value).distance_to(focus))
	var cam: Camera3D = scene.camera
	cam.position = focus
	cam.look_at(Vector3(focus.x, 0.0, focus.z))
	scene.backend.update_visual_focus(focus)
	var started := Time.get_ticks_msec()
	var deadline := started + STREAMING_SWEEP_CAP_MS
	while not scene.backend.terrain.is_area_meshed(region) and Time.get_ticks_msec() < deadline:
		scene.backend.update_visual_focus(focus)
		await settle_frames(20000)
	scene._update_camera()
	var waited_ms := float(Time.get_ticks_msec() - started)
	print("STARTER_MESH_WAIT ", JSON.stringify({"label": "capture-region", "area_cells": [int(region.size.x), int(region.size.y), int(region.size.z)], "meshed": scene.backend.terrain.is_area_meshed(region), "wait_ms": waited_ms, "cap_ms": STREAMING_SWEEP_CAP_MS, "focus_metres": [focus.x, focus.y, focus.z], "viewer_radius": reach, "farthest_region_corner": worst, "covered": worst <= reach}))

func _mesh_framed_area(scene: Node, label: String) -> void:
	var area := _framed_area(scene)
	var started := Time.get_ticks_msec()
	var deadline := started + FRAMED_MESH_CAP_MS
	# World-metres centre of the area this gate demands. The live scene re-points
	# the streaming focus at the camera every frame (m1_scene.gd _process), but
	# this test freezes scene processing for clean captures, so the gate must
	# drive that focus itself. It centres on the FRAMED AREA, not the camera:
	# a panorama parks its camera ~234 m from what it looks at, outside the
	# viewer's 128 m sphere, so a camera-following focus would stream away from
	# the very terrain the capture frames. With the focus left wherever the
	# sweep left it, captures framing regions the sweep did not stream starve
	# forever (run 37811836652: the first four captures burned their whole caps
	# while seven later gates passed at 0 ms).
	var focus := area.get_center() * float(scene.backend.voxel_scale)
	while not scene.backend.terrain.is_area_meshed(area) and Time.get_ticks_msec() < deadline:
		scene.backend.update_visual_focus(focus)
		await process_frame
	var waited_ms := float(Time.get_ticks_msec() - started)
	print("STARTER_MESH_WAIT ", JSON.stringify({"label": label, "area_cells": [int(area.size.x), int(area.size.y), int(area.size.z)], "meshed": scene.backend.terrain.is_area_meshed(area), "wait_ms": waited_ms, "cap_ms": FRAMED_MESH_CAP_MS}))
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
