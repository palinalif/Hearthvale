extends SceneTree
## Native scene integration: water and its excavated bed are one undo command.
var checks := 0
var failures := 0
var scene: Node

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)

func terrain_hash() -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(scene.backend.voxels.get_channel_as_byte_array(0))
	return hash.finish().hex_encode()

func aim(point: Vector3) -> void:
	scene.cursor = point
	scene.terrain_cursor = point
	scene._update_brush_preview()
	scene._update_water_validity()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://water-history-%d" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 90000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "native water scene ready")
	if scene._player_restored:
		scene.set_process(false)
		scene._set_view_context("terrain")
		scene._select_terrain_tool("water")
		scene.brush_radius = 0.75
		aim(Vector3(48, 8, 48))
		var before_document := JSON.stringify(scene.landscape_state.document())
		var before_terrain := terrain_hash()
		var history_count: int = scene._history_tags.size()
		var landing_roots: Array = scene._landing_rim_roots.values()
		check(scene._start_water_stream(), "native water stroke starts")
		aim(Vector3(50, 8, 48))
		check(scene._sample_water_stream(), "native water stroke grows")
		var commit_started := Time.get_ticks_usec()
		check(scene._commit_water_stream(), "native water stroke commits")
		print("WATER_COMMIT_COSTS ", JSON.stringify({"total_ms": (Time.get_ticks_usec() - commit_started) / 1000.0, "costs": scene.last_frame_costs}))
		check(not landing_roots.is_empty() and landing_roots == scene._landing_rim_roots.values(), "local water edit keeps distant house decoration meshes")
		var after_document := JSON.stringify(scene.landscape_state.document())
		var after_terrain := terrain_hash()
		check(after_document != before_document and after_terrain != before_terrain, "commit records water and carves its bed")
		check(scene._history_tags.size() == history_count + 1, "commit creates exactly one undo transaction")
		scene._undo()
		check(JSON.stringify(scene.landscape_state.document()) == before_document, "undo restores the complete landscape")
		check(terrain_hash() == before_terrain, "undo restores exact native terrain bytes")
		scene._redo()
		check(JSON.stringify(scene.landscape_state.document()) == after_document, "redo restores the complete water record")
		check(terrain_hash() == after_terrain, "redo restores exact carved terrain bytes")
		scene._reset_water_baseline()
		aim(Vector3(52, 8, 48))
		check(scene._start_water_stream(), "second native water stroke starts")
		aim(Vector3(54, 8, 48))
		scene._sample_water_stream()
		scene._cancel_water_stroke()
		check(JSON.stringify(scene.landscape_state.document()) == after_document and terrain_hash() == after_terrain, "cancelled preview changes neither saved water nor terrain")
	scene.queue_free()
	await process_frame
	await process_frame
	print("water_history_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
