extends SceneTree

var checks := 0
var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-surface-colours-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene._player_restored, "surface-colour scene ready")
	if not scene._player_restored:
		_finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	var original: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var original_wall := str(original.get("wall_material_id", "stone_plaster"))
	var original_roof := str(original.get("roof_material_id", "terracotta"))
	var wall_choice := _different_choice("wall", original_wall)
	var roof_choice := _different_choice("roof", original_roof)
	_check(not wall_choice.is_empty() and not roof_choice.is_empty(), "picker has alternate wall and roof colours")
	var wall_button_found := false
	var roof_button_found := false
	for button in scene._building_buttons:
		wall_button_found = wall_button_found or button.text == "Wall colour"
		roof_button_found = roof_button_found or button.text == "Roof colour"
	_check(wall_button_found and roof_button_found, "home options expose Wall colour and Roof colour actions")

	var before_serialized := scene.building_world.serialize_document()
	scene._begin_surface_material_picker("wall")
	_check(scene._surface_picker_mode == "wall" and scene._surface_picker_panel.visible, "Wall colour opens the shared preview picker")
	scene._preview_surface_material(wall_choice)
	_check(scene.building_world.serialize_document() == before_serialized, "wall colour browsing is read-only")
	var visual = scene.cottage_visuals.get(scene.selected_building_id, null)
	_check(visual != null and str(visual._applied_view.get("wall_material_id", "")) == wall_choice, "wall colour focus previews directly on the house")
	scene._cancel_surface_material_picker()
	_check(scene.building_world.serialize_document() == before_serialized and scene._surface_picker_mode.is_empty(), "B-style cancel restores wall colour without history")

	var history_before: int = scene._history_tags.size()
	scene._begin_surface_material_picker("wall")
	scene._commit_surface_material(wall_choice)
	_check(str(scene.building_world.get_building(scene.selected_building_id).get("wall_material_id", "")) == wall_choice, "A-style apply persists wall colour")
	_check(scene._history_tags.size() == history_before + 1, "wall colour apply records one undo step")

	scene._begin_surface_material_picker("roof")
	_check(scene._surface_picker_mode == "roof" and scene._surface_picker_panel.visible, "Roof colour uses the same picker")
	var wall_persisted := str(scene.building_world.get_building(scene.selected_building_id).get("wall_material_id", ""))
	var roof_before_preview := scene.building_world.serialize_document()
	scene._preview_surface_material(roof_choice)
	_check(scene.building_world.serialize_document() == roof_before_preview, "roof colour browsing is read-only")
	_check(visual != null and str(visual._applied_view.get("roof_material_id", "")) == roof_choice, "roof colour focus previews directly on the house")
	scene._commit_surface_material(roof_choice)
	var after: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	_check(str(after.get("roof_material_id", "")) == roof_choice and str(after.get("wall_material_id", "")) == wall_persisted, "roof apply persists independently from wall colour")
	_check(scene._history_tags.size() == history_before + 2, "roof colour apply records one undo step")
	_finish()

func _different_choice(mode: String, current: String) -> String:
	for spec_value in scene.SURFACE_MATERIAL_CHOICES[mode]:
		var spec: Array = spec_value
		if str(spec[0]) != current: return str(spec[0])
	return ""

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures}))
	quit(1 if failures else 0)
