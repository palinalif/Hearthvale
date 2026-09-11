extends SceneTree

const Layout = preload("res://scripts/facade_depth_layout.gd")
const OUTPUT := ".tools/cottage-repair/facade-depth"
var scene: Node
var checks := 0
var failures := 0
var captures := 0
var receipts: Array[Dictionary] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "mobile":
		push_error("Facade depth review requires actual Mobile rendering")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	check(DirAccess.make_dir_recursive_absolute(OUTPUT) == OK, "facade review folder created")
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://facade-render-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "facade Mobile scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	scene.edit_pointer = Vector2(12, 12)
	scene.camera.attributes = CameraAttributesPractical.new()
	scene.hud.visible = false
	scene.garden_visual.set_wind_enabled(false)
	var original := scene.building_world.serialize_document()
	var cases := [
		{"id": "front-close", "yaw": 1.20, "distance": 9.0, "fixture": "base"},
		{"id": "reverse", "yaw": 0.20, "distance": 12.0, "fixture": "base"},
		{"id": "u-courtyard", "yaw": 1.00, "distance": 12.0, "fixture": "u"},
		{"id": "upper-floor", "yaw": 1.20, "distance": 11.0, "fixture": "upper"},
	]
	for spec in cases:
		check(scene.building_world.load_serialized_document(original), "restore clean facade comparison fixture")
		scene._presentation_key = ""
		scene._update_presentation()
		if spec["fixture"] == "u":
			check(scene._apply_house_shape_preset("u_shape"), "U comparison uses house-shape API")
		elif spec["fixture"] == "upper":
			scene._begin_next_storey()
			check(scene.portion_valid and scene._commit_portion_placement(), "upper comparison uses add-floor API")
		var buildings_before := scene.building_world.serialize_document()
		var landscape_before := JSON.stringify(scene.landscape_state.document())
		scene.camera_yaw = PI * float(spec["yaw"])
		scene.camera_pitch = 0.43
		scene.camera_distance = float(spec["distance"])
		scene._update_camera()
		var camera_transform := scene.camera.global_transform
		var before_hash := 0
		for enabled in [false, true]:
			Layout.enabled = enabled
			scene._refresh_facade_depth(true)
			scene.hud.visible = false
			for frame in 7: await RenderingServer.frame_post_draw
			check(scene.camera.global_transform.is_equal_approx(camera_transform), "facade comparison framing is identical")
			var image := root.get_texture().get_image()
			check(not image.is_empty() and image.get_size() == Vector2i(1280,720), "actual Mobile facade image exists")
			var finish := "depth" if enabled else "previous"
			var path := "%s/%s-%s.png" % [OUTPUT, spec["id"], finish]
			check(image.save_png(path) == OK, "facade comparison saved")
			var pixels := hash(image.get_data())
			captures += 1
			var visual := scene.cottage_visuals[scene.selected_building_id] as Node3D
			var instances := _facade_instances(visual)
			if enabled:
				check(instances > 0 and visual.get_node_or_null("M2FacadeDepthMarker") != null, "enabled frame contains generated facade relief")
				check(pixels != before_hash, "facade relief changes actual rendered pixels")
			else:
				before_hash = pixels
				check(instances == 0 and visual.get_node_or_null("M2FacadeDepthMarker") == null, "control frame contains no new facade geometry")
			check(scene.building_world.serialize_document() == buildings_before and JSON.stringify(scene.landscape_state.document()) == landscape_before, "facade finish is presentation-only")
			receipts.append({"case": spec["id"], "finish": finish, "path": path, "facade_instances": instances})
	var manifest := FileAccess.open(OUTPUT + "/manifest.json", FileAccess.WRITE)
	check(manifest != null, "facade manifest writable")
	if manifest:
		manifest.store_string(JSON.stringify({"source": OS.get_environment("GITHUB_SHA"), "engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(), "frames": receipts}, "\t"))
		manifest.close()
	await _finish()

func _facade_instances(visual: Node3D) -> int:
	var total := 0
	for child in visual.get_children():
		if not str(child.name).begins_with("M2Facade") or not child is MultiMeshInstance3D: continue
		var multi: MultiMesh = (child as MultiMeshInstance3D).multimesh
		if multi: total += multi.instance_count
	return total

func _finish() -> void:
	Layout.enabled = true
	if is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	check(captures == 8, "front reverse courtyard and upper-floor views all have matched captures")
	print("FACADE_DEPTH_RENDER " + JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "captures": captures}))
	quit(1 if failures else 0)
