extends SceneTree

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

func _settle() -> void:
	for frame in 3: await process_frame

func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	scene._input(event)

func _run() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-compact-colour-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "compact colour scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	for detail in scene.building_world.get_building(scene.selected_building_id).get("details", []):
		if str(detail.get("kind", "")) == "window" and bool(detail.get("visible", false)) and not bool(detail.get("needs_placement", true)):
			scene.selected_detail_id = str(detail["id"])
			break
	check(not scene.selected_detail_id.is_empty(), "visible window selected")
	var before: String = scene.building_world.serialize_document()
	scene._begin_style_picker("colour")
	await _settle()
	var popover: PanelContainer = scene._detail_colour_popover
	check(popover.visible and not scene.tools_panel.visible and not scene._building_panel.visible, "only compact detail palette is visible")
	check(not scene._tool_card.visible and not scene._style_category_label.visible, "no redundant tool heading or colour instructions")
	var buttons: Array = scene._style_candidates("colour")
	for button in buttons:
		check(button.is_visible_in_tree() and popover.is_ancestor_of(button), "colour remains a reachable palette choice")
		check(button.text.is_empty() and not button.accessibility_name.is_empty(), "choice has no visible prose but keeps accessible name")
		check(button.custom_minimum_size.x >= 48 and button.custom_minimum_size.y >= 48, "readable controller and touch target")
	var focus: Control = root.gui_get_focus_owner()
	var index := buttons.find(focus)
	_press("m1_cycle_right")
	await _settle()
	check(root.gui_get_focus_owner() == buttons[(index + 1) % buttons.size()], "right browses palette exactly once")
	_press("m1_cycle_left")
	await _settle()
	check(root.gui_get_focus_owner() == focus, "left returns to prior choice")
	check(scene.building_world.serialize_document() == before, "browsing does not change world authority")
	_press("m1_cancel")
	await _settle()
	check(not popover.visible and not scene.tools_open and scene.building_world.serialize_document() == before, "cancel closes and restores without history")
	for kind in ["wall", "roof", "accent"]:
		scene._open_surface_material_picker(kind)
		await _settle()
		var panel: PanelContainer = scene._surface_material_picker_panel
		check(panel.visible and panel.size.y <= 90, kind + " is a compact row, not a text submenu")
		check(not scene._building_panel.visible and not scene._tool_card.visible, kind + " hides competing panels")
		for button in scene._surface_material_candidates():
			check(button.text.is_empty() and button.is_visible_in_tree(), kind + " choice is icon-only and reachable")
		_press("m1_cycle_right")
		await _settle()
		check(scene.building_world.serialize_document() == before, kind + " preview is read-only")
		var available := Rect2(16, 16, 768, 510)
		for point in [Vector2(20, 20), Vector2(750, 20), Vector2(20, 470), Vector2(750, 470), Vector2(390, 250)]:
			var target := Rect2(point, Vector2(20, 20))
			panel.call("place_near", target, available)
			check(available.grow(1).encloses(panel.get_rect()), kind + " palette stays within screen and prompt clearance")
			check(not panel.get_rect().intersects(target), kind + " palette avoids its target when room exists")
		_press("m1_cancel")
		await _settle()
		check(not panel.visible and scene.building_world.serialize_document() == before, kind + " cancel restores original")
	scene._begin_style_picker("colour")
	scene._preview_style_choice("colour", "berry")
	scene._cancel_current_edit("Focus lost")
	await _settle()
	check(not popover.visible and not scene.tools_open and scene.building_world.serialize_document() == before, "focus loss cancels compact colour preview")
	await _finish()

func _finish() -> void:
	if is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m2_compact_colour_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
