extends SceneTree

const Layout = preload("res://scripts/facade_depth_layout.gd")
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
	scene.checkpoint_root = "user://facade-depth-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "facade test scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	var view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var before: String = scene.building_world.serialize_document()
	var runs := Layout.wall_runs(view)
	check(runs.size() == 4, "single-section house exposes four facade runs")
	check(_orientations(runs).size() == 4, "single-section facade covers every cardinal wall")
	var visual := scene.cottage_visuals[scene.selected_building_id] as Node3D
	var detail_unit: Vector3 = visual.get("_detail_unit")
	var shell := Layout.shell_pieces(view, runs, detail_unit)
	check(not shell["plinth"].is_empty() and shell["eave"].size() == 4, "simple house receives plinth and four wall-top reveals")
	check(scene.building_world.serialize_document() == before, "layout inspection does not edit the building recipe")
	var segments := Layout.subtract_intervals(-5.0, 5.0, [Vector2(-1.0, 1.0), Vector2(3.0, 9.0)])
	check(segments == [Vector2(-5.0, -1.0), Vector2(1.0, 3.0)], "door openings split and clamp foundation facing")

	check(scene._apply_house_shape_preset("u_shape"), "U-house fixture uses normal shape API")
	view = scene.building_world.get_building(scene.selected_building_id)
	before = scene.building_world.serialize_document()
	runs = Layout.wall_runs(view)
	check(runs.size() > 4 and _planes(runs).size() > 4, "joined U-house retains outer and courtyard facade planes")
	var valid := true
	for run in runs: valid = valid and float(run["tangent_max"]) > float(run["tangent_min"]) and float(run["top"]) > float(run["bottom"])
	check(valid, "all joined facade runs have positive exposed area")
	check(scene.building_world.serialize_document() == before, "joined facade derivation is read-only")

	check(scene.building_world.load_serialized_document(before), "joined fixture reloads before floor edit")
	scene._presentation_key = ""
	scene._update_presentation()
	scene._begin_next_storey()
	check(scene.portion_valid and scene._commit_portion_placement(), "upper facade fixture uses actual add-floor API")
	view = scene.building_world.get_building(scene.selected_building_id)
	runs = Layout.wall_runs(view)
	var upper := 0
	for run in runs:
		if float(run["bottom"]) > 0.01: upper += 1
	check(upper >= 4, "upper storey contributes its own exposed facade runs")
	visual = scene.cottage_visuals[scene.selected_building_id] as Node3D
	detail_unit = visual.get("_detail_unit")
	shell = Layout.shell_pieces(view, runs, detail_unit)
	check(shell["eave"].size() == runs.size(), "every exposed wall run receives a roof-contact reveal")

	var fixture: String = scene.building_world.serialize_document()
	Layout.enabled = false
	scene._refresh_facade_depth(true)
	check(not visual.get_node_or_null("M2FacadeDepthMarker"), "facade finish can be disabled without rebuilding authoritative geometry")
	Layout.enabled = true
	scene._refresh_facade_depth(true)
	check(visual.get_node_or_null("M2FacadeDepthMarker") != null, "facade finish regenerates from the current recipe")
	check(_facade_instances(visual) > 0, "generated facade contains actual fine-grid relief instances")
	check(scene.building_world.serialize_document() == fixture, "facade generation changes no saved building records")
	await _finish()

func _orientations(runs: Array[Dictionary]) -> Dictionary:
	var result := {}
	for run in runs: result[str(run["orientation"])] = true
	return result

func _planes(runs: Array[Dictionary]) -> Dictionary:
	var result := {}
	for run in runs: result["%s|%.3f" % [str(run["orientation"]), float(run["normal"])]] = true
	return result

func _facade_instances(visual: Node3D) -> int:
	var total := 0
	for child in visual.get_children():
		if not str(child.name).begins_with("M2Facade") or not child is MultiMeshInstance3D: continue
		var multi: MultiMesh = (child as MultiMeshInstance3D).multimesh
		if multi: total += multi.instance_count
	return total

func _finish() -> void:
	Layout.enabled = true
	if is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("facade_depth_layout_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)