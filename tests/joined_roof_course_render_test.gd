extends SceneTree

const Layout = preload("res://scripts/joined_roof_course_layout.gd")
const Massing = preload("res://scripts/m2_house_massing.gd")
const Edit = preload("res://scripts/m2_section_edit.gd")
const OUTPUT := ".tools/cottage-repair/joined-roof-courses"
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
		push_error("Joined-roof review requires actual Mobile rendering")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	check(DirAccess.make_dir_recursive_absolute(OUTPUT) == OK, "review folder created")
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://joined-course-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "native editable scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	scene.edit_pointer = Vector2(12,12)
	scene.camera.attributes = CameraAttributesPractical.new()
	var original: String = scene.building_world.serialize_document()
	for spec in [["u-normal", 16.0, 1.20], ["u-close", 10.0, 1.20], ["u-reverse", 14.0, 0.20], ["upper-edited", 10.0, 1.20]]:
		check(scene.building_world.load_serialized_document(original), "restore isolated comparison recipe")
		if spec[0] == "upper-edited":
			scene._begin_next_storey()
			check(scene.portion_valid and scene._commit_portion_placement(), "upper roof uses actual add-floor API")
			var view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
			var section: Dictionary = Massing.sections_for(view).back()
			var candidate := Edit.resize_edge(section, "left", 1.0)
			check(scene.building_world.commit_section_resize(scene.selected_building_id, str(section["id"]), candidate, scene.building_world.get_revision()), "upper roof follows a real one-sided section edit")
		else:
			check(scene._apply_house_shape_preset("u_shape"), "U-house uses normal shape API")
		var saved: String = scene.building_world.serialize_document()
		var landscape: String = JSON.stringify(scene.landscape_state.document())
		var camera_transform := Transform3D.IDENTITY
		var before_pixels := 0
		for enabled in [false, true]:
			Layout.enabled = enabled
			_force_rebuild()
			scene.camera_yaw = PI * float(spec[2])
			scene.camera_pitch = 0.48
			scene.camera_distance = float(spec[1])
			scene._update_camera()
			if not enabled: camera_transform = scene.camera.global_transform
			check(scene.camera.global_transform.is_equal_approx(camera_transform), "comparison framing stays identical")
			for frame in 6: await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			check(not image.is_empty() and image.get_size() == Vector2i(1280,720), "actual Mobile capture exists")
			var finish := "skin" if enabled else "previous"
			var path := "%s/%s-%s.png" % [OUTPUT, spec[0], finish]
			check(image.save_png(path) == OK, "comparison saved")
			captures += 1
			var visual: Node3D = scene.cottage_visuals[scene.selected_building_id]
			var joined := visual.get_node("M2JoinedMassing") as Node3D
			var meshes := 0
			var triangles := 0
			for shade in 3:
				var node := joined.get_node_or_null("JoinedRoof_%d" % shade) as GeometryInstance3D
				if node is MultiMeshInstance3D: triangles += (node as MultiMeshInstance3D).multimesh.instance_count * 12
				elif node is MeshInstance3D:
					meshes += 1
					var mesh := (node as MeshInstance3D).mesh
					if mesh.get_surface_count() > 0: triangles += (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var pixels := hash(image.get_data())
			if not enabled: before_pixels = pixels
			else:
				check(meshes == 3 and triangles > 0, "roof has three actual batched stepped meshes")
				var tile_count := Massing.roof_tiles(scene.building_world.get_building(scene.selected_building_id)).size()
				check(triangles <= tile_count * 12, "surface-only meshing reduces triangles versus old boxes")
				check(pixels != before_pixels, "physical relief visibly changes the rendered roof")
				var first := joined.get_node("JoinedRoof_0") as MeshInstance3D
				var mesh_id := first.mesh.get_instance_id()
				scene._update_presentation()
				for frame in 3: await RenderingServer.frame_post_draw
				check(first.mesh.get_instance_id() == mesh_id, "unchanged presentation does not retessellate the roof")
				check(hash(root.get_texture().get_image().get_data()) == pixels, "unchanged roof remains pixel-stable")
				scene._roof_pick_groups.clear()
				scene._roof_pick_nodes.clear()
				scene._cache_roof_boxes(joined, visual, false)
				check(first in scene._roof_pick_nodes and not scene._roof_pick_groups.is_empty(), "actual roof mesh remains selectable and highlightable")
				if str(spec[0]).begins_with("u-"):
					var courtyard := true
					for group in scene._roof_pick_groups:
						for box in group["boxes"]:
							if scene._ray_box_distance(Vector3(0,100,-12), Vector3.DOWN, box) >= 0: courtyard = false
					check(courtyard, "roof selection never bridges the U courtyard")
			check(scene.building_world.serialize_document() == saved and JSON.stringify(scene.landscape_state.document()) == landscape, "roof meshing changes no saved building, detail or planting records")
			receipts.append({"case": spec[0], "finish": finish, "path": path, "roof_triangles": triangles, "skin_draws": meshes})
		# Reopening the exact edited recipe must regenerate identical geometry.
		var visual: Node3D = scene.cottage_visuals[scene.selected_building_id]
		var signature := _mesh_signature(visual)
		check(scene.building_world.load_serialized_document(saved), "edited/concave roof save loads")
		_force_rebuild()
		check(_mesh_signature(scene.cottage_visuals[scene.selected_building_id]) == signature, "reload regenerates identical surface meshes")
	var manifest := FileAccess.open(OUTPUT + "/manifest.json", FileAccess.WRITE)
	check(manifest != null, "manifest writable")
	if manifest: manifest.store_string(JSON.stringify({"source": OS.get_environment("GITHUB_SHA"), "engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(), "frames": receipts}, "\t"))
	await _finish()

func _force_rebuild() -> void:
	for visual in scene.cottage_visuals.values(): visual._applied_view = {}
	scene._roof_overlay_signatures.clear()
	scene._roof_pick_key = ""
	scene._presentation_key = ""
	scene._update_presentation()
	scene.hud.visible = false
	scene.garden_visual.set_wind_enabled(false)

func _mesh_signature(visual: Node3D) -> Array:
	var result: Array = []
	for shade in 3:
		var node := visual.get_node("M2JoinedMassing/JoinedRoof_%d" % shade) as MeshInstance3D
		if not node: return []
		result.append(node.mesh.surface_get_arrays(0) if node.mesh.get_surface_count() else [])
	return result

func _finish() -> void:
	Layout.enabled = true
	if is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	check(captures == 8, "normal close reverse and resized-upper views all have two real captures")
	print("JOINED_COURSE_RENDER " + JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "captures": captures}))
	quit(1 if failures else 0)
