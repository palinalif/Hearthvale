extends SceneTree

var scene: Node
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-colour-priority-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "native scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	var building_id: String = scene.selected_building_id
	var window_id := ""
	var door_id := ""
	for value in scene.building_world.get_building(building_id).get("details", []):
		var detail: Dictionary = value
		if not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)): continue
		if str(detail.get("kind", "")) == "window" and window_id.is_empty(): window_id = str(detail["id"])
		if str(detail.get("kind", "")) == "door": door_id = str(detail["id"])
	check(not window_id.is_empty() and not door_id.is_empty(), "real window and door fixture")
	if window_id.is_empty() or door_id.is_empty():
		await _finish()
		return
	scene.selected_detail_id = window_id
	var original: String = scene.building_world.serialize_document()
	scene._begin_style_picker("colour")
	scene._preview_style_choice("colour", "berry")
	await _refresh()
	_check_colour(building_id, "Joinery_" + window_id, scene.DETAIL_COLOURS["berry"], "live preview survives full accent pass")
	check(scene.building_world.serialize_document() == original, "browsing is read-only")
	var labels := 0
	for child in scene._actions_box().get_children():
		if (child is Label or child is RichTextLabel) and child.visible: labels += 1
	check(labels == 1, "colour submenu has one heading, not legacy help paragraphs")
	check(scene._style_buttons["colour-natural"].text == "House colour" and scene._style_buttons.has("colour-wood"), "inheritance and explicit wood are distinct choices")
	scene._cancel_style_picker()
	await _refresh()
	check(scene.building_world.serialize_document() == original, "cancel leaves document unchanged")
	var accent_id: String = scene._accent_material_id(scene.building_world.get_building(building_id))
	_check_colour(building_id, "Joinery_" + window_id, scene.ACCENT_COLOURS[accent_id], "cancel restores inherited colour")
	var revision: int = scene.building_world.get_revision()
	scene._begin_style_picker("colour")
	scene._commit_style_choice("colour", "berry")
	await _refresh()
	check(scene.building_world.get_revision() == revision + 1, "one colour confirmation is one revision")
	_check_colour(building_id, "Joinery_" + window_id, scene.DETAIL_COLOURS["berry"], "committed colour survives normal update")
	check(scene.building_world.undo(), "colour undo")
	await _refresh()
	_check_colour(building_id, "Joinery_" + window_id, scene.ACCENT_COLOURS[accent_id], "undo restores inherited presentation")
	check(scene.building_world.redo(), "colour redo")
	await _refresh()
	_check_colour(building_id, "Joinery_" + window_id, scene.DETAIL_COLOURS["berry"], "redo restores explicit presentation")
	scene._open_accent_colour_picker()
	scene._preview_surface_material("ochre")
	_check_colour(building_id, "Joinery_" + window_id, scene.DETAIL_COLOURS["berry"], "house preview cannot override individual window")
	scene._commit_surface_material("ochre")
	await _refresh()
	_check_colour(building_id, "Joinery_" + window_id, scene.DETAIL_COLOURS["berry"], "house accent commit preserves individual colour")
	_check_colour(building_id, "DoorJoinery_" + door_id, scene.ACCENT_COLOURS["ochre"], "unmodified door still follows house colour")
	var saved: String = scene.building_world.serialize_document()
	check(scene.building_world.load_serialized_document(saved), "recolour save reloads")
	await _refresh()
	_check_colour(building_id, "Joinery_" + window_id, scene.DETAIL_COLOURS["berry"], "loaded explicit colour is visible")
	var duplicate_id: String = scene.building_world.duplicate_building(building_id, Vector3(10, 0, 0))
	check(not duplicate_id.is_empty(), "duplicate for unselected-house regression")
	scene.selected_building_id = duplicate_id
	await _refresh()
	_check_colour(building_id, "Joinery_" + window_id, scene.DETAIL_COLOURS["berry"], "unselected house keeps individual colours")
	scene.selected_building_id = building_id
	scene.selected_detail_id = door_id
	scene._begin_style_picker("colour")
	scene._commit_style_choice("colour", "wood")
	await _refresh()
	_check_colour(building_id, "DoorJoinery_" + door_id, scene.DETAIL_COLOURS["natural"], "explicit natural wood overrides house accent")
	scene._begin_style_picker("colour")
	scene._commit_style_choice("colour", "natural")
	await _refresh()
	_check_colour(building_id, "DoorJoinery_" + door_id, scene.ACCENT_COLOURS["ochre"], "House colour resets to inheritance")
	await _finish()

func _refresh() -> void:
	scene._presentation_key = ""
	scene._update_presentation()
	await process_frame

func _check_colour(building_id: String, name: String, expected: Color, label: String) -> void:
	var visual := scene.cottage_visuals.get(building_id) as Node3D
	var node := visual.get_node_or_null(name) as GeometryInstance3D if visual else null
	var material := node.material_override as StandardMaterial3D if node else null
	check(material != null and material.albedo_color.is_equal_approx(expected), label)

func _finish() -> void:
	if is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m2_colour_priority_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
