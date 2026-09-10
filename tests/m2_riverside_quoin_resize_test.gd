extends SceneTree

var scene: Node
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-riverside-quoin-resize-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline: int = Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene._player_restored, "native Riverside quoin resize scene ready")
	if not scene._player_restored:
		_finish()
		return
	scene.set_process(false)

	var building_id: String = str(scene.selected_building_id)
	var original: Dictionary = scene.building_world.get_building(building_id)
	var original_dimensions: Vector3 = original.get("dimensions", Vector3.ZERO)
	_check(original.get("style_id", "") == "riverside_cottage" and is_equal_approx(original_dimensions.y, 7.0), "fixture starts from the standard seven-unit Riverside Cottage")

	scene._refresh_raised_foundation_masonry(true)
	_check(not scene._raised_quoin_roots.has(building_id), "standard-height Riverside Cottage keeps its authored three quoin levels only")

	var taller: Vector3 = original_dimensions
	taller.y = 8.0
	_check(scene.building_world.resize(building_id, taller), "Riverside Cottage can be resized one unit taller")
	scene._refresh_raised_foundation_masonry(true)
	_check(scene._raised_quoin_roots.has(building_id), "raising the wall adds a quoin extension root")
	var one_level_count: int = _extra_quoin_instance_count(building_id)
	_check(one_level_count == 4, "first taller step adds one new corner stone at each of four corners")

	var tallest: Vector3 = taller
	tallest.y = 10.0
	_check(scene.building_world.resize(building_id, tallest), "Riverside Cottage can continue growing vertically")
	scene._refresh_raised_foundation_masonry(true)
	var two_level_count: int = _extra_quoin_instance_count(building_id)
	_check(two_level_count == 8, "additional height continues the quoin rhythm with a second four-corner level")

	_check(scene.building_world.resize(building_id, original_dimensions), "Riverside Cottage can return to its authored height")
	scene._refresh_raised_foundation_masonry(true)
	_check(not scene._raised_quoin_roots.has(building_id), "returning to standard height removes only the generated extension courses")
	_finish()

func _extra_quoin_instance_count(building_id: String) -> int:
	var root_node: Node = scene._raised_quoin_roots.get(building_id)
	if not is_instance_valid(root_node): return 0
	var courses: MultiMeshInstance3D = root_node.get_node_or_null("ExtraQuoinCourses") as MultiMeshInstance3D
	if not courses or not courses.multimesh: return 0
	return courses.multimesh.instance_count

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
