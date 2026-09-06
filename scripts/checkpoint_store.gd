extends RefCounted
class_name CheckpointStore

const ROOT := "user://checkpoints"
const SCHEMA := 2
const LEGACY_SCHEMA := 1
const KEEP_GENERATIONS := 2
const DIMENSIONS := Vector3i(48, 32, 48)
const MAX_MANIFEST_BYTES := 16 * 1024
const MAX_PAYLOAD_BYTES := DIMENSIONS.x * DIMENSIONS.y * DIMENSIONS.z * 2
const GENERATION_RE := "^checkpoint_([0-9]{16,})\\.(json|bin)$"
const PatchGenerator := preload("res://scripts/patch_generator.gd")

var root_path: String = ROOT
var last_error := ""
var loaded_revision := -1

func _init(test_root: String = "") -> void:
	if not test_root.is_empty(): root_path = test_root

func save(buffer: Object, revision: int, generator_id: String) -> bool:
	last_error = ""; loaded_revision = -1
	if revision < 0: return _fail("invalid revision")
	if buffer == null or not buffer.has_method("get_voxel"): return _fail("invalid voxel buffer")
	if not buffer.has_method("get_size") or buffer.get_size() != DIMENSIONS: return _fail("invalid voxel dimensions")
	if generator_id != PatchGenerator.GENERATOR_ID: return _fail("generator")
	var payload := _encode(buffer)
	if payload.size() != MAX_PAYLOAD_BYTES: return _fail("payload encoding")
	var absolute := ProjectSettings.globalize_path(root_path)
	if DirAccess.make_dir_recursive_absolute(absolute) != OK: return _fail("cannot create checkpoint root")
	var generation := _next_generation(absolute)
	if generation.is_empty(): return _fail("generation exhausted")
	var base := root_path.path_join("checkpoint_%s" % generation)
	while _generation_paths_exist(base):
		generation = _increment_generation(generation)
		if generation.is_empty(): return _fail("generation exhausted")
		base = root_path.path_join("checkpoint_%s" % generation)
	var staged_data := base + ".staged.bin"
	var final_data := base + ".bin"
	var staged_manifest := base + ".staged.json"
	var final_manifest := base + ".json"
	var f := FileAccess.open(staged_data, FileAccess.WRITE)
	if f == null: return _fail("cannot open staged data")
	f.store_buffer(payload); f.flush(); f.close()
	if not _verify_data_file(staged_data, payload): return _fail("staged data verification failed")
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(staged_data), ProjectSettings.globalize_path(final_data)) != OK: return _fail("data rename failed")
	var manifest := {"schema": SCHEMA, "generator_id": generator_id, "revision": revision, "size": [DIMENSIONS.x, DIMENSIONS.y, DIMENSIONS.z], "payload_bytes": MAX_PAYLOAD_BYTES, "payload_layout": "voxelbuffer_channel_raw_zxy", "channel": PatchGenerator.CHANNEL_TYPE, "depth": 1, "sha256": _hash(payload), "generation": generation}
	var manifest_text := JSON.stringify(manifest)
	f = FileAccess.open(staged_manifest, FileAccess.WRITE)
	if f == null: return _fail("cannot open staged manifest")
	f.store_string(manifest_text); f.flush(); f.close()
	var staged_check := _validate_candidate({"generation": generation, "manifest": staged_manifest, "data": final_data})
	if not staged_check["valid"]: return _fail("staged manifest verification failed: %s" % staged_check["error"])
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(staged_manifest), ProjectSettings.globalize_path(final_manifest)) != OK: return _fail("manifest rename failed")
	_gc()
	return true

func load(revision: int = -1) -> Object:
	last_error = ""; loaded_revision = -1
	if revision < -1: last_error = "invalid revision"; return null
	var saw_candidate := false
	for item in _candidates():
		var result: Dictionary = _validate_candidate(item)
		if not result["valid"]:
			last_error = result["error"]
			continue
		saw_candidate = true
		var manifest: Dictionary = result["manifest"]
		var candidate_revision: int = manifest["revision"]
		if revision >= 0 and candidate_revision != revision: continue
		var f := FileAccess.open(item["data"], FileAccess.READ)
		if f == null: last_error = "data open"; continue
		var payload := f.get_buffer(MAX_PAYLOAD_BYTES); f.close()
		var buffer: Object = _decode(payload, int(manifest["schema"]))
		if buffer == null: last_error = "VoxelBuffer unavailable"; continue
		loaded_revision = candidate_revision
		return buffer
	if not saw_candidate: last_error = "no valid checkpoint" if last_error.is_empty() else last_error
	elif revision >= 0: last_error = "no checkpoint for revision %d" % revision
	return null

func _candidates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []; var d := DirAccess.open(root_path)
	if d == null: return out
	var rx := RegEx.new(); rx.compile(GENERATION_RE)
	d.list_dir_begin(); var n := d.get_next()
	while not n.is_empty():
		var m := rx.search(n)
		if m != null:
			var generation: String = m.get_string(1); var base := root_path.path_join("checkpoint_%s" % generation); var found := false
			for existing in out:
				if existing["generation"] == generation: found = true; break
			if not found: out.append({"generation": generation, "manifest": base + ".json", "data": base + ".bin"})
		n = d.get_next()
	d.list_dir_end(); out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _generation_newer(a["generation"], b["generation"]))
	return out

func _validate_candidate(item: Dictionary) -> Dictionary:
	var invalid := func(reason: String) -> Dictionary: return {"valid": false, "error": reason, "manifest": {}}
	if not FileAccess.file_exists(item["manifest"]): return invalid.call("manifest missing")
	var mf := FileAccess.open(item["manifest"], FileAccess.READ)
	if mf == null: return invalid.call("manifest open")
	if mf.get_length() > MAX_MANIFEST_BYTES: mf.close(); return invalid.call("manifest too large")
	var parsed = JSON.parse_string(mf.get_as_text()); mf.close()
	if not parsed is Dictionary: return invalid.call("manifest schema")
	if not _is_exact_int(parsed.get("schema", null), SCHEMA) and not _is_exact_int(parsed.get("schema", null), LEGACY_SCHEMA): return invalid.call("manifest schema")
	if typeof(parsed.get("generator_id", null)) != TYPE_STRING or parsed["generator_id"] != PatchGenerator.GENERATOR_ID: return invalid.call("generator")
	if not _is_integer(parsed.get("revision", null)) or int(parsed["revision"]) < 0: return invalid.call("revision")
	var dims = parsed.get("size", null)
	if not dims is Array or dims.size() != 3: return invalid.call("dimensions")
	var expected_dims := [DIMENSIONS.x, DIMENSIONS.y, DIMENSIONS.z]
	for i in 3:
		if not _is_exact_int(dims[i], expected_dims[i]): return invalid.call("dimensions")
	if not _is_exact_int(parsed.get("payload_bytes", null), MAX_PAYLOAD_BYTES): return invalid.call("payload bytes")
	var schema: int = int(parsed["schema"])
	if schema == SCHEMA:
		if parsed.get("payload_layout", null) != "voxelbuffer_channel_raw_zxy" or not _is_exact_int(parsed.get("channel", null), PatchGenerator.CHANNEL_TYPE) or not _is_exact_int(parsed.get("depth", null), 1): return invalid.call("payload layout")
	if typeof(parsed.get("sha256", null)) != TYPE_STRING or not _is_sha256(parsed["sha256"]): return invalid.call("hash")
	if typeof(parsed.get("generation", null)) != TYPE_STRING or parsed["generation"] != item["generation"]: return invalid.call("generation")
	var f := FileAccess.open(item["data"], FileAccess.READ)
	if f == null: return invalid.call("data missing")
	if f.get_length() != MAX_PAYLOAD_BYTES: f.close(); return invalid.call("data length")
	var payload := f.get_buffer(MAX_PAYLOAD_BYTES); f.close()
	if _hash(payload) != parsed["sha256"]: return invalid.call("hash")
	return {"valid": true, "error": "", "manifest": parsed}

func _verify_data_file(path: String, expected: PackedByteArray) -> bool:
	var r := FileAccess.open(path, FileAccess.READ)
	if r == null or r.get_length() != expected.size():
		if r != null: r.close()
		return false
	var bytes := r.get_buffer(expected.size()); r.close(); return _hash(bytes) == _hash(expected)

func _gc() -> void:
	var candidates := _candidates(); var valid_generations: Array[String] = []
	for item in candidates:
		var result: Dictionary = _validate_candidate(item)
		if result["valid"]: valid_generations.append(item["generation"])
	for item in candidates:
		var keep := false
		for i in mini(KEEP_GENERATIONS, valid_generations.size()):
			if item["generation"] == valid_generations[i]: keep = true; break
		if not keep:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(item["manifest"]))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(item["data"]))

func _next_generation(absolute: String) -> String:
	var d := DirAccess.open(absolute); if d == null: return ""
	var rx := RegEx.new(); rx.compile("^checkpoint_([0-9]{16,})(?:\\.(?:json|bin)|\\.staged\\.(?:json|bin))$")
	var highest := "0000000000000000"
	d.list_dir_begin(); var n := d.get_next()
	while not n.is_empty():
		var m := rx.search(n)
		if m != null and _generation_newer(m.get_string(1), highest): highest = m.get_string(1)
		n = d.get_next()
	d.list_dir_end(); return _increment_generation(highest)

func _increment_generation(value: String) -> String:
	var numeric := int(value)
	if numeric >= 9223372036854775806: return ""
	return "%016d" % (numeric + 1)

func _generation_newer(a: String, b: String) -> bool:
	var aa := a.lstrip("0"); var bb := b.lstrip("0")
	if aa.is_empty(): aa = "0"
	if bb.is_empty(): bb = "0"
	return aa.length() > bb.length() or (aa.length() == bb.length() and aa > bb)

func _generation_paths_exist(base: String) -> bool:
	return FileAccess.file_exists(base + ".json") or FileAccess.file_exists(base + ".bin") or FileAccess.file_exists(base + ".staged.json") or FileAccess.file_exists(base + ".staged.bin")

func _encode(buffer: Object) -> PackedByteArray:
	if not buffer.has_method("get_channel_as_byte_array") or not buffer.has_method("get_channel_depth"):
		return PackedByteArray()
	if int(buffer.get_channel_depth(PatchGenerator.CHANNEL_TYPE)) != 1:
		return PackedByteArray()
	var native_bytes: PackedByteArray = buffer.get_channel_as_byte_array(PatchGenerator.CHANNEL_TYPE)
	if native_bytes.size() != MAX_PAYLOAD_BYTES:
		return PackedByteArray()
	return native_bytes

func _decode(payload: PackedByteArray, schema: int) -> Object:
	var buffer: Object = ClassDB.instantiate("VoxelBuffer")
	if buffer == null: return null
	buffer.create(DIMENSIONS.x, DIMENSIONS.y, DIMENSIONS.z)
	if schema == SCHEMA and buffer.has_method("set_channel_from_byte_array"):
		buffer.set_channel_depth(PatchGenerator.CHANNEL_TYPE, 1)
		buffer.set_channel_from_byte_array(PatchGenerator.CHANNEL_TYPE, payload)
		return buffer
	if schema == SCHEMA: return null
	var offset := 0
	for x in DIMENSIONS.x:
		for y in DIMENSIONS.y:
			for z in DIMENSIONS.z:
				buffer.set_voxel(payload.decode_u16(offset), x, y, z, PatchGenerator.CHANNEL_TYPE); offset += 2
	return buffer

func _is_sha256(value: String) -> bool:
	if value.length() != 64: return false
	var rx := RegEx.new(); rx.compile("^[0-9a-f]{64}$"); return rx.search(value) != null

func _is_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and floor(value) == value)

func _is_exact_int(value: Variant, expected: int) -> bool:
	return _is_integer(value) and int(value) == expected

func _hash(payload: PackedByteArray) -> String:
	var c := HashingContext.new(); c.start(HashingContext.HASH_SHA256); c.update(payload); return c.finish().hex_encode()

func _fail(message: String) -> bool:
	last_error = message; return false
