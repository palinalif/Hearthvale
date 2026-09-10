extends SceneTree
const Pick = preload("res://scripts/m2_house_part_pick.gd")
const Edit = preload("res://scripts/m2_section_edit.gd")
var scene: Node
var checks := 0
var failures := 0
var captures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + label)
func _initialize() -> void: _run.call_deferred()
func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action; event.pressed = true
	scene._input(event)
func _settle() -> void:
	for i in 3: await process_frame
func _run() -> void:
	var rendering := "--require-rendering" in OS.get_cmdline_user_args()
	if rendering: check(DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "mobile", "real Mobile renderer required")
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://house-edit-ux-%d" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + (120000 if rendering else 65000)
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "house editing scene ready")
	if not scene._player_restored: await _finish(); return
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
	before = scene.building_world.serialize_document()
	scene._begin_section_edit(upper_id)
	var original: Dictionary = Edit.section(view,upper_id)
	scene._change_section_size(1)
	await _settle()
	check(scene._section_edit_active and scene._section_reason.is_empty(), "already placed upper section can expand with visible edge controls")
	check(scene._part_lines.visible and scene._part_lines.handles.size() == 4, "all four edge handles are visible")
	check(scene.building_world.serialize_document() == before, "resize preview has no saved side effects")
	if rendering: await _capture("upper-floor-resize")
	_press("m1_cancel")
	check(not scene._section_edit_active and scene.building_world.serialize_document() == before, "controller cancel restores exact section and history")
	scene._begin_section_edit(upper_id); scene._change_section_size(1)
	var revision: int = scene.building_world.get_revision()
	_press("m1_accept")
	check(scene.building_world.get_revision() == revision + 1, "controller confirmation is one section edit")
	check(Edit.section(scene.building_world.get_building(id), upper_id)["size"] != original["size"], "existing upper section changes, not a new appended section")
	check(scene.building_world.undo(), "section undo")
	check(Edit.section(scene.building_world.get_building(id),upper_id) == original, "undo restores full original section")
	if rendering:
		# Pick an actual rendered roof: the cache reads real MultiMesh transforms.
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
