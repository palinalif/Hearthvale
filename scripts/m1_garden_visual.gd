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

func attach_backend(backend: Node) -> void:
	_tuft_backend = backend
	if backend != null and backend.has_signal("changed") and not backend.is_connected("changed", _on_meadow_terrain_changed):
		backend.connect("changed", _on_meadow_terrain_changed)
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
	var exclusions: Array = []
	exclusions.append_array(_tuft_record_rects)
	exclusions.append_array(_tuft_extra_rects)
	var plan := Scatter.plan(Vector2.ZERO, world, Scatter.DENSITY, exclusions)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var base := 0
	var tufts := 0
	var cells := 0
	for tuft: Dictionary in plan:
		var cell: Vector2i = tuft["cell"]
		var step: Vector2i = tuft["step"]
		var columns: Array = tuft["columns"]
		var tone: Color = tuft["tone"]
		var root := _meadow_column_top((cell.x + 0.5) * MEADOW_UNIT, (cell.y + 0.5) * MEADOW_UNIT)
		if is_nan(root):
			continue
		var companion_valid := true
		var companion_root := root
		if int(columns[1]) > 0:
			var companion := cell + step
			companion_root = _meadow_column_top((companion.x + 0.5) * MEADOW_UNIT, (companion.y + 0.5) * MEADOW_UNIT)
			if is_nan(companion_root) or absf(companion_root - root) > MEADOW_UNIT * 2.0:
				companion_valid = false
		for column_index in 2:
			var height := int(columns[column_index])
			if height <= 0:
				continue
			if column_index == 1 and not companion_valid:
				continue
			var column_cell := cell if column_index == 0 else cell + step
			var column_root := root if column_index == 0 else companion_root
			for level in height:
				var center := Vector3((column_cell.x + 0.5) * MEADOW_UNIT, column_root + (float(level) + 0.5) * MEADOW_UNIT, (column_cell.y + 0.5) * MEADOW_UNIT)
				base = _append_tuft_box(vertices, normals, colors, indices, base, center, tone)
				cells += 1
		tufts += 1
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
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
		material.roughness = 1.0
		material.metallic_specular = 0.0
		mesh.surface_set_material(0, material)
		var node := MeshInstance3D.new()
		node.name = "MeadowTufts"
		node.mesh = mesh
		add_child(node)
		_tuft_node = node

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
