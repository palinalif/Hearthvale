extends SceneTree

const Excavation = preload("res://scripts/m2_path_terrain_excavation.gd")

var checks := 0
var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-path-plaza-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene._player_restored, "native plaza scene ready")
	if not scene._player_restored:
		_finish()
		return
	scene.set_process(false)

	# Use a compact 9x9 structural-grid fixture well away from the default home.
	# Nine cells are wide enough to contain edge, one-voxel shoulder and two-voxel
	# centre rings in the distance-field profile.
	var plaza_cells: Array = []
	for z in range(64, 73):
		for x in range(64, 73): plaza_cells.append(Vector2i(x, z))
	_check(not scene._cells_hit_home_interior(plaza_cells), "broad plaza fixture avoids home interiors")

	var before_document: Dictionary = scene.landscape_state.document()
	var before_ownership: int = scene.path_terrain_ownership_count()
	var before_packed: Array = scene.landscape_state.path_cells("packed_earth")
	var plan: Dictionary = Excavation.plan_packed_earth_transition(scene.backend, before_packed, before_packed + plaza_cells, scene._path_terrain_ownership)
	_check(bool(plan.ok), "broad plaza transition plans against the real terrain backend")

	var centre := Vector2i(68, 68)
	var centre_removals: Array = []
	for item: Dictionary in plan.removals:
		var position: Vector3i = item.position
		if position.x == centre.x and position.z == centre.y:
			centre_removals.append(item)
	_check(centre_removals.size() == 2, "broad plaza plans exactly two native removals at its centre")
	if centre_removals.size() != 2:
		_finish()
		return

	var originals: Array = []
	for item: Dictionary in centre_removals:
		originals.append({"position": item.position, "material": int(item.before)})

	scene.path_style_id = "packed_earth"
	scene.path_width = 1.5
	scene._begin_path_placement()
	scene._reset_path_baseline()
	scene.path_painting = true
	scene.path_cells = plaza_cells.duplicate()
	_check(scene._commit_path_stroke(), "broad plaza commits through normal path transaction")
	_check(scene.path_terrain_ownership_count() > before_ownership, "broad plaza acquires native terrain ownership")

	var cut_ok := true
	for entry: Dictionary in originals:
		cut_ok = cut_ok and scene.backend.voxel_at(entry.position) == 0
	_check(cut_ok, "broad plaza centre is physically lowered by two native voxels")

	var profile: Dictionary = scene.path_visual.stats().get("packed_earth", {}).get("profile_depth_steps", {})
	_check(int(profile.get(2, profile.get("2", 0))) > 0, "committed broad plaza renderer sees depth-two centre cells")

	scene._undo()
	var restore_ok := true
	for entry: Dictionary in originals:
		restore_ok = restore_ok and scene.backend.voxel_at(entry.position) == int(entry.material)
	_check(restore_ok, "undo restores both native voxels removed by the plaza")
	_check(scene.landscape_state.document() == before_document, "undo restores pre-plaza painted authority")
	_check(scene.path_terrain_ownership_count() == before_ownership, "undo restores pre-plaza terrain ownership")

	_finish()

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
