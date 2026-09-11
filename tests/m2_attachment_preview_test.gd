extends SceneTree

const Ghost = preload("res://scripts/detail_placement_ghost.gd")
const Placement = preload("res://scripts/wall_attachment_placement.gd")
var scene: Node
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check_ghost_geometry()
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-window-preview-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "attachment repair scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	var building_id: String = scene.selected_building_id
	var ids: Array[String] = []
	for x in [-4.0, 4.0]:
		var id: String = scene.building_world.add_detail(building_id, "window", "wall-front", Vector3(x, 3.5, -7.02), "window_wood")
		check(not id.is_empty(), "create independent manual window")
		if not id.is_empty(): ids.append(id)
	if ids.size() != 2:
		await _finish()
		return
	var before: String = scene.building_world.serialize_document()
	scene.detail_move_position = Vector3(1, 1, 1)
	for id in [ids[1], ids[0], ids[1]]:
		scene.selected_detail_id = id
		var record: Dictionary = scene._selected_detail_record()
		check((record.get("anchor", {}) as Dictionary).get("local_position") is Array, "move fixture uses persisted array anchor")
		var position: Vector3 = record["resolved_position"]
		scene._begin_detail_move()
		check(scene.detail_move_active and scene.selected_detail_id == id, "move keeps exact selected ID")
		check(scene.detail_move_position.is_equal_approx(position) and scene._detail_free_position.is_equal_approx(position), "move starts at selected window, never previous placement")
		for frame in 3: scene._read_detail_move(0.1)
		check(scene.detail_move_position.is_equal_approx(position), "idle pickup never aligns or jumps")
		check(scene.placement_ghost.visible and scene.placement_ghost.has_node("FootprintTop"), "moving window shows whole reserved footprint")
		check(not scene.placement_ghost.has_node("OpeningPreview"), "moving preview retains real window instead of covering it")
		scene._cancel_detail_move()
		check(scene.building_world.serialize_document() == before, "cancel leaves all windows and revision identical")
	scene.selected_detail_id = ids[1]
	var original: Dictionary = scene._selected_detail_record()
	scene._begin_detail_move()
	scene.detail_move_position += Vector3(0.5, 0, 0)
	var intended: Vector3 = scene.detail_move_position
	var revision: int = scene.building_world.get_revision()
	check(scene._commit_detail_move(), "window move confirms")
	check(scene.building_world.get_revision() == revision + 1, "window move is one edit")
	check((scene._selected_detail_record()["resolved_position"] as Vector3).is_equal_approx(intended), "committed position matches preview")
	check(scene.building_world.undo(), "move undo succeeds")
	check(scene._selected_detail_record() == original, "undo restores selected window exactly")
	check(scene.building_world.redo(), "move redo succeeds")
	var stable: String = scene.building_world.serialize_document()
	check(scene.building_world.load_serialized_document(stable), "moved window reloads")
	scene.selected_detail_id = ids[1]
	scene.detail_move_position = Vector3(-50, -50, -50)
	scene._begin_detail_move()
	check(scene.detail_move_position.is_equal_approx(intended), "reloaded window pickup resolves its own array position")
	scene._cancel_detail_move()

	# Sequential moves must be invalidated by unrelated authoritative edits.
	scene.selected_detail_id = ids[1]
	scene._begin_detail_move()
	check(scene.building_world.suppress_detail(building_id, ids[0]), "separate edit changes revision during preview")
	stable = scene.building_world.serialize_document()
	check(not scene._commit_detail_move() and not scene.detail_move_active, "stale placement is cancelled")
	check(scene.building_world.serialize_document() == stable, "stale rejection does not overwrite newer edit")
	await _finish()

func _check_ghost_geometry() -> void:
	var ghost := Ghost.new()
	root.add_child(ghost)
	var records: Array[Dictionary] = [
		{"kind": "window", "asset_id": "window_wood"},
		{"kind": "window", "asset_id": "window_round"},
		{"kind": "door", "asset_id": "door_timber"},
		{"kind": "window", "asset_id": "window_wood", "override": {"size": [3.5, 4.0]}},
	]
	for record in records:
		var half := Placement.footprint_for_detail(record)
		var size := Placement.detail_size(record)
		for orientation in ["front", "back", "left", "right"]:
			var house := Transform3D(Basis(Vector3.UP, 0.37).scaled(Vector3.ONE * 0.25), Vector3(10, 8, 4))
			var position := Vector3(4, 10.5, -7.02)
			ghost.show_attachment(house, orientation, position, record["kind"], record, half)
			var top := ghost.get_node("FootprintTop") as MeshInstance3D
			var right := ghost.get_node("FootprintRight") as MeshInstance3D
			var body := ghost.get_node("OpeningPreview") as MeshInstance3D
			check((top.mesh as BoxMesh).size.x == half.x * 2 and top.position.y == half.y, "ghost spans full reserved width/height")
			check((right.mesh as BoxMesh).size.y == half.y * 2 and right.position.x == half.x, "ghost includes frame and trim clearance")
			check((body.mesh as BoxMesh).size.x == size.x and (body.mesh as BoxMesh).size.y == size.y, "body preview uses actual resized window or door dimensions")
			check(ghost.position.is_equal_approx(house * position), "ghost anchors to correct floor under rotated miniature transform")
			check(ghost.basis.get_scale().is_equal_approx(Vector3.ONE * 0.25), "preview retains miniature scale")
			var identity := top.get_instance_id()
			ghost.show_attachment(house, orientation, position + Vector3.UP, record["kind"], record, half)
			check(ghost.get_node("FootprintTop").get_instance_id() == identity, "moving unchanged preview does not rebuild meshes")
	ghost.show_attachment(Transform3D.IDENTITY, "front", Vector3.ZERO, "window", records[0], Vector2(1.375, 2.07), false)
	check(ghost.has_node("InvalidMark"), "invalid placement has non-colour-only marker")
	ghost.hide_attachment()
	check(not ghost.visible, "closing hides footprint and body")
	ghost.free()

func _finish() -> void:
	if is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m2_attachment_preview_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
