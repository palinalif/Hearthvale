extends SceneTree

## Read-only: boots the real scene and reports the DistantHamlet mesh the world
## builder produced (surface count, AABBs, vertex counts) plus the outer-floor
## height function at sample points. Used to verify the step-4 backdrop.
##
##   DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --path . --renderer mobile \
##       --script tools/bob_scenery_probe.gd

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene: Node = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://bob-scenery-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline: int = Time.get_ticks_msec() + 90000
	while (not scene._player_restored or scene.backend == null or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline:
		await process_frame
	var node: MeshInstance3D = scene.distant_scenery
	if node == null or node.mesh == null:
		print("SCENERY_PROBE no mesh")
		quit(2)
		return
	var mesh: Mesh = node.mesh
	print("SCENERY surfaces=%d aabb=%s" % [mesh.get_surface_count(), str(mesh.get_aabb())])
	for index in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		for vertex in vertices:
			lo = lo.min(vertex)
			hi = hi.max(vertex)
		print("SCENERY surface %d verts=%d min=%s max=%s" % [index, vertices.size(), str(lo), str(hi)])
	# Sample the outer floor at a few radii along +x from the island centre.
	for step in 14:
		var x := 20.0 + float(step) * 14.0
		print("SCENERY floor x=%.1f z=24.0 h=%.1f" % [x, scene._outer_floor_height(x, 24.0)])
	for step in 8:
		var x := -8.0 - float(step) * 4.0
		print("SCENERY floor x=%.1f z=24.0 h=%.1f" % [x, scene._outer_floor_height(x, 24.0)])
	print("SCENERY_PROBE_DONE")
	scene._shutting_down = true
	scene.queue_free()
	await process_frame
	quit(0)
