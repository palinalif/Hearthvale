extends SceneTree

var failures := 0
var checks := 0
var scene: Node

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-home-options-layout-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "native home-options scene ready")
	if not scene._player_restored: await _finish(); return
	scene.set_process(false)
	scene._set_view_context("building")
	for viewport_size in [Vector2i(1280, 720), Vector2i(1280, 600), Vector2i(1920, 1080)]:
		root.size = viewport_size
		await _settle()
		await _check_options_navigation(str(viewport_size))
		await _check_shape_navigation(str(viewport_size))
	# A taller/repositioned prompt bar must reserve its actual space too.
	scene._prompt_bar.position.y -= 72.0
	await _settle()
	await _check_options_navigation("raised prompt bar")
	await _check_shape_navigation("raised prompt bar")
	await _finish()

func _settle() -> void:
	for frame in 3: await process_frame

func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	scene._input(event)

func _check_options_navigation(label: String) -> void:
	var before: String = scene.building_world.serialize_document()
	var cursor_before: Vector3 = scene.cursor
	scene._open_building_panel()
	await _settle()
	var panel: PanelContainer = scene._building_panel
	var scroll: ScrollContainer = scene._home_options_scroll
	check(scroll != null and scroll.follow_focus, label + ": options follow controller focus")
	if not scroll: return
	var bounds := panel.get_global_rect()
	check(bounds.end.y <= scene._prompt_bar.get_global_rect().position.y - 10.0, label + ": panel clears prompt bar")
	check(root.get_visible_rect().grow(1.0).encloses(bounds), label + ": panel stays on screen")
	check(scroll.get_global_rect().size.y >= 100.0, label + ": scroll area remains usable")
	check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, label + ": long options actually overflow into scrolling")
	var buttons: Array[Button] = []
	for button in scene._building_buttons:
		check(scroll.is_ancestor_of(button), label + ": action remains in scroll content")
		check(button.custom_minimum_size.y >= 42.0, label + ": action retains readable height")
		if button.is_visible_in_tree() and not button.disabled: buttons.append(button)
	buttons.sort_custom(func(a: Button, b: Button) -> bool: return a.get_index() < b.get_index())
	check(not buttons.is_empty(), label + ": actions remain available")
	if buttons.is_empty(): return
	buttons[0].grab_focus()
	await _settle()
	var did_scroll := false
	for index in buttons.size():
		check(root.gui_get_focus_owner() == buttons[index], label + ": controller preserves visual action order")
		check(scroll.get_global_rect().grow(1.0).encloses(buttons[index].get_global_rect()), "%s: focused option %d (%s) is fully visible; option=%s scroll=%s offset=%d" % [label, index, buttons[index].text, buttons[index].get_global_rect(), scroll.get_global_rect(), scroll.scroll_vertical])
		did_scroll = did_scroll or scroll.scroll_vertical > 0
		_press("m1_height_down")
		await _settle()
	check(did_scroll, label + ": controller reaches offscreen options")
	check(root.gui_get_focus_owner() == buttons[0], label + ": downward navigation wraps to first option")
	_press("m1_height_up")
	await _settle()
	check(root.gui_get_focus_owner() == buttons.back(), label + ": upward navigation wraps to final option")
	check(scroll.get_global_rect().grow(1.0).encloses(buttons.back().get_global_rect()), label + ": wrapped option is visible")
	check(panel.get_global_rect().end.y <= scene._prompt_bar.get_global_rect().position.y - 10.0, label + ": scrolling never grows panel into prompts")
	_press("m1_cancel")
	await _settle()
	check(not panel.visible and not scene.tools_open, label + ": controller cancel closes options")
	check(scene.building_world.serialize_document() == before and scene.cursor == cursor_before, label + ": menu navigation does not edit or move world")
	scene._open_building_panel()
	await _settle()
	var focus := root.gui_get_focus_owner()
	check(focus in scene._building_buttons and scroll.get_global_rect().grow(1.0).encloses(focus.get_global_rect()), label + ": reopened menu reveals its initial focus")
	scene._close_building_panel()

func _check_shape_navigation(label: String) -> void:
	var before: String = scene.building_world.serialize_document()
	var cursor_before: Vector3 = scene.cursor
	scene._open_house_shape_picker()
	await _settle()
	var panel: PanelContainer = scene._house_shape_picker
	var scroll: ScrollContainer = scene._house_shape_options_scroll
	check(scroll != null and scroll.follow_focus, label + ": shape options follow controller focus")
	if not scroll: return
	check(scene._catalogue_box(panel) is VBoxContainer, label + ": wrapped picker retains catalogue accessor")
	check(panel.get_global_rect().end.y <= scene._prompt_bar.get_global_rect().position.y - 10.0, label + ": shape picker clears prompt bar")
	check(root.get_visible_rect().grow(1.0).encloses(panel.get_global_rect()), label + ": shape picker stays on screen")
	var buttons: Array[Button] = []
	for button in scene._house_shape_buttons:
		check(scroll.is_ancestor_of(button) and button.custom_minimum_size.y >= 42.0, label + ": readable shape action remains in scroll content")
		if button.is_visible_in_tree() and not button.disabled: buttons.append(button)
	check(not buttons.is_empty(), label + ": shape actions remain available")
	if buttons.is_empty(): return
	buttons[0].grab_focus()
	await _settle()
	var did_scroll := false
	for index in buttons.size():
		check(root.gui_get_focus_owner() == buttons[index], label + ": shape controller order skips disabled actions")
		check(scroll.get_global_rect().grow(1.0).encloses(buttons[index].get_global_rect()), "%s: shape option %d (%s) is fully visible; option=%s scroll=%s offset=%d" % [label, index, buttons[index].text, buttons[index].get_global_rect(), scroll.get_global_rect(), scroll.scroll_vertical])
		did_scroll = did_scroll or scroll.scroll_vertical > 0
		_press("m1_height_down")
		await _settle()
	check(did_scroll, label + ": controller scrolls to all floor commands")
	check(root.gui_get_focus_owner() == buttons[0], label + ": shape navigation wraps down")
	_press("m1_height_up")
	await _settle()
	check(root.gui_get_focus_owner() == buttons.back(), label + ": shape navigation wraps up")
	check(scroll.get_global_rect().grow(1.0).encloses(buttons.back().get_global_rect()), label + ": last enabled shape action is visible")
	_press("m1_cancel")
	await _settle()
	check(not panel.visible and scene._building_panel.visible, label + ": back returns from shape picker to home options")
	check(root.gui_get_focus_owner() == scene._house_shape_button, label + ": back restores shape action focus")
	check(scene._home_options_scroll.get_global_rect().grow(1.0).encloses(scene._house_shape_button.get_global_rect()), label + ": returned home action is visible")
	check(scene.building_world.serialize_document() == before and scene.cursor == cursor_before, label + ": shape navigation leaves world unchanged")
	scene._close_building_panel()

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m2_home_options_layout_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
