extends SceneTree

var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scripts/m1_scene_cottage_style.gd").new()
	scene.checkpoint_root = "user://m1-cottage-ux-test-%s" % Time.get_ticks_usec()
	scene.test_mode = true
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 15000
	while (scene.backend == null or not scene.backend.is_ready() or not scene._player_restored) and Time.get_ticks_msec() < deadline:
		await process_frame
	if scene.backend == null or not scene.backend.is_ready():
		_fail("M1 backend becomes ready")
		_finish()
		return

	_check(scene._set_view_context("building", "UX test"), "enter building context")
	await process_frame
	var stable_target: Vector3 = scene._selected_building_camera_target()
	var pointer_before: Vector2 = scene.edit_pointer
	Input.action_press("m1_move_right")
	scene._read_camera_and_cursor(0.12)
	Input.action_release("m1_move_right")
	_check(scene.edit_pointer.x > pointer_before.x, "left stick moves edit pointer")
	_check(scene._selected_building_camera_target().is_equal_approx(stable_target), "pointer does not move cottage orbit target")

	var view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var picked: Dictionary = {}
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)):
			continue
		var local = detail.get("resolved_position", null)
		if not local is Vector3:
			continue
		var transform_value = view.get("transform", Transform3D.IDENTITY)
		var building_transform: Transform3D = transform_value if transform_value is Transform3D else Transform3D.IDENTITY
		var world_position: Vector3 = building_transform * (local as Vector3)
		if scene.camera.is_position_behind(world_position):
			continue
		var result: Dictionary = scene._pick_detail_at_screen_position(scene.camera.unproject_position(world_position))
		if str(result.get("id", "")) == str(detail.get("id", "")):
			picked = result
			break
	_check(not picked.is_empty(), "front-facing detail can be picked from its projected position")
	if picked.is_empty():
		_finish()
		return

	scene.hovered_detail_id = str(picked["id"])
	scene.hovered_surface_id = str(picked["surface_id"])
	scene.hovered_detail_kind = str(picked["kind"])
	var document_before: Dictionary = scene.building_world.get_document()
	_check(scene._begin_hovered_detail_move(), "A direct edit starts detail move")
	_check(scene.detail_move_active and scene.selected_detail_id == str(picked["id"]), "hovered detail becomes active move target")
	scene._cancel_detail_move()
	_check(scene.building_world.get_document() == document_before, "B-style cancel leaves building document unchanged")

	scene.hovered_detail_id = str(picked["id"])
	scene.hovered_surface_id = str(picked["surface_id"])
	scene.hovered_detail_kind = str(picked["kind"])
	_check(scene._open_hovered_detail_actions(), "X opens contextual detail actions")
	var visible_labels: Array[String] = []
	for key in scene._tool_buttons.keys():
		var button := scene._tool_buttons[key] as Button
		if button.visible:
			visible_labels.append(str(key))
	_check("Move selected window" in visible_labels and "Suppress / restore" in visible_labels and "Close" in visible_labels, "context menu exposes move remove and close")
	_check("Detail colour" in visible_labels, "context menu exposes colour")
	_check(not "Duplicate cottage" in visible_labels and not "Delete selected surface" in visible_labels, "context menu hides unrelated cottage actions")
	if str(picked["kind"]) == "window":
		_check("Replace selected" in visible_labels, "window context exposes variation")

	scene._context_actions_open = false
	scene.tools_open = false
	if scene.tools_panel: scene.tools_panel.visible = false
	scene.selected_detail_id = str(picked["id"])
	var style_before: Dictionary = scene.building_world.get_document()
	var revision_before: int = scene.building_world.get_revision()
	scene._begin_style_picker("colour")
	scene._preview_style_choice("colour", "sage")
	_check(scene.building_world.get_document() == style_before, "colour browse does not mutate building document")
	_check(scene.building_world.get_revision() == revision_before, "colour browse does not create history revision")
	scene._cancel_style_picker()
	_check(scene.building_world.get_document() == style_before, "colour cancel restores without mutation")

	scene._begin_style_picker("colour")
	scene._commit_style_choice("colour", "sage")
	_check(scene.building_world.get_revision() == revision_before + 1, "colour confirm creates one building revision")
	var styled: Dictionary = scene._selected_detail_record()
	_check(str((styled.get("override", {}) as Dictionary).get("color_id", "")) == "sage", "confirmed colour persists on detail override")
	var revision_after_colour: int = scene.building_world.get_revision()
	if str(picked["kind"]) == "window":
		scene._begin_style_picker("variation")
		scene._preview_style_choice("variation", "window_round")
		_check(scene.building_world.get_revision() == revision_after_colour, "variation browse does not create history revision")
		scene._commit_style_choice("variation", "window_round")
		_check(scene.building_world.get_revision() == revision_after_colour + 1, "variation confirm creates one building revision")
		styled = scene._selected_detail_record()
		_check(str(styled.get("asset_id", "")) == "window_round", "confirmed variation persists")

	_finish()

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: %s" % label)

func _fail(label: String) -> void:
	failures += 1
	print("FAIL: %s" % label)

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene.queue_free()
		await process_frame
		await process_frame
	print(JSON.stringify({"ok": failures == 0, "failures": failures, "cottage_edit_ux": failures == 0}))
	quit(1 if failures > 0 else 0)
