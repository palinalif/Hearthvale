extends SceneTree

## Native M1 resolution probe. Public brush/plane coordinates stay in world
## units while the authoritative VoxelBuffer uses 0.125-unit cells.

const Backend := preload("res://scripts/terrain_backend.gd")
const Generator := preload("res://scripts/m1_patch_generator.gd")
const BuildingWorld := preload("res://scripts/building_world.gd")

var checks := 0
var failures := 0
var backend: Node

func _initialize() -> void:
	backend = Backend.new()
	backend.patch_size = Generator.PATCH_SIZE
	backend.voxel_scale = Generator.VOXEL_SCALE
	backend.initial_generator = Generator
	backend.generator_id = Generator.GENERATOR_ID
	backend.checkpoint_root = "user://m1-scaled-backend-%d" % Time.get_ticks_usec()
	backend.require_building_document = true
	root.add_child(backend)
	var deadline := Time.get_ticks_msec() + 60000
	while not backend.is_ready() and Time.get_ticks_msec() < deadline: await process_frame
	_check(backend.is_ready(), "scaled native backend ready")
	if not backend.is_ready():
		_finish()
		return
	_check(backend.world_size().is_equal_approx(Vector3(48, 32, 48)), "M1 keeps 48×32×48 world bounds")
	_check(backend.patch_size == Vector3i(384, 256, 384) and backend.patch_size == Generator.PATCH_SIZE, "M1 uses 384×256×384 index grid")
	_check(is_equal_approx(backend.voxel_scale, 0.125), "M1 uses eighth-unit editable voxels")
	_check(backend.terrain.bounds.size == Vector3(Generator.PATCH_SIZE), "native bounds use index dimensions")
	_check(backend.terrain.scale.is_equal_approx(Vector3.ONE * Generator.VOXEL_SCALE), "native terrain scales geometry uniformly")
	_check(backend.voxel_at(Generator.PATCH_SIZE - Vector3i.ONE) >= 0 and backend.voxel_at(Generator.PATCH_SIZE) == 0, "index bounds are clamped")

	var plane: Dictionary = backend.sample_surface_plane(Vector3(20.0, 8.0, 18.0), Vector3.UP, 3.0)
	_check(bool(plane.get("valid", false)), "world-space surface sample is valid")
	if bool(plane.get("valid", false)):
		_check(absf((plane["point"] as Vector3).y - 8.0) <= 1.0, "surface sample returns world height")
		_check((plane["normal"] as Vector3).is_finite(), "surface normal is finite")

	var preview: Array[Vector3i] = backend.preview_sphere(Vector3(20.0, 8.0, 18.0), 2.0, true)
	_check(not preview.is_empty(), "world radius converts to native sphere cells")
	var preview_valid := true
	var preview_min := Generator.PATCH_SIZE
	var preview_max := Vector3i.ZERO
	for cell in preview:
		preview_valid = preview_valid and cell.x >= 0 and cell.x < Generator.PATCH_SIZE.x and cell.y >= 0 and cell.y < Generator.PATCH_SIZE.y and cell.z >= 0 and cell.z < Generator.PATCH_SIZE.z
		preview_min = Vector3i(mini(preview_min.x, cell.x), mini(preview_min.y, cell.y), mini(preview_min.z, cell.z))
		preview_max = Vector3i(maxi(preview_max.x, cell.x), maxi(preview_max.y, cell.y), maxi(preview_max.z, cell.z))
	_check(preview_valid, "preview cells remain inside M1 grid")
	if not preview.is_empty():
		var center := Vector3(20.0, 8.0, 18.0)
		var physical_extent := Vector3(preview_max - preview_min + Vector3i.ONE) * Generator.VOXEL_SCALE
		_check(physical_extent.x <= 4.5 and physical_extent.y <= 4.5 and physical_extent.z <= 4.5, "preview footprint matches physical brush radius")
		_check((Vector3(preview_min) * Generator.VOXEL_SCALE).distance_to(center) <= 4.0, "preview origin stays near world center")

	var world := BuildingWorld.new()
	var before_buffer: Object = backend._clone_buffer(backend.voxels)
	var before_hash := _hash_buffer(backend.voxels)
	var before_revision := int(backend.stats().get("revision", -1))
	_check(backend.begin_stroke("raise", Vector3(20.0, 8.0, 18.0), {"radius": 2.0, "strength": 2.0, "falloff": 0.5, "surface_normal": Vector3.UP}), "M1 world-space stroke begins")
	backend.update_stroke(Vector3(20.5, 8.0, 18.0), 2.0)
	_check(backend.end_stroke(), "M1 stroke commits a bounded command")
	var edited_hash := _hash_buffer(backend.voxels)
	_check(edited_hash != before_hash and int(backend.stats().get("revision", -1)) > before_revision, "M1 stroke changes authoritative cells")
	var changed_cells := _changed_cells(before_buffer, backend.voxels)
	_check(changed_cells > 0, "M1 physical stroke changes at least one native cell")
	_check(backend.undo(), "M1 undo succeeds")
	_check(_hash_buffer(backend.voxels) == before_hash, "M1 undo restores exact bytes")
	_check(backend.redo(), "M1 redo succeeds")
	_check(_hash_buffer(backend.voxels) == edited_hash, "M1 redo restores exact bytes")
	var document := world.get_document()
	_check(backend.save_world(document), "M1 scaled checkpoint saves")
	var saved_revision := int(backend.stats().get("revision", -1))
	var saved_hash := _hash_buffer(backend.voxels)
	_check(backend.load_world(), "M1 scaled checkpoint reloads")
	_check(_hash_buffer(backend.voxels) == saved_hash, "M1 reload preserves terrain bytes")
	_check(int(backend.stats().get("revision", -1)) == saved_revision, "M1 reload preserves revision")
	_check(BuildingWorld.validate_document(backend.loaded_building_document), "M1 reload returns building document")
	_finish()

func _hash_buffer(buffer: Object) -> String:
	var c := HashingContext.new(); c.start(HashingContext.HASH_SHA256)
	c.update(buffer.get_channel_as_byte_array(0))
	return c.finish().hex_encode()

func _changed_cells(before: Object, after: Object) -> int:
	# Inspect the native stroke's changed region, then undo only those reported
	# cells in a clone. Equality of the entire payload proves the report omitted
	# no changes, without a 37-million-cell GDScript traversal.
	var restored: Object = backend._clone_buffer(after)
	var count := 0
	var seen := {}
	for world_cell: Vector3 in backend.get_last_edit_cells():
		var cell := Vector3i(floor(world_cell / Generator.VOXEL_SCALE))
		if seen.has(cell): continue
		seen[cell] = true
		var prior := int(before.get_voxel(cell.x, cell.y, cell.z, 0))
		if prior != int(after.get_voxel(cell.x, cell.y, cell.z, 0)): count += 1
		restored.set_voxel(prior, cell.x, cell.y, cell.z, 0)
	_check(count == seen.size(), "reported edit cells correspond to actual voxel changes")
	_check(_hash_buffer(restored) == _hash_buffer(before), "reported changed cells account for every modified payload byte")
	return count

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: %s" % label)

func _finish() -> void:
	if backend and is_instance_valid(backend):
		backend.queue_free()
		await process_frame
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures}))
	quit(1 if failures > 0 else 0)
