extends SceneTree

const Massing = preload("res://scripts/m2_house_massing.gd")
const WallPlacement = preload("res://scripts/wall_attachment_placement.gd")
const M2World = preload("res://scripts/m2_building_world.gd")

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
	var upper_id: String = str(upper_front.get("id", ""))
	check(upper_id in WallPlacement.wall_ids(view), "existing attachment wall cycle includes floor 2")
	check(WallPlacement.surface_label(view, upper_id).begins_with("Floor 2"), "controller support label identifies the storey")

	var geometry: Dictionary = WallPlacement.wall_geometry(view, upper_front)
	var intended := Vector3((float(geometry["tangent_min"]) + float(geometry["tangent_max"])) * 0.5, (float(geometry["bottom"]) + float(geometry["top"])) * 0.5, float(geometry["normal"]))
	var half: Vector2 = WallPlacement.footprint("window", "window_wood")
	var placement: Dictionary = WallPlacement.nearest_available(view, "", upper_id, intended, half)
	check(not placement.is_empty(), "normal window placement fits the generated upstairs facade")
	var placed_position: Vector3 = placement.get("position", Vector3.ZERO)
	check(placed_position.y > storey, "upstairs placement resolves above the first storey")

	var visual: Node3D = scene.cottage_visuals.get(scene.selected_building_id, null) as Node3D
	var joined: Node3D = visual.get_node_or_null("M2JoinedMassing") as Node3D if visual else null
	var wall_before := _wall_instance_count(joined, "JoinedWall_Front")
	var window_id: String = scene.building_world.add_detail(scene.selected_building_id, "window", upper_id, placed_position, "window_wood")
	check(not window_id.is_empty(), "BuildingWorld accepts a real manual window on floor 2")
	scene.selected_detail_id = window_id
	scene.selected_surface_id = upper_id
	scene._presentation_key = ""
	scene._update_presentation()
	await process_frame
	view = scene.building_world.get_building(scene.selected_building_id)
	var window: Dictionary = _detail(view, window_id)
	check(not window.is_empty() and not bool(window.get("needs_placement", true)), "floor-2 window remains valid after authoritative resolution")
	var resolved: Vector3 = window.get("resolved_position", Vector3.ZERO)
	check(resolved.y > storey and str((window.get("anchor", {}) as Dictionary).get("surface_id", "")) == upper_id, "saved anchor retains its upper-storey surface and height")
	joined = visual.get_node_or_null("M2JoinedMassing") as Node3D if visual else null
	var wall_after := _wall_instance_count(joined, "JoinedWall_Front")
	check(wall_after < wall_before, "joined wall mesh recuts immediately for the upstairs window opening")

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
	print("m2_upper_storey_detail_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
