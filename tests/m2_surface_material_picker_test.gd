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
	var original_wall := str(original.get("wall_material_id", original.get("material_id", "stone_plaster")))
	var original_roof := str(original.get("roof_material_id", "terracotta"))
	var wall_choice := _different_choice(scene.WALL_MATERIALS, original_wall)
	var roof_choice := _different_choice(scene.ROOF_MATERIALS, original_roof)
	_check(not wall_choice.is_empty() and not roof_choice.is_empty(), "picker has alternate wall and roof colours")
	var wall_button: Button = null
	var roof_button: Button = null
	for button in scene._building_buttons:
		if button.text == "Wall colour": wall_button = button
		if button.text == "Roof colour": roof_button = button
	_check(wall_button != null and roof_button != null, "home options expose Wall colour and Roof colour")

	var before_serialized: String = str(scene.building_world.serialize_document())
	scene._open_surface_material_picker("wall")
	_check(scene._surface_material_picker_open and scene._surface_material_picker_kind == "wall" and scene._surface_material_picker_panel.visible, "Wall colour opens browse picker")
	_check(scene._surface_material_candidates().size() == scene.WALL_MATERIALS.size(), "wall picker shows every wall material")
	scene._preview_surface_material(wall_choice)
	_check(scene.building_world.serialize_document() == before_serialized, "wall colour browsing is read-only")
	var visual = scene.cottage_visuals.get(scene.selected_building_id, null)
	_check(visual != null and str(visual._applied_view.get("wall_material_id", "")) == wall_choice, "wall colour focus previews directly on house")
	scene._cancel_surface_material_picker()
	_check(scene.building_world.serialize_document() == before_serialized and not scene._surface_material_picker_open, "B cancel restores wall colour without history")

	var history_before: int = scene._history_tags.size()
	scene._open_surface_material_picker("wall")
	scene._commit_surface_material(wall_choice)
	_check(str(scene.building_world.get_building(scene.selected_building_id).get("wall_material_id", "")) == wall_choice, "A apply persists wall colour")
	_check(scene._history_tags.size() == history_before + 1, "wall colour apply records one undo step")

	scene._open_surface_material_picker("roof")
	_check(scene._surface_material_picker_open and scene._surface_material_picker_kind == "roof", "Roof colour uses the same picker")
	_check(scene._surface_material_candidates().size() == scene.ROOF_MATERIALS.size(), "roof picker shows every roof material")
	var wall_persisted := str(scene.building_world.get_building(scene.selected_building_id).get("wall_material_id", ""))
	var roof_before_preview: String = str(scene.building_world.serialize_document())
	scene._preview_surface_material(roof_choice)
	_check(scene.building_world.serialize_document() == roof_before_preview, "roof colour browsing is read-only")
	_check(visual != null and str(visual._applied_view.get("roof_material_id", "")) == roof_choice, "roof colour focus previews directly on house")
	scene._commit_surface_material(roof_choice)
	var after: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	_check(str(after.get("roof_material_id", "")) == roof_choice and str(after.get("wall_material_id", "")) == wall_persisted, "roof apply persists independently from wall colour")
	_check(scene._history_tags.size() == history_before + 2, "roof colour apply records one undo step")
	_finish()

func _different_choice(choices: Array, current: String) -> String:
	for value in choices:
		if str(value) != current: return str(value)
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
