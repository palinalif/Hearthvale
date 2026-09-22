extends Node3D
class_name M1GardenVisual

const Flora = preload("res://scripts/vegetation_mesh.gd")
const State = preload("res://scripts/landscape_state.gd")
const Scatter = preload("res://scripts/grass_tuft_scatter.gd")
const VEGETATION_WIND_SHADER = preload("res://shaders/vegetation_wind.gdshader")
## Native surface voxel type that carries the meadow tone (see M1PatchGenerator).
const MEADOW_GRASS_TYPE := 2
## Presentation fine cell for auto-scattered ground tufts (non-terrain).
const MEADOW_UNIT := 0.0625
## Keep auto tufts off hand-planted scenery by this half-extent (metres).
const MEADOW_RECORD_CLEARANCE := 0.35
const TREE_ROTATION_STEP := PI * 0.5
const TREE_TURN_COUNT := 4
const FOLIAGE_TURN_COUNT := 4
const TREE_WIND_STRENGTH := 0.18
const FOLIAGE_WIND_STRENGTHS := [0.05, 0.045, 0.05, 0.055, 0.04, 0.05, 0.075, 0.045, 0.0, 0.0, 0.0]
const MAX_WIND_STRENGTH := 0.18
const PROP_TINTS: Array[Color] = [
	Color(0.92, 0.97, 0.90),
	Color(0.96, 0.92, 0.88),
	Color.WHITE,
	Color(0.90, 0.94, 1.0),
	Color(1.0, 0.90, 0.94),
]
const PROP_TINT_SHADER_CODE := """
shader_type spatial;
render_mode diffuse_burley, specular_disabled;
uniform vec4 base_color : source_color;
void fragment() {
	ALBEDO = base_color.rgb * COLOR.rgb;
	// Solid voxel surfaces must stay in the opaque pipeline. Writing ALPHA,
	// even as 1.0, opts into transparency and changes depth/shadow behaviour.
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
}
"""
static var _prop_tint_shader: Shader
var _groups: Dictionary = {}
var wind_enabled := true
var _tuft_backend: Node
var _tuft_node: MeshInstance3D
var _tuft_last_key := ""
var _tuft_record_rects: Array = []
var _tuft_extra_rects: Array = []
## Current merged scatter plan (stable scan order), kept across exclusion-only
## changes so a single placement re-plans one region instead of the world.
var _tuft_plan: Array = []
var _tuft_last_revision := -1
var _tuft_last_exclusions: Array = []
## Per-fine-cell column-top cache; invalidated inside each terrain edit.
var _tuft_heights: Dictionary = {}
## Per-tuft vertex-block cache keyed by main fine cell; fingerprint-checked.
var _tuft_blocks: Dictionary = {}
var _tuft_material: StandardMaterial3D = null

func attach_backend(backend: Node) -> void:
	if backend != null and backend.has_signal("changed") and not backend.is_connected("changed", _on_meadow_terrain_changed):
		backend.connect("changed", _on_meadow_terrain_changed)
	if _tuft_backend != null and backend != _tuft_backend:
		if _tuft_backend.has_signal("changed") and _tuft_backend.is_connected("changed", _on_meadow_terrain_changed):
			_tuft_backend.disconnect("changed", _on_meadow_terrain_changed)
		# New world source: the kept plan and per-cell caches belong to the
		# old world regardless of what revision number the new one reports.
		_tuft_plan = []
		_tuft_last_revision = -1
		_tuft_last_exclusions = []
		_tuft_heights.clear()
		_tuft_blocks.clear()
		_tuft_last_key = ""
	_tuft_backend = backend
	_rebuild_meadow_tufts()

func refresh_terrain() -> void:
	# Saved roots do not relocate or resurrect automatically after edits; the
	# auto-scattered meadow tufts do, re-derived deterministically on each
	# terrain revision (see _rebuild_meadow_tufts).
	_rebuild_meadow_tufts()

func set_meadow_exclusions(rects: Array) -> void:
	_tuft_extra_rects = rects
	_rebuild_meadow_tufts()

func _on_meadow_terrain_changed() -> void:
	_rebuild_meadow_tufts()

func set_wind_enabled(enabled: bool) -> void:
	wind_enabled = enabled
	for key: String in _groups:
		var material := (_groups[key] as MultiMeshInstance3D).material_override as ShaderMaterial
		if material == null or material.shader != VEGETATION_WIND_SHADER: continue
		var kind := key.get_slice("_", 0)
		var variant := int(key.get_slice("_", 1))
		material.set_shader_parameter("wind_strength", wind_strength(kind, variant) if wind_enabled else 0.0)

func apply_records(records: Array) -> void:
	# Existing records keep their authored quarter-turn variation. Newly brushed
	# plants may also carry a saved yaw marker, which unlocks a deterministic
	# random 15-degree sub-turn without reshuffling old scenery.
	_tuft_record_rects.clear()
	for record: Dictionary in records:
		var planted := State.position_of(record)
		_tuft_record_rects.append(Rect2(planted.x - MEADOW_RECORD_CLEARANCE, planted.z - MEADOW_RECORD_CLEARANCE, MEADOW_RECORD_CLEARANCE * 2.0, MEADOW_RECORD_CLEARANCE * 2.0))
	var batches := {}
	for record: Dictionary in records:
		var kind := str(record["kind"]); var variant := posmod(int(record["seed"]), Flora.variant_count(kind))
		var meshes: Array = Flora.meshes(kind, variant)
		var animated := wind_strength(kind, variant) > 0.0
		var mesh_height := _mesh_group_height(meshes)
		for index in meshes.size():
			var key := "%s_%d_%d" % [kind, variant, index]
			if not batches.has(key): batches[key] = {"mesh": meshes[index], "transforms": [], "colors": [], "custom_data": [], "tinted": kind in ["foliage", "rock"], "animated": animated, "height": mesh_height, "strength": wind_strength(kind, variant)}
			batches[key]["transforms"].append(Transform3D(planting_rotation(record), State.position_of(record)))
			batches[key]["colors"].append(prop_instance_color(record))
			batches[key]["custom_data"].append(Color(wind_phase(record), 0.0, 0.0, 1.0))
	for key in batches:
		var batch: Dictionary = batches[key]
		if not _groups.has(key):
			var node := MultiMeshInstance3D.new(); node.name = "PlantBatch_" + key
			var multi := MultiMesh.new(); multi.transform_format = MultiMesh.TRANSFORM_3D; multi.use_colors = bool(batch["tinted"]) or bool(batch["animated"]); multi.use_custom_data = bool(batch["animated"]); multi.mesh = batch["mesh"]
			node.multimesh = multi
			if bool(batch["animated"]):
				node.material_override = _wind_material(batch["mesh"], float(batch["strength"]) if wind_enabled else 0.0, float(batch["height"]))
				node.extra_cull_margin = MAX_WIND_STRENGTH
			elif bool(batch["tinted"]): node.material_override = _prop_color_material(batch["mesh"])
			add_child(node); _groups[key] = node
		var node: MultiMeshInstance3D = _groups[key]
		var multi: MultiMesh = node.multimesh
		var transforms: Array = batch["transforms"]
		if multi.instance_count != transforms.size(): multi.instance_count = transforms.size()
		for index in transforms.size():
			multi.set_instance_transform(index, transforms[index])
			if multi.use_colors: multi.set_instance_color(index, batch["colors"][index])
			if multi.use_custom_data: multi.set_instance_custom_data(index, batch["custom_data"][index])
	for key in _groups:
		if not batches.has(key): _groups[key].multimesh.instance_count = 0
	_rebuild_meadow_tufts()

func reset_records(records: Array) -> void:
	apply_records(records)

func _rebuild_meadow_tufts() -> void:
	if _tuft_backend == null or not _tuft_backend.has_method("voxel_at"):
		return
	if _tuft_backend.has_method("is_ready") and not _tuft_backend.is_ready():
		return
	var key := _tuft_key()
	if key == _tuft_last_key:
		return
	_tuft_last_key = key
	var scale := maxf(0.001, float(_tuft_backend.get("voxel_scale")))
	var patch: Vector3i = _tuft_backend.get("patch_size")
	var world := Vector2(float(patch.x) * scale, float(patch.z) * scale)
	var revision := 0
	if _tuft_backend.has_method("revision"):
		revision = int(_tuft_backend.call("revision"))
	var exclusions: Array = []
	exclusions.append_array(_tuft_record_rects)
	exclusions.append_array(_tuft_extra_rects)
	if _tuft_last_revision < 0:
		_tuft_heights.clear()
		_tuft_blocks.clear()
		_tuft_plan = Scatter.plan(Vector2.ZERO, world, Scatter.DENSITY, exclusions)
	else:
		if revision != _tuft_last_revision:
			_invalidate_tuft_heights(revision)
		if _tuft_last_exclusions != exclusions:
			# Re-plan only the region affected by changed exclusions.
			_tuft_plan = _merge_exclusion_change(world, exclusions)
	_tuft_last_revision = revision
	_tuft_last_exclusions = exclusions.duplicate()
	_commit_tuft_mesh()

func _invalidate_tuft_heights(revision: int) -> void:
	# The scatter candidates depend on exclusions, not terrain. Keep the plan
	# and unchanged columns; cached geometry validates its heights on reuse.
	var bounds := AABB()
	if revision == _tuft_last_revision + 1 and _tuft_backend.has_method("get_last_edit_bounds"):
		bounds = _tuft_backend.get_last_edit_bounds()
	if not bounds.has_volume():
		_tuft_heights.clear()
		return
	var area := Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))
	for cell: Vector2i in _tuft_heights.keys():
		var point := (Vector2(cell) + Vector2.ONE * 0.5) * MEADOW_UNIT
		if area.has_point(point): _tuft_heights.erase(cell)

## Splice a region re-plan into the kept plan after an exclusion change.
## Scan order is (coarse z, then coarse x); the region span is the padded
## coarse bounding box of the changed rects. Kept entries outside the span
## are byte-identical to a full re-plan: their exclusion status cannot
## change (the span covers every changed rect) and the re-plan is seeded
## with their occupied fine cells, reproducing full-plan dedupe exactly.
func _merge_exclusion_change(world: Vector2, exclusions: Array) -> Array:
	var changed: Array = _exclusion_delta(_tuft_last_exclusions, exclusions)
	if changed.is_empty():
		return _tuft_plan
	# A capped plan cannot reconstruct its exact tail after removals; a full
	# re-plan is the only exact path there (worlds denser than MAX_TUFTS).
	if _tuft_plan.size() >= Scatter.MAX_TUFTS:
		return Scatter.plan(Vector2.ZERO, world, Scatter.DENSITY, exclusions)
	var coarse_max := Vector2i(int(ceili(world.x / Scatter.COARSE_STEP)), int(ceili(world.y / Scatter.COARSE_STEP)))
	var pad := 0.5
	var min_c := Vector2i(0, 0)
	var max_c := Vector2i(0, 0)
	var first_span := true
	for area: Variant in changed:
		var r := area as Rect2
		var x0 := int(floori((r.position.x - pad) / Scatter.COARSE_STEP))
		var y0 := int(floori((r.position.y - pad) / Scatter.COARSE_STEP))
		var x1 := int(ceili((r.position.x + r.size.x + pad) / Scatter.COARSE_STEP))
		var y1 := int(ceili((r.position.y + r.size.y + pad) / Scatter.COARSE_STEP))
		if first_span:
			min_c = Vector2i(x0, y0)
			max_c = Vector2i(x1, y1)
			first_span = false
		else:
			min_c.x = mini(min_c.x, x0)
			min_c.y = mini(min_c.y, y0)
			max_c.x = maxi(max_c.x, x1)
			max_c.y = maxi(max_c.y, y1)
	min_c.x = clampi(min_c.x, 0, coarse_max.x)
	min_c.y = clampi(min_c.y, 0, coarse_max.y)
	max_c.x = clampi(max_c.x, 0, coarse_max.x)
	max_c.y = clampi(max_c.y, 0, coarse_max.y)
	var before: Array = []
	var deferred_after: Array = []
	var seed: Dictionary = {}
	for tuft: Dictionary in _tuft_plan:
		var point: Vector2 = tuft["point"]
		var c := Vector2i(int(floori(point.x / Scatter.COARSE_STEP)), int(floori(point.y / Scatter.COARSE_STEP)))
		var in_region := c.x >= min_c.x and c.x < max_c.x and c.y >= min_c.y and c.y < max_c.y
		if not in_region:
			var cell: Vector2i = tuft["cell"]
			if c.y < min_c.y or (c.y == min_c.y and c.x < min_c.x):
				before.append(tuft)
				# Seed the region re-plan with earlier-in-scan cells only: the
				# full plan's occupied state at region start is exactly the
				# before cells (after cells are processed later, never before).
				seed[cell] = true
				if int(tuft["columns"][1]) > 0:
					seed[cell + tuft["step"]] = true
			else:
				deferred_after.append(tuft)
	var region := Scatter.plan(
		Vector2(float(min_c.x) * Scatter.COARSE_STEP, float(min_c.y) * Scatter.COARSE_STEP),
		Vector2(float(max_c.x - min_c.x) * Scatter.COARSE_STEP, float(max_c.y - min_c.y) * Scatter.COARSE_STEP),
		Scatter.DENSITY, exclusions, seed)
	# Kept later entries may now collide with cells the region just claimed
	# (a freed candidate earlier in scan took the cell they were deduped
	# against): drop the main cell entirely, or just its companion.
	var region_occupied: Dictionary = {}
	for tuft: Dictionary in region:
		region_occupied[tuft["cell"]] = true
		if int(tuft["columns"][1]) > 0:
			region_occupied[tuft["cell"] + tuft["step"]] = true
	var after: Array = []
	for tuft: Dictionary in deferred_after:
		var kept: Dictionary = tuft
		if int(tuft["columns"][1]) > 0 and region_occupied.has(tuft["cell"] + tuft["step"]):
			kept = {"cell": tuft["cell"], "point": tuft["point"], "columns": [int(tuft["columns"][0]), 0], "step": tuft["step"], "tone": tuft["tone"], "seed": tuft["seed"]}
		if not region_occupied.has(kept["cell"]):
			after.append(kept)
	var merged := before.duplicate()
	merged.append_array(region)
	merged.append_array(after)
	# The changed-rect span is a 2D box, not a contiguous interval in the
	# plan's row-major scan (cells outside the box but inside its row range
	# interleave with it), so the three parts are re-joined in true scan
	# order. Every entry's coarse cell is its unique scan position, so
	# sorting by (coarse y, coarse x) reproduces a fresh full plan's order
	# exactly (including the MAX_TUFTS truncation point).
	merged.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := Vector2i(int(floori((a["point"] as Vector2).x / Scatter.COARSE_STEP)), int(floori((a["point"] as Vector2).y / Scatter.COARSE_STEP)))
		var cb := Vector2i(int(floori((b["point"] as Vector2).x / Scatter.COARSE_STEP)), int(floori((b["point"] as Vector2).y / Scatter.COARSE_STEP)))
		return ca.y < cb.y or (ca.y == cb.y and ca.x < cb.x))
	if merged.size() > Scatter.MAX_TUFTS:
		merged = merged.slice(0, Scatter.MAX_TUFTS)
	return merged

func _exclusion_delta(old_value: Array, new_value: Array) -> Array:
	var changed: Array = []
	for area: Variant in old_value:
		if not _rect_present(new_value, area as Rect2):
			changed.append(area)
	var matched := 0
	for area: Variant in new_value:
		if _rect_present(old_value, area as Rect2): matched += 1
		else: changed.append(area)
	return changed

func _rect_present(haystack: Array, needle: Rect2) -> bool:
	for area: Variant in haystack:
		if (area as Rect2) == needle:
			return true
	return false

## Assemble the meadow mesh from the current plan. Per-tuft vertex blocks
## are cached (fingerprint-checked), so an exclusion-only change re-copies
## unchanged blocks instead of re-deriving box geometry.
func _commit_tuft_mesh() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var cells := 0
	for tuft: Dictionary in _tuft_plan:
		var cell: Vector2i = tuft["cell"]
		var step: Vector2i = tuft["step"]
		var columns: Array = tuft["columns"]
		var tone: Color = tuft["tone"]
		var root := _column_top_cached(cell)
		if is_nan(root):
			continue
		var companion_valid := true
		var companion_root := root
		if int(columns[1]) > 0:
			var companion := cell + step
			companion_root = _column_top_cached(companion)
			if is_nan(companion_root) or absf(companion_root - root) > MEADOW_UNIT * 2.0:
				companion_valid = false
		var fingerprint := "%d|%d|%d|%d|%.4f|%.4f|%d" % [int(columns[0]), int(columns[1]), step.x, step.y, root, companion_root, int(companion_valid)]
		var cached: Variant = _tuft_blocks.get(cell)
		var block: Dictionary
		if cached is Dictionary and (cached as Dictionary).get("fp") == fingerprint and (cached as Dictionary).get("tone") == tone:
			block = cached
		else:
			block = _build_tuft_block(cell, step, columns, tone, root, companion_valid, companion_root)
			block["fp"] = fingerprint
			block["tone"] = tone
			_tuft_blocks[cell] = block
		if (block["v"] as PackedVector3Array).is_empty():
			continue
		var index_base := vertices.size()
		vertices.append_array(block["v"])
		normals.append_array(block["n"])
		colors.append_array(block["c"])
		for local: int in block["i"]:
			indices.append(local + index_base)
		cells += int(block["count"])
	_clear_meadow_tuft_node()
	if cells > 0:
		var mesh := ArrayMesh.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if _tuft_material == null:
			_tuft_material = StandardMaterial3D.new()
			_tuft_material.vertex_color_use_as_albedo = true
			_tuft_material.vertex_color_is_srgb = true
			_tuft_material.roughness = 1.0
			_tuft_material.metallic_specular = 0.0
		mesh.surface_set_material(0, _tuft_material)
		var node := MeshInstance3D.new()
		node.name = "MeadowTufts"
		node.mesh = mesh
		add_child(node)
		_tuft_node = node

func _column_top_cached(cell: Vector2i) -> float:
	var v: Variant = _tuft_heights.get(cell)
	if v != null:
		return float(v)
	var top := _meadow_column_top((cell.x + 0.5) * MEADOW_UNIT, (cell.y + 0.5) * MEADOW_UNIT)
	_tuft_heights[cell] = top
	return top

func _build_tuft_block(cell: Vector2i, step: Vector2i, columns: Array, tone: Color, root: float, companion_valid: bool, companion_root: float) -> Dictionary:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()
	var base := 0
	var count := 0
	var companion := cell + step
	for column_index in 2:
		var height := int(columns[column_index])
		if height <= 0:
			continue
		if column_index == 1 and not companion_valid:
			continue
		var column_cell := cell if column_index == 0 else companion
		var column_root := root if column_index == 0 else companion_root
		for level in height:
			var center := Vector3((column_cell.x + 0.5) * MEADOW_UNIT, column_root + (float(level) + 0.5) * MEADOW_UNIT, (column_cell.y + 0.5) * MEADOW_UNIT)
			base = _append_tuft_box(v, n, c, i, base, center, tone)
			count += 1
	return {"v": v, "n": n, "c": c, "i": i, "count": count}

func _tuft_key() -> String:
	var revision := 0
	if _tuft_backend.has_method("revision"):
		revision = int(_tuft_backend.call("revision"))
	return "%d|%s" % [revision, _exclusion_digest()]

func _exclusion_digest() -> String:
	var payload: Array = []
	for area: Variant in _tuft_record_rects:
		if area is Rect2:
			payload.append([snappedf((area as Rect2).position.x, 0.01), snappedf((area as Rect2).position.y, 0.01), snappedf((area as Rect2).size.x, 0.01), snappedf((area as Rect2).size.y, 0.01)])
	for area: Variant in _tuft_extra_rects:
		if area is Rect2:
			payload.append([snappedf((area as Rect2).position.x, 0.01), snappedf((area as Rect2).position.y, 0.01), snappedf((area as Rect2).size.x, 0.01), snappedf((area as Rect2).size.y, 0.01)])
	return var_to_bytes(payload).hex_encode().sha256_text()

func _meadow_column_top(x: float, z: float) -> float:
	if _tuft_backend == null:
		return NAN
	var scale := maxf(0.001, float(_tuft_backend.get("voxel_scale")))
	var patch: Vector3i = _tuft_backend.get("patch_size")
	var vx := int(floori(x / scale))
	var vz := int(floori(z / scale))
	if vx < 0 or vz < 0 or vx >= patch.x or vz >= patch.z:
		return NAN
	for y in range(patch.y - 2, -1, -1):
		var top := int(_tuft_backend.voxel_at(Vector3i(vx, y, vz)))
		if top != 0 and int(_tuft_backend.voxel_at(Vector3i(vx, y + 1, vz))) == 0:
			return float(y + 1) * scale if top == MEADOW_GRASS_TYPE else NAN
	return NAN

func _clear_meadow_tuft_node() -> void:
	if _tuft_node != null and is_instance_valid(_tuft_node):
		_tuft_node.queue_free()
	_tuft_node = null

func _append_tuft_box(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, base: int, center: Vector3, tone: Color) -> int:
	var size := Vector3.ONE * MEADOW_UNIT
	var half := size * 0.5
	var faces := [
		[Vector3.UP, [Vector3(-half.x, half.y, -half.z), Vector3(half.x, half.y, -half.z), Vector3(half.x, half.y, half.z), Vector3(-half.x, half.y, half.z)]],
		[Vector3.DOWN, [Vector3(-half.x, -half.y, half.z), Vector3(half.x, -half.y, half.z), Vector3(half.x, -half.y, -half.z), Vector3(-half.x, -half.y, -half.z)]],
		[Vector3.FORWARD, [Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z), Vector3(half.x, half.y, -half.z), Vector3(-half.x, half.y, -half.z)]],
		[Vector3.BACK, [Vector3(half.x, -half.y, half.z), Vector3(-half.x, -half.y, half.z), Vector3(-half.x, half.y, half.z), Vector3(half.x, half.y, half.z)]],
		[Vector3.LEFT, [Vector3(-half.x, -half.y, half.z), Vector3(-half.x, -half.y, -half.z), Vector3(-half.x, half.y, -half.z), Vector3(-half.x, half.y, half.z)]],
		[Vector3.RIGHT, [Vector3(half.x, -half.y, half.z), Vector3(half.x, -half.y, -half.z), Vector3(half.x, half.y, -half.z), Vector3(half.x, half.y, half.z)]],
	]
	for face: Array in faces:
		var normal: Vector3 = face[0]
		var corners: Array = face[1]
		for corner: Vector3 in corners:
			vertices.append(center + corner)
			normals.append(normal)
			colors.append(tone)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
		base += 4
	return base

static func planting_rotation(record: Dictionary) -> Basis:
	if not str(record.get("kind", "")) in ["tree", "foliage"]: return Basis.IDENTITY
	var step := TREE_ROTATION_STEP if str(record.get("kind", "")) == "tree" else PI * 0.5
	var angle := float(planting_turn(record)) * step
	if record.has("yaw_degrees"):
		var fine_turn := posmod(floori(float(_variation_hash(record)) / 4.0), 6)
		angle += deg_to_rad(float(fine_turn) * 15.0 + float(record.get("yaw_degrees", 0.0)))
	return Basis(Vector3.UP, angle)

static func planting_turn(record: Dictionary) -> int:
	var count := TREE_TURN_COUNT if str(record.get("kind", "")) == "tree" else FOLIAGE_TURN_COUNT
	return posmod(_variation_hash(record), count)

static func prop_tint_slot(record: Dictionary) -> int:
	return posmod(floori(float(_variation_hash(record)) / float(FOLIAGE_TURN_COUNT)), PROP_TINTS.size())

static func prop_instance_color(record: Dictionary) -> Color:
	return PROP_TINTS[prop_tint_slot(record)] if str(record.get("kind", "")) in ["foliage", "rock"] else Color.WHITE

static func wind_phase(record: Dictionary) -> float:
	return float(posmod(_variation_hash(record) * 37 + 11, 1024)) / 1024.0

static func wind_strength(kind: String, variant: int) -> float:
	if kind == "tree": return TREE_WIND_STRENGTH
	if kind == "foliage" and variant >= 0 and variant < FOLIAGE_WIND_STRENGTHS.size(): return FOLIAGE_WIND_STRENGTHS[variant]
	return 0.0

static func _variation_hash(record: Dictionary) -> int:
	var point := State.position_of(record)
	var x_cell := roundi(point.x / 0.125)
	var z_cell := roundi(point.z / 0.125)
	return posmod(int(record.get("seed", 0)) * 31 + int(record.get("id", 0)) * 17 + x_cell * 7 + z_cell * 13, 1000003)

static func _prop_color_material(mesh: Mesh) -> Material:
	var source := mesh.surface_get_material(0) as StandardMaterial3D
	if source == null: return mesh.surface_get_material(0)
	if _prop_tint_shader == null:
		_prop_tint_shader = Shader.new()
		_prop_tint_shader.code = PROP_TINT_SHADER_CODE
	var tinted := ShaderMaterial.new()
	tinted.shader = _prop_tint_shader
	tinted.set_shader_parameter("base_color", source.albedo_color)
	return tinted

static func _wind_material(mesh: Mesh, strength: float, height: float) -> Material:
	var source := mesh.surface_get_material(0) as StandardMaterial3D
	if source == null: return mesh.surface_get_material(0)
	var material := ShaderMaterial.new()
	material.shader = VEGETATION_WIND_SHADER
	material.set_shader_parameter("base_color", source.albedo_color)
	material.set_shader_parameter("wind_strength", strength)
	material.set_shader_parameter("mesh_height", height)
	return material

static func _mesh_group_height(meshes: Array) -> float:
	var height := 0.0625
	for mesh: Mesh in meshes: height = maxf(height, mesh.get_aabb().end.y)
	return height
