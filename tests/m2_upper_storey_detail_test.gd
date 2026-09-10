extends SceneTree

const Massing = preload("res://scripts/m2_house_massing.gd")
const WallPlacement = preload("res://scripts/wall_attachment_placement.gd")
const M2World = preload("res://scripts/m2_building_world.gd")
const JoinedVisual = preload("res://scripts/m2_house_massing_visual.gd")

var scene: Node
var checks := 0
var failures := 0
var geometry_checks := 0
var unverified_headless_openings := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var rendered := DisplayServer.get_name() != "headless"
	if "--require-rendering" in OS.get_cmdline_user_args():
		check(rendered and RenderingServer.get_current_rendering_method() == "mobile", "actual Mobile renderer is required for opening geometry")
		if failures:
			await _finish()
			return
	if rendered: root.size = Vector2i(1280, 720)
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-upper-detail-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline: int = Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "upper-storey detail scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	await process_frame

	var base_view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var storey: float = Massing.storey_height(base_view)
	scene._begin_next_storey()
	await process_frame
	check(scene.portion_valid and scene.portion_level == 1, "floor 2 preview starts supported")
	check(scene._commit_portion_placement(), "floor 2 commits with facade surfaces in the same transaction")
	await process_frame

	var view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var upper_walls: Array[Dictionary] = []
	for surface_value in view.get("surfaces", []):
		var support: Dictionary = surface_value
		if bool(support.get("massing_wall", false)) and int(support.get("massing_level", -1)) == 1 and not bool(support.get("deleted", false)):
			upper_walls.append(support)
	check(upper_walls.size() >= 4, "floor 2 exposes merged selectable wall runs")
	var upper_front: Dictionary = {}
	var best_span := -1.0
	for support in upper_walls:
		if str(support.get("orientation", "")) != "front": continue
		var span: float = float(support.get("tangent_max", 0.0)) - float(support.get("tangent_min", 0.0))
		if span > best_span:
			best_span = span
			upper_front = support
	check(not upper_front.is_empty(), "floor 2 has a selectable front facade")
	if upper_front.is_empty():
		await _finish()
		return
	var upper_id: String = str(upper_front.get("id", ""))
	check(upper_id in WallPlacement.wall_ids(view), "existing attachment wall cycle includes floor 2")
	check(WallPlacement.surface_label(view, upper_id).begins_with("Floor 2"), "controller support label identifies the storey")

	# A manual window may replace an automatic one without decreasing the total
	# wall instance count. Exercise that real player path before isolating a
	# genuinely new opening on a wall with its generated windows suppressed.
	await _check_automatic_replacement(view, upper_id)
	view = scene.building_world.get_building(scene.selected_building_id)
	var suppressed := 0
	for value in view.get("details", []):
		var generated: Dictionary = value
		if str(generated.get("state", "")) != "automatic" or str(generated.get("kind", "")) != "window": continue
		if str((generated.get("anchor", {}) as Dictionary).get("surface_id", "")) != upper_id: continue
		check(scene.building_world.suppress_detail(scene.selected_building_id, str(generated["id"])), "generated upstairs window can be suppressed for the fresh-cut fixture")
		suppressed += 1
	check(suppressed > 0, "fresh-cut fixture starts with generated upstairs windows, not a legacy bare floor")
	await _refresh_visual()
	view = scene.building_world.get_building(scene.selected_building_id)

	var geometry: Dictionary = WallPlacement.wall_geometry(view, upper_front)
	var intended := Vector3((float(geometry["tangent_min"]) + float(geometry["tangent_max"])) * 0.5, (float(geometry["bottom"]) + float(geometry["top"])) * 0.5, float(geometry["normal"]))
	var half: Vector2 = WallPlacement.footprint("window", "window_wood")
	var placement: Dictionary = WallPlacement.nearest_available(view, "", upper_id, intended, half)
	check(not placement.is_empty(), "normal window placement fits the generated upstairs facade")
	var placed_position: Vector3 = placement.get("position", Vector3.ZERO)
	check(placed_position.y > storey, "upstairs placement resolves above the first storey")

	var joined: Node3D = _joined_visual()
	var wall_before := _wall_instance_count(joined, "JoinedWall_Front")
	check(wall_before > 0, "fresh-cut fixture contains a front-wall batch")
	_check_opening(joined, placed_position, false, "fresh-cut fixture has real wall geometry behind the intended window")
	var window_id: String = scene.building_world.add_detail(scene.selected_building_id, "window", upper_id, placed_position, "window_wood")
	check(not window_id.is_empty(), "BuildingWorld accepts a real manual window on floor 2")
	scene.selected_detail_id = window_id
	scene.selected_surface_id = upper_id
	await _refresh_visual()
	view = scene.building_world.get_building(scene.selected_building_id)
	var window: Dictionary = _detail(view, window_id)
	check(not window.is_empty() and not bool(window.get("needs_placement", true)), "floor-2 window remains valid after authoritative resolution")
	var resolved: Vector3 = window.get("resolved_position", Vector3.ZERO)
	check(resolved.y > storey and str((window.get("anchor", {}) as Dictionary).get("surface_id", "")) == upper_id, "saved anchor retains its upper-storey surface and height")
	joined = _joined_visual()
	var wall_after := _wall_instance_count(joined, "JoinedWall_Front")
	check(wall_after < wall_before, "joined wall mesh recuts immediately for the upstairs window opening")
	_check_opening(joined, resolved, true, "no rendered front-wall boxes intersect the new upstairs opening")

	check(scene.building_world.undo(), "manual upstairs opening is undoable")
	await _refresh_visual()
	check(_wall_instance_count(_joined_visual(), "JoinedWall_Front") == wall_before, "undo restores the original wall instance count")
	_check_opening(_joined_visual(), placed_position, false, "undo restores solid wall geometry at the removed opening")
	check(scene.building_world.redo(), "manual upstairs opening is redoable")
	await _refresh_visual()
	check(_wall_instance_count(_joined_visual(), "JoinedWall_Front") == wall_after, "redo restores the cut wall instance count")
	_check_opening(_joined_visual(), resolved, true, "redo recuts the same upstairs opening")
	scene.selected_detail_id = window_id
	scene.selected_surface_id = upper_id

	scene._open_window_extras()
	check(scene._window_extras_open, "existing Window extras menu opens for an upstairs window")
	scene._window_extras_preview["shutter_style"] = "louvered"
	scene._window_extras_preview["shutter_state"] = "half_open"
	scene._window_extras_preview["flower_box"] = "bracketed"
	check(scene._commit_window_extras(), "upstairs window accepts normal shutter and flower-box customization")
	await process_frame
	view = scene.building_world.get_building(scene.selected_building_id)
	window = _detail(view, window_id)
	var extras: Dictionary = (window.get("override", {}) as Dictionary).get("window_extras", {})
	check(str(extras.get("shutter_style", "")) == "louvered" and str(extras.get("shutter_state", "")) == "half_open" and str(extras.get("flower_box", "")) == "bracketed", "upstairs window stores combinatorial extras normally")

	var serialized: String = scene.building_world.serialize_document()
	var restored = M2World.new()
	check(restored.load_serialized_document(serialized), "upper-storey facade document reloads")
	var restored_view: Dictionary = restored.get_building(scene.selected_building_id)
	var restored_window: Dictionary = _detail(restored_view, window_id)
	check(not restored_window.is_empty() and not bool(restored_window.get("needs_placement", true)) and (restored_window.get("resolved_position", Vector3.ZERO) as Vector3).y > storey, "reload preserves a usable floor-2 window")
	var rebuilt := JoinedVisual.new()
	root.add_child(rebuilt)
	rebuilt.show_view(restored_view, Color.WHITE, [Color.WHITE], Color.WHITE)
	check(_wall_instance_count(rebuilt, "JoinedWall_Front") == wall_after, "reload regenerates the same wall instance count")
	if rendered: await RenderingServer.frame_post_draw
	_check_opening(rebuilt, resolved, true, "reload regenerates the same open wall geometry, not only the saved detail record")
	rebuilt.free()

	# Removing the supporting storey must not silently eat authored facade decor.
	check(scene._remove_last_portion(), "floor 2 can be removed after decorating it")
	await process_frame
	view = scene.building_world.get_building(scene.selected_building_id)
	window = _detail(view, window_id)
	var retired_surface: Dictionary = WallPlacement.surface(view, upper_id)
	check(not retired_surface.is_empty() and bool(retired_surface.get("deleted", false)), "removed upstairs wall keeps its stable ID as deleted recovery support")
	check(bool(window.get("needs_placement", false)), "window on a removed floor enters Needs placement instead of disappearing")
	check(scene.building_world.undo(), "removing the decorated floor is undoable")
	view = scene.building_world.get_building(scene.selected_building_id)
	window = _detail(view, window_id)
	check(not bool(window.get("needs_placement", true)) and str((window.get("anchor", {}) as Dictionary).get("surface_id", "")) == upper_id, "undo restores the same upper wall identity and window")

	await _finish()

func _check_automatic_replacement(view: Dictionary, upper_id: String) -> void:
	var automatic: Dictionary = {}
	for value in view.get("details", []):
		var detail: Dictionary = value
		if str(detail.get("state", "")) != "automatic" or str(detail.get("kind", "")) != "window": continue
		if not bool(detail.get("visible", false)) or bool(detail.get("needs_placement", true)): continue
		if str((detail.get("anchor", {}) as Dictionary).get("surface_id", "")) == upper_id:
			automatic = detail
			break
	check(not automatic.is_empty(), "new floor has an active automatic front window to replace")
	if automatic.is_empty(): return
	var position: Vector3 = automatic["resolved_position"]
	var manual_id: String = scene.building_world.add_detail(scene.selected_building_id, "window", upper_id, position, "window_wood")
	check(not manual_id.is_empty(), "manual upstairs window may occupy an automatic window's position")
	if manual_id.is_empty(): return
	await _refresh_visual()
	var replaced_view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var manual: Dictionary = _detail(replaced_view, manual_id)
	var displaced: Dictionary = _detail(replaced_view, str(automatic["id"]))
	check(bool(manual.get("visible", false)) and not bool(manual.get("needs_placement", true)) and not bool(displaced.get("visible", true)), "manual window wins while the overlapping automatic window yields")
	_check_opening(_joined_visual(), position, true, "replacement opening remains clear even when total wall count does not decrease")
	check(scene.building_world.undo(), "automatic-to-manual replacement is one undoable edit")
	await _refresh_visual()
	var undone: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	check(undone.get("details", []) == view.get("details", []), "undo exactly restores all automatic window records and visibility")

func _refresh_visual() -> void:
	scene._presentation_key = ""
	scene._update_presentation()
	await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func _joined_visual() -> Node3D:
	var visual := scene.cottage_visuals.get(scene.selected_building_id, null) as Node3D
	return visual.get_node_or_null("M2JoinedMassing") as Node3D if visual else null

func _check_opening(joined: Node3D, center: Vector3, expect_clear: bool, label: String) -> void:
	# Godot's dummy rendering backend does not retain per-instance transforms.
	# Authority and instance counts still run headlessly; the same test must
	# also pass in Mobile CI with every geometry assertion actually executed.
	if DisplayServer.get_name() == "headless":
		unverified_headless_openings += 1
		return
	geometry_checks += 1
	var blockers := _opening_blockers(joined, center)
	check(blockers == 0 if expect_clear else blockers > 0, label + " (blockers=%d)" % blockers)

func _opening_blockers(joined: Node3D, center: Vector3) -> int:
	# Inspect actual rendered box extents, independently of the generator's
	# _opening_at predicate. An absent mesh is an error, not an empty opening.
	if not joined: return -1
	var wall := joined.get_node_or_null("JoinedWall_Front") as MultiMeshInstance3D
	if not wall or not wall.multimesh: return -1
	var half_opening := Vector3(0.95, 1.35, 0.025)
	var blockers := 0
	for index in wall.multimesh.instance_count:
		var cell: Transform3D = wall.multimesh.get_instance_transform(index)
		var half_cell: Vector3 = cell.basis.get_scale() * 0.5
		var delta: Vector3 = (cell.origin - center).abs()
		if delta.x < half_cell.x + half_opening.x and delta.y < half_cell.y + half_opening.y and delta.z < half_cell.z + half_opening.z:
			blockers += 1
	return blockers

func _wall_instance_count(joined: Node3D, node_name: String) -> int:
	if not joined: return 0
	var wall := joined.get_node_or_null(node_name) as MultiMeshInstance3D
	return wall.multimesh.instance_count if wall and wall.multimesh else 0

func _detail(view: Dictionary, detail_id: String) -> Dictionary:
	for value in view.get("details", []):
		var detail: Dictionary = value
		if str(detail.get("id", "")) == detail_id: return detail
	return {}

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("UPPER_STOREY_GEOMETRY checked=%d unverified=%d" % [geometry_checks, unverified_headless_openings])
	print("m2_upper_storey_detail_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
