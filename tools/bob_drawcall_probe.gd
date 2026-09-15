extends SceneTree

## Step-4 perf evidence, read-only. Boots the real Mobile scene, rebuilds the
## three-home hamlet fixture (same as tests/m2_hamlet_composition_render_test.gd)
## and reports the vegetation instancing cost: draw calls in frame, MultiMesh
## batches, total instances, and the landscape record count.
##
##   DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --path . --renderer mobile \
##       --script tools/bob_drawcall_probe.gd

const World = preload("res://scripts/building_world.gd")

var scene: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://bob-drawcall-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline: int = Time.get_ticks_msec() + 65000
	while (not scene._player_restored or scene.backend == null or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not scene._player_restored or not scene.backend.is_ready():
		print("DRAWCALL_PROBE_UNAVAILABLE")
		quit(2)
		return
	scene.set_process(false)
	var lodge_basis: Basis = Basis(Vector3.UP, deg_to_rad(-10.0)).scaled(Vector3.ONE * World.MINIATURE_SCALE)
	scene.building_world.create_home_at("woodland_lodge", Transform3D(lodge_basis, Vector3(12.0, 8.0, 32.0)), scene.building_world.get_revision())
	var gable_basis: Basis = Basis(Vector3.UP, deg_to_rad(12.0)).scaled(Vector3.ONE * World.MINIATURE_SCALE)
	scene.building_world.create_home_at("village_gable", Transform3D(gable_basis, Vector3(31.0, 8.0, 31.0)), scene.building_world.get_revision())
	if scene.has_method("_sync_cottage_visuals"): scene._sync_cottage_visuals()
	scene.cursor = Vector3(25.0, 8.0, 25.0)
	scene.terrain_cursor = scene.cursor
	scene.camera_yaw = -1.04
	scene.camera_pitch = 0.72
	scene.camera_distance = 42.0
	scene._update_camera()
	for _frame in 24: await RenderingServer.frame_post_draw
	var metrics: Array = Performance.get_custom_monitor_names()
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var objects := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var batches := 0
	var instances := 0
	var multimesh_nodes := 0
	for key: String in scene.garden_visual._groups:
		var node: MultiMeshInstance3D = scene.garden_visual._groups[key]
		batches += 1
		multimesh_nodes += 1
		instances += node.multimesh.instance_count
	var kinds := {}
	for record_value in scene.landscape_state.records:
		var record: Dictionary = record_value
		var kind: String = str(record.get("kind", record.get("type", "?")))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	print("DRAWCALL_KINDS " + JSON.stringify(kinds))
	print("DRAWCALL_PROBE " + JSON.stringify({
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"draw_calls": draw_calls,
		"primitives": primitives,
		"objects": objects,
		"plant_batches": batches,
		"plant_instances": instances,
		"records": scene.landscape_state.records.size(),
		"custom_monitors": metrics.size(),
	}))
	scene._shutting_down = true
	scene.queue_free()
	await process_frame
	quit(0)