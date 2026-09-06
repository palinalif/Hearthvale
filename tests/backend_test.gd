extends SceneTree

const Backend = preload("res://scripts/terrain_backend.gd")
var failures := 0
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _init() -> void:
	var backend: Node = Backend.new()
	root.add_child(backend)
	await _wait_ready(backend, 16000)
	check(backend.is_ready(), "backend ready")
	print("backend_stats=", backend.stats())
	check(backend.terrain != null, "native terrain instance")
	if backend.terrain != null:
		print("terrain_bounds=", backend.terrain.bounds, "block_size=", backend.terrain.get_data_block_size(), "statistics=", backend.terrain.get_statistics())
		for bx in 3:
			for by in 2:
				for bz in 3:
					print("data_block ", Vector3i(bx, by, bz), "=", backend.terrain.has_data_block(Vector3i(bx, by, bz)))
	check(backend.stats().get("initial_mesh_ready", false), "initial mesh readiness reported")
	if backend.terrain != null: check(backend.terrain.is_area_meshed(AABB(Vector3.ZERO, Vector3(48, 32, 48))), "native terrain meshed")
	check(backend.voxel_at(Vector3i(24, 5, 24)) == 0, "tunnel floor opening")
	check(backend.voxel_at(Vector3i(24, 8, 24)) != 0, "tunnel roof intact")
	check(int(backend.terrain.get_voxel_tool().get_voxel(Vector3i(24, 5, 24))) == backend.voxel_at(Vector3i(24, 5, 24)), "native opening sample")
	check(int(backend.terrain.get_voxel_tool().get_voxel(Vector3i(24, 8, 24))) == backend.voxel_at(Vector3i(24, 8, 24)), "native roof sample")
	var before: int = backend.voxel_at(Vector3i(10, 10, 10))
	check(backend.apply_sphere(Vector3(10, 10, 10), 1.0, false), "add")
	check(backend.voxel_at(Vector3i(10, 10, 10)) != before, "add changed")
	check(int(backend.terrain.get_voxel_tool().get_voxel(Vector3i(10, 10, 10))) == backend.voxel_at(Vector3i(10, 10, 10)), "native add sample")
	check(backend.undo(), "undo")
	check(backend.voxel_at(Vector3i(10, 10, 10)) == before, "undo exact")
	check(int(backend.terrain.get_voxel_tool().get_voxel(Vector3i(10, 10, 10))) == before, "native undo sample")
	check(backend.redo(), "redo")
	check(backend.voxel_at(Vector3i(10, 10, 10)) != before, "redo exact")
	check(int(backend.terrain.get_voxel_tool().get_voxel(Vector3i(10, 10, 10))) == backend.voxel_at(Vector3i(10, 10, 10)), "native redo sample")
	check(not backend.apply_sphere(Vector3(-1, 4, 4), 1.0, true), "bounds")
	check(not backend.apply_sphere(Vector3(10, 10, 10), INF, true), "infinite radius rejected")
	check(not backend.apply_sphere(Vector3(10, 10, 10), NAN, true), "nan radius rejected")
	var revision_before_noop: int = backend.stats().revision
	check(not backend.apply_sphere(Vector3(10, 10, 10), 1.0, false), "no-op rejected")
	check(backend.stats().revision == revision_before_noop, "no-op revision stable")
	# A sphere at the edge exercises clipped region snapshots and native paste bounds.
	var edge_before: int = backend.voxel_at(Vector3i(1, 8, 1))
	check(backend.apply_sphere(Vector3(1.0, 8.0, 1.0), 2.0, true), "boundary remove")
	check(backend.voxel_at(Vector3i(1, 8, 1)) != edge_before, "boundary changed")
	check(backend.undo() and backend.voxel_at(Vector3i(1, 8, 1)) == edge_before, "boundary undo")
	check(backend.redo() and backend.voxel_at(Vector3i(1, 8, 1)) != edge_before, "boundary redo")
	# Save and load through a fresh backend instance with an injected root.
	var checkpoint_root := "user://backend-test-fresh-%d" % Time.get_ticks_usec()
	var writer: Node = Backend.new(); writer.checkpoint_root = checkpoint_root; root.add_child(writer)
	await _wait_ready(writer, 16000)
	check(writer.is_ready(), "fresh writer ready")
	var writer_before: int = writer.voxel_at(Vector3i(8, 8, 8))
	check(writer.apply_sphere(Vector3(8, 8, 8), 2.0, true), "fresh writer edit")
	var saved_revision: int = writer.stats().revision
	var saved_voxel: int = writer.voxel_at(Vector3i(8, 8, 8))
	check(writer.save_world(), "fresh writer save")
	var reader: Node = Backend.new(); reader.checkpoint_root = checkpoint_root; root.add_child(reader)
	await _wait_ready(reader, 16000)
	check(reader.is_ready(), "fresh reader ready")
	check(reader.load_world(), "fresh reader load")
	check(reader.stats().revision == saved_revision, "loaded revision forwarded")
	check(reader.voxel_at(Vector3i(8, 8, 8)) == saved_voxel and saved_voxel != writer_before, "fresh load voxel")
	backend.queue_free(); writer.queue_free(); reader.queue_free()
	await process_frame
	print("backend_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _wait_ready(backend: Node, timeout_ms: int) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not backend.is_ready() and Time.get_ticks_msec() < deadline:
		await process_frame
