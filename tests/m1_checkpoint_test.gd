extends SceneTree

const CheckpointStore := preload("res://scripts/checkpoint_store.gd")
const BuildingWorld := preload("res://scripts/building_world.gd")
const M1PatchGenerator := preload("res://scripts/m1_patch_generator.gd")
const ROOT := "user://test-checkpoint-m1"
const DIMS: Vector3i = M1PatchGenerator.PATCH_SIZE
const PAYLOAD_BYTES: int = DIMS.x * DIMS.y * DIMS.z * 2

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
		var world := BuildingWorld.new()
		var document := world.get_document()
		world.set_material("building-1", "warm_plaster")
		document = world.get_document()
		var source := M1PatchGenerator.generate()
		var store := _store()
		var ok: bool = store.save(source, 1, M1PatchGenerator.GENERATOR_ID, document)
		print(JSON.stringify({"ok": ok, "mode": "write-fixture", "terrain_hash": _buffer_hash(source), "document_hash": _document_hash(document)}))
		quit(0 if ok else 1)
		return
	if "--read-fixture" in args:
		var store := _store()
		var loaded = store.load(1)
		var expected := M1PatchGenerator.generate()
		var ok: bool = loaded != null and _buffer_hash(loaded) == _buffer_hash(expected) and store.loaded_revision == 1 and BuildingWorld.validate_document(store.loaded_building_document)
		print(JSON.stringify({"ok": ok, "mode": "read-fixture", "loaded_revision": store.loaded_revision, "terrain_hash": _buffer_hash(loaded) if loaded != null else "", "document_hash": _document_hash(store.loaded_building_document)}))
		quit(0 if ok else 1)
		return
	if "--write-second" in args:
		var world := BuildingWorld.new()
		world.set_material("building-1", "stone_plaster")
		var document := world.get_document()
		var store := _store()
		var source := M1PatchGenerator.generate()
		var ok: bool = store.save(source, 2, M1PatchGenerator.GENERATOR_ID, document)
		print(JSON.stringify({"ok": ok, "mode": "write-second", "terrain_hash": _buffer_hash(source), "document_hash": _document_hash(document)}))
		quit(0 if ok else 1)
		return
	if "--read-second" in args:
		var store := _store()
		var loaded = store.load(2)
		var expected := M1PatchGenerator.generate()
		var ok: bool = loaded != null and _buffer_hash(loaded) == _buffer_hash(expected) and store.loaded_revision == 2 and BuildingWorld.validate_document(store.loaded_building_document)
		print(JSON.stringify({"ok": ok, "mode": "read-second", "loaded_revision": store.loaded_revision, "terrain_hash": _buffer_hash(loaded) if loaded != null else "", "document_hash": _document_hash(store.loaded_building_document)}))
		quit(0 if ok else 1)
		return
	_clear(ProjectSettings.globalize_path(ROOT))
	_run_store_checks()
	_run_format_retention_checks()
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "root": ROOT}))
	quit(1 if failures > 0 else 0)

func _run_store_checks() -> void:
	var source := M1PatchGenerator.generate()
	var world := BuildingWorld.new()
	world.set_material("building-1", "warm_plaster")
	var document_one := world.get_document()
	var store := _store()
	check(store.require_building_document, "M1 store requires document")
	check(store.save(source, 1, M1PatchGenerator.GENERATOR_ID, document_one), "M1 initial save")
	var loaded = store.load(1)
	check(loaded != null and _buffer_hash(loaded) == _buffer_hash(source), "M1 initial terrain hash")
	check(_document_hash(store.loaded_building_document) == _document_hash(document_one), "M1 initial document roundtrip")
	var manifest_files := _json_files(ProjectSettings.globalize_path(ROOT))
	var first_manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_files[0])) if not manifest_files.is_empty() else {}
	check(first_manifest.get("schema", -1) == 3 and first_manifest.get("building_document_bytes", 0) > 0, "M1 schema3 manifest")
	check(int(first_manifest.get("building_document_bytes", 0)) <= CheckpointStore.MAX_BUILDING_DOCUMENT_BYTES and FileAccess.get_file_as_string(manifest_files[0]).to_utf8_buffer().size() <= CheckpointStore.MAX_BUILDING_MANIFEST_BYTES, "M1 document and manifest bounds")
	check(first_manifest.get("building_document_json", "") == JSON.stringify(document_one), "M1 embedded exact JSON")

	world.set_material("building-1", "stone_plaster")
	var document_two := world.get_document()
	check(store.save(source, 2, M1PatchGenerator.GENERATOR_ID, document_two), "M1 second generation")
	manifest_files = _json_files(ProjectSettings.globalize_path(ROOT))
	check(manifest_files.size() == 2, "M1 keeps two valid generations")
	var newest_path := manifest_files[0]
	var newest_body: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(newest_path))
	newest_body["building_document_json"] = "{malformed"
	_write(newest_path, JSON.stringify(newest_body))
	loaded = store.load()
	check(loaded != null and store.loaded_revision == 1 and _document_hash(store.loaded_building_document) == _document_hash(document_one), "malformed newest document falls back as a pair")

	check(store.save(source, 3, M1PatchGenerator.GENERATOR_ID, document_one), "M1 third generation")
	manifest_files = _json_files(ProjectSettings.globalize_path(ROOT))
	newest_path = manifest_files[0]
	newest_body = JSON.parse_string(FileAccess.get_file_as_string(newest_path))
	newest_body.erase("building_document_json")
	_write(newest_path, JSON.stringify(newest_body))
	loaded = store.load()
	check(loaded != null and store.loaded_revision == 1 and _document_hash(store.loaded_building_document) == _document_hash(document_one), "missing embedded document falls back")

	check(store.save(source, 4, M1PatchGenerator.GENERATOR_ID, document_two), "M1 fourth generation")
	manifest_files = _json_files(ProjectSettings.globalize_path(ROOT))
	newest_path = manifest_files[0]
	newest_body = JSON.parse_string(FileAccess.get_file_as_string(newest_path))
	newest_body["building_document_sha256"] = "0".repeat(64)
	_write(newest_path, JSON.stringify(newest_body))
	loaded = store.load()
	check(loaded != null and store.loaded_revision == 1 and _document_hash(store.loaded_building_document) == _document_hash(document_one), "document hash corruption falls back")

	check(store.save(source, 5, M1PatchGenerator.GENERATOR_ID, document_one), "M1 fifth generation")
	manifest_files = _json_files(ProjectSettings.globalize_path(ROOT))
	newest_path = manifest_files[0]
	var newest_data := newest_path.trim_suffix(".json") + ".bin"
	_write_bytes(newest_data, PackedByteArray([1, 2, 3]))
	loaded = store.load()
	check(loaded != null and store.loaded_revision == 1 and _document_hash(store.loaded_building_document) == _document_hash(document_one), "terrain truncation falls back with matching document")

	var staged_base := ProjectSettings.globalize_path(ROOT).path_join("checkpoint_9999999999999999")
	_write_bytes(staged_base + ".staged.bin", _buffer_payload(source))
	var staged_manifest := {"schema": 3, "generator_id": M1PatchGenerator.GENERATOR_ID, "revision": 999, "size": [DIMS.x, DIMS.y, DIMS.z], "payload_bytes": PAYLOAD_BYTES, "payload_layout": "voxelbuffer_channel_raw_zxy", "channel": 0, "depth": 1, "sha256": _buffer_hash(source), "generation": "9999999999999999", "building_document_bytes": JSON.stringify(document_two).to_utf8_buffer().size(), "building_document_sha256": _document_hash(document_two), "building_document_json": JSON.stringify(document_two)}
	_write(staged_base + ".staged.json", JSON.stringify(staged_manifest))
	check(store.load(1) != null and store.loaded_revision == 1, "staged M1 pair ignored")
	var raw_store := CheckpointStore.new(ROOT)
	raw_store.expected_generator_id = M1PatchGenerator.GENERATOR_ID
	raw_store.expected_dimensions = DIMS
	check(raw_store.save(source, 9, M1PatchGenerator.GENERATOR_ID), "raw M1 schema2 candidate can be written by optional store")
	loaded = store.load()
	check(loaded != null and store.loaded_revision != 9 and BuildingWorld.validate_document(store.loaded_building_document), "required-document store rejects schema2 candidate")

	var invalid_document: Dictionary = document_one.duplicate(true)
	invalid_document["schema_version"] = 999
	check(not store.save(source, 6, M1PatchGenerator.GENERATOR_ID, invalid_document), "invalid building document rejected")
	check(store.load(1) != null and store.loaded_revision == 1 and _document_hash(store.loaded_building_document) == _document_hash(document_one), "invalid document preserves prior valid pair")
	check(not store.save(source, 7, "unknown_generator", document_one), "unknown M1 generator rejected")
	var no_doc_store := _store()
	check(not no_doc_store.save(source, 8, M1PatchGenerator.GENERATOR_ID), "required document cannot be omitted")
	_run_landscape_checks(source, document_one, store)

func _run_landscape_checks(source: Object, legacy_document: Dictionary, store: RefCounted) -> void:
	var document: Dictionary = legacy_document.duplicate(true)
	document["landscape"] = {"version": 1, "next_id": 4, "records": [
		{"id": 1, "kind": "tree", "position": [12.0, 8.0, 16.0], "seed": 1042},
		{"id": 2, "kind": "foliage", "position": [14.0, 8.0, 17.0], "seed": 1043},
		{"id": 3, "kind": "rock", "position": [15.0, 8.0, 18.0], "seed": 1044}
	]}
	check(store.save(source, 10, M1PatchGenerator.GENERATOR_ID, document), "landscape saved in building generation")
	var loaded = store.load(10)
	check(loaded != null and _buffer_hash(loaded) == _buffer_hash(source) and _document_hash(store.loaded_building_document) == _document_hash(document), "landscape and terrain roundtrip as one generation")
	var valid_manifests := _json_files(ProjectSettings.globalize_path(ROOT))
	for malformed in [null, [], "invalid", {"version": 1, "next_id": 1, "records": "invalid"}, {"version": 1, "next_id": 2, "records": [{"id": 1, "kind": "tree", "position": [999, 8, 16], "seed": 1042}]}]:
		var invalid: Dictionary = document.duplicate(true)
		invalid["landscape"] = malformed
		check(not store.save(source, 11, M1PatchGenerator.GENERATOR_ID, invalid), "malformed landscape rejected before save")
		check(_json_files(ProjectSettings.globalize_path(ROOT)) == valid_manifests, "invalid landscape publishes no checkpoint")
	check(store.load(10) != null and _document_hash(store.loaded_building_document) == _document_hash(document), "invalid landscape leaves prior generation intact")
	var next_document: Dictionary = document.duplicate(true)
	next_document["landscape"]["records"][0]["seed"] = 2000
	check(store.save(source, 11, M1PatchGenerator.GENERATOR_ID, next_document), "second landscape generation")
	var newest_path := _json_files(ProjectSettings.globalize_path(ROOT))[0]
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(newest_path))
	# Repair bytes and digest deliberately: the candidate must fail semantic
	# landscape validation, rather than merely its JSON integrity checks.
	var corrupt_document: Dictionary = next_document.duplicate(true)
	corrupt_document["landscape"]["records"][0]["kind"] = "unsupported"
	var corrupt_text := JSON.stringify(corrupt_document)
	manifest["building_document_json"] = corrupt_text
	manifest["building_document_bytes"] = corrupt_text.to_utf8_buffer().size()
	manifest["building_document_sha256"] = corrupt_text.sha256_text()
	_write(newest_path, JSON.stringify(manifest))
	loaded = store.load()
	check(loaded != null and store.loaded_revision == 10 and _buffer_hash(loaded) == _buffer_hash(source) and _document_hash(store.loaded_building_document) == _document_hash(document), "malformed newest landscape falls back to complete valid pair")
	check(store.load(11) == null, "requested malformed landscape generation rejected")

func _store() -> RefCounted:
	var store := CheckpointStore.new(ROOT)
	store.expected_generator_id = M1PatchGenerator.GENERATOR_ID
	store.expected_dimensions = DIMS
	store.require_building_document = true
	return store

func _run_format_retention_checks() -> void:
	# Tiny native buffers isolate retention policy from the full valley's I/O
	# cost. The migration integration test covers real 96 -> 384 dimensions.
	var retention_root := ROOT + "-format-retention"
	_clear(ProjectSettings.globalize_path(retention_root))
	var legacy := CheckpointStore.new(retention_root)
	legacy.expected_dimensions = Vector3i(4, 4, 4)
	legacy.expected_generator_id = M1PatchGenerator.LEGACY_GENERATOR_ID
	var legacy_buffer: Object = ClassDB.instantiate("VoxelBuffer")
	legacy_buffer.create(4, 4, 4)
	legacy_buffer.fill(2, 0)
	check(legacy.save(legacy_buffer, 1, legacy.expected_generator_id), "retention fixture saves predecessor format")
	var legacy_path := _json_files(ProjectSettings.globalize_path(retention_root))[0]
	var legacy_data_path := legacy_path.trim_suffix(".json") + ".bin"
	var legacy_manifest_bytes := FileAccess.get_file_as_bytes(legacy_path)
	var legacy_data_bytes := FileAccess.get_file_as_bytes(legacy_data_path)
	var unknown_path := ProjectSettings.globalize_path(retention_root).path_join("checkpoint_0000000000000002.json")
	_write(unknown_path, JSON.stringify({"schema": 99, "generator_id": M1PatchGenerator.GENERATOR_ID, "size": [8, 8, 8]}))
	var unknown_bytes := FileAccess.get_file_as_bytes(unknown_path)
	var current := CheckpointStore.new(retention_root)
	current.expected_dimensions = Vector3i(8, 8, 8)
	current.expected_generator_id = M1PatchGenerator.GENERATOR_ID
	var current_buffer: Object = ClassDB.instantiate("VoxelBuffer")
	current_buffer.create(8, 8, 8)
	current_buffer.fill(3, 0)
	for revision in [2, 3, 4]: check(current.save(current_buffer, revision, current.expected_generator_id), "new format checkpoint saves while predecessor exists")
	check(FileAccess.get_file_as_bytes(legacy_path) == legacy_manifest_bytes and FileAccess.get_file_as_bytes(legacy_data_path) == legacy_data_bytes, "new-format GC preserves predecessor pair byte-for-byte")
	check(legacy.load(1) != null, "predecessor remains independently recoverable")
	check(FileAccess.get_file_as_bytes(unknown_path) == unknown_bytes, "GC preserves unknown checkpoint format")
	check(current.load(4) != null and current.load(3) != null and current.load(2) != null, "new format retains its own three generations")

func _buffer_hash(buffer: Object) -> String:
	if buffer == null: return ""
	var c := HashingContext.new(); c.start(HashingContext.HASH_SHA256); c.update(_buffer_payload(buffer)); return c.finish().hex_encode()

func _document_hash(document: Dictionary) -> String:
	var c := HashingContext.new(); c.start(HashingContext.HASH_SHA256); c.update(JSON.stringify(_canonical(document)).to_utf8_buffer()); return c.finish().hex_encode()

func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		var keys: Array = value.keys(); keys.sort()
		for key in keys: out[str(key)] = _canonical(value[key])
		return out
	if value is Array:
		var result: Array = []
		for entry in value: result.append(_canonical(entry))
		return result
	if value is float and is_finite(value) and floor(value) == value: return int(value)
	return value

func _buffer_payload(buffer: Object) -> PackedByteArray:
	var bytes: PackedByteArray = buffer.get_channel_as_byte_array(M1PatchGenerator.CHANNEL_TYPE)
	return bytes

func _json_files(path: String) -> Array[String]:
	var out: Array[String] = []; var d := DirAccess.open(path)
	if d == null: return out
	d.list_dir_begin(); var n := d.get_next()
	while not n.is_empty():
		if n.begins_with("checkpoint_") and n.ends_with(".json") and not n.ends_with(".staged.json"): out.append(path.path_join(n))
		n = d.get_next()
	d.list_dir_end(); out.sort(); out.reverse(); return out

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
