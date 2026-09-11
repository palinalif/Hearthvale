extends SceneTree

var scene: Node
var checks := 0
var failures := 0
var captures := 0
var rendered := false
const OUTPUT := ".tools/cottage-repair/build-browser"

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	_run.call_deferred()

func _settle() -> void:
	for i in 4: await process_frame

func _press(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	event = InputEventJoypadButton.new()
	event.button_index = button
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _settle()

func _run() -> void:
	rendered = "--require-rendering" in OS.get_cmdline_user_args()
	if rendered:
		check(DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "mobile", "actual Mobile renderer required")
		DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1280, 720)
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-build-browser-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "native browser scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	scene.edit_pointer = Vector2(12, 12)
	var before: String = scene.building_world.serialize_document()
	var landscape_before: String = JSON.stringify(scene.landscape_state.document())
	var registry_before: String = JSON.stringify(scene._browser_entries)
	var offset: float = scene.camera.v_offset
	await _press(JOY_BUTTON_X)
	var browser = scene._build_browser
	check(scene._browser_open and browser.visible and scene.tools_open, "physical X opens build browser")
	check(not scene._building_panel.visible and not scene.tools_panel.visible, "no old placement action list behind catalogue")
	check(browser.get_rect().position.y == 360 and browser.get_rect().end.y < scene._prompt_bar.position.y, "catalogue occupies lower half above prompts")
	check(browser.tabs.size() == 5, "five construction categories available")
	var ids: Dictionary = {}
	for item in scene._browser_entries:
		check(item.has("id"), "thumbnail queue retains catalogue record identity")
		if not item.has("id"): continue
		check(not ids.has(item["id"]), "one card per asset or home")
		ids[item["id"]] = true
	for id in ["window_round", "window_awning", "window_bay", "door_tudor_arch", "flower_box_woven", "shutter_braced", "chimney_brick", "dormer_gable", "village_gable"]:
		check(ids.has(id), "existing variant remains available: " + id)
	check(scene.camera.v_offset < offset, "world is reframed into unobscured upper half")
	for size in [Vector2(1280,720), Vector2(960,600), Vector2(1920,1080)]:
		browser.fit(size, size.y - 66)
		await _settle()
		check(Rect2(Vector2.ZERO, size).encloses(browser.get_rect()), "responsive browser remains on screen")
		check(browser.get_rect().position.y >= size.y * 0.5 and browser.get_rect().end.y <= size.y - 66, "responsive browser reserves upper world and prompts")
	scene._fit_build_browser()
	for category in ["windows", "doors", "wall", "roof", "homes"]:
		browser.select_category(category)
		await _settle()
		check(not browser.cards.is_empty(), "category has real choices: " + category)
		var first := root.gui_get_focus_owner()
		await _press(JOY_BUTTON_DPAD_RIGHT)
		check(root.gui_get_focus_owner() != first, "D-pad moves between cards")
		await _press(JOY_BUTTON_DPAD_LEFT)
		check(root.gui_get_focus_owner() == first, "D-pad returns without double stepping")
		check(scene.building_world.serialize_document() == before and JSON.stringify(scene.landscape_state.document()) == landscape_before, "browsing leaves building and terrain composition unchanged")
		if rendered:
			var render_deadline := Time.get_ticks_msec() + 30000
			while not _category_cached(category) and Time.get_ticks_msec() < render_deadline: await process_frame
			check(_category_cached(category), "every card has an actual rendered thumbnail: " + category)
			for card in browser.cards:
				var picture := card.get_node("CardContent/Preview") as TextureRect
				check(picture.texture != null, "card displays its rendered thumbnail")
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			check(not image.is_empty() and image.save_png(OUTPUT + "/" + category + ".png") == OK, "save actual catalogue screenshot")
			captures += 1
		check(JSON.stringify(scene._browser_entries) == registry_before, "rendering preserves the complete catalogue registry")
	# Controller shoulders select categories, not global undo/redo.
	browser.select_category("windows")
	await _settle()
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	check(browser.category == "doors", "RB selects next category")
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	check(browser.category == "windows", "LB selects previous category")
	check(scene.building_world.serialize_document() == before, "category navigation never undoes world edits")
	for spec in [["windows", "window_round"], ["wall", "flower_box_woven"], ["roof", "chimney_brick"], ["homes", "woodland_lodge"]]:
		browser.select_category(spec[0])
		await _settle()
		var card := _card(spec[1])
		check(card != null, "specific variant card exists")
		if not card: continue
		card.grab_focus()
		await _press(JOY_BUTTON_A)
		check(not scene._browser_open and not browser.visible and not scene.tools_open, "A hides browser for full-screen placement")
		check(scene.camera.v_offset == offset, "placement restores original camera offset")
		if spec[0] in ["windows", "wall"]:
			check(scene.detail_move_active and scene.placement_asset_id == spec[1], "selected variant, not family default, enters placement")
			check(scene.placement_ghost.has_node("FootprintTop"), "normal full-footprint placement preview retained")
		elif spec[0] == "roof": check(scene.roof_accessory_placement_active and scene.roof_accessory_asset_id == spec[1], "roof card starts existing accessory preview")
		else: check(scene.building_placement_active and scene.building_placement_design_id == spec[1], "home card starts independent home preview")
		check(scene.building_world.serialize_document() == before, "item selection has not committed a placement")
		await _press(JOY_BUTTON_B)
		check(scene._browser_open and browser.category == spec[0] and root.gui_get_focus_owner() == _card(spec[1]), "cancel returns to remembered category and exact item")
		check(scene.building_world.serialize_document() == before, "cancel preserves all records and revisions")
	if rendered:
		var count: int = scene._catalogue_thumbnails.rendered_count
		browser.select_category("windows")
		for i in 12: await process_frame
		check(scene._catalogue_thumbnails.rendered_count == count, "cached thumbnails do not keep rendering")
		check(scene._catalogue_thumbnails.get_child_count() == 1 and scene._catalogue_thumbnails._viewport.own_world_3d, "one private render viewport, not one live renderer per card")
		check(scene._catalogue_thumbnails.cache.size() <= 64, "thumbnail memory is bounded")
	# Blank world clicks and held brush actions cannot select or place anything.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	scene._unhandled_input(click)
	check(scene._browser_open and scene.building_world.serialize_document() == before, "clicking outside catalogue cannot activate a focused card")
	scene._cancel_current_edit("Controller disconnected")
	await _settle()
	check(not scene._browser_open and not scene.tools_open and scene.camera.v_offset == offset, "interrupt closes catalogue and restores camera")
	check(not scene._catalogue_thumbnails.active, "hidden catalogue does no thumbnail work")
	check(JSON.stringify(scene._browser_entries) == registry_before, "interrupting a render never clears shared catalogue records")
	await _finish()

func _category_cached(category: String) -> bool:
	for item in scene._browser_entries:
		if not item.has("category") or not item.has("id"): return false
		if item["category"] == category and not scene._catalogue_thumbnails.cache.has(item["id"]): return false
	return true

func _card(id: String) -> Button:
	for card in scene._build_browser.cards:
		if str(card.get_meta("item")["id"]) == id: return card
	return null

func _finish() -> void:
	if is_instance_valid(scene):
		scene._shutting_down = true
		scene._catalogue_thumbnails.stop()
		scene.queue_free()
		await process_frame
		await process_frame
	if rendered: check(captures == 5, "all five catalogue categories captured")
	print("BUILD_BROWSER_RESULT " + JSON.stringify({"checks": checks, "failures": failures, "ok": failures == 0, "captures": captures}))
	quit(1 if failures else 0)
