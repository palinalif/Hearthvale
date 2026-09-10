extends SceneTree

var scene: Node
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-window-customization-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "window customization scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	var view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var window_ids: Array[String] = []
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("kind", "")) == "window" and bool(detail.get("visible", true)) and not bool(detail.get("needs_placement", false)):
			window_ids.append(str(detail.get("id", "")))
	check(window_ids.size() >= 2, "test cottage has two editable windows")
	if window_ids.size() < 2:
		await _finish()
		return
	var window_id: String = window_ids[0]
	var extras_window_id: String = window_ids[1]
	scene.selected_detail_id = window_id

	var candidates: Array[String] = []
	for button_value in scene._style_candidates("variation"):
		var button := button_value as Button
		var spec: Dictionary = scene._style_button_specs.get(str(button.name), {})
		candidates.append(str(spec.get("value", "")))
	for asset_id in scene.ADVENTURE_WINDOW_ASSETS:
		check(asset_id in candidates, "variation picker exposes " + asset_id)
	check(candidates.size() >= 14, "adventurous shapes extend rather than replace the existing window set")

	check(scene._commit_detail_style(window_id, "window_arch_casement", "natural"), "arched window commits through normal variation authority")
	scene._update_presentation()
	await process_frame
	var visual := scene.cottage_visuals.get(scene.selected_building_id, null) as Node3D
	check(visual != null, "selected cottage visual exists")
	if visual:
		var arch := visual.get_node_or_null("M2WindowAdventure_" + window_id) as Node3D
		check(arch != null and arch.find_child("ArchCenter", true, false) != null, "arched casement builds distinct stepped joinery")
		var joinery := visual.get_node_or_null("Joinery_" + window_id) as Node3D
		check(joinery == null or not joinery.visible, "adventurous shape replaces generic muntins")

	check(scene._commit_detail_style(window_id, "window_bay", "natural"), "bay window style commits")
	scene._update_presentation()
	await process_frame
	if visual:
		var bay := visual.get_node_or_null("M2WindowAdventure_" + window_id) as Node3D
		check(bay != null and bay.find_child("BayCenterGlass", true, false) != null and bay.find_child("BayWingLeft", true, false) != null, "bay window protrudes with centre and side panes")
		var base_pane := visual.get_node_or_null("Detail_" + window_id) as Node3D
		check(base_pane == null or not base_pane.visible, "bay window hides the old flat pane instead of stacking geometry")

	# Use an untouched automatic window for extras so cosmetic modifiers prove
	# they can follow future house reflow instead of locking the attachment.
	scene.selected_detail_id = extras_window_id
	scene._update_presentation()
	await process_frame
	var before_preview: String = scene.building_world.serialize_document()
	scene._open_window_extras()
	check(scene._window_extras_open and scene._window_extras_panel.visible, "Window extras opens its own controller picker")
	check(scene._window_extras_preview.get("shutter_style", "") == "original", "existing windows begin with original shutters")
	scene._window_extras_preview = {
		"shutter_style": "louvered",
		"shutter_state": "half_open",
		"flower_box": "woven",
		"window_state": "open",
		"balcony": "juliet",
	}
	scene._refresh_window_extra_buttons()
	scene._refresh_window_customization()
	await process_frame
	check(scene.building_world.serialize_document() == before_preview, "browsing window extras is read-only")
	if visual:
		var preview := visual.get_node_or_null("M2WindowAdventure_" + extras_window_id) as Node3D
		check(preview != null and preview.find_child("CustomShutter0_closed", true, false) != null and preview.find_child("CustomShutter1_open", true, false) != null, "half-open louvered shutters preview as two different leaf states")
		check(preview != null and preview.find_child("WindowFlowerBox", true, false) != null and preview.find_child("FlowerWeave0", true, false) != null, "woven flower box is built into the window composition")
		check(preview != null and preview.find_child("JulietTopRail", true, false) != null and preview.find_child("JulietBaluster3", true, false) != null, "Juliet balcony adds a tiny exterior rail")
		check(preview != null and preview.find_child("CasementOpenLeaf", true, false) != null, "open window state creates a projected casement leaf")
		var base_pane := visual.get_node_or_null("Detail_" + extras_window_id) as Node3D
		check(base_pane == null or not base_pane.visible, "open state hides the closed base pane during preview")

	check(scene._commit_window_extras(), "A-style apply saves the composed window extras")
	var saved_view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var saved_detail: Dictionary = _detail(saved_view, extras_window_id)
	var saved_extras: Dictionary = (saved_detail.get("override", {}) as Dictionary).get("window_extras", {})
	check(str(saved_extras.get("shutter_style", "")) == "louvered" and str(saved_extras.get("shutter_state", "")) == "half_open", "shutter style and state persist independently")
	check(str(saved_extras.get("flower_box", "")) == "woven" and str(saved_extras.get("balcony", "")) == "juliet" and str(saved_extras.get("window_state", "")) == "open", "flower box balcony and open state persist together")
	check(str(saved_detail.get("state", "")) == "automatic", "cosmetic extras do not freeze an automatic window's resize reflow")

	var serialized: String = scene.building_world.serialize_document()
	var restored = preload("res://scripts/building_world.gd").new()
	check(restored.load_serialized_document(serialized), "composed window extras survive document validation")
	var restored_detail: Dictionary = _detail(restored.get_building(scene.selected_building_id), extras_window_id)
	var restored_extras: Dictionary = (restored_detail.get("override", {}) as Dictionary).get("window_extras", {})
	check(str(restored_extras.get("balcony", "")) == "juliet" and str(restored_extras.get("window_state", "")) == "open", "window extras survive save and reload")

	# Cancel must restore the authoritative composition, not commit whatever was
	# highlighted last in the picker.
	scene._open_window_extras()
	var before_cancel: String = scene.building_world.serialize_document()
	scene._window_extras_preview["balcony"] = "none"
	scene._window_extras_preview["flower_box"] = "none"
	scene._refresh_window_customization()
	await process_frame
	scene._cancel_window_extras()
	check(scene.building_world.serialize_document() == before_cancel, "B cancel leaves saved window extras untouched")
	scene._update_presentation()
	await process_frame
	if visual:
		var restored_overlay := visual.get_node_or_null("M2WindowAdventure_" + extras_window_id) as Node3D
		check(restored_overlay != null and restored_overlay.find_child("JulietTopRail", true, false) != null and restored_overlay.find_child("WindowFlowerBox", true, false) != null, "cancel restores the saved balcony and planter presentation")

	await _finish()

func _detail(view: Dictionary, detail_id: String) -> Dictionary:
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("id", "")) == detail_id: return detail
	return {}

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m2_window_customization_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
