extends SceneTree

var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scripts/m1_scene_detail_resize.gd").new()
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
		_check("Resize detail" in visible_labels, "window context exposes resize")

	scene._context_actions_open = false
	scene.tools_open = false
	if scene.tools_panel: scene.tools_panel.visible = false
	scene.selected_detail_id = str(picked["id"])
	var style_before: Dictionary = scene.building_world.get_document()
	var revision_before: int = scene.building_world.get_revision()
	scene._begin_style_picker("colour")
	await process_frame
	var selected_local: Vector3 = scene._selected_detail_record()["resolved_position"]
	var selected_transform: Transform3D = scene.building_world.get_building(scene.selected_building_id)["transform"]
	var selected_screen: Vector2 = scene.camera.unproject_position(selected_transform * selected_local)
	_check(not scene.tools_panel.get_global_rect().grow(20).has_point(selected_screen), "live picker docks away from the selected detail")
	_check(scene._highlighted_detail_geometry_count() > 0, "live picker outlines the edited detail's actual mesh")
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

	# Resize previews are non-authoritative and commit as one undoable recipe
	# edit. The default door uses the same direct picker/actions path.
	scene.selected_detail_id = str(picked["id"])
	var resize_before: Dictionary = scene.building_world.get_document()
	scene._begin_detail_resize()
	_check(scene.detail_resize_active, "window resize starts from contextual action")
	scene.detail_resize_size = scene._detail_resize_original + Vector2(0.5, 0.5)
	scene._update_presentation()
	_check(scene.building_world.get_document() == resize_before, "window resize preview is read only")
	_check(scene._commit_detail_resize(), "window resize commits")
	_check((scene._selected_detail_record().get("override", {}) as Dictionary).has("size"), "window size persists as an authored override")
	var door: Dictionary = {}
	for detail in scene.building_world.get_building(scene.selected_building_id).get("details", []):
		if str(detail.get("kind", "")) == "door": door = detail
	_check(not door.is_empty() and bool(door.get("visible", false)), "editable door is present and visible")
	if not door.is_empty():
		scene.selected_detail_id = str(door["id"])
		scene.hovered_detail_id = str(door["id"])
		scene.hovered_detail_kind = "door"
		scene._context_actions_open = true
		scene._update_action_buttons()
		_check(scene._detail_resize_button.visible and scene._detail_colour_button.visible, "door actions expose resize and colour")
		_check((scene._tool_buttons["Replace selected"] as Button).visible, "door exposes categorized variations")
		scene._context_actions_open = false
		var door_variation_revision: int = scene.building_world.get_revision()
		scene._begin_style_picker("variation")
		_check(scene._style_candidates("variation").size() == 6, "door variation category contains two choices for every home family")
		scene._preview_style_choice("variation", "door_tudor")
		_check(scene.building_world.get_revision() == door_variation_revision, "door variation browse remains read only")
		scene._cancel_style_picker()
		var door_revision: int = scene.building_world.get_revision()
		_check(scene._commit_detail_style(str(door["id"]), str(door["asset_id"]), "berry"), "door recolour commits")
		_check(scene.building_world.get_revision() == door_revision + 1, "door recolour creates one revision")
		door = scene._selected_detail_record()
		_check(str((door.get("override", {}) as Dictionary).get("color_id", "")) == "berry", "door colour persists")
		var door_position: Vector3 = door["resolved_position"]
		_check(scene.building_world.move_detail(scene.selected_building_id, str(door["id"]), str(door["anchor"]["surface_id"]), door_position + Vector3(0, 0, 1.0)), "door can move along its wall")
		door = scene._selected_detail_record()
		_check(scene.building_world.resize_detail(scene.selected_building_id, str(door["id"]), Vector2(2.25, 4.0)), "door can resize")
		var persisted_size = (scene._selected_detail_record().get("override", {}) as Dictionary).get("size", [])
		_check(persisted_size == [2.25, 4.0], "door size persists")

	# Shutters and flower boxes now use the same intentional variation browser
	# instead of receiving an unchangeable derived craft choice.
	var attachment_specs := [
		["flower_box", Vector3(0, 1.5, 7.02), "flower_box_wood", "flower_box_woven"],
		["shutter", Vector3(0, 4.0, 7.02), "shutter_wood", "shutter_braced"],
	]
	var attachment_ids: Dictionary = {}
	var expected_attachment_assets: Dictionary = {}
	for spec in attachment_specs:
		var detail_id: String = scene.building_world.add_detail(scene.selected_building_id, str(spec[0]), "wall-back", spec[1], str(spec[2]))
		_check(not detail_id.is_empty(), "%s fixture can be placed" % spec[0])
		if detail_id.is_empty(): continue
		attachment_ids[str(spec[0])] = detail_id
		scene.selected_detail_id = detail_id
		scene.hovered_detail_id = detail_id
		scene.hovered_detail_kind = str(spec[0])
		scene._context_actions_open = true
		scene._update_action_buttons()
		_check((scene._tool_buttons["Replace selected"] as Button).visible, "%s exposes variations" % spec[0])
		scene._context_actions_open = false
		var before_attachment_preview: Dictionary = scene.building_world.get_document()
		scene._begin_style_picker("variation")
		_check(scene._style_candidates("variation").size() == 4, "%s category contains mixed plus three intentional crafts" % spec[0])
		scene._preview_style_choice("variation", str(spec[3]))
		_check(scene.building_world.get_document() == before_attachment_preview, "%s preview remains read only" % spec[0])
		scene._commit_style_choice("variation", str(spec[3]))
		_check(str(scene._selected_detail_record().get("asset_id", "")) == str(spec[3]), "%s variation commits" % spec[0])
		_check(scene.building_world.undo(), "%s variation is undoable" % spec[0])
		_check(str(scene._selected_detail_record().get("asset_id", "")) == str(spec[2]), "%s undo restores its prior craft" % spec[0])
		_check(scene.building_world.redo(), "%s variation is redoable" % spec[0])
		_check(str(scene._selected_detail_record().get("asset_id", "")) == str(spec[3]), "%s redo restores its selected craft" % spec[0])
		expected_attachment_assets[str(spec[0])] = str(spec[3])
	var decoration_document: String = scene.building_world.serialize_document()
	var restored := preload("res://scripts/building_world.gd").new()
	_check(restored.load_serialized_document(decoration_document), "expanded decoration assets reload")
	for kind in attachment_ids:
		var restored_asset := ""
		for detail in restored.get_building(scene.selected_building_id).get("details", []):
			if str(detail.get("id", "")) == str(attachment_ids[kind]): restored_asset = str(detail.get("asset_id", ""))
		_check(restored_asset == str(expected_attachment_assets[kind]), "%s variation survives save reload" % kind)

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
