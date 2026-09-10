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
	_run.call_deferred()

func _run() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-decor-colour-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "decor-colour scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	var building_id: String = scene.selected_building_id
	var view: Dictionary = scene.building_world.get_building(building_id)
	var windows: Array[String] = []
	var ids: Array[String] = []
	for value in view.get("details", []):
		var detail: Dictionary = value
		if not bool(detail.get("visible", false)) or bool(detail.get("needs_placement", false)): continue
		if str(detail.get("kind", "")) == "window": windows.append(str(detail["id"]))
		if str(detail.get("kind", "")) == "door": ids.append(str(detail["id"]))
	check(windows.size() >= 2 and not ids.is_empty(), "fixture contains editable windows and a door")
	if windows.size() < 2 or ids.is_empty():
		await _finish()
		return
	ids.append(windows[0])
	for spec in [["flower_box", "wall-front", Vector3(0, 1.5, -7.02), "flower_box_wood"], ["shutter", "wall-back", Vector3(0, 3.4, 7.02), "shutter_wood"]]:
		var id: String = scene.building_world.add_detail(building_id, spec[0], spec[1], spec[2], spec[3])
		check(not id.is_empty(), "fixture adds " + str(spec[0]))
		if not id.is_empty(): ids.append(id)
	await _refresh()
	for id in ids:
		scene.selected_detail_id = id
		var original: String = scene.building_world.serialize_document()
		var inherited: Color = scene.ACCENT_COLOURS[scene._accent_material_id(scene.building_world.get_building(building_id))]
		scene._begin_style_picker("colour")
		for colour_id in scene.DETAIL_COLOURS:
			scene._preview_style_choice("colour", colour_id)
			_check_base_colour(building_id, id, scene.DETAIL_COLOURS[colour_id], "immediate preview " + str(colour_id))
			await _refresh()
			_check_base_colour(building_id, id, scene.DETAIL_COLOURS[colour_id], "preview survives presentation " + str(colour_id))
			check(scene.building_world.serialize_document() == original, "colour preview leaves authority untouched")
		scene._cancel_style_picker()
		await _refresh()
		check(scene.building_world.serialize_document() == original, "cancel leaves document and revision intact")
		_check_base_colour(building_id, id, inherited, "cancel restores house accent")
		var revision: int = scene.building_world.get_revision()
		scene._begin_style_picker("colour")
		scene._commit_style_choice("colour", "natural")
		await _refresh()
		check(scene.building_world.get_revision() == revision + 1, "explicit natural wood is one revision, not a no-op")
		_check_base_colour(building_id, id, scene.DETAIL_COLOURS["natural"], "natural wood beats house accent")
		check(scene.building_world.undo(), "colour undo succeeds")
		await _refresh()
		_check_base_colour(building_id, id, inherited, "undo restores inheritance")
		check(scene.building_world.redo(), "colour redo succeeds")
		await _refresh()
		_check_base_colour(building_id, id, scene.DETAIL_COLOURS["natural"], "redo restores explicit colour")

	# A variation-only edit must not silently lock in the old picker default.
	scene.selected_detail_id = windows[1]
	scene._begin_style_picker("variation")
	scene._commit_style_choice("variation", "window_cottage_cross")
	await _refresh()
	check(not (scene._selected_detail_record().get("override", {}) as Dictionary).has("color_id"), "changing window shape preserves house-colour inheritance")
	var before_accent: String = scene.building_world.serialize_document()
	scene._open_accent_colour_picker()
	scene._preview_surface_material("plum")
	_check_cross_colour(building_id, windows[1], scene.ACCENT_COLOURS["plum"], "custom window follows live accent preview")
	for id in ids: _check_base_colour(building_id, id, scene.DETAIL_COLOURS["natural"], "accent preview respects manual colours")
	scene._cancel_surface_material_picker()
	await _refresh()
	check(scene.building_world.serialize_document() == before_accent, "accent cancel remains read-only")
	var saved_accent: Color = scene.ACCENT_COLOURS[scene._accent_material_id(scene.building_world.get_building(building_id))]
	_check_cross_colour(building_id, windows[1], saved_accent, "accent cancel restores custom window colour")
	scene._open_accent_colour_picker()
	scene._commit_surface_material("plum")
	await _refresh()
	for id in ids: _check_base_colour(building_id, id, scene.DETAIL_COLOURS["natural"], "saved accent respects manual colours")
	_check_cross_colour(building_id, windows[1], scene.ACCENT_COLOURS["plum"], "unpainted custom window follows saved accent")

	# A later selection, duplicate and reload must not rely on selection-only tint.
	var copy_id: String = scene.building_world.duplicate_building(building_id, Vector3(10, 0, 0))
	check(not copy_id.is_empty(), "edited home duplicates")
	scene.selected_building_id = copy_id
	scene.selected_detail_id = ""
	await _refresh()
	for id in ids: _check_base_colour(building_id, id, scene.DETAIL_COLOURS["natural"], "unselected original retains personal colours")
	var serialized: String = scene.building_world.serialize_document()
	check(scene.building_world.load_serialized_document(serialized), "decor colour save reloads")
	await _refresh()
	for id in ids: _check_base_colour(building_id, id, scene.DETAIL_COLOURS["natural"], "reloaded original retains personal colours")
	var copy: Dictionary = scene.building_world.get_building(copy_id)
	var coloured_copy_details := 0
	for value in copy.get("details", []):
		var detail: Dictionary = value
		if str((detail.get("override", {}) as Dictionary).get("color_id", "")) != "natural": continue
		coloured_copy_details += 1
		_check_base_colour(copy_id, str(detail["id"]), scene.DETAIL_COLOURS["natural"], "duplicate keeps independent detail colour")
	check(coloured_copy_details >= ids.size(), "duplication retains all manually coloured records")
	await _finish()

func _refresh() -> void:
	scene._presentation_key = ""
	scene._update_presentation()
	await process_frame

func _check_base_colour(building_id: String, detail_id: String, expected: Color, label: String) -> void:
	var visual: Node = scene.cottage_visuals.get(building_id, null)
	check(visual != null, label + ": actual gameplay visual exists")
	if not visual: return
	var found := 0
	for prefix in ["Joinery_", "Shutters_", "ManualShutter_", "FlowerBox_", "DoorJoinery_", "PorchBrackets_"]:
		var piece := visual.get_node_or_null(prefix + detail_id) as GeometryInstance3D
		if not piece: continue
		found += 1
		var material := piece.material_override as StandardMaterial3D
		check(material != null and material.albedo_color.is_equal_approx(expected), label + ": effective " + prefix + detail_id)
	check(found > 0, label + ": inspect real material, not just saved colour ID")

func _check_cross_colour(building_id: String, detail_id: String, expected: Color, label: String) -> void:
	var visual: Node = scene.cottage_visuals.get(building_id, null)
	var overlay: Node = visual.get_node_or_null("M2WindowDecor_" + detail_id) if visual else null
	check(overlay != null and overlay.get_child_count() > 0, label + ": custom joinery exists")
	if not overlay: return
	for child in overlay.get_children():
		if not child is GeometryInstance3D: continue
		var material := (child as GeometryInstance3D).material_override as StandardMaterial3D
		check(material != null and material.albedo_color.is_equal_approx(expected), label + ": custom joinery material")

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m2_decor_colour_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
