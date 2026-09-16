extends SceneTree

const Backend = preload("res://scripts/terrain_backend.gd")
const PatchGenerator = preload("res://scripts/patch_generator.gd")
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
	# Preview must use the same native sphere operation as commit, while leaving
	# both authoritative and native terrain state untouched.
	var preview_center := Vector3(24.25, 5.5, 24.75)
	var preview_radius := 2.2
	var preview_before_bytes: PackedByteArray = backend.voxels.get_channel_as_byte_array(PatchGenerator.CHANNEL_TYPE)
	var preview_before_stats: Dictionary = backend.stats()
	var preview_native_sample := int(backend.terrain.get_voxel_tool().get_voxel(Vector3i(24, 5, 24)))
	var expected_add := _native_changed_set(backend, preview_center, preview_radius, false)
	var preview_add: Array[Vector3i] = backend.preview_sphere(preview_center, preview_radius, false)
	check(_points_set(preview_add) == expected_add, "fractional add preview matches native changed set")
	check(not preview_add.is_empty(), "fractional add preview has changes")
	var expected_remove := _native_changed_set(backend, Vector3(12.25, 10.5, 12.75), 1.6, true)
	var preview_remove: Array[Vector3i] = backend.preview_sphere(Vector3(12.25, 10.5, 12.75), 1.6, true)
	check(_points_set(preview_remove) == expected_remove, "fractional remove preview matches native changed set")
	check(not preview_remove.is_empty(), "fractional remove preview has changes")
	var expected_boundary := _native_changed_set(backend, Vector3(0.25, 8.2, 0.4), 2.3, true)
	var preview_boundary: Array[Vector3i] = backend.preview_sphere(Vector3(0.25, 8.2, 0.4), 2.3, true)
	check(_points_set(preview_boundary) == expected_boundary, "boundary preview matches native changed set")
	for point in preview_boundary:
		check(point.x >= 0 and point.y >= 0 and point.z >= 0 and point.x < 48 and point.y < 32 and point.z < 48, "boundary preview coordinate clipped")
	var preview_noop: Array[Vector3i] = backend.preview_sphere(Vector3(24.2, 5.2, 24.4), 0.8, true)
	check(preview_noop.is_empty(), "no-op preview empty")
	check(backend.preview_sphere(Vector3(-0.1, 4, 4), 1.0, true).is_empty(), "preview bounds rejected")
	check(backend.preview_sphere(Vector3(10, 10, 10), INF, true).is_empty(), "preview infinite radius rejected")
	check(backend.preview_sphere(Vector3(10, 10, 10), NAN, true).is_empty(), "preview nan radius rejected")
	check(backend.preview_sphere(Vector3(10, 10, 10), 0.0, true).is_empty(), "preview zero radius rejected")
	check(backend.preview_sphere(Vector3(10, 10, 10), 8.01, true).is_empty(), "preview oversized radius rejected")
	var preview_after_bytes: PackedByteArray = backend.voxels.get_channel_as_byte_array(PatchGenerator.CHANNEL_TYPE)
	var preview_after_stats: Dictionary = backend.stats()
	check(preview_after_bytes == preview_before_bytes, "repeated previews preserve authoritative voxels")
	check(int(preview_after_stats.revision) == int(preview_before_stats.revision), "repeated previews preserve revision")
	check(int(preview_after_stats.undo_count) == int(preview_before_stats.undo_count) and int(preview_after_stats.redo_count) == int(preview_before_stats.redo_count) and int(preview_after_stats.history_bytes) == int(preview_before_stats.history_bytes), "repeated previews preserve history")
	check(bool(preview_after_stats.dirty) == bool(preview_before_stats.dirty), "repeated previews preserve dirty state")
	check(int(backend.terrain.get_voxel_tool().get_voxel(Vector3i(24, 5, 24))) == preview_native_sample, "repeated previews preserve native terrain")
	# Commit the same operation and compare the complete changed set, then undo
	# so the existing add/undo/redo assertions start from the same world.
	var commit_before: Object = backend._clone_buffer(backend.voxels)
	check(backend.apply_sphere(preview_center, preview_radius, false), "preview parity commit")
	check(_changed_set_full(commit_before, backend.voxels) == expected_add, "add commit full changed set equals preview")
	check(backend.undo(), "preview parity undo")
	check(backend.voxels.get_channel_as_byte_array(PatchGenerator.CHANNEL_TYPE) == preview_before_bytes, "add undo restores complete buffer")
	var boundary_before: Object = backend._clone_buffer(backend.voxels)
	check(backend.apply_sphere(Vector3(0.25, 8.2, 0.4), 2.3, true), "boundary preview parity commit")
	check(_changed_set_full(boundary_before, backend.voxels) == expected_boundary, "remove boundary commit full changed set equals preview")
	check(backend.undo(), "boundary preview parity undo")
	check(backend.voxels.get_channel_as_byte_array(PatchGenerator.CHANNEL_TYPE) == preview_before_bytes, "remove undo restores complete buffer")
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

func _native_changed_set(backend: Node, center: Vector3, radius: float, remove: bool) -> Dictionary:
	var before: Object = backend._clone_buffer(backend.voxels)
	var after: Object = backend._clone_buffer(backend.voxels)
	var tool = after.get_voxel_tool()
	tool.channel = PatchGenerator.CHANNEL_TYPE
	tool.mode = 2
	tool.value = 0 if remove else 2
	tool.do_sphere(center, radius)
	return _changed_set_full(before, after)

func _changed_set_full(before: Object, after: Object) -> Dictionary:
	var changed := {}
	for x in 48:
		for y in 32:
			for z in 48:
				if before.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE) != after.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE):
					changed[_point_key(Vector3i(x, y, z))] = true
	return changed

func _points_set(points: Array[Vector3i]) -> Dictionary:
	var result := {}
	for point in points:
		result[_point_key(point)] = true
	return result

func _point_key(point: Vector3i) -> String:
	return "%d,%d,%d" % [point.x, point.y, point.z]
