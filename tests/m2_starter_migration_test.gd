extends SceneTree
const Store = preload("res://scripts/checkpoint_store.gd")
const World = preload("res://scripts/m2_building_world.gd")
const Landscape = preload("res://scripts/landscape_state.gd")
const Generator = preload("res://scripts/m1_patch_generator.gd")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var root_path := "user://m2-starter-migration-%d" % Time.get_ticks_usec()
	var store := Store.new(root_path)
	store.expected_dimensions = Generator.Bounds.PREVIOUS_NATIVE_SIZE
	store.expected_generator_id = Generator.Bounds.PREVIOUS_GENERATOR_ID
	store.require_building_document = true
	var source: Object = ClassDB.instantiate("VoxelBuffer")
	source.create(640,256,640)
	source.fill_area(1,Vector3i.ZERO,Vector3i(640,63,640),0)
	source.fill_area(2,Vector3i(0,63,0),Vector3i(640,64,640),0)
	source.fill_area(0,Vector3i(50,30,50),Vector3i(60,50,60),0)
	source.set_voxel(1,120,150,120,0)
	var world := World.new()
	var document := world.get_document()
	document["landscape"] = Landscape.new().document()
	check(store.save(source,7,store.expected_generator_id,document),"Previous-format fixture saves")
	var originals := {}
	for filename in DirAccess.get_files_at(root_path):
		if filename.ends_with(".json") or filename.ends_with(".bin"):
			var path := root_path.path_join(filename)
			originals[path] = FileAccess.get_sha256(path)
	var scene = load("res://scripts/m2_scene_starter_valley.gd").new()
	scene.test_mode = true
	scene.starter_hamlet_in_tests = true
	scene.checkpoint_root = root_path
	root.add_child(scene)
	var deadline := Time.get_ticks_msec()+180000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored,"Saved-world scene restores")
	if scene._player_restored:
		check(not scene._starter_seeded,"Saved world does not receive starter layout")
		check(scene.building_world.get_document()["buildings"].size() == 1,"Existing home count preserved")
		check(scene.landscape_state.water.is_empty(), "saved world does not acquire a new river or reservoir")
		check(scene.landscape_state.records.is_empty() and scene.landscape_state.composition.is_empty() and scene.landscape_state.paths.is_empty(),"Cleared landscape does not repopulate")
		check(scene.backend.voxel_at(Vector3i(55,40,55)) == 0,"Saved underground cave preserved")
		check(scene.backend.voxel_at(Vector3i(120,150,120)) == 1,"Saved disconnected overhead material preserved")
		check(scene.backend.voxel_at(Vector3i(720,8,720)) == 1,"New ring exists outside saved map")
		check(scene.backend.stats()["dirty"],"Migrated world is marked for a new generation")
		# A manual reload before the first current-format save must restore the new outskirts
		# too, rather than keeping edits that were never part of the checkpoint.
		scene.backend.voxels.set_voxel(0,720,8,720,0)
		check(scene.backend.load_world(),"Second previous-format load succeeds")
		check(scene.backend.voxel_at(Vector3i(720,8,720)) == 1,"Reload rebuilds unsaved ring deterministically")
		check(scene._save_all(),"Migrated generation saves under new generator ID")
		for path: String in originals:
			check(FileAccess.file_exists(path) and FileAccess.get_sha256(path) == originals[path],"Original checkpoint file remains byte-identical")
		print("STARTER_LEGACY_RESULT " + JSON.stringify({"original_files":originals.size(),"homes":1,"landscape_reseeded":false,"passed":failures.is_empty()}))
	scene._shutting_down = true
	scene.queue_free()
	await process_frame
	await process_frame
	print("STARTER_MIGRATION_RESULT " + JSON.stringify({"ok":failures.is_empty(),"failures":failures.size(),"messages":failures}))
	quit(0 if failures.is_empty() else 1)
