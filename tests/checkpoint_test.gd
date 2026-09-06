extends SceneTree

const CheckpointStore := preload("res://scripts/checkpoint_store.gd")
const PatchGenerator := preload("res://scripts/patch_generator.gd")
const ROOT := "user://test-checkpoint-m0"
const DIMS := Vector3i(48, 32, 48)
const PAYLOAD_BYTES := 147456
var failures := 0
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if "--write-fixture" in args:
		_clear(ProjectSettings.globalize_path(ROOT))
		var source := _source(77)
		var store := CheckpointStore.new(ROOT)
		var ok := store.save(source, 77, PatchGenerator.GENERATOR_ID)
		print(JSON.stringify({"ok": ok, "mode": "write-fixture", "hash": _buffer_hash(source), "sample": source.get_voxel(24, 8, 24, 0)}))
		quit(0 if ok else 1)
		return
	if "--read-fixture" in args:
		var store := CheckpointStore.new(ROOT)
		var loaded = store.load(77)
		var expected := _source(77)
		var ok: bool = loaded != null and _buffer_hash(loaded) == _buffer_hash(expected) and loaded.get_voxel(24, 8, 24, 0) == 77
		print(JSON.stringify({"ok": ok, "mode": "read-fixture", "loaded_revision": store.loaded_revision, "hash": _buffer_hash(loaded) if loaded != null else ""}))
		quit(0 if ok else 1)
		return
	if "--write-second" in args:
		var store := CheckpointStore.new(ROOT)
		var ok := store.save(_source(88), 88, PatchGenerator.GENERATOR_ID)
		print(JSON.stringify({"ok": ok, "mode": "write-second", "hash": _buffer_hash(_source(88))}))
		quit(0 if ok else 1)
		return
	if "--read-second" in args:
		var store := CheckpointStore.new(ROOT)
		var loaded = store.load(88)
		var ok: bool = loaded != null and _buffer_hash(loaded) == _buffer_hash(_source(88)) and store.loaded_revision == 88
		print(JSON.stringify({"ok": ok, "mode": "read-second", "loaded_revision": store.loaded_revision, "hash": _buffer_hash(loaded) if loaded != null else ""}))
		quit(0 if ok else 1)
		return
	_clear(ProjectSettings.globalize_path(ROOT))
	_run_store_checks()
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "root": ROOT}))
	quit(1 if failures > 0 else 0)

func _run_store_checks() -> void:
	var source := _source(17)
	var store := CheckpointStore.new(ROOT)
	var schema2_started := Time.get_ticks_usec()
	check(store.save(source, 4, PatchGenerator.GENERATOR_ID), "initial save")
	print("schema2_save_ms=", float(Time.get_ticks_usec() - schema2_started) / 1000.0)
	var loaded = store.load(4)
	check(loaded != null and _buffer_hash(loaded) == _buffer_hash(source), "initial full hash and sample")
	_write_schema1("0000000000000000", 3, source)
	var legacy = store.load(3)
	check(legacy != null and _buffer_hash(legacy) == _buffer_hash(source), "schema1 legacy load")
	var migration_started := Time.get_ticks_usec()
	check(store.save(legacy, 5, PatchGenerator.GENERATOR_ID), "schema1 to schema2 save")
	print("schema1_to_schema2_save_ms=", float(Time.get_ticks_usec() - migration_started) / 1000.0)
	var migrated_files := _json_files(ProjectSettings.globalize_path(ROOT))
	var migrated_manifest = JSON.parse_string(FileAccess.get_file_as_string(migrated_files[0])) if not migrated_files.is_empty() else null
	check(migrated_manifest is Dictionary and migrated_manifest.get("schema", -1) == 2 and migrated_manifest.get("payload_layout", "") == "voxelbuffer_channel_raw_zxy", "schema2 manifest layout")
	var store2 := CheckpointStore.new(ROOT)
	check(store2.save(_source(18), 4, PatchGenerator.GENERATOR_ID), "second store same revision")
	var files := _json_files(ProjectSettings.globalize_path(ROOT))
	check(files.size() == 2, "same-second saves have two generations")
	check(files.size() == 2 and _generation(files[0]).length() >= 16 and _generation(files[0]) != _generation(files[1]), "fixed-width unique generations")
	for i in 12:
		check(store.save(_source(100 + i), 10 + i, PatchGenerator.GENERATOR_ID), "save generation %d" % i)
	files = _json_files(ProjectSettings.globalize_path(ROOT))
	check(files.size() == 2, "GC retains two valid generations")
	var newest = store.load(21)
	check(newest != null and _buffer_hash(newest) == _buffer_hash(_source(111)), "newest numeric generation ordering")
	files = _json_files(ProjectSettings.globalize_path(ROOT))
	var newest_data := files[0].trim_suffix(".json") + ".bin"
	_write_bytes(newest_data, PackedByteArray([1]))
	var fallback = store.load()
	check(fallback != null and store.loaded_revision == 20 and _buffer_hash(fallback) == _buffer_hash(_source(110)), "corrupt newest falls back")
	check(store.save(_source(112), 22, PatchGenerator.GENERATOR_ID), "save after corrupt newest")
	files = _json_files(ProjectSettings.globalize_path(ROOT))
	var new_data := files[0].trim_suffix(".json") + ".bin"
	DirAccess.remove_absolute(new_data)
	fallback = store.load()
	check(fallback != null and store.loaded_revision == 20, "missing data falls back")
	var staged_source := _source(200)
	_write_bytes(ProjectSettings.globalize_path(ROOT).path_join("checkpoint_9999999999999999.staged.bin"), _buffer_payload(staged_source))
	_write(ProjectSettings.globalize_path(ROOT).path_join("checkpoint_9999999999999999.staged.json"), JSON.stringify({"schema": 1, "generator_id": PatchGenerator.GENERATOR_ID, "revision": 999, "size": [48, 32, 48], "payload_bytes": PAYLOAD_BYTES, "sha256": _buffer_hash(staged_source), "generation": "9999999999999999"}))
	check(store.load(20) != null and store.loaded_revision == 20, "staged manifest ignored")
	_write_invalid("0000000000000100", 100, "schema", 99)
	_write_invalid("0000000000000101", 101, "generator_id", "unknown")
	_write_invalid("0000000000000102", 102, "size", [48.5, 32, 48])
	_write_invalid("0000000000000103", 103, "payload_bytes", 1)
	_write_invalid("0000000000000105", 105, "sha256", "0")
	_write_invalid("0000000000000106", 106, "payload_layout", "wrong_layout")
	_write_invalid("0000000000000107", 107, "depth", 0)
	_write(ProjectSettings.globalize_path(ROOT).path_join("checkpoint_0000000000000104.json"), "x".repeat(16385))
	for revision in [100, 101, 102, 103, 104, 105, 106, 107]:
		check(store.load(revision) == null, "invalid candidate rejected revision %d" % revision)
	var bad_root := ProjectSettings.globalize_path(ROOT).path_join("as_file")
	_write(bad_root, "x")
	check(not CheckpointStore.new(bad_root).save(source, 300, PatchGenerator.GENERATOR_ID), "invalid write root rejected")
	var wrong_depth := _source(600)
	wrong_depth.set_channel_depth(PatchGenerator.CHANNEL_TYPE, 0)
	check(not store.save(wrong_depth, 301, PatchGenerator.GENERATOR_ID), "native depth mismatch rejected")
	check(store.load(20) != null and store.loaded_revision == 20, "depth rejection preserves prior checkpoint")
	check(not store.save(source, -2, PatchGenerator.GENERATOR_ID), "negative revision rejected")

func _source(value: int) -> Object:
	var out: Object = ClassDB.instantiate("VoxelBuffer")
	out.create(DIMS.x, DIMS.y, DIMS.z)
	out.set_voxel(value, 24, 8, 24, PatchGenerator.CHANNEL_TYPE)
	out.set_voxel(value + 1, 2, 3, 4, PatchGenerator.CHANNEL_TYPE)
	return out

func _buffer_hash(buffer: Object) -> String:
	if buffer == null: return ""
	var bytes := _buffer_payload(buffer)
	var c := HashingContext.new(); c.start(HashingContext.HASH_SHA256); c.update(bytes); return c.finish().hex_encode()

func _buffer_payload(buffer: Object) -> PackedByteArray:
	if buffer.has_method("get_channel_as_byte_array"):
		var native_bytes: PackedByteArray = buffer.get_channel_as_byte_array(PatchGenerator.CHANNEL_TYPE)
		if native_bytes.size() == PAYLOAD_BYTES: return native_bytes
	return _buffer_payload_loop(buffer)

func _buffer_payload_loop(buffer: Object) -> PackedByteArray:
	var bytes := PackedByteArray(); bytes.resize(PAYLOAD_BYTES); var offset := 0
	for x in DIMS.x:
		for y in DIMS.y:
			for z in DIMS.z:
				bytes.encode_u16(offset, int(buffer.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE))); offset += 2
	return bytes

func _write_schema1(generation: String, revision: int, source: Object) -> void:
	var base := ProjectSettings.globalize_path(ROOT).path_join("checkpoint_%s" % generation)
	var payload := _buffer_payload_loop(source)
	_write_bytes(base + ".bin", payload)
	_write(base + ".json", JSON.stringify({"schema": 1, "generator_id": PatchGenerator.GENERATOR_ID, "revision": revision, "size": [48, 32, 48], "payload_bytes": PAYLOAD_BYTES, "sha256": _hash_bytes(payload), "generation": generation}))

func _hash_bytes(payload: PackedByteArray) -> String:
	var c := HashingContext.new(); c.start(HashingContext.HASH_SHA256); c.update(payload); return c.finish().hex_encode()

func _json_files(path: String) -> Array[String]:
	var out: Array[String] = []; var d := DirAccess.open(path)
	if d == null: return out
	var rx := RegEx.new(); rx.compile("^checkpoint_[0-9]{16,}\\.json$")
	d.list_dir_begin(); var n := d.get_next()
	while not n.is_empty():
		if rx.search(n) != null: out.append(path.path_join(n))
		n = d.get_next()
	d.list_dir_end(); out.sort(); out.reverse(); return out

func _generation(path: String) -> String:
	return path.get_file().trim_prefix("checkpoint_").trim_suffix(".json")

func _write_invalid(generation: String, revision: int, field: String, value: Variant) -> void:
	var base := ProjectSettings.globalize_path(ROOT).path_join("checkpoint_%s" % generation)
	var source := _source(revision)
	_write_bytes(base + ".bin", _buffer_payload(source))
	var body := {"schema": 2, "generator_id": PatchGenerator.GENERATOR_ID, "revision": revision, "size": [48, 32, 48], "payload_bytes": PAYLOAD_BYTES, "payload_layout": "voxelbuffer_channel_raw_zxy", "channel": 0, "depth": 1, "sha256": _buffer_hash(source), "generation": generation}
	body[field] = value
	_write(base + ".json", JSON.stringify(body))

func _write(path: String, value: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null: f.store_string(value); f.close()

func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null: f.store_buffer(bytes); f.close()

func _clear(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path): return
	var d := DirAccess.open(path); d.list_dir_begin(); var n := d.get_next()
	while not n.is_empty():
		var child := path.path_join(n)
		if d.current_is_dir(): _clear(child)
		else: DirAccess.remove_absolute(child)
		n = d.get_next()
	d.list_dir_end(); DirAccess.remove_absolute(path)
