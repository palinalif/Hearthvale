extends SceneTree

var checks := 0
var failures := 0
var scene: Node

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-window-expansion-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "window expansion scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	var view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var window_id := ""
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("kind", "")) == "window" and bool(detail.get("visible", true)) and not bool(detail.get("needs_placement", false)):
			window_id = str(detail.get("id", ""))
			break
	check(not window_id.is_empty(), "test cottage has an editable window")
	if window_id.is_empty():
		await _finish()
		return
	scene.selected_detail_id = window_id
	var candidate_assets: Array[String] = []
	for button_value in scene._style_candidates("variation"):
		var button := button_value as Button
		var spec: Dictionary = scene._style_button_specs.get(str(button.name), {})
		candidate_assets.append(str(spec.get("value", "")))
	check("window_cottage_cross" in candidate_assets and "window_cottage_triple" in candidate_assets and "window_round_sunburst" in candidate_assets, "style picker exposes three additional window silhouettes")
	check(candidate_assets.size() >= 10, "expanded window picker retains the existing designs")

	check(scene._commit_detail_style(window_id, "window_cottage_cross", "natural"), "cross-pane window style commits")
	scene._update_presentation()
	await process_frame
	var visual := scene.cottage_visuals.get(scene.selected_building_id, null) as Node3D
	check(visual != null, "selected cottage visual exists")
	if visual:
		check(visual.get_node_or_null("M2WindowDecor_" + window_id) != null, "cross-pane window receives custom joinery overlay")
		var base_joinery := visual.get_node_or_null("Joinery_" + window_id) as Node3D
		check(base_joinery == null or not base_joinery.visible, "custom joinery replaces rather than doubles the generic muntins")

	check(scene._commit_detail_style(window_id, "window_round_sunburst", "natural"), "sunburst window style commits")
	scene._update_presentation()
	await process_frame
	if visual:
		var sunburst := visual.get_node_or_null("M2WindowDecor_" + window_id) as Node3D
		check(sunburst != null and sunburst.get_child_count() >= 6, "round sunburst builds a visibly distinct multi-piece pattern")
	var serialized: String = scene.building_world.serialize_document()
	var restored = preload("res://scripts/building_world.gd").new()
	check(restored.load_serialized_document(serialized), "expanded window design save reloads")
	var restored_view: Dictionary = restored.get_building(scene.selected_building_id)
	check(restored_view.get("details", []).any(func(detail): return str(detail.get("id", "")) == window_id and str(detail.get("asset_id", "")) == "window_round_sunburst"), "chosen extra window design survives reload")
	await _finish()

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m2_window_style_expansion_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
