extends SceneTree

var checks := 0
var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-terrain-house-outline-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "terrain outline scene ready")
	if not scene._player_restored:
		await finish()
		return
	scene.set_process(false)
	var building_id: String = scene.selected_building_id
	var visual: Node3D = scene.cottage_visuals.get(building_id, null) as Node3D
	check(visual != null, "selected cottage visual exists")
	if not visual:
		await finish()
		return

	scene._set_view_context("terrain", "test")
	scene._set_world_mesh_highlight(building_id)
	check(is_equal_approx(highlight_grow(visual), 0.24), "terrain hover uses thicker house outline")

	scene._set_world_mesh_highlight("")
	visual.set_building_highlight(true)
	check(is_equal_approx(highlight_grow(visual), 0.12), "normal building highlight remains at established thickness after terrain hover")
	visual.set_building_highlight(false)

	scene._set_view_context("building", "test")
	visual.set_building_highlight(true)
	check(is_equal_approx(highlight_grow(visual), 0.12), "building mode highlight remains unchanged")
	visual.set_building_highlight(false)
	await finish()

func highlight_grow(visual: Node3D) -> float:
	for child in visual.get_children():
		if not child is GeometryInstance3D: continue
		var overlay: Material = (child as GeometryInstance3D).material_overlay
		if overlay is StandardMaterial3D:
			return (overlay as StandardMaterial3D).grow_amount
	return -1.0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print("m2_terrain_house_outline_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
