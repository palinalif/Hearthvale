# Controller-level drag resize: pointer aims the edge, A drags it, release A
# leaves a read-only proposal, a fresh A applies exactly one edit, and a stale
# world revision blocks the confirm.
extends SceneTree
const Edit = preload("res://scripts/m2_section_edit.gd")
const M2HouseMassing = preload("res://scripts/m2_house_massing.gd")
const SceneReadiness = preload("res://tests/scene_readiness.gd")
var scene: Node
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + label)
func _initialize() -> void: _run.call_deferred()
func _press(action: String) -> void:
	Input.action_press(action)
	var event := InputEventAction.new()
	event.action = action; event.pressed = true
	scene._input(event)
func _release(action: String) -> void:
	Input.action_release(action)
	var event := InputEventAction.new()
	event.action = action; event.pressed = false
	scene._input(event)
func _settle() -> void:
	for i in 3: await process_frame
func _run() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://section-drag-%d" % Time.get_ticks_usec()
	root.add_child(scene)
	var scene_ready := await SceneReadiness.wait_for_player(self, scene)
	check(scene_ready, "drag resize scene ready")
	if not scene_ready: await _finish(); return
	scene.set_process(false)
	scene._set_view_context("building")
	check(scene._apply_house_shape_preset("u_shape"), "U house fixture built through edit API")
	await _settle()
	var id: String = scene.selected_building_id
	scene._begin_next_storey()
	check(scene.portion_valid and scene._commit_portion_placement(), "supported upper section placed")
	await _settle()
	var view: Dictionary = scene.building_world.get_building(id)
	var upper_id := ""
	for section in scene.HouseMassing.sections_for(view):
		if int(section["level"]) == 1: upper_id = str(section["id"]); break
	check(not upper_id.is_empty(), "upper section has a stable identity")
	var transform: Transform3D = view["transform"]
	var original: Dictionary = Edit.section(view, upper_id)
	var before: String = scene.building_world.serialize_document()
	var revision: int = int(scene.building_world.get_revision())
	# Face contract: the aim handles sit on the true `section_rect` faces
	# (offset is the section centre in x/z, faces at offset +/- size/2).
	var rect: Rect2 = scene.HouseMassing.section_rect(original)
	var mid_height := (original["offset"] as Vector3).y + (original["size"] as Vector3).y * 0.5
	check(scene._section_handle_point(original["offset"], original["size"], "left").is_equal_approx(Vector3(rect.position.x, mid_height, rect.position.y + rect.size.y * 0.5)), "left handle is on the section_rect left face")
	check(scene._section_handle_point(original["offset"], original["size"], "right").is_equal_approx(Vector3(rect.end.x, mid_height, rect.position.y + rect.size.y * 0.5)), "right handle is on the section_rect right face")
	var expected_bounds: AABB = AABB(
		Vector3(rect.position.x, M2HouseMassing.section_bottom(original), rect.position.y),
		Vector3(original["size"]))
	check(scene._section_aabb(original) == expected_bounds, "section AABB matches section_rect centred x/z with level-base y")
	check(scene._section_handle_point(original["offset"], original["size"], "front").is_equal_approx(Vector3(rect.position.x + rect.size.x * 0.5, mid_height, rect.position.y)), "front handle is on the section_rect front face")
	check(scene._section_handle_point(original["offset"], original["size"], "back").is_equal_approx(Vector3(rect.position.x + rect.size.x * 0.5, mid_height, rect.end.y)), "back handle is on the section_rect back face")
	scene.camera_distance = 9.0
	scene.camera_pitch = 0.7
	scene._update_camera()
	# 1) Aim, drag, release, confirm: one revision and one clean undo.
	scene._begin_section_edit(upper_id)
	await _settle()
	var left_handle: Vector2 = scene.camera.unproject_position(transform * scene._section_handle_point(Vector3(original["offset"]), Vector3(original["size"]), "left"))
	scene.edit_pointer = left_handle + Vector2(-18, 0)
	scene._section_update_pointer()
	scene.edit_pointer = left_handle + Vector2(-60, 0)
	_press("m1_accept")
	scene._section_update_drag()
	check(scene._section_dragging and scene._section_candidate != original and scene._section_reason.is_empty(), "held A drags the aimed edge into a valid proposal")
	_release("m1_accept")
	scene._section_update_drag()
	check(not scene._section_dragging and scene._section_reviewing, "release A leaves a read-only proposal")
	var proposal: Dictionary = scene._section_candidate.duplicate(true)
	_press("m1_accept")
	check(scene.building_world.get_revision() == revision + 1, "fresh A applies exactly one revision")
	check(Edit.section(scene.building_world.get_building(id), upper_id) == proposal, "committed section equals the reviewed proposal with the same id")
	check(scene.building_world.undo(), "one undo")
	await _settle()
	check(Edit.section(scene.building_world.get_building(id), upper_id) == original, "undo restores the original section")
	# 2) A stale world revision blocks the section confirm.
	scene._begin_section_edit(upper_id)
	scene._begin_next_storey()
	check(scene.portion_valid and scene._commit_portion_placement(), "external storey edit advances the world")
	check(not scene._commit_section_edit() and scene._section_edit_active, "stale revision blocks the confirm without applying")
	_press("m1_cancel"); _release("m1_cancel")
	check(not scene._section_edit_active and scene.building_world.get_revision() == revision + 3, "cancel keeps the external edit and closes the section")
	# 2b) Controller disconnect / window focus loss: releasing A mid-drag ends
	# the drag at the read-only proposal and never commits; a fresh deliberate
	# A press is the only confirm path and commits exactly once; B cancels.
	scene._begin_section_edit(upper_id)
	await _settle()
	var left_handle2: Vector2 = scene.camera.unproject_position(transform * scene._section_handle_point(original["offset"], original["size"], "left"))
	scene.edit_pointer = left_handle2 + Vector2(-18, 0)
	scene._section_update_pointer()
	scene.edit_pointer = left_handle2 + Vector2(-60, 0)
	_press("m1_accept")
	scene._section_update_drag()
	check(scene._section_dragging, "held A starts the drag")
	_release("m1_accept")
	scene._section_update_drag()
	check(scene._section_reviewing and scene.building_world.get_revision() == revision + 3, "accept release mid-drag ends at the proposal without committing")
	var proposal2: Dictionary = scene._section_candidate.duplicate(true)
	check(scene._section_reviewing and scene._section_reason.is_empty(), "released proposal is valid and silently reviewable")
	_press("m1_accept")
	check(scene.building_world.get_revision() == revision + 4, "one deliberate A press commits the proposal exactly once")
	check(Edit.section(scene.building_world.get_building(id), upper_id) == proposal2, "committed section equals the reviewed proposal")
	check(not scene._section_edit_active, "confirm closes the section edit")
	# 3) Pointer aiming selects the nearest visible edge handle.
	scene._begin_section_edit(upper_id)
	var right_handle: Vector2 = scene.camera.unproject_position(transform * scene._section_handle_point(Vector3(original["offset"]), Vector3(original["size"]), "right"))
	scene.edit_pointer = right_handle + Vector2(18, 0)
	scene._section_update_pointer()
	check(scene._section_edge == Edit.EDGES.find("right"), "pointer near the right handle aims the right edge")
	_press("m1_cancel"); _release("m1_cancel")
	await _finish()
func _finish() -> void:
	if is_instance_valid(scene):
		scene._shutting_down = true; scene.queue_free(); await process_frame; await process_frame
	print("SECTION_DRAG_RESULT " + JSON.stringify({"ok":failures == 0,"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
