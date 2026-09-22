extends SceneTree

const Generator = preload("res://scripts/m1_patch_generator.gd")
const SceneScript = preload("res://scripts/m2_scene_starter_valley.gd")

var failures: Array[String] = []
var scene: Node
var check_count := 0

func check(ok: bool, message: String) -> void:
	check_count += 1
	if not ok:
		failures.append(message)
		printerr("CHECK FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	_clear_dir("user://m2_scene_test")
	DirAccess.make_dir_recursive_absolute("user://m2_scene_test")
	scene = SceneScript.new()
	scene.test_mode = true
	scene.starter_hamlet_in_tests = true
	scene.checkpoint_root = "user://m2_scene_test/valley"
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 60000
	while scene.backend == null or not scene.backend.is_ready():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			failures.append("backend did not become ready in time")
			print("M2_STARTER_SCENE_RESULT " + JSON.stringify({"ok": false, "checks": check_count, "failures": failures}))
			quit(1)
			return
	check(scene._valley_surround != null, "valley surround is mounted")
	check(scene._valley_surround.stats()["peak_height"] == 56.0, "valley surround peak height is the 56 m ring")
	check(scene.river_water != null, "river water is mounted")
	check(
		is_equal_approx(scene.landscape_state.bridges.size(), 1)
		and (scene.landscape_state.bridges[0]["points"] as Array).size() >= 2,
		"one starter bridge across the river"
	)
	var document: Dictionary = scene.building_world.get_document()
	var buildings: Array = document.get("buildings", [])
	check(buildings.size() == 3, "three starter buildings (got %d)" % buildings.size())
	check(scene._starter_seeded, "starter hamlet seeded for the new world")
	_check_flat_hamlet()
	_check_home_anchor_support(buildings)
	check(_check_library(), "terrain library has the full 10-model ground set")
	_check_material_round_trip()
	scene._shutting_down = true
	scene._save_all()
	scene.queue_free()
	check(failures.is_empty(), "all checks passed")
	print("M2_STARTER_SCENE_RESULT " + JSON.stringify({"ok": failures.is_empty(), "checks": check_count, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

## The hamlet plateau is the farm's flat ground: every column inside the
## hamlet rectangle must sit at exactly the 8 m level.
func _check_flat_hamlet() -> void:
	var flat := true
	for x in range(13, 32, 2):
		for z in range(11, 26, 2):
			if absf(Generator.terrain_height(float(x), float(z)) - 8.0) > 0.001:
				flat = false
	check(flat, "hamlet plateau is flat at 8 m")

## Every home anchor (building origin) stands on solid ground: the voxel
## column under each anchor must contain material within two meters down.
func _check_home_anchor_support(buildings: Array) -> void:
	for building in buildings:
		var transform: Dictionary = building.get("transform", {})
		var data: Array = transform.get("position", [0.0, 0.0, 0.0])
		var anchor := Vector3(float(data[0]), float(data[1]), float(data[2]))
		var supported := false
		var tool: Object = scene.backend.terrain.get_voxel_tool()
		for y in range(64, -1, -1):
			if int(tool.get_voxel(Vector3i(int(anchor.x * 8.0), y, int(anchor.z * 8.0)))) != 0:
				var world_y := (y + 1) * 0.125
				if anchor.y - world_y <= 2.0 and anchor.y - world_y >= -0.5:
					supported = true
				break
		check(supported, "home anchor at (%.1f, %.1f, %.1f) stands on solid ground" % [anchor.x, anchor.y, anchor.z])

func _check_library() -> bool:
	var mesher: Object = scene.backend.terrain.mesher
	var library: Object = mesher.get("library")
	return library != null and library.get_models().size() == 10

## Paint two hamlet cells dirt via the native voxel tool (net height
## unchanged), then prove the material survives a save/load round trip
## through the 8-bit checkpoint channel.
func _check_material_round_trip() -> void:
	var tool: Object = scene.backend.terrain.get_voxel_tool()
	var center := Vector3(20.0, 8.0, 18.0)
	var top := _top_voxel(tool, center)
	check(top >= 0, "painted column has a surface")
	# Paint the top two cells of the column dirt: a 1x2x1 buffer on the tool
	# (VoxelBuffer.set_voxel takes value, x, y, z, channel) plus the same cells
	# on the checkpoint buffer, which is the authoritative save source.
	var x := int(center.x * 8.0)
	var z := int(center.z * 8.0)
	var buffer: Object = ClassDB.instantiate("VoxelBuffer")
	buffer.create(1, 2, 1)
	buffer.set_voxel(3, 0, 0, 0, 0)
	buffer.set_voxel(3, 0, 1, 0, 0)
	tool.paste(Vector3i(x, top - 1, z), buffer, 1)
	var store: Object = scene.backend.voxels
	store.set_voxel(3, x, top - 1, z, 0)
	store.set_voxel(3, x, top, z, 0)
	check(int(tool.get_voxel(Vector3i(x, top, z))) == 3, "painted cell is dirt (3)")
	check(absf((top + 1) * 0.125 - 8.0) < 0.001, "hamlet stays flat after the paint")
	check(scene._save_all(), "scene saves after the paint")
	check(scene._reload_all(), "scene reloads after the paint")
	check(int(tool.get_voxel(Vector3i(x, top, z))) == 3, "dirt (3) survives the save/load round trip")
	check(int(tool.get_voxel(Vector3i(x, top - 1, z))) == 3, "second dirt cell survives the save/load round trip")

func _top_voxel(tool: Object, center: Vector3) -> int:
	for y in range(64, -1, -1):
		if int(tool.get_voxel(Vector3i(int(center.x * 8.0), y, int(center.z * 8.0)))) != 0:
			return y
	return -1

func _clear_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full := path.path_join(entry)
		if dir.current_is_dir():
			_clear_dir(full)
		else:
			DirAccess.remove_absolute(full)
		entry = dir.get_next()
	DirAccess.remove_absolute(path)
