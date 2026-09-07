extends SceneTree
## Exercise the actual exported scene, not only a historical base script.
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
	check(scene.brush_strength_level == 5 and is_equal_approx(scene.brush_strength, 2.0), "exported scene uses gentle default")
	check(scene.terrain_edit_preview.visible, "new cell preview visible")
	check(not scene.brush_preview.visible, "old sphere preview hidden for sculpting")
	check(not scene.reference_plane.visible, "raise has no flat reference square")
	check(scene.preview_cells.size() > 9, "preview covers the footprint")
	check(scene.target_label.text.contains("Strength 5/10") and scene.target_label.text.contains("Next layer"), "HUD labels scale and horizon")
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
	scene._open_actions_for_context()
	await process_frame
	check(not scene.terrain_edit_preview.visible, "tools menu hides preview")
	scene._tool_choice("Strength +")
	await process_frame
	check(scene.brush_strength_level == 6 and scene.brush_strength > 2.0, "controller strength selection")
	scene._tool_choice("Smooth")
	await _settle()
	check(not scene.reference_plane.visible, "smooth has no generic blue plane")
	check(scene.terrain_edit_preview.visible, "smooth uses candidate preview")
	scene._tool_choice("Level")
	await process_frame
	check(scene.reference_plane.visible, "level retains meaningful target plane")
	scene._tool_choice("Dig")
	await _settle()
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
	scene._tool_choice("Foliage brush")
	await process_frame
	check(not scene.terrain_edit_preview.visible and scene.brush_preview.visible, "planting keeps its existing influence preview")
	print("m1_terrain_ux_test checks=%d failures=%d" % [checks, failures])
	scene._shutting_down = true
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _settle() -> void:
	# Async previews must become current, not necessarily finish in one frame.
	# The visual/cell/HUD assertions above are unchanged.
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if not scene._layer_pending and scene.terrain_edit_preview.visible: return
	check(false, "preview becomes current within 3 seconds")
