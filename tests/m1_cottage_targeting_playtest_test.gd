extends SceneTree
## Expectations are specified from authored wall coordinates, not from the
## picker's own facing predicate. Exercise the actual exported scene.
var scene: Node
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)

func _run() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://cottage-targeting-playtest-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene.backend != null and scene.backend.is_ready() and scene._player_restored, "backend ready")
	if not scene._player_restored:
		_finish(); return
	scene.set_process(false)
	scene._set_view_context("building", "targeting regression")
	var first_id: String = scene.selected_building_id
	var view: Dictionary = scene.building_world.get_building(first_id)
	var dims: Vector3 = view["dimensions"]
	# All four sides, including a rotated miniature in the second half.
	for side in ["left", "right"]:
		var x := (-1.0 if side == "left" else 1.0) * (dims.x * 0.5 + 0.02)
		var id: String = scene.building_world.add_detail(first_id, "flower_box", "wall-" + side, Vector3(x, 2.0, 0.0), "flower_box_wood")
		check(not id.is_empty(), "side attachment fixture created")
	scene._update_presentation()
	_test_sides(first_id)

	check(scene._pointer_label.text.is_empty() and scene._pointer_label.get_child_count() == 4, "reticle draws geometry instead of a missing Unicode glyph")
	scene._update_cursor_reticle()
	check(not scene.cursor_reticle.visible, "terrain reticle hidden in cottage context")

	var copy_id: String = scene.building_world.duplicate_building(first_id, Vector3(10, 0, 10))
	check(not copy_id.is_empty(), "second cottage fixture created")
	scene.selected_building_id = copy_id
	scene._update_presentation()
	_test_sides(copy_id)
	var copy_view: Dictionary = scene.building_world.get_building(copy_id)
	var front := _detail_on(copy_view, "front")
	_point_camera(copy_view, Vector3.FORWARD)
	var transform: Transform3D = copy_view["transform"]
	var p: Vector3 = transform * (front["resolved_position"] as Vector3)
	scene.edit_pointer = scene.camera.unproject_position(p)
	scene._update_detail_hover()
	scene._update_direct_edit_hud()
	check(scene.hovered_detail_id == str(front["id"]), "hover picks selected cottage window")
	check(scene._hover_outline.visible and scene._hover_prompt.visible, "hover outline and attached action prompt visible")
	check(scene._hover_prompt.text.contains("X Options") and scene._hover_prompt.text.contains("A Move"), "attached prompt teaches both direct and contextual actions")
	check(scene._begin_hovered_detail_move(), "hover A starts movement")
	scene._cancel_detail_move()
	scene._update_detail_hover()
	check(scene._open_hovered_detail_actions(), "hover X opens contextual actions")
	for button in scene._visible_action_buttons():
		check(button.visible and not button.disabled, "controller only visits visible enabled actions")
	scene._context_actions_open = false
	scene.tools_open = false
	scene.tools_panel.visible = false
	# Stale hover cannot carry an A-cottage detail into B-cottage editing.
	var first_front := _detail_on(scene.building_world.get_building(first_id), "front")
	scene.hovered_detail_id = str(first_front["id"])
	scene._hovered_building_id = first_id
	check(not scene._select_hovered_detail(), "old cottage hover rejected after selection changes")
	# Explicit non-identity rotation: independent world-space wall expectations.
	var document: Dictionary = scene.building_world.get_document()
	for b in document["buildings"]:
		if str(b["id"]) == copy_id: b["transform"]["rotation"] = [0.0, 0.63, 0.0]
	check(scene.building_world.load_document(document), "rotated fixture valid")
	scene._update_presentation()
	_test_sides(copy_id)
	_finish()

func _detail_on(view: Dictionary, side: String) -> Dictionary:
	var surface_id := ""
	for surface in view.get("surfaces", []):
		if str(surface.get("orientation", "")) == side and str(surface.get("kind", "")) == "wall": surface_id = str(surface["id"])
	for detail in view.get("details", []):
		if str(detail["anchor"]["surface_id"]) == surface_id and bool(detail.get("visible", false)) and not bool(detail.get("needs_placement", false)): return detail
	return {}

func _point_camera(view: Dictionary, outward: Vector3) -> void:
	var transform: Transform3D = view["transform"]
	var dims: Vector3 = view["dimensions"]
	var target := transform * Vector3(0, dims.y * 0.48, 0)
	var direction := (transform.basis * outward).normalized()
	scene.camera.global_position = target + direction * 12.0
	scene.camera.look_at(target, Vector3.UP)

func _test_sides(building_id: String) -> void:
	var view: Dictionary = scene.building_world.get_building(building_id)
	var transform: Transform3D = view["transform"]
	var sides := {"front": Vector3.FORWARD, "back": Vector3.BACK, "left": Vector3.LEFT, "right": Vector3.RIGHT}
	var opposite := {"front": "back", "back": "front", "left": "right", "right": "left"}
	for side in sides:
		var detail := _detail_on(view, side)
		check(not detail.is_empty(), "visible fixture on " + side)
		if detail.is_empty(): continue
		_point_camera(view, sides[side])
		var point: Vector3 = transform * (detail["resolved_position"] as Vector3)
		var hit: Dictionary = scene._pick_detail_at_screen_position(scene.camera.unproject_position(point))
		check(str(hit.get("id", "")) == str(detail["id"]) and str(hit.get("building_id", "")) == building_id, "visible selected wall detail picked: " + side)
		var rear := _detail_on(view, opposite[side])
		if not rear.is_empty():
			var rear_point: Vector3 = transform * (rear["resolved_position"] as Vector3)
			var rear_hit: Dictionary = scene._pick_detail_at_screen_position(scene.camera.unproject_position(rear_point))
			check(str(rear_hit.get("id", "")) != str(rear["id"]), "opposite wall cannot be picked through cottage: " + side)

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m1_cottage_targeting_playtest_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
