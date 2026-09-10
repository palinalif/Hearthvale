extends Node3D
class_name M1GardenVisual

const Flora = preload("res://scripts/vegetation_mesh.gd")
const State = preload("res://scripts/landscape_state.gd")
const VEGETATION_WIND_SHADER = preload("res://shaders/vegetation_wind.gdshader")
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
	ALPHA = base_color.a * COLOR.a;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
}
"""
static var _prop_tint_shader: Shader
var _groups: Dictionary = {}
var wind_enabled := true

func attach_backend(_backend: Node) -> void:
	pass

func refresh_terrain() -> void:
	pass # Saved roots do not relocate or resurrect automatically after edits.

func set_wind_enabled(enabled: bool) -> void:
	wind_enabled = enabled
	for key: String in _groups:
		var material := (_groups[key] as MultiMeshInstance3D).material_override as ShaderMaterial
		if material == null or material.shader != VEGETATION_WIND_SHADER: continue
		var kind := key.get_slice("_", 0)
		var variant := int(key.get_slice("_", 1))
		material.set_shader_parameter("wind_strength", wind_strength(kind, variant) if wind_enabled else 0.0)

func apply_records(records: Array) -> void:
	# Trees return to quarter turns so their authored dense canopy views remain
	# intact; arbitrary 15-degree yaw exposed intentional interior cavities.
	# Foliage also keeps quarter turns, while per-instance colors vary foliage
	# and rocks without extra draws.
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

func reset_records(records: Array) -> void:
	apply_records(records)

static func planting_rotation(record: Dictionary) -> Basis:
	if not str(record.get("kind", "")) in ["tree", "foliage"]: return Basis.IDENTITY
	var step := TREE_ROTATION_STEP if str(record.get("kind", "")) == "tree" else PI * 0.5
	return Basis(Vector3.UP, float(planting_turn(record)) * step)

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
