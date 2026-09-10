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
	scene.checkpoint_root = "user://m2-roof-design-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline: int = Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "roof design scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	scene._open_building_panel()
	await process_frame
	var labels: Array[String] = []
	for button in scene._building_buttons: labels.append(button.text)
	check("Roof design" in labels, "home options expose a dedicated roof design row")
	check(scene._building_panel.get_global_rect().end.y <= scene._prompt_bar.get_global_rect().position.y + 1.0, "roof design row keeps home options above prompt bar")
	scene._close_building_panel()

	var original: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var original_profile: String = str(original.get("roof_profile", "gentle_gable"))
	var before_serialized: String = scene.building_world.serialize_document()
	scene._open_roof_design_picker()
	check(scene._roof_design_picker_open and scene._roof_design_picker.visible, "Roof design opens browse picker")
	check(scene._roof_design_buttons.size() == 7, "roof picker exposes three gables plus hip shed saltbox and gambrel")
	var ids: Array[String] = []
	for button in scene._roof_design_buttons: ids.append(str(button.get_meta("roof_profile", "")))
	check("hip" in ids and "shed" in ids and "saltbox" in ids and "gambrel" in ids, "roof picker includes reference-inspired silhouettes")

	scene._preview_roof_design("hip")
	await process_frame
	check(scene.building_world.serialize_document() == before_serialized, "roof browsing is read-only")
	var visual := scene.cottage_visuals.get(scene.selected_building_id, null) as Node3D
	check(visual != null and visual.get_node_or_null("M2RoofDesign") != null, "hip preview builds custom roof geometry")
	check(_base_roof_hidden(visual), "custom roof preview hides generic gable geometry")
	scene._cancel_roof_design_picker()
	await process_frame
	check(scene.building_world.serialize_document() == before_serialized and str(scene.building_world.get_building(scene.selected_building_id).get("roof_profile", "")) == original_profile, "B cancel restores authored roof without history")

	var history_before: int = scene._history_tags.size()
	scene._open_roof_design_picker()
	scene._commit_roof_design("saltbox")
	await process_frame
	var changed: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	check(str(changed.get("roof_profile", "")) == "saltbox", "A apply saves the selected roof design")
	check(scene._history_tags.size() == history_before + 1, "roof design apply records one scene history step")
	check(visual != null and visual.get_node_or_null("M2RoofDesign") != null, "saved saltbox renders through custom roof layer")
	check(scene.building_world.undo() and str(scene.building_world.get_building(scene.selected_building_id).get("roof_profile", "")) == original_profile, "roof design is one BuildingWorld undo transaction")
	check(scene.building_world.redo() and str(scene.building_world.get_building(scene.selected_building_id).get("roof_profile", "")) == "saltbox", "roof design redo restores silhouette")

	var serialized: String = scene.building_world.serialize_document()
	var restored = preload("res://scripts/building_world.gd").new()
	check(restored.load_serialized_document(serialized), "roof design document reloads")
	check(str(restored.get_building(scene.selected_building_id).get("roof_profile", "")) == "saltbox", "saved roof design survives reload")

	for profile in ["shed", "gambrel"]:
		scene._open_roof_design_picker()
		scene._preview_roof_design(str(profile))
		await process_frame
		var overlay := visual.get_node_or_null("M2RoofDesign") as Node3D if visual else null
		check(overlay != null and overlay.get_child_count() >= 4, "%s preview has a distinct multi-piece silhouette" % str(profile))
		scene._cancel_roof_design_picker()
		await process_frame
	await _finish()

func _base_roof_hidden(visual: Node3D) -> bool:
	if not visual: return false
	var found := false
	for child in visual.get_children():
		var name := str(child.name)
		if name.begins_with("RoofTiles_"):
			found = true
			if bool(child.get("visible")): return false
	return found

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m2_roof_design_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
