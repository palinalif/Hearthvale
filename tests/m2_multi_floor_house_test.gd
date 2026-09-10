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
	scene.checkpoint_root = "user://m2-multi-floor-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline: int = Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "multi-floor scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	await process_frame

	scene._open_house_shape_picker()
	await process_frame
	var labels: Array[String] = []
	for button in scene._house_shape_buttons: labels.append(button.text)
	check(labels.any(func(label): return label.begins_with("Add portion to floor")), "House shape menu exposes upper-floor portion editing")
	check(labels.any(func(label): return label.begins_with("Start floor")), "House shape menu exposes starting another storey")
	check(scene._house_shape_picker.get_global_rect().end.y <= scene._prompt_bar.get_global_rect().position.y + 2.0, "expanded house shape menu stays above the 720p prompt bar")
	scene._close_house_shape_picker(false)

	var base_view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var storey: float = Massing.storey_height(base_view)
	var before_serialized: String = scene.building_world.serialize_document()
	scene._begin_next_storey()
	await process_frame
	check(scene.portion_placement_active and scene.portion_level == 1, "Start floor 2 enters the existing portion placement flow on level 1")
	check(scene.portion_valid, "first upper-floor preview starts fully supported")
	check(scene.building_world.serialize_document() == before_serialized, "upper-floor preview remains save-data pure")
	var visual: Node3D = scene.cottage_visuals.get(scene.selected_building_id, null) as Node3D
	var ghost: Node3D = visual.get_node_or_null("M2PortionGhost") as Node3D if visual else null
	check(ghost != null and ghost.position.y >= storey + scene.portion_size.y * 0.45, "upper-floor placement ghost is visibly stacked above floor 1")
	check(scene._commit_portion_placement(), "supported floor 2 portion commits")
	await process_frame
	var view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	check(Massing.floor_count(view) == 2, "committed upper portion makes a two-floor house")
	var floor_two: Array[Dictionary] = Massing.sections_on_level(Massing.sections_for(view), 1)
	check(floor_two.size() == 1, "floor 2 starts with one authored portion")

	scene._begin_upper_floor_portion()
	await process_frame
	check(scene.portion_level == 1, "Add upper-floor portion stays on the current highest occupied floor")
	check(scene.portion_valid, "second floor-2 portion finds a supported starting position")
	if scene.portion_valid: check(scene._commit_portion_placement(), "second floor-2 portion joins")
	await process_frame
	view = scene.building_world.get_building(scene.selected_building_id)
	floor_two = Massing.sections_on_level(Massing.sections_for(view), 1)
	check(floor_two.size() >= 2, "same-floor portions can form an L/T-style upper storey")

	scene._begin_upper_floor_portion()
	await process_frame
	check(scene.portion_level == 1, "support rejection test is editing floor 2")
	scene.portion_offset.x += 40.0
	scene._update_portion_preview()
	await process_frame
	check(not scene.portion_valid and scene.portion_reason.contains("support"), "upper portion dragged beyond floor below is rejected instead of floating")
	scene._cancel_portion_placement()

	scene._begin_next_storey()
	await process_frame
	check(scene.portion_level == 2, "Start floor 3 advances above the current top floor")
	check(scene.portion_valid, "floor 3 preview finds support on floor 2")
	if scene.portion_valid: check(scene._commit_portion_placement(), "floor 3 portion commits")
	await process_frame
	view = scene.building_world.get_building(scene.selected_building_id)
	check(Massing.floor_count(view) == 3, "house can reach three authored storeys")
	check(Massing.sections_on_level(Massing.sections_for(view), 2).size() == 1, "third storey is stored as its own vertical mass")

	visual = scene.cottage_visuals.get(scene.selected_building_id, null) as Node3D
	var joined: Node3D = visual.get_node_or_null("M2JoinedMassing") as Node3D if visual else null
	check(joined != null and joined.get_node_or_null("JoinedFloorBands") != null, "multi-floor joined renderer adds readable storey bands")
	check(scene._selected_building_camera_target().y > storey * 0.45, "building camera target expands vertically for stacked houses")

	var serialized: String = scene.building_world.serialize_document()
	var restored = preload("res://scripts/building_world.gd").new()
	check(restored.load_serialized_document(serialized), "multi-floor house document reloads")
	var restored_view: Dictionary = restored.get_building(scene.selected_building_id)
	check(Massing.floor_count(restored_view) == 3 and Massing.max_level(Massing.sections_for(restored_view)) == 2, "storey levels survive save and reload")
	check(scene.building_world.undo(), "third-floor placement is undoable as one transaction")
	check(Massing.floor_count(scene.building_world.get_building(scene.selected_building_id)) == 2, "undo removes the latest storey without flattening floor 2")

	await _finish()

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m2_multi_floor_house_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
