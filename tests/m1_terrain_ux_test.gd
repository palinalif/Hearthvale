extends SceneTree
## Exercise the actual exported scene, not only a historical base script.
## Raise/Dig 3, Smooth 5 and the visible settings rows are the Thor-accepted
## contract. Keep the original native preview, caching and cancellation gates.
const StrengthScale = preload("res://scripts/sculpt_strength.gd")
var checks := 0
var failures := 0
var scene: Node

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _init() -> void:
	call_deferred("_run")

func _press(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	await process_frame
	var release := InputEventJoypadButton.new()
	release.button_index = button
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await process_frame

func _run() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://terrain-ux-test-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene.backend.is_ready() and Time.get_ticks_msec() < deadline: await process_frame
	check(scene.backend.is_ready(), "native M1 ready")
	if not scene.backend.is_ready():
		scene.queue_free()
		quit(1)
		return
	await _settle()
	check(scene.sculpt_tool == "raise" and scene.brush_strength_level == 3 and is_equal_approx(scene.brush_strength, StrengthScale.rate(3)), "exported scene uses accepted Raise default 3")
	check(scene.terrain_edit_preview.visible, "new cell preview visible")
	check(not scene.brush_preview.visible, "old sphere preview hidden for sculpting")
	check(not scene.reference_plane.visible, "raise has no flat reference square")
	check(scene.preview_cells.size() > 9, "preview covers the footprint")
	check(scene._tool_card.is_visible_in_tree() and scene._tool_meta.text.contains("Strength 3/10"), "visible HUD shows accepted strength scale")
	check(scene.target_label.text.contains("Next layer"), "terrain preview retains next-layer horizon summary")
	var query_count: int = scene._layer_query.query_count
	for _i in 10: await process_frame
	check(scene._layer_query.query_count == query_count, "stationary preview and geometry cached")
	scene._set_menu(true)
	await process_frame
	check(not scene.terrain_edit_preview.visible, "pause hides preview")
	check(not scene.stroke_active, "pause cannot sculpt")
	scene._set_menu(false)
	await _settle()
	check(scene.terrain_edit_preview.visible, "resume restores cached preview")

	# Enter the current settings panel, then navigate with physical buttons.
	# X entry/held-repeat/focus memory have their own complete-scene gate.
	scene._open_terrain_settings()
	await process_frame
	check(scene.tools_open and scene._terrain_panel.visible, "current terrain settings panel opens")
	check(not scene.terrain_edit_preview.visible, "tools menu hides preview")
	var focus := root.gui_get_focus_owner()
	check(focus != null and str(focus.get_meta("setting", "")) == "radius", "settings starts on Radius")
	await _press(JOY_BUTTON_DPAD_DOWN)
	focus = root.gui_get_focus_owner()
	check(focus != null and str(focus.get_meta("setting", "")) == "strength", "D-pad reaches Strength row")
	await _press(JOY_BUTTON_DPAD_RIGHT)
	check(scene.brush_strength_level == 4 and is_equal_approx(scene.brush_strength, StrengthScale.rate(4)), "controller increments accepted Raise strength from 3 to 4")
	check(scene.tools_open and not scene.stroke_active, "strength adjustment stays in settings without sculpting")
	await _press(JOY_BUTTON_B)
	await _settle()
	check(not scene.tools_open and scene.terrain_edit_preview.visible, "B closes settings and restores preview")
	check(scene._tool_meta.text.contains("Strength 4/10"), "visible HUD reflects adjusted strength")

	scene._select_terrain_tool("smooth")
	await _settle()
	check(scene.brush_strength_level == 5 and is_equal_approx(scene.brush_strength, StrengthScale.rate(5)), "Smooth retains independent accepted default 5")
	check(not scene.reference_plane.visible, "smooth has no generic blue plane")
	check(scene.terrain_edit_preview.visible, "smooth uses candidate preview")
	scene._select_terrain_tool("level")
	await process_frame
	check(scene.reference_plane.visible, "level retains meaningful target plane")
	scene._select_terrain_tool("raise")
	await _settle()
	check(scene.brush_strength_level == 4, "Raise remembers its adjusted strength across tool changes")
	scene._select_terrain_tool("dig")
	await _settle()
	check(scene.brush_strength_level == 3 and is_equal_approx(scene.brush_strength, StrengthScale.rate(3)), "Dig retains independent accepted default 3")
	check(scene.terrain_edit_preview.removals.multimesh.visible_instance_count > 0, "dig uses hatching layer")
	check(scene.terrain_edit_preview.additions.multimesh.visible_instance_count == 0, "dig never shows additions")
	var before_revision: int = scene.backend.stats().revision
	scene._begin_stroke()
	check(scene.stroke_active, "gentle native stroke begins")
	for _i in 12: await process_frame
	scene._cancel_current_edit("test cancel")
	await process_frame
	check(not scene.stroke_active and scene.backend.stats().revision == before_revision, "cancel preserves committed revision")
	scene._set_view_context("building")
	await process_frame
	check(not scene.terrain_edit_preview.visible, "cottage editing hides terrain layer")
	scene._begin_building_placement()
	check(scene.building_placement_active, "existing free cottage placement retained")
	scene._cancel_building_placement()
	check(not scene.building_placement_active, "existing cottage cancel retained")
	scene._set_view_context("terrain")
	scene._select_terrain_tool("foliage")
	await process_frame
	check(not scene.terrain_edit_preview.visible and scene.brush_preview.visible, "planting keeps its existing influence preview")
	print("m1_terrain_ux_test checks=%d failures=%d" % [checks, failures])
	scene._shutting_down = true
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _settle() -> void:
	# Async previews must become current, not necessarily finish in one frame.
	# Keep the existing three-second deadline and visible/current requirement.
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if not scene._layer_pending and scene.terrain_edit_preview.visible: return
	check(false, "preview becomes current within 3 seconds")
