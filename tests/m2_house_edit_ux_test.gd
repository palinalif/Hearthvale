extends SceneTree
const Pick = preload("res://scripts/m2_house_part_pick.gd")
const Edit = preload("res://scripts/m2_section_edit.gd")
const SceneReadiness = preload("res://tests/scene_readiness.gd")
var scene: Node
var checks := 0
var failures := 0
var captures := 0
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
func _document_equal_ignoring_revision(a: String, b: String) -> bool:
	var da: Dictionary = JSON.parse_string(a)
	var db: Dictionary = JSON.parse_string(b)
	da.erase("revision")
	db.erase("revision")
	return da == db
func _run() -> void:
	var rendering := "--require-rendering" in OS.get_cmdline_user_args()
	if rendering: check(DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "mobile", "real Mobile renderer required")
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://house-edit-ux-%d" % Time.get_ticks_usec()
	root.add_child(scene)
	var scene_ready := await SceneReadiness.wait_for_player(self, scene)
	check(scene_ready, "house editing scene ready")
	if not scene_ready: await _finish(); return
	scene.set_process(false)
	scene._set_view_context("building")
	check(scene._apply_house_shape_preset("u_shape"), "U house fixture built through edit API")
	await _settle()
	var id: String = scene.selected_building_id
	var view: Dictionary = scene.building_world.get_building(id)
	var runs := Pick.walls(view)
	var courtyard := Pick.pick_wall(runs, Vector3(0,3.5,-30), Vector3.BACK)
	check(not courtyard.is_empty() and absf((courtyard["position"] as Vector3).z + 7) < 0.1, "ray through empty U courtyard finds the actual recessed front wall")
	var inner := Pick.pick_wall(runs, Vector3(0,3.5,-12), Vector3.RIGHT)
	check(not inner.is_empty() and inner["run"]["orientation"] == "left", "inner courtyard side wall is separately targetable")
	inner["section_id"] = "u-right"; inner["building_id"] = id
	scene._open_part_menu(inner)
	await _settle()
	check(scene._part_menu.visible and not scene._building_panel.visible, "surface actions replace the big Home options route")
	var before: String = scene.building_world.serialize_document()
	scene._choose_part_action("window")
	check(scene.detail_move_active and scene.detail_move_surface_id == inner["surface_id"], "Window starts directly on the pointed-at courtyard wall")
	check(scene.placement_ghost.has_node("FootprintTop"), "courtyard placement has a full-size footprint")
	scene._cancel_detail_move()
	check(scene.building_world.serialize_document() == before, "window cancel preserves the house")
	scene._open_part_menu(inner)
	scene._choose_part_action("material")
	scene._preview_surface_material("rose_lime")
	check(scene._surface_material_picker_kind == "wall" and scene._preview_massing_view(view)["wall_material_id"] == "rose_lime", "wall preview covers joined house rather than a single original rectangle")
	check(scene.building_world.serialize_document() == before, "material preview is read-only")
	scene._cancel_surface_material_picker()
	scene._begin_next_storey()
	check(scene.portion_valid and scene._commit_portion_placement(), "place supported upper section")
	await _settle()
	view = scene.building_world.get_building(id)
	var upper_id := ""
	for section in scene.HouseMassing.sections_for(view):
		if int(section["level"]) == 1: upper_id = str(section["id"]); break
	check(not upper_id.is_empty(), "upper section has a stable identity")
	# Drag the section edge with the pointer: A starts a drag on the nearest
	# handle, releasing A leaves a read-only proposal, a fresh A applies it.
	var section_view: Dictionary = scene.building_world.get_building(id)
	var section_transform: Transform3D = section_view["transform"]
	var original: Dictionary = Edit.section(section_view, upper_id)
	var original_right := Vector3(original["offset"]).x + Vector3(original["size"]).x * 0.5
	before = scene.building_world.serialize_document()
	var revision: int = scene.building_world.get_revision()
	scene.camera_distance = 9.0
	scene.camera_pitch = 0.7
	scene._update_camera()
	scene._begin_section_edit(upper_id)
	var center_screen: Vector2 = scene.camera.unproject_position(section_transform * (Vector3(original["offset"]) + Vector3(0.0, Vector3(original["size"]).y * 0.5, 0.0)))
	check(scene.edit_pointer.distance_to(center_screen) < 1.0, "section editing starts with the pointer centred on the section")
	await _settle()
	check(scene._section_edit_active and scene._section_reason.is_empty(), "already placed upper section opens read-only section editing")
	check(scene._part_lines.visible and scene._part_lines.points.size() == 4, "all four edge handles are visible")
	check(scene.building_world.serialize_document() == before, "section editing has no saved side effects")
	var left_handle: Vector2 = scene.camera.unproject_position(section_transform * scene._section_handle_point(Vector3(original["offset"]), Vector3(original["size"]), "left"))
	scene.edit_pointer = left_handle + Vector2(-18, 0)
	scene._section_update_pointer()
	check(scene._section_edge == Edit.EDGES.find("left"), "pointer near the left handle aims the left edge")
	_press("m1_accept")
	check(scene._section_dragging, "A press starts a drag on the aimed edge")
	scene.edit_pointer = left_handle + Vector2(-190, 0)
	scene._section_update_drag()
	check(scene._section_candidate != original and scene._section_reason.is_empty(), "drag grows the left edge as a read-only proposal")
	check(absf(Vector3(scene._section_candidate["offset"]).x + Vector3(scene._section_candidate["size"]).x * 0.5 - original_right) < 0.001, "left drag keeps the right edge fixed")
	check(scene.building_world.serialize_document() == before, "drag proposal never writes the house")
	if rendering: await _capture("upper-floor-drag-resize")
	_release("m1_accept")
	scene._section_update_drag()
	check(not scene._section_dragging and scene._section_reviewing, "release A leaves a reviewable proposal and never commits")
	_press("m1_cancel")
	check(not scene._section_edit_active and scene.building_world.serialize_document() == before and scene.building_world.get_revision() == revision, "B during review restores exact section and history")
	scene._begin_section_edit(upper_id)
	scene.edit_pointer = left_handle + Vector2(-18, 0)
	scene._section_update_pointer()
	_press("m1_accept")
	scene.edit_pointer = left_handle + Vector2(-190, 0)
	scene._section_update_drag()
	scene.menu_open = true
	scene._section_update_drag()
	check(not scene._section_dragging and scene._section_reviewing, "menu over a held drag ends the drag into a proposal")
	check(scene.building_world.get_revision() == revision, "menu over a held drag never commits")
	scene.menu_open = false
	_press("m1_accept")
	check(scene.building_world.get_revision() == revision + 1, "A after release is one section edit")
	check(Edit.section(scene.building_world.get_building(id), upper_id)["size"] != original["size"], "existing upper section changes, not a new appended section")
	check(scene.building_world.undo(), "section undo")
	check(Edit.section(scene.building_world.get_building(id), upper_id) == original, "undo restores full original section")
	var revision2: int = scene.building_world.get_revision()
	scene._begin_section_edit(upper_id)
	var bad := original.duplicate(true)
	bad["size"] = Vector3(19, 3, 19)
	scene._section_candidate = bad
	check(not scene._commit_section_edit() and scene._section_edit_active, "invalid proposal blocks the confirm action")
	check(not scene._section_reason.is_empty(), "invalid proposal shows its reason")
	_press("m1_cancel"); _release("m1_cancel")
	check(not scene._section_edit_active and _document_equal_ignoring_revision(scene.building_world.serialize_document(), before) and scene.building_world.get_revision() == revision2, "cancel after blocked confirm restores exact section")
	scene._begin_section_edit(upper_id)
	_press("m1_accept")
	scene._section_update_drag()
	_press("m1_pause")
	check(not scene._section_edit_active and _document_equal_ignoring_revision(scene.building_world.serialize_document(), before) and scene.building_world.get_revision() == revision2, "pause cancels the edit without committing")
	_release("m1_accept"); _release("m1_pause")
	scene.menu_open = false
	scene._part_menu_open = false
	if rendering:
		scene._update_presentation(); scene._update_camera()
		await _settle()
		var roof_hit: Dictionary = {}
		for y in range(160,520,30):
			for x in range(200,1080,30):
				var hit: Dictionary = scene._pick_house_part(Vector2(x,y))
				if hit.get("kind", "") == "roof": roof_hit = hit; break
			if not roof_hit.is_empty(): break
		check(not roof_hit.is_empty(), "actual Mobile roof geometry is directly targetable")
		if not roof_hit.is_empty():
			scene._open_part_menu(roof_hit); await _settle(); scene._refresh_part_feedback()
			await _capture("roof-context")
			scene._choose_part_action("shape"); await _settle(); scene._refresh_part_feedback()
			check(scene._roof_design_picker.visible and scene._roof_design_picker.size.y < 100, "roof shape chooser is a compact visual row")
			await _capture("roof-shapes")
			scene._cancel_roof_design_picker()
		scene._open_part_menu(inner); scene._choose_part_action("material"); await _settle(); scene._refresh_part_feedback()
		await _capture("all-walls-material")
		scene._cancel_surface_material_picker()
		check(captures == 4, "four actual UX captures produced")
	await _finish()
func _capture(label: String) -> void:
	DirAccess.make_dir_recursive_absolute(".tools/cottage-repair/house-ux")
	for i in 4: await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png(".tools/cottage-repair/house-ux/%s.png" % label) == OK, "actual UX capture saved")
	captures += 1
func _finish() -> void:
	if is_instance_valid(scene):
		scene._shutting_down = true; scene.queue_free(); await process_frame; await process_frame
	print("HOUSE_EDIT_UX_RESULT " + JSON.stringify({"ok":failures == 0,"checks":checks,"failures":failures,"captures":captures}))
	quit(1 if failures else 0)
