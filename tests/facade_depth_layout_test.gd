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
	var first_plinth: Dictionary = shell["plinth"][0]
	check(is_equal_approx((first_plinth["size"] as Vector3).y, detail_unit.y * 2.0), "plinth is the tuned two-detail-cell height")
	check(scene.building_world.serialize_document() == before, "layout inspection does not edit the building recipe")
	var segments := Layout.subtract_intervals(-5.0, 5.0, [Vector2(-1.0, 1.0), Vector2(3.0, 9.0)])
	check(segments == [Vector2(-5.0, -1.0), Vector2(1.0, 3.0)], "door openings split and clamp foundation facing")

	var base_bricks: Array = scene._brick_corner_pieces(view, runs, detail_unit)
	check(base_bricks.size() == 16, "default riverside cottage has four fine brick courses on four corners")
	var fine_bricks := true
	for piece_value in base_bricks:
		var piece: Dictionary = piece_value
		var size: Vector3 = piece["size"]
		fine_bricks = fine_bricks and size.y <= detail_unit.y * 2.01 and size.x <= detail_unit.x * 3.01 and size.z <= detail_unit.z * 3.01
	check(fine_bricks, "brick accents stay on the 0.0625 decorative-cell tier")
	var nonbrick_view: Dictionary = view.duplicate(true)
	nonbrick_view["style_id"] = "woodland_lodge"
	check((scene._brick_corner_pieces(nonbrick_view, runs, detail_unit) as Array).is_empty(), "log house receives no brick corner accents")
	nonbrick_view["style_id"] = "village_gable"
	check((scene._brick_corner_pieces(nonbrick_view, runs, detail_unit) as Array).is_empty(), "village gable receives no brick corner accents")
	var tall_view: Dictionary = view.duplicate(true)
	var tall_dimensions: Vector3 = tall_view["dimensions"]
	tall_dimensions.y += 3.0
	tall_view["dimensions"] = tall_dimensions
	var tall_runs := Layout.wall_runs(tall_view)
	check((scene._brick_corner_pieces(tall_view, tall_runs, detail_unit) as Array).size() > base_bricks.size(), "taller riverside walls extend the brick rhythm upward")
	var legacy_quoins := visual.get_node_or_null("CornerQuoins") as Node3D
	check(not legacy_quoins or not legacy_quoins.visible, "fine facade bricks replace the old coarse rectangle-only quoins")
	var legacy_foundation_courses := visual.get_node_or_null("FoundationCourses") as Node3D
	var facade_plinth := visual.get_node_or_null("M2FacadePlinth") as Node3D
	check(facade_plinth != null and (legacy_foundation_courses == null or not legacy_foundation_courses.visible), "fine facade plinth replaces overlapping legacy foundation courses")

	check(scene._apply_house_shape_preset("u_shape"), "U-house fixture uses normal shape API")
	view = scene.building_world.get_building(scene.selected_building_id)
	before = scene.building_world.serialize_document()
	runs = Layout.wall_runs(view)
	check(runs.size() > 4 and _planes(runs).size() > 4, "joined U-house retains outer and courtyard facade planes")
	var valid := true
	for run in runs: valid = valid and float(run["tangent_max"]) > float(run["tangent_min"]) and float(run["top"]) > float(run["bottom"])
	check(valid, "all joined facade runs have positive exposed area")
	var u_bricks: Array = scene._brick_corner_pieces(view, runs, detail_unit)
	check(u_bricks.size() > base_bricks.size(), "U-house brick style covers its additional exposed corners")
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
	var upper_bricks: Array = scene._brick_corner_pieces(view, runs, detail_unit)
	check(upper_bricks.size() > u_bricks.size(), "upper-floor exposed corners continue or begin sensible brick courses")

	var fixture: String = scene.building_world.serialize_document()
	Layout.enabled = false
	scene._refresh_facade_depth(true)
	check(not visual.get_node_or_null("M2FacadeDepthMarker"), "facade finish can be disabled without rebuilding authoritative geometry")
	legacy_foundation_courses = visual.get_node_or_null("FoundationCourses") as Node3D
	check(legacy_foundation_courses == null or legacy_foundation_courses.visible, "disabling facade finish restores legacy foundation courses")
	Layout.enabled = true
	scene._refresh_facade_depth(true)
	check(visual.get_node_or_null("M2FacadeDepthMarker") != null, "facade finish regenerates from the current recipe")
	legacy_foundation_courses = visual.get_node_or_null("FoundationCourses") as Node3D
	check(legacy_foundation_courses == null or not legacy_foundation_courses.visible, "regenerated facade plinth keeps legacy foundation courses hidden")
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
