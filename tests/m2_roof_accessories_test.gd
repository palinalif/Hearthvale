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
	scene.checkpoint_root = "user://m2-roof-accessories-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline: int = Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "roof accessory scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	scene._open_building_panel()
	await process_frame
	var labels: Array[String] = []
	for button in scene._building_buttons: labels.append(button.text)
	check("Roof decor" in labels, "home options expose roof decor separately from roof design")
	check(scene._building_panel.get_global_rect().end.y <= scene._prompt_bar.get_global_rect().position.y + 1.0, "roof decor row keeps compact home options above prompt bar")
	scene._close_building_panel()

	scene._open_roof_decor_picker()
	check(scene._roof_decor_picker_open and scene._roof_decor_picker.visible, "Roof decor opens its own picker")
	check(scene._roof_decor_buttons.size() == 7, "roof decor offers six accessories plus remove-last")
	var assets: Array[String] = []
	for button in scene._roof_decor_buttons:
		var asset_id: String = str(button.get_meta("asset_id", ""))
		if not asset_id.is_empty(): assets.append(asset_id)
	check("chimney_stone" in assets and "chimney_brick" in assets and "dormer_gable" in assets and "dormer_shed" in assets and "weathervane_arrow" in assets and "weathervane_rooster" in assets, "picker includes chimneys dormers and weathervanes")

	var before_serialized: String = scene.building_world.serialize_document()
	scene._begin_roof_accessory_placement("chimney_stone")
	check(scene.roof_accessory_placement_active and scene.roof_accessory_asset_id == "chimney_stone", "choosing chimney enters roof placement")
	check(scene.building_world.serialize_document() == before_serialized, "roof accessory preview is authoritative-data pure")
	scene.roof_accessory_u = 0.72
	scene.roof_accessory_v = 0.34
	scene._refresh_roof_accessory_preview()
	await process_frame
	var visual: Node3D = scene.cottage_visuals.get(scene.selected_building_id, null) as Node3D
	check(visual != null, "selected cottage visual exists")
	var preview_root: Node3D = null
	if visual: preview_root = visual.get_node_or_null("M2RoofAccessories") as Node3D
	check(preview_root != null and preview_root.get_child_count() == 1, "roof placement renders one preview accessory")
	scene._cancel_roof_accessory_placement()
	await process_frame
	check(scene.building_world.serialize_document() == before_serialized and not scene.roof_accessory_placement_active, "B cancel removes preview without save history")

	var history_before: int = scene._history_tags.size()
	scene._begin_roof_accessory_placement("chimney_brick")
	scene.roof_accessory_u = 0.68
	scene.roof_accessory_v = 0.42
	check(scene._commit_roof_accessory_placement(), "brick chimney commits from roof placement")
	var view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var accessories: Array = view.get("roof_accessories", [])
	check(accessories.size() == 1 and str((accessories[0] as Dictionary).get("asset_id", "")) == "chimney_brick", "chimney is saved on the house recipe")
	check(scene._history_tags.size() == history_before + 1, "chimney placement records one scene history step")

	scene._begin_roof_accessory_placement("dormer_gable")
	scene.roof_accessory_u = 0.38
	scene.roof_accessory_v = 0.28
	check(scene._commit_roof_accessory_placement(), "gabled dormer commits")
	scene._begin_roof_accessory_placement("weathervane_rooster")
	scene.roof_accessory_u = 0.52
	scene.roof_accessory_v = 0.50
	check(scene._commit_roof_accessory_placement(), "rooster weathervane commits")
	await process_frame
	view = scene.building_world.get_building(scene.selected_building_id)
	accessories = view.get("roof_accessories", [])
	check(accessories.size() == 3, "multiple roof accessory families coexist on one house")
	var kinds: Array[String] = []
	for record_value in accessories:
		var record: Dictionary = record_value
		kinds.append(str(record.get("kind", "")))
	check("chimney" in kinds and "dormer" in kinds and "weathervane" in kinds, "saved roof composition keeps accessory kinds")
	var render_root: Node3D = null
	if visual: render_root = visual.get_node_or_null("M2RoofAccessories") as Node3D
	check(render_root != null and render_root.get_child_count() == 3, "saved chimney dormer and vane all render")

	var serialized: String = scene.building_world.serialize_document()
	var restored = preload("res://scripts/building_world.gd").new()
	check(restored.load_serialized_document(serialized), "roof accessory document reloads")
	var restored_view: Dictionary = restored.get_building(scene.selected_building_id)
	var restored_accessories: Array = restored_view.get("roof_accessories", [])
	check(restored_accessories.size() == 3, "roof accessories survive save reload")
	check(restored_accessories.any(func(record): return str(record.get("asset_id", "")) == "dormer_gable") and restored_accessories.any(func(record): return str(record.get("asset_id", "")) == "weathervane_rooster"), "dormer and weathervane asset choices survive reload")
	check(scene.building_world.undo() and (scene.building_world.get_building(scene.selected_building_id).get("roof_accessories", []) as Array).size() == 2, "latest roof accessory is one undo transaction")
	check(scene.building_world.redo() and (scene.building_world.get_building(scene.selected_building_id).get("roof_accessories", []) as Array).size() == 3, "roof accessory redo restores composition")
	await _finish()

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m2_roof_accessories_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
