extends SceneTree

const Massing = preload("res://scripts/m2_house_massing.gd")
var scene: Node
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-house-massing-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "massing scene ready")
	if not scene._player_restored:
		await _finish(); return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	await process_frame

	var shape_button: Button = null
	for button in scene._building_buttons:
		if button.text.begins_with("House shape"):
			shape_button = button
			break
	check(shape_button != null, "Home options expose one House shape entry")
	var base_serialized: String = scene.building_world.serialize_document()
	var history_before: int = scene._history_tags.size()
	check(scene._apply_house_shape_preset("l_shape"), "L-shaped preset commits")
	await process_frame
	var view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	check(Massing.sections_for(view).size() == 2 and str(view.get("massing_preset", "")) == "l_shape", "L shape is saved as connected massing sections")
	check(scene._history_tags.size() == history_before + 1, "shape preset records one scene undo step")
	check(scene.building_world.serialize_document() != base_serialized, "shape preset changes authoritative save data")

	var visual := scene.cottage_visuals.get(scene.selected_building_id, null) as Node3D
	var joined := visual.get_node_or_null("M2JoinedMassing") as Node3D if visual else null
	check(joined != null and joined.get_child_count() >= 4, "joined shell replaces overlapping independent cottage roofs")
	var base_wall := visual.get_node_or_null("WallFront") as Node3D if visual else null
	check(base_wall == null or not base_wall.visible, "legacy rectangular wall shell is hidden for multi-portion houses")
	var detail_found := false
	if visual:
		for child in visual.get_children():
			if str(child.name).begins_with("Detail_"):
				detail_found = true
				break
	check(detail_found, "existing doors and windows remain rendered over the joined shell")

	var before_preview: String = scene.building_world.serialize_document()
	scene._begin_portion_placement()
	await process_frame
	check(scene.portion_placement_active, "Add house portion enters direct placement")
	check(scene.building_world.serialize_document() == before_preview, "portion preview does not mutate save data")
	check(scene.portion_valid, "default portion preview starts joined to an exterior wall")
	var preview_root := visual.get_node_or_null("M2PortionGhost") if visual else null
	check(preview_root != null, "portion placement has an explicit validity ghost")

	var section_count_before: int = Massing.sections_for(view).size()
	check(scene._commit_portion_placement(), "valid portion commits")
	await process_frame
	view = scene.building_world.get_building(scene.selected_building_id)
	check(Massing.sections_for(view).size() == section_count_before + 1 and str(view.get("massing_preset", "")) == "custom", "committed portion becomes part of custom house footprint")
	check(not scene.portion_placement_active, "portion placement exits after commit")

	var serialized: String = scene.building_world.serialize_document()
	var restored = preload("res://scripts/building_world.gd").new()
	var loaded: bool = restored.load_serialized_document(serialized)
	if not loaded:
		print("MASSING_SAVE_DIAGNOSTIC " + JSON.stringify({"bytes": serialized.to_utf8_buffer().size(), "source_valid": scene.building_world._validate_document(scene.building_world.get_document()), "parsed_valid": restored._validate_document(JSON.parse_string(serialized)), "document": scene.building_world.get_document()}))
	check(loaded, "multi-portion house save reloads through BuildingWorld")
	var restored_view: Dictionary = restored.get_building(scene.selected_building_id)
	check(Massing.sections_for(restored_view).size() == section_count_before + 1, "custom portions survive save and reload")

	check(scene.building_world.undo(), "authoritative portion commit is undoable")
	var undone_view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	check(Massing.sections_for(undone_view).size() == section_count_before, "undo removes only the latest portion")

	await _finish()

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m2_house_massing_edit_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
