extends SceneTree
## Physical joypad events routed through the complete exported scene. Synthetic
## geometry checks are not a substitute for the subsequent Mobile/Thor review.
var scene: Node
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + message)

func _button(index: int) -> void:
	var down := InputEventJoypadButton.new()
	down.button_index = index
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventJoypadButton.new()
	up.button_index = index
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame

func _front(view: Dictionary) -> Dictionary:
	var wall := ""
	for s in view["surfaces"]:
		if str(s.get("orientation", "")) == "front": wall = str(s["id"])
	for detail in view["details"]:
		if str(detail["anchor"]["surface_id"]) == wall and str(detail["kind"]) == "window" and bool(detail.get("visible", false)) and not bool(detail.get("needs_placement", false)): return detail
	return {}

func _aim_detail(detail: Dictionary) -> void:
	var view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var transform_value: Transform3D = view["transform"]
	scene.camera_yaw = PI
	scene.camera_pitch = 0.20
	scene.camera_distance = 12.0
	scene._update_camera()
	scene.edit_pointer = scene.camera.unproject_position(transform_value * (detail["resolved_position"] as Vector3))
	scene._update_detail_hover()
	scene._update_direct_edit_hud()

func _renderer_identities() -> void:
	var roots: Array = []
	for node in scene.get_children():
		if node.get_script() == preload("res://scripts/cottage_visual.gd"): roots.append(node)
	check(roots.size() == scene.building_world.get_buildings().size(), "one renderer per authoritative cottage")
	for view in scene.building_world.get_buildings():
		var visual: Node3D = scene.cottage_visuals.get(str(view["id"]))
		check(visual != null and str(visual.building_id) == str(view["id"]), "renderer keeps its own building ID")
		if visual: check(visual.transform.is_equal_approx(view["transform"]), "renderer keeps its own transform")

func _run() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m1-repair-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene.backend != null and scene.backend.is_ready() and scene._player_restored, "scene ready")
	if not scene._player_restored: _finish(); return
	scene.set_process(false)
	check(scene.brush_strength_level == 3, "Raise defaults to 3")
	scene._set_sculpt_tool("smooth")
	check(scene.brush_strength_level == 5 and is_equal_approx(scene.brush_strength, 2.0), "Smooth retains playtested rate")
	scene.set_brush_strength_level(6)
	scene._set_sculpt_tool("dig")
	check(scene.brush_strength_level == 3, "Dig has its own gentle default")
	scene._set_sculpt_tool("smooth")
	check(scene.brush_strength_level == 6, "per-tool manual strength survives switching")
	scene._set_sculpt_tool("raise")
	var first_id: String = scene.selected_building_id
	var first: Dictionary = scene.building_world.get_building(first_id)
	var transform_value: Transform3D = first["transform"]
	var dims: Vector3 = first["dimensions"]
	var target := transform_value * Vector3(0, dims.y * 0.5, -dims.z * 0.5)
	scene.cursor = target
	scene._terrain_target_point = target
	scene._terrain_target_valid = true
	scene.camera.global_position = target + Vector3(0, 2, -12)
	scene.camera.look_at(target)
	scene._update_world_hover()
	check(str(scene._world_hover.get("id", "")) == first_id and scene._world_mesh_highlight_id == first_id, "Terrain hover highlights the cottage mesh")
	var highlighted_geometry := 0
	for child in (scene.cottage_visuals[first_id] as Node3D).get_children():
		if child is GeometryInstance3D and (child as GeometryInstance3D).material_overlay != null: highlighted_geometry += 1
	check(highlighted_geometry > 0, "terrain hover applies amber outline material to actual house geometry")
	await _button(JOY_BUTTON_X)
	check(scene.view_context == "building" and scene.selected_building_id == first_id, "physical X enters hovered cottage, not terrain settings")
	check(not scene.tools_open, "entry does not open a second menu")
	var window := _front(first)
	check(not window.is_empty(), "window fixture exists")
	if window.is_empty(): _finish(); return
	_aim_detail(window)
	check(scene.hovered_detail_id == str(window["id"]), "visible window is selected deliberately")
	var history: int = scene._history_tags.size()
	await _button(JOY_BUTTON_A)
	check(scene.detail_move_active, "physical A picks up hovered window")
	var y_start: float = scene.detail_move_position.y
	Input.action_press("m1_move_up", 1.0)
	for i in 14: scene._read_detail_move(1.0 / 60.0)
	Input.action_release("m1_move_up")
	check(scene.detail_move_position.y > y_start + 0.4, "small held deltas escape alignment snapping")
	await _button(JOY_BUTTON_A)
	check(not scene.detail_move_active and scene._history_tags.size() == history + 1, "window movement commits exactly one undo entry")
	var moved: Dictionary = scene._selected_detail_record()
	check(str(moved.get("anchor", {}).get("policy", "")) == "surface_local", "manual window anchor persists")
	_aim_detail(moved)
	var before_cancel: String = scene.building_world.serialize_document()
	await _button(JOY_BUTTON_A)
	Input.action_press("m1_move_down", 1.0)
	scene._read_detail_move(0.20)
	Input.action_release("m1_move_down")
	await _button(JOY_BUTTON_B)
	check(scene.view_context == "building" and not scene.detail_move_active and scene.building_world.serialize_document() == before_cancel, "B cancels move before exiting, without data mutation")

	var copy_id: String = scene.building_world.duplicate_building(first_id, Vector3(10, 0, 10))
	check(not copy_id.is_empty(), "second cottage created")
	scene.selected_building_id = copy_id
	scene._update_presentation()
	_renderer_identities()
	var copy_view: Dictionary = scene.building_world.get_building(copy_id)
	var copy_window := _front(copy_view)
	_aim_detail(copy_window)
	await _button(JOY_BUTTON_X)
	scene._refresh_controller_hud()
	check(scene._context_actions_open and not scene._building_panel.visible, "detail menu is not covered by shell actions")
	var variation: Button = scene._tool_buttons["Replace selected"]
	check(variation.visible, "Variation remains reachable after hover is cleared")
	variation.grab_focus()
	await _button(JOY_BUTTON_A)
	scene._refresh_controller_hud()
	check(scene._style_picker_mode == "variation" and not scene._building_panel.visible, "A opens variation picker, without overlapping shell menu")
	scene._preview_style_choice("variation", "window_round")
	_renderer_identities()
	var child_count: int = scene.cottage_visual.get_child_count()
	var first_child: int = scene.cottage_visual.get_child(0).get_instance_id()
	for i in 5: scene._update_presentation()
	check(scene.cottage_visual.get_child_count() == child_count and scene.cottage_visual.get_child(0).get_instance_id() == first_child, "stationary style preview does not rebuild meshes every frame")
	await _button(JOY_BUTTON_B)
	scene._update_presentation()
	_renderer_identities()
	check(scene._style_picker_mode.is_empty() and scene.view_context == "building", "B cancels style without exiting cottage")

	# A deliberately unsupported shutter is recovered through real menu focus.
	var wall := ""
	for surface in copy_view["surfaces"]:
		if str(surface.get("orientation", "")) == "front": wall = str(surface["id"])
	var shutter_id: String = scene.building_world.add_detail(copy_id, "shutter", wall, Vector3(0, dims.y + 2, -dims.z * 0.5 - 0.02), "shutter_wood")
	check(not shutter_id.is_empty() and not scene._needs_details().is_empty(), "unsupported shutter fixture retained")
	scene._open_building_panel()
	scene._refresh_needs_placement_panel()
	scene._needs_action.grab_focus()
	await _button(JOY_BUTTON_A)
	check(scene._needs_open and scene._needs_panel.visible, "Needs Placement is controller reachable")
	check(scene._needs_box.is_ancestor_of(root.gui_get_focus_owner()), "focus moves into recovery tray")
	before_cancel = scene.building_world.serialize_document()
	await _button(JOY_BUTTON_A)
	check(scene.detail_move_active and scene.selected_detail_id == shutter_id, "A picks the actual recovery item")
	check(scene.detail_move_surface_id == wall, "recovered attachment starts on camera-facing wall")
	await _button(JOY_BUTTON_B)
	check(scene.building_world.serialize_document() == before_cancel, "recovery cancel preserves unsupported detail")
	scene._open_needs_placement()
	await _button(JOY_BUTTON_A)
	await _button(JOY_BUTTON_A)
	check(scene._needs_details().is_empty(), "recovery confirm makes shutter supported")

	# Empty ground cannot advertise sculpting while the cottage owns editing.
	scene.edit_pointer = Vector2(50, 600)
	scene._update_detail_hover()
	scene._shell_hovered = scene._pointer_over_selected_shell()
	scene._refresh_controller_hud()
	var prompt_signature: String = scene._prompt_row.get_meta("signature", "")
	check(not prompt_signature.contains("Sculpt") and prompt_signature.contains("Finish editing"), "ground hover retains Building-only prompts")
	var before_exit: Transform3D = scene.camera.global_transform
	await _button(JOY_BUTTON_B)
	scene._update_camera()
	check(scene.view_context == "terrain" and not scene.menu_open, "idle B exits cottage editing")
	check(scene.camera.global_transform.is_equal_approx(before_exit), "exiting does not teleport to old terrain view")

	scene._world_hover = {}
	scene._set_view_context("building")
	var source_id: String = scene.selected_building_id
	var camera_before: Transform3D = scene.camera.global_transform
	scene._begin_building_placement()
	scene.building_placement_target += Vector3(2, 0, 2)
	scene.cursor = scene.building_placement_target
	scene._update_camera()
	var placement_target: Vector3 = scene.building_placement_target + Vector3(0, 2, 0)
	check((-scene.camera.global_basis.z).dot((placement_target - scene.camera.global_position).normalized()) > 0.999, "duplicate camera follows free placement, not source cottage")
	await _button(JOY_BUTTON_B)
	check(scene.selected_building_id == source_id and scene.camera.global_transform.is_equal_approx(camera_before), "duplicate cancel restores source orbit")
	_renderer_identities()

	# Save/modify/reload/resume must immediately regain a usable terrain target.
	scene._set_view_context("terrain")
	scene._set_sculpt_tool("dig")
	scene.cursor = Vector3(32, 8, 28)
	check(scene._save_all(), "checkpoint saved")
	var old_buffer: int = scene.backend.voxels.get_instance_id()
	check(scene.backend.apply_sphere(Vector3(32, 8, 28), 0.5, true), "post-save terrain edit fixture")
	scene.cursor.y = 0.5
	scene._terrain_target_valid = false
	scene._set_menu(true)
	await process_frame
	for button in scene._pause_stack.get_children():
		if button is Button and button.text == "Reload last save" and not button.is_queued_for_deletion(): button.grab_focus()
	await _button(JOY_BUTTON_A)
	check(scene.backend.voxels.get_instance_id() != old_buffer, "reload actually replaced the authoritative buffer")
	await _button(JOY_BUTTON_B)
	deadline = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		scene._update_brush_preview()
		if scene._terrain_target_valid and not scene._layer_pending: break
		await process_frame
	check(scene._terrain_target_valid and scene.terrain_edit_preview.visible, "reload/resume restores live terrain target and preview")
	check(not scene._blocked_until_accept_release, "reload did not strand the accept-release safety latch")
	var down := InputEventJoypadButton.new()
	down.button_index = JOY_BUTTON_A
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	check(scene.stroke_active, "physical A can immediately sculpt after reload")
	for i in 10: scene.backend.update_stroke(scene.cursor + scene.stroke_aim_offset, 1.0 / 60.0)
	var up := InputEventJoypadButton.new()
	up.button_index = JOY_BUTTON_A
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame
	check(not scene.stroke_active, "post-reload stroke commits on release")
	_finish()

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m1_playtest_repair_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
