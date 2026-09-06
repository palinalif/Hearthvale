extends SceneTree

## Joypad-only M1 acceptance pass.  Every world operation below is dispatched
## through the same input paths as a physical controller; the document/backend
## are read only for assertions and fixture snapshots.

const SceneScript = preload("res://scripts/m1_scene.gd")
const Generator = preload("res://scripts/m1_patch_generator.gd")
const BuildingWorldScript = preload("res://scripts/building_world.gd")
const PROCESS_ROOT := "user://m1-acceptance-process"

var failures := 0
var checks := 0
var missing: Array[String] = []
var scene: Node

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var write_fixture := "--write-fixture" in args
	var read_fixture := "--read-fixture" in args
	if write_fixture: _clear_root()
	scene = SceneScript.new()
	scene.checkpoint_root = PROCESS_ROOT if (write_fixture or read_fixture) else "user://m1-acceptance-%d" % Time.get_ticks_usec()
	scene.test_mode = true
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 30000
	while (scene.backend == null or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(scene.backend != null and scene.backend.is_ready(), "native M1 backend ready")
	if scene.backend == null or not scene.backend.is_ready():
		_finish()
		return
	if read_fixture:
		_run_read_fixture()
		_finish()
		return
	await _run_acceptance()
	if write_fixture: _write_fixture_expectation()
	_finish()

func _run_acceptance() -> void:
	_check(scene.building_world != null, "building document available")
	if scene.building_world == null:
		return
	# Terrain is the safe default context.  X opens only terrain tools here;
	# accepting a focused menu item must not leak a held A into sculpting.
	_check(scene.view_context == "terrain", "default context is terrain")
	await process_frame
	_check(scene._terrain_target_valid, "default terrain cursor has a target")
	_check(scene.cursor_reticle != null and scene.cursor_reticle.visible, "terrain target reticle is visible")
	scene.camera_distance = 12.0
	await process_frame
	_check(scene.cursor_reticle != null and scene.cursor_reticle.visible, "reticle remains visible at minimum zoom")
	var min_zoom_reticle_span: float = _reticle_screen_span_pixels()
	_check(min_zoom_reticle_span >= 10.0, "reticle projected cue remains readable at minimum zoom")
	scene.camera_distance = 52.0
	await process_frame
	_check(scene.cursor_reticle != null and scene.cursor_reticle.visible, "reticle remains visible at maximum zoom")
	var max_zoom_reticle_span: float = _reticle_screen_span_pixels()
	_check(max_zoom_reticle_span >= 10.0, "reticle projected cue remains readable at maximum zoom")
	scene.cursor = Vector3(23.0, 13.0, 20.0)
	await process_frame
	var occluded_footprint: Node = scene.cursor_reticle.get_node_or_null("OccludedFootprint") if scene.cursor_reticle else null
	_check(scene._terrain_target_valid and scene.cursor_reticle != null and scene.cursor_reticle.visible and occluded_footprint != null and (occluded_footprint as MeshInstance3D).visible, "occluded ground keeps projected reticle cue")
	var terrain_menu_hash := _terrain_hash()
	await _press(JOY_BUTTON_X)
	_check(scene.tools_open and not scene.detail_open, "X opens terrain context menu")
	_check(_context_menu_is_filtered("terrain"), "terrain menu shows only relevant actions")
	await _hold_button(JOY_BUTTON_A, 30)
	_check(not scene.stroke_active and _terrain_hash() == terrain_menu_hash, "held A in terrain menu is consumed")
	await _choose_action("Dig")
	_check(scene.view_context == "terrain" and scene.sculpt_tool == "dig", "Dig selects terrain context")
	var dig_document_before: Dictionary = scene.building_world.get_document()
	var dig_hash_before := _terrain_hash()
	await _hold_button(JOY_BUTTON_A, 90)
	_check(not scene.stroke_active and _terrain_hash() != dig_hash_before, "held Dig changes authoritative terrain")
	_check(scene.building_world.get_document() == dig_document_before, "terrain Dig leaves all building records unchanged")
	await _press(JOY_BUTTON_BACK)
	_check(scene.view_context == "building", "View toggles to cottage context safely")
	await _press(JOY_BUTTON_X)
	_check(_context_menu_is_filtered("building"), "cottage menu shows only relevant actions")
	await _press(JOY_BUTTON_B)
	var original_id := str(scene.selected_building_id)
	var original_before: Dictionary = scene.building_world.get_building(original_id)
	_check((original_before["transform"] as Transform3D).basis.get_scale().is_equal_approx(Vector3.ONE * BuildingWorldScript.MINIATURE_SCALE), "selected cottage starts as miniature")
	var original_details: Array = original_before.get("details", [])
	var windows: Array[String] = []
	for item_value in original_details:
		var item: Dictionary = item_value
		if str(item.get("kind", "")) == "window": windows.append(str(item.get("id", "")))
	_check(windows.size() == 6, "six cottage windows are selectable")

	# Select all six through the detail carousel.  The four destructive actions
	# are deliberately assigned to different stable windows.
	var seen: Dictionary = {}
	for window_id in windows:
		var selected: bool = await _select_window(window_id)
		_check(selected, "joypad selects window %s" % window_id)
		if selected: seen[scene.selected_detail_id] = true
	_check(seen.size() == windows.size(), "all six windows selected distinctly")

	if windows.size() >= 5:
		await _select_window(windows[0]); await _choose_action("Move selected window")
		_check(scene.detail_move_active, "move opens a live preview")
		var move_before: Vector3 = scene.detail_move_position
		await _axis(JOY_AXIS_LEFT_X, 1.0)
		_check(scene.detail_move_position != move_before, "move preview follows left stick")
		await _press(JOY_BUTTON_A)
		_check(not scene.detail_move_active, "A commits moved window")

		await _select_window(windows[1]); await _choose_action("Replace selected")
		var replaced: Dictionary = _detail(scene.building_world.get_building(original_id), windows[1])
		_check(str(replaced.get("asset_id", "")).contains("round"), "replace changes the selected asset")

		await _select_window(windows[2]); await _choose_action("Suppress / restore")
		var suppressed: Dictionary = _detail(scene.building_world.get_building(original_id), windows[2])
		_check(str(suppressed.get("state", "")) == "suppressed", "suppress changes selected window state")

		await _select_window(windows[3]); await _choose_action("Reattach selected")
		var reattached: Dictionary = _detail(scene.building_world.get_building(original_id), windows[3])
		_check(str(reattached.get("state", "")) != "orphaned", "reattach restores a valid anchor")

		await _select_window(windows[4]); await _choose_action("Add flower box")
		_check(_count_kind(scene.building_world.get_building(original_id), "flower_box") > 0, "add flower box creates a detail")

	# Resize preview and cancellation are read-only until A.  Then commit a
	# bounded shrink to exercise orphan detection and recovery in the model.
	var dims_before: Vector3 = scene.building_world.get_building(original_id).get("dimensions", Vector3.ZERO)
	await _press(JOY_BUTTON_A)
	var preview_before: Vector3 = scene.resize_preview_dimensions
	await _press(JOY_BUTTON_DPAD_UP)
	_check(scene.resize_active and scene.resize_preview_dimensions.y > preview_before.y, "height resize preview is constrained")
	var resize_cursor_before: Vector3 = scene.cursor
	await _press(JOY_BUTTON_DPAD_DOWN)
	_check(scene.cursor == resize_cursor_before, "D-pad resize does not move world cursor")
	await process_frame
	var resize_view: Dictionary = scene.building_world.get_building(original_id)
	var resize_transform: Transform3D = resize_view["transform"]
	var authored_handle := Vector3(scene.resize_preview_dimensions.x * 0.5 + 0.5, scene.resize_preview_dimensions.y * 0.5, 0)
	if scene.resize_handles and scene.resize_handles.get_child_count() > 0:
		_check((scene.resize_handles.get_child(0) as Node3D).position.is_equal_approx(resize_transform * authored_handle), "resize handles follow miniature transform")
	else:
		_missing_api("transformed resize handles")
	await _press(JOY_BUTTON_B)
	_check(not scene.resize_active and scene.building_world.get_building(original_id).get("dimensions", Vector3.ZERO) == dims_before, "B cancels resize without mutation")
	await _press(JOY_BUTTON_A)
	await _hold_axis(JOY_AXIS_LEFT_X, -1.0, 150)
	for _i in 8: await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_A)
	var shrunk: Vector3 = scene.building_world.get_building(original_id).get("dimensions", Vector3.ZERO)
	_check(shrunk.x <= dims_before.x and shrunk.y <= dims_before.y, "committed resize stays within bounds")
	var needs_recovery := _count_needing_placement(scene.building_world.get_building(original_id))
	_check(needs_recovery > 0, "shrink reports orphaned detail placement")
	await _press(JOY_BUTTON_A)
	await _hold_axis(JOY_AXIS_LEFT_X, 1.0, 150)
	for _i in 8: await _press(JOY_BUTTON_DPAD_UP)
	await _press(JOY_BUTTON_A)
	_check(_count_needing_placement(scene.building_world.get_building(original_id)) == 0, "expanded cottage recovers orphaned placement")

	# Delete support and reattach via the focused menu, then recover dimensions.
	await _select_window(windows[5] if windows.size() > 5 else windows[0])
	await _choose_action("Delete selected surface")
	_check(_count_deleted_surfaces(scene.building_world.get_building(original_id)) > 0, "delete support marks a surface deleted")
	await _select_window(windows[5] if windows.size() > 5 else windows[0])
	await _choose_action("Reattach selected")
	var recovered_detail := _detail(scene.building_world.get_building(original_id), str(scene.selected_detail_id))
	_check(not bool(recovered_detail.get("needs_placement", true)) and str(recovered_detail.get("state", "")) != "orphaned", "reattached detail renders on a surviving surface")

	# Material must be one history operation and undo/redo must restore exact
	# documents.  These are still initiated by the focused menu.
	var material_before: Dictionary = scene.building_world.get_document()
	await _choose_action("Material: warm plaster")
	var material_after: Dictionary = scene.building_world.get_document()
	_check(material_after != material_before, "material menu mutates the design")
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(_same_design(scene.building_world.get_document(), material_before), "building material undo is exact")
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	_check(_same_design(scene.building_world.get_document(), material_after), "building material redo is exact")
	var miniature_before: Dictionary = scene.building_world.get_document()
	await _choose_action("Miniature scale")
	_check((scene.building_world.get_building(original_id)["transform"] as Transform3D).basis.get_scale().is_equal_approx(Vector3.ONE * BuildingWorldScript.MINIATURE_SCALE), "Miniature scale action keeps half scale")
	_check(_same_design(scene.building_world.get_document(), miniature_before), "repeated Miniature scale is an idempotent action")

	# Duplicate through UI, switch to the copy with D-pad, and edit only it.
	var buildings_before: int = scene.building_world.get_buildings().size()
	await _choose_action("Duplicate cottage")
	_check(scene.building_world.get_buildings().size() == buildings_before + 1, "duplicate creates an independent cottage")
	var copy_id := str(scene.selected_building_id)
	_check(copy_id != original_id, "duplicate selection moves to the copy")
	var original_after_duplicate: Dictionary = scene.building_world.get_building(original_id)
	_check((scene.building_world.get_building(copy_id)["transform"] as Transform3D).basis.get_scale().is_equal_approx((original_after_duplicate["transform"] as Transform3D).basis.get_scale()), "duplicate preserves miniature transform scale")
	await _select_window_for_building(copy_id, 0)
	await _choose_action("Suppress / restore")
	_check(scene.building_world.get_building(original_id) == original_after_duplicate, "copy edit leaves original unchanged")

	# Renderer stale-result guard: submit an old revision to the actual visual
	# node and require it to reject the result while the current one remains.
	var visual: Node = scene.cottage_visual
	var visual_revision := int(scene.building_world.get_revision())
	if visual and visual.has_method("request_revision") and visual.has_method("apply_building"):
		visual.request_revision(visual_revision + 1)
		_check(not visual.apply_building(scene.building_world.get_building(original_id), visual_revision), "renderer rejects stale revision")
	else:
		_missing_api("CottageVisual revision guard")
	_check(not scene.building_world.accept_mesh_result(visual_revision - 1), "document rejects stale mesh revision")

	# Save/reload is reached through the pause menu, preserving the full doc and
	# terrain revision.  The fixture already exercised the independent process.
	var save_doc: Dictionary = scene.building_world.get_document()
	var save_revision := int(scene.backend.stats().get("revision", -1))
	await _press(JOY_BUTTON_START)
	await _press(JOY_BUTTON_A)
	_check(str(scene.backend.stats().get("save_status", "")) == "saved", "focused pause Save publishes terrain and design")
	await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_A)
	_check(str(scene.backend.stats().get("save_status", "")) == "loaded", "focused pause Reload reports loaded")
	_check(_same_design(scene.building_world.get_document(), save_doc), "Reload restores complete building document")
	_check(int(scene.backend.stats().get("revision", -1)) == save_revision, "Reload restores saved terrain revision")
	await _press(JOY_BUTTON_B)
	_check(not scene.menu_open, "B closes pause after Reload")

	# Terrain context: tool selection, held A progress, drag, release, and
	# history are all physical joypad events.
	await _press(JOY_BUTTON_BACK)
	_check(scene.view_context == "terrain", "Back enters terrain view")
	await _press(JOY_BUTTON_RIGHT_STICK)
	await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_DPAD_DOWN)
	await _choose_action("Radius +")
	var radius_after: float = scene.brush_radius
	_check(radius_after > 2.0, "radius setting is controller accessible")
	await _choose_action("Strength +")
	_check(scene.brush_strength > 0.75, "strength setting is controller accessible")
	await _choose_action("Reference: wall")
	_check(scene.reference_mode == "wall", "wall reference is controller accessible")
	await _choose_action("Reference: ground")
	_check(scene.reference_mode == "ground", "ground reference is controller accessible")
	await _choose_action("Raise")
	_check(scene.sculpt_tool == "raise", "raise tool is focused")
	var terrain_revision := int(scene.backend.stats().get("revision", -1))
	var terrain_before_hash := _terrain_hash()
	await _hold_drag(70)
	_check(not scene.stroke_active, "held A releases a completed stroke")
	_check(int(scene.backend.stats().get("revision", -1)) > terrain_revision, "held A makes gradual terrain progress")
	var after_raise_revision := int(scene.backend.stats().get("revision", -1))
	var terrain_after_hash := _terrain_hash()
	_check(terrain_after_hash != terrain_before_hash, "dragged stroke changes authoritative terrain")
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(int(scene.backend.stats().get("revision", -1)) > after_raise_revision, "terrain stroke is one undo transaction")
	_check(_terrain_hash() == terrain_before_hash, "terrain undo restores full patch")
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	_check(int(scene.backend.stats().get("revision", -1)) > after_raise_revision, "terrain redo restores the transaction")
	_check(_terrain_hash() == terrain_after_hash, "terrain redo restores full patch exactly")

	# Level/slope references and the keep/resample controls are required public
	# UI; report missing controls instead of silently driving backend methods.
	await _choose_action("Level")
	_check(scene.sculpt_tool == "level", "level tool is focused")
	await _choose_action("Keep reference")
	_check(bool(scene.keep_reference), "keep reference toggles through focused UI")
	await _choose_action("Resample reference")
	_check(scene.stroke_reference is Dictionary, "resample reference runs through focused UI")
	var level_ui_reference: Dictionary = scene.stroke_reference.duplicate(true)
	await _choose_action("Level")
	var level_hold := InputEventJoypadButton.new(); level_hold.button_index = JOY_BUTTON_A; level_hold.pressed = true
	Input.parse_input_event(level_hold); Input.flush_buffered_events(); await process_frame
	var level_stroke_reference: Dictionary = scene.stroke_reference.duplicate(true)
	await _axis(JOY_AXIS_LEFT_X, 1.0)
	_check(scene.stroke_reference == level_stroke_reference and scene.stroke_active, "level plane stays fixed while moving")
	var level_release := InputEventJoypadButton.new(); level_release.button_index = JOY_BUTTON_A; level_release.pressed = false
	Input.parse_input_event(level_release); Input.flush_buffered_events(); await process_frame
	_check(not scene.stroke_active, "level stroke releases through UI")
	await _choose_action("Slope")
	_check(scene.sculpt_tool == "slope", "slope tool is focused")
	var slope_ref_before: Dictionary = scene.stroke_reference.duplicate(true)
	var slope_hold := InputEventJoypadButton.new(); slope_hold.button_index = JOY_BUTTON_A; slope_hold.pressed = true
	Input.parse_input_event(slope_hold); Input.flush_buffered_events(); await process_frame
	await _axis(JOY_AXIS_LEFT_X, -1.0)
	_check(scene.stroke_reference == slope_ref_before and scene.stroke_active, "slope plane stays fixed while moving")
	var slope_release := InputEventJoypadButton.new(); slope_release.button_index = JOY_BUTTON_A; slope_release.pressed = false
	Input.parse_input_event(slope_release); Input.flush_buffered_events(); await process_frame
	_check(not scene.stroke_active, "slope stroke releases through UI")
	# B while A is held must cancel, and a fresh A is needed afterwards.
	await _choose_action("Dig")
	var rev_before_cancel := int(scene.backend.stats().get("revision", -1))
	var cancel_before_hash := _terrain_hash()
	await _hold_then_cancel(90)
	_check(not scene.stroke_active, "B cancels a held terrain stroke")
	_check(int(scene.backend.stats().get("revision", -1)) == rev_before_cancel, "cancelled stroke does not publish history")
	_check(_terrain_hash() == cancel_before_hash, "cancelled stroke restores full terrain")
	# Godot exposes controller disconnect as a singleton signal. Emit the real
	# signal after an actually changing held stroke and require cancellation.
	_check(Input.has_signal("joy_connection_changed"), "joypad disconnect signal is available")
	var disconnect_before_hash := _terrain_hash()
	var held := InputEventJoypadButton.new(); held.button_index = JOY_BUTTON_A; held.pressed = true
	Input.parse_input_event(held); Input.flush_buffered_events()
	for _i in 90: await process_frame
	_check(int(scene.backend.get_stroke_state().get("changed_count", 0)) > 0, "disconnect fixture has a real pending edit")
	if Input.has_signal("joy_connection_changed"): Input.emit_signal("joy_connection_changed", 0, false)
	await process_frame
	_check(not scene.stroke_active, "controller disconnect cancels held stroke")
	_check(_terrain_hash() == disconnect_before_hash, "disconnect cancellation preserves terrain")
	var disconnect_release := InputEventJoypadButton.new(); disconnect_release.button_index = JOY_BUTTON_A; disconnect_release.pressed = false
	Input.parse_input_event(disconnect_release); Input.flush_buffered_events(); await process_frame
	_check(scene.menu_open, "disconnect pauses the UI")
	await _press(JOY_BUTTON_B)
	_check(not scene.menu_open, "B closes disconnect pause menu after release")
	# Focus loss follows the same cancellation route and also requires a fresh
	# A press after the held input is released.
	var focus_before_hash := _terrain_hash()
	var focus_held := InputEventJoypadButton.new(); focus_held.button_index = JOY_BUTTON_A; focus_held.pressed = true
	Input.parse_input_event(focus_held); Input.flush_buffered_events()
	for _i in 90: await process_frame
	_check(int(scene.backend.get_stroke_state().get("changed_count", 0)) > 0, "focus fixture has a real pending edit")
	scene.notification(NOTIFICATION_APPLICATION_FOCUS_OUT); await process_frame
	_check(not scene.stroke_active, "focus loss cancels held stroke")
	_check(_terrain_hash() == focus_before_hash, "focus cancellation preserves terrain")
	var focus_release := InputEventJoypadButton.new(); focus_release.button_index = JOY_BUTTON_A; focus_release.pressed = false
	Input.parse_input_event(focus_release); Input.flush_buffered_events(); await process_frame
	if scene.menu_open: await _press(JOY_BUTTON_B)
	var fresh_before_hash := _terrain_hash()
	var fresh_before_revision := int(scene.backend.stats().get("revision", -1))
	await _hold_button(JOY_BUTTON_A, 90)
	_check(_terrain_hash() != fresh_before_hash, "fresh held A after cancellation really starts a stroke")
	_check(int(scene.backend.stats().get("revision", -1)) > fresh_before_revision, "fresh stroke commits exactly once")

	# Opening pause or tools while A is physically held must cancel and must not
	# restart until a new A press arrives.
	await _choose_action("Raise")
	var pause_before_hash := _terrain_hash()
	var pause_held := InputEventJoypadButton.new(); pause_held.button_index = JOY_BUTTON_A; pause_held.pressed = true
	Input.parse_input_event(pause_held); Input.flush_buffered_events()
	for _i in 90: await process_frame
	_check(int(scene.backend.get_stroke_state().get("changed_count", 0)) > 0, "pause interruption has a real pending edit")
	await _press(JOY_BUTTON_START)
	_check(scene.menu_open and not scene.stroke_active, "pause cancels held stroke")
	_check(_terrain_hash() == pause_before_hash, "pause cancellation restores terrain")
	# Close the pause menu while A is still physically down. The world must stay
	# suspended until that original release; a repeated pressed event models a
	# reconnect-held controller and must not restart the cancelled stroke.
	await _press(JOY_BUTTON_B)
	_check(not scene.menu_open, "B closes pause while A remains held")
	for _i in 90: await process_frame
	_check(not scene.stroke_active and _terrain_hash() == pause_before_hash, "held A does not resume after pause closes")
	var pause_repeated := InputEventJoypadButton.new(); pause_repeated.button_index = JOY_BUTTON_A; pause_repeated.pressed = true
	Input.parse_input_event(pause_repeated); Input.flush_buffered_events(); await process_frame
	_check(not scene.stroke_active and _terrain_hash() == pause_before_hash, "repeated held A remains blocked after pause")
	var pause_release := InputEventJoypadButton.new(); pause_release.button_index = JOY_BUTTON_A; pause_release.pressed = false
	Input.parse_input_event(pause_release); Input.flush_buffered_events(); await process_frame
	var pause_fresh_before := _terrain_hash()
	await _hold_button(JOY_BUTTON_A, 90)
	_check(_terrain_hash() != pause_fresh_before, "fresh A after pause release edits terrain")

	var tools_before_hash := _terrain_hash()
	var tools_held := InputEventJoypadButton.new(); tools_held.button_index = JOY_BUTTON_A; tools_held.pressed = true
	Input.parse_input_event(tools_held); Input.flush_buffered_events()
	for _i in 90: await process_frame
	_check(int(scene.backend.get_stroke_state().get("changed_count", 0)) > 0, "tools interruption has a real pending edit")
	await _press(JOY_BUTTON_X)
	_check(scene.tools_open and not scene.stroke_active, "opening tools cancels held stroke")
	_check(_terrain_hash() == tools_before_hash, "tools cancellation restores terrain")
	# The same release latch must survive closing the tools overlay while A is
	# still down, including a duplicate pressed event before the real release.
	await _press(JOY_BUTTON_B)
	_check(not scene.tools_open and not scene.detail_open, "B closes tools while A remains held")
	for _i in 90: await process_frame
	_check(not scene.stroke_active and _terrain_hash() == tools_before_hash, "held A does not resume after tools close")
	var tools_repeated := InputEventJoypadButton.new(); tools_repeated.button_index = JOY_BUTTON_A; tools_repeated.pressed = true
	Input.parse_input_event(tools_repeated); Input.flush_buffered_events(); await process_frame
	_check(not scene.stroke_active and _terrain_hash() == tools_before_hash, "repeated held A remains blocked after tools")
	var tools_release := InputEventJoypadButton.new(); tools_release.button_index = JOY_BUTTON_A; tools_release.pressed = false
	Input.parse_input_event(tools_release); Input.flush_buffered_events(); await process_frame
	var tools_fresh_before := _terrain_hash()
	await _hold_button(JOY_BUTTON_A, 90)
	_check(_terrain_hash() != tools_fresh_before, "fresh A after tools release edits terrain")

	# Final cold path is after both sculpt and manual design edits.  Keep the
	# exact terrain hash and complete design snapshot across the real pause-menu
	# save/reload route.
	await _press(JOY_BUTTON_BACK)
	var final_doc: Dictionary = scene.building_world.get_document()
	var final_terrain_hash := _terrain_hash()
	var final_revision := int(scene.backend.stats().get("revision", -1))
	await _press(JOY_BUTTON_START)
	await _press(JOY_BUTTON_A)
	_check(str(scene.backend.stats().get("save_status", "")) == "saved", "final Save publishes sculpt and design")
	await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_A)
	_check(_same_design(scene.building_world.get_document(), final_doc), "cold Reload restores complete final design")
	_check(_terrain_hash() == final_terrain_hash, "cold Reload restores complete final terrain hash")
	_check(int(scene.backend.stats().get("revision", -1)) == final_revision, "cold Reload restores final revision")

func _select_window(window_id: String) -> bool:
	if not scene.detail_open:
		await _press(JOY_BUTTON_X)
	for _i in 8:
		if str(scene.selected_detail_id) == window_id: return true
		await _press(JOY_BUTTON_DPAD_RIGHT)
	return str(scene.selected_detail_id) == window_id

func _select_window_for_building(building_id: String, index: int) -> void:
	# Building switching is a public controller action; the selected copy is
	# already active after duplication, so only carousel selection is needed.
	if str(scene.selected_building_id) != building_id: await _press(JOY_BUTTON_DPAD_RIGHT)
	var view: Dictionary = scene.building_world.get_building(building_id)
	var ids: Array[String] = []
	for item_value in view.get("details", []):
		var item: Dictionary = item_value
		if str(item.get("kind", "")) == "window": ids.append(str(item.get("id", "")))
	if index < ids.size(): await _select_window(ids[index])

func _choose_action(label: String) -> void:
	if not scene.tools_open and not scene.detail_open: await _press(JOY_BUTTON_X)
	var labels: Array = scene._visible_action_labels() if scene.has_method("_visible_action_labels") else scene._tool_buttons.keys()
	var buttons: Array = scene._visible_action_buttons() if scene.has_method("_visible_action_buttons") else scene._tool_buttons.values()
	var index := labels.find(label)
	if index < 0:
		_missing_api("focused action: %s" % label)
		return
	var focus := scene.get_viewport().gui_get_focus_owner()
	var start := buttons.find(focus)
	if start < 0: start = 0
	var steps: int = posmod(index - start, labels.size())
	for _i in steps: await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_A)

func _context_menu_is_filtered(context: String) -> bool:
	var expected: Array = scene._terrain_action_labels if context == "terrain" else scene._cottage_action_labels
	var visible_count := 0
	for label in scene._tool_buttons.keys():
		var button: Button = scene._tool_buttons[label]
		var should_show := expected.has(str(label))
		if button.visible: visible_count += 1
		if button.visible != should_show or button.disabled == should_show: return false
	return visible_count == expected.size()

func _hold_button(button: JoyButton, frames: int) -> void:
	var event := InputEventJoypadButton.new(); event.button_index = button; event.pressed = true
	Input.parse_input_event(event); Input.flush_buffered_events()
	for _i in frames: await process_frame
	var release := InputEventJoypadButton.new(); release.button_index = button; release.pressed = false
	Input.parse_input_event(release); Input.flush_buffered_events(); await process_frame

func _hold_drag(frames: int) -> void:
	var event := InputEventJoypadButton.new(); event.button_index = JOY_BUTTON_A; event.pressed = true
	Input.parse_input_event(event); Input.flush_buffered_events(); await process_frame
	for axis_value in [1.0, 0.65, 0.25]:
		var motion := InputEventJoypadMotion.new(); motion.axis = JOY_AXIS_LEFT_X; motion.axis_value = axis_value
		Input.parse_input_event(motion); Input.flush_buffered_events()
		for _i in frames: await process_frame
		var neutral := InputEventJoypadMotion.new(); neutral.axis = JOY_AXIS_LEFT_X; neutral.axis_value = 0.0
		Input.parse_input_event(neutral); Input.flush_buffered_events(); await process_frame
	var release := InputEventJoypadButton.new(); release.button_index = JOY_BUTTON_A; release.pressed = false
	Input.parse_input_event(release); Input.flush_buffered_events(); await process_frame

func _hold_then_cancel(frames: int) -> void:
	var event := InputEventJoypadButton.new(); event.button_index = JOY_BUTTON_A; event.pressed = true
	Input.parse_input_event(event); Input.flush_buffered_events()
	for _i in frames: await process_frame
	await _press(JOY_BUTTON_B)
	var release := InputEventJoypadButton.new(); release.button_index = JOY_BUTTON_A; release.pressed = false
	Input.parse_input_event(release); Input.flush_buffered_events(); await process_frame

func _hold_axis(axis: JoyAxis, value: float, frames: int) -> void:
	var event := InputEventJoypadMotion.new(); event.axis = axis; event.axis_value = value
	Input.parse_input_event(event); Input.flush_buffered_events()
	for _i in frames: await process_frame
	var release := InputEventJoypadMotion.new(); release.axis = axis; release.axis_value = 0.0
	Input.parse_input_event(release); Input.flush_buffered_events(); await process_frame

func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new(); event.axis = axis; event.axis_value = value
	Input.parse_input_event(event); Input.flush_buffered_events(); await process_frame
	var release := InputEventJoypadMotion.new(); release.axis = axis; release.axis_value = 0.0
	Input.parse_input_event(release); Input.flush_buffered_events(); await process_frame

func _press(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new(); event.button_index = button; event.pressed = true
	Input.parse_input_event(event); Input.flush_buffered_events(); await process_frame
	var release := InputEventJoypadButton.new(); release.button_index = button; release.pressed = false
	Input.parse_input_event(release); Input.flush_buffered_events(); await process_frame

func _detail(building: Dictionary, detail_id: String) -> Dictionary:
	for item_value in building.get("details", []):
		var item: Dictionary = item_value
		if str(item.get("id", "")) == detail_id: return item
	return {}

func _count_kind(building: Dictionary, kind: String) -> int:
	var count := 0
	for item_value in building.get("details", []):
		if str((item_value as Dictionary).get("kind", "")) == kind: count += 1
	return count

func _count_needing_placement(building: Dictionary) -> int:
	var count := 0
	for item_value in building.get("details", []):
		if bool((item_value as Dictionary).get("needs_placement", false)): count += 1
	return count

func _count_deleted_surfaces(building: Dictionary) -> int:
	var count := 0
	for item_value in building.get("surfaces", []):
		if bool((item_value as Dictionary).get("deleted", false)): count += 1
	return count

func _same_design(left: Dictionary, right: Dictionary) -> bool:
	var a := left.duplicate(true)
	var b := right.duplicate(true)
	# BuildingWorld revisions are monotonic history metadata; all design fields
	# must still match exactly after undo/redo.
	a["revision"] = 0
	b["revision"] = 0
	a["next_id"] = 0
	b["next_id"] = 0
	# JSON restores integral metadata as floats; compare every design field in
	# the same persisted representation, without dropping or tolerating fields.
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func _terrain_hash() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(scene.backend.voxels.get_channel_as_byte_array(0))
	return context.finish().hex_encode()

func _reticle_screen_span_pixels() -> float:
	if scene.camera == null or scene.cursor_reticle == null: return -1.0
	var center: MeshInstance3D = scene.cursor_reticle.get_node_or_null("CenterDiamond")
	if center == null or not center.mesh is ArrayMesh: return -1.0
	var arrays: Array = (center.mesh as ArrayMesh).surface_get_arrays(0)
	if arrays.size() <= Mesh.ARRAY_VERTEX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array: return -1.0
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.is_empty(): return -1.0
	var min_pixel := Vector2(INF, INF)
	var max_pixel := Vector2(-INF, -INF)
	for vertex in vertices:
		var pixel: Vector2 = scene.camera.unproject_position(center.global_transform * vertex)
		min_pixel.x = minf(min_pixel.x, pixel.x); min_pixel.y = minf(min_pixel.y, pixel.y)
		max_pixel.x = maxf(max_pixel.x, pixel.x); max_pixel.y = maxf(max_pixel.y, pixel.y)
	return maxf(max_pixel.x - min_pixel.x, max_pixel.y - min_pixel.y)

func _design_hash(document: Dictionary) -> String:
	var copy := document.duplicate(true)
	copy["revision"] = 0
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(_canonical(copy)).to_utf8_buffer())
	return context.finish().hex_encode()

func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		var keys: Array = value.keys(); keys.sort()
		for key in keys: result[str(key)] = _canonical(value[key])
		return result
	if value is Array:
		var array: Array = []
		for item in value: array.append(_canonical(item))
		return array
	if value is float and is_finite(value) and floor(value) == value: return int(value)
	return value

func _write_fixture_expectation() -> void:
	var document: Dictionary = scene.building_world.get_document()
	var path := ProjectSettings.globalize_path(PROCESS_ROOT.path_join("expectation.json"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "write cold process expectation")
		return
	file.store_string(JSON.stringify({"design_hash": _design_hash(document), "terrain_hash": _terrain_hash()}))
	file.flush(); file.close()

func _missing_api(label: String) -> void:
	if not missing.has(label): missing.append(label)
	_check(false, "missing UI function: %s" % label)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: %s" % label)

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene.queue_free()
		await process_frame
		await process_frame
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "missing_ui": missing}))
	quit(1 if failures > 0 else 0)

func _clear_root() -> void:
	var absolute := ProjectSettings.globalize_path(PROCESS_ROOT)
	if not DirAccess.dir_exists_absolute(absolute): return
	var directory := DirAccess.open(absolute)
	if directory == null: return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if not directory.current_is_dir(): DirAccess.remove_absolute(absolute.path_join(name))
		name = directory.get_next()
	directory.list_dir_end()

func _run_read_fixture() -> void:
	_check(scene.backend.loaded_building_document is Dictionary and not scene.backend.loaded_building_document.is_empty(), "cold process loads embedded building document")
	_check(BuildingWorldScript.validate_document(scene.backend.loaded_building_document), "cold process validates building document")
	var loaded_doc: Dictionary = scene.backend.loaded_building_document
	_check((loaded_doc.get("buildings", []) as Array).size() >= 2, "cold process retains duplicated cottage")
	var expectation_path := ProjectSettings.globalize_path(PROCESS_ROOT.path_join("expectation.json"))
	var expectation: Variant = JSON.parse_string(FileAccess.get_file_as_string(expectation_path)) if FileAccess.file_exists(expectation_path) else null
	_check(expectation is Dictionary, "cold process expectation is present")
	if expectation is Dictionary:
		_check(_design_hash(loaded_doc) == str(expectation.get("design_hash", "")), "cold process restores exact design records")
		_check(_terrain_hash() == str(expectation.get("terrain_hash", "")), "cold process restores exact full terrain bytes")
