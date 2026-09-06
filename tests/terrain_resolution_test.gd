extends SceneTree

const Backend = preload("res://scripts/terrain_backend.gd")
const Generator = preload("res://scripts/m1_patch_generator.gd")
const Grid = preload("res://scripts/visual_grid.gd")
const Store = preload("res://scripts/checkpoint_store.gd")
const World = preload("res://scripts/building_world.gd")
var checks := 0
var failures := 0
var backend: Node
var metrics := {}

func _initialize() -> void:
	var fixture_root := "user://terrain-resolution-%d" % Time.get_ticks_usec()
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--fixture-root="): fixture_root = arg.trim_prefix("--fixture-root=")
	_check(Generator.VOXEL_SCALE == Grid.UNIT and Grid.UNIT == 0.125, "native terrain and visible geometry share .125 world cells")
	_check(Generator.PATCH_SIZE == Vector3i(384, 256, 384), "finite fine-grid dimensions are explicit")
	var began := Time.get_ticks_msec()
	backend = Backend.new(); backend.initial_generator = Generator; backend.generator_id = Generator.GENERATOR_ID
	backend.patch_size = Generator.PATCH_SIZE; backend.voxel_scale = Generator.VOXEL_SCALE
	backend.checkpoint_root = fixture_root; backend.require_building_document = true
	root.add_child(backend)
	var deadline := Time.get_ticks_msec() + 60000
	while not backend.is_ready() and Time.get_ticks_msec() < deadline: await process_frame
	metrics["native_ready_ms"] = Time.get_ticks_msec() - began
	_check(backend.is_ready(), "384x256x384 native volume initializes and meshes within bounded time")
	if not backend.is_ready(): print(backend.stats()); _finish(); return
	_check(backend.world_size() == Vector3(48, 32, 48), "world bounds stay fixed")
	_check(backend.terrain.scale == Vector3.ONE * Grid.UNIT, "actual native terrain transform uses shared unit")
	_check(backend.terrain.mesh_block_size == 32 and backend.terrain.get_data_block_size() == 16, "supported native mesh grouping preserves 16-cell data blocks")
	if "--read-fixture" in args:
		var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_root.path_join("resolution-expectation.json")))
		_check(expected is Dictionary, "cold restart expectation exists")
		_check(backend.load_world(), "cold restart loads saved fine resolution")
		if expected is Dictionary:
			_check(_hash(backend.voxels) == expected.hash, "cold restart preserves every fine terrain byte")
			_check(JSON.parse_string(JSON.stringify(backend.loaded_building_document)) == expected.document, "cold restart preserves complete building and planting document")
		_check(not backend.stats().dirty and backend.stats().save_status == "loaded", "fine checkpoint requires no further migration")
		_finish(); return
	var fine_steps := {}
	for x in range(8, 90):
		fine_steps[int(backend._column_surface_y(backend.voxels, x, 70)) % 4] = true
	_check(fine_steps.size() > 1, "fresh terrain exposes fine height steps instead of old half-unit terraces")
	var initial_hash := _hash(backend.voxels)
	var center := Vector3(20, 8, 18)
	var settings := {"radius": 0.75, "strength": 6.0, "falloff": 0.5}
	began = Time.get_ticks_usec()
	_check(backend.begin_stroke("raise", center, settings), "fine terrain raise starts")
	for _i in 30: backend.update_stroke(center, 1.0 / 60.0)
	metrics["half_second_stroke_cpu_ms"] = (Time.get_ticks_usec() - began) / 1000.0
	_check(backend._column_surface_y(backend.voxels, 160, 144) == 88.0, "fine brush grows exactly three world units in half a second")
	_check(backend.end_stroke(), "fine held brush commits")
	var raised_hash := _hash(backend.voxels)
	_check(raised_hash != initial_hash, "fine brush changes authoritative bytes")
	_check(backend.undo() and _hash(backend.voxels) == initial_hash, "fine brush undo restores every voxel")
	_check(backend.begin_stroke("raise", center, settings), "30fps fine brush starts")
	for _i in 15: backend.update_stroke(center, 1.0 / 30.0)
	_check(backend.end_stroke() and _hash(backend.voxels) == raised_hash, "fine brush 30fps and 60fps are byte-identical")
	_check(backend.undo() and _hash(backend.voxels) == initial_hash, "timing comparison restores fixture")
	# A constructed 45-degree fine-grid incline verifies that bounded plane
	# sampling still derives the physical local slope rather than a voxel face.
	var ramp_min := Vector3i(140, 0, 124)
	var ramp_max := Vector3i(181, 96, 165)
	var ramp_before: Object = backend._clone_region(backend.voxels, ramp_min, ramp_max)
	backend.voxels.fill_area(0, ramp_min, ramp_max, 0)
	for x in range(ramp_min.x, ramp_max.x):
		backend.voxels.fill_area(1, Vector3i(x, 0, ramp_min.z), Vector3i(x + 1, 64 + x - 160, ramp_max.z), 0)
	var sampled: Dictionary = backend.sample_surface_plane(center, Vector3.UP, 2.0)
	_check(bool(sampled.get("valid", false)) and sampled.get("point", Vector3.ZERO) == center, "bounded fine plane sampling preserves exact centre hit")
	_check(absf(float(sampled.get("slope_x", 0.0)) - 1.0) < 0.001 and absf(float(sampled.get("slope_z", 1.0))) < 0.001, "bounded fine plane sampling recovers actual 45-degree incline")
	backend.voxels.copy_channel_from_area(ramp_before, Vector3i.ZERO, ramp_before.get_size(), ramp_min, 0)
	_check(_hash(backend.voxels) == initial_hash, "fine slope fixture restores every voxel")
	var fast := {"radius": 0.75, "strength": 16.0, "falloff": 0.5}
	_check(backend.begin_stroke("raise", center, fast), "fast fine raise starts")
	for _i in 15: backend.update_stroke(center, 1.0 / 60.0)
	_check(backend._column_surface_y(backend.voxels, 160, 144) == 96.0, "16 unit/sec fine raise grows four units in quarter second")
	_check(backend.get_stroke_preview_center(center) == center + Vector3.UP * 4, "raise preview follows actual fine surface")
	_check(backend.cancel_stroke() and _hash(backend.voxels) == initial_hash, "fast raise cancel exact")
	_check(backend.begin_stroke("dig", center, fast), "fast fine dig starts")
	for _i in 15: backend.update_stroke(center, 1.0 / 60.0)
	_check(backend._column_surface_y(backend.voxels, 160, 144) == 32.0, "16 unit/sec fine dig removes four units in quarter second")
	_check(backend.get_stroke_preview_center(center) == center - Vector3.UP * 4, "dig preview follows actual fine surface without distant retarget")
	_check(backend.cancel_stroke() and _hash(backend.voxels) == initial_hash, "fast dig cancel exact")
	var plane := {"valid": true, "point": center + Vector3.UP * 6.0, "normal": Vector3.UP}
	_check(backend.begin_stroke("level", center, fast, plane), "fast fine level starts")
	for _i in 15: backend.update_stroke(center, 1.0 / 60.0)
	_check(backend._column_surface_y(backend.voxels, 160, 144) == 96.0, "16 unit/sec fine level advances four units in quarter second")
	_check(backend.cancel_stroke() and _hash(backend.voxels) == initial_hash, "fast level cancel exact")
	# Build the old native resolution with independent native volume fills.
	# A cave, disconnected overhang, high-valued material and edge cells must
	# all expand exactly, not be reconstructed from a top-surface sample.
	var old: Object = ClassDB.instantiate("VoxelBuffer"); old.create(96, 64, 96)
	old.fill_area(1, Vector3i.ZERO, Vector3i(96, 16, 96), 0)
	old.fill_area(2, Vector3i(0, 15, 0), Vector3i(96, 16, 96), 0)
	old.fill_area(0, Vector3i(20, 6, 20), Vector3i(30, 12, 30), 0)
	old.fill_area(2, Vector3i(40, 22, 40), Vector3i(45, 25, 45), 0)
	old.set_voxel(65535, 95, 63, 95, 0)
	var expected_fine: Object = ClassDB.instantiate("VoxelBuffer"); expected_fine.create(384, 256, 384)
	expected_fine.fill_area(1, Vector3i.ZERO, Vector3i(384, 64, 384), 0)
	expected_fine.fill_area(2, Vector3i(0, 60, 0), Vector3i(384, 64, 384), 0)
	expected_fine.fill_area(0, Vector3i(80, 24, 80), Vector3i(120, 48, 120), 0)
	expected_fine.fill_area(2, Vector3i(160, 88, 160), Vector3i(180, 100, 180), 0)
	expected_fine.fill_area(65535, Vector3i(380, 252, 380), Vector3i(384, 256, 384), 0)
	var expected_hash := _hash(expected_fine)
	expected_fine = null
	var store := Store.new(fixture_root); store.expected_dimensions = Generator.LEGACY_PATCH_SIZE
	store.expected_generator_id = Generator.LEGACY_GENERATOR_ID; store.require_building_document = true
	var world := World.new(); var document: Dictionary = world.get_document()
	document["landscape"] = {"version": 1, "next_id": 2, "records": [{"id": 1, "kind": "tree", "position": [32, 8, 26], "seed": 1}]}
	_check(store.save(old, 17, Generator.LEGACY_GENERATOR_ID, document), "write complete legacy checkpoint")
	var legacy_files := {}
	for item in store._candidates():
		legacy_files[item.manifest] = FileAccess.get_sha256(item.manifest)
		legacy_files[item.data] = FileAccess.get_sha256(item.data)
	began = Time.get_ticks_usec()
	_check(backend.load_world(), "fine backend finds validated legacy checkpoint")
	metrics["legacy_load_and_upsample_ms"] = (Time.get_ticks_usec() - began) / 1000.0
	_check(_hash(backend.voxels) == expected_hash, "migration preserves all 37748736 cells including cave overhang materials and bounds")
	_check(backend.stats().dirty and backend.stats().save_status == "migrated", "legacy migration is dirty until next explicit save")
	_check(JSON.parse_string(JSON.stringify(backend.loaded_building_document)) == JSON.parse_string(JSON.stringify(document)), "migration preserves full cottage and planting document")
	_check(backend.stats().revision == 17, "migration preserves authoritative revision")
	var ceiling := Vector3(12, 6, 12)
	_check(backend.begin_stroke("dig", ceiling, {"radius": 0.5, "strength": 6.0, "surface_normal": Vector3.DOWN}), "ceiling dig begins on migrated cave")
	for _i in 15: backend.update_stroke(ceiling, 1.0 / 60.0)
	_check(backend.get_stroke_preview_center(ceiling) == ceiling + Vector3.UP * 1.5, "downward-facing dig preview tracks advancing underside")
	_check(backend.cancel_stroke() and _hash(backend.voxels) == expected_hash, "ceiling preview does not change cancel or migration data")
	for path in legacy_files: _check(FileAccess.file_exists(path) and FileAccess.get_sha256(path) == legacy_files[path], "migration leaves old file byte-identical")
	began = Time.get_ticks_usec()
	_check(backend.save_world(document), "save publishes validated fine checkpoint")
	metrics["fine_checkpoint_save_ms"] = (Time.get_ticks_usec() - began) / 1000.0
	for path in legacy_files: _check(FileAccess.file_exists(path) and FileAccess.get_sha256(path) == legacy_files[path], "first fine save preserves legacy recovery files")
	_check(backend.load_world() and _hash(backend.voxels) == expected_hash, "fine checkpoint reload is byte-identical")
	_check(not backend.stats().dirty and backend.stats().save_status == "loaded", "fine checkpoint is preferred after migration")
	var file := FileAccess.open(fixture_root.path_join("resolution-expectation.json"), FileAccess.WRITE)
	_check(file != null, "write fine cold-restart expectation")
	if file: file.store_string(JSON.stringify({"hash": expected_hash, "document": document})); file.close()
	metrics["fixture_root"] = fixture_root
	_finish()

func _hash(buffer: Object) -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256)
	context.update(buffer.get_channel_as_byte_array(0)); return context.finish().hex_encode()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: " + label)

func _finish() -> void:
	backend.queue_free(); await process_frame; await process_frame
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "metrics": metrics}))
	quit(1 if failures else 0)
