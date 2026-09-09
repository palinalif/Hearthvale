extends Node3D
class_name M1GardenVisual

const Flora = preload("res://scripts/vegetation_mesh.gd")
const State = preload("res://scripts/landscape_state.gd")
const PLANTING_TURN_COUNT := 4
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

func attach_backend(_backend: Node) -> void:
	pass

func refresh_terrain() -> void:
	pass # Saved roots do not relocate or resurrect automatically after edits.

func apply_records(records: Array) -> void:
	# Quarter turns keep authored cells on-grid while breaking up repeated
	# silhouettes. Per-instance colors vary foliage and rocks without extra draws.
	var batches := {}
	for record: Dictionary in records:
		var kind := str(record["kind"]); var variant := posmod(int(record["seed"]), Flora.variant_count(kind))
		var meshes: Array = Flora.meshes(kind, variant)
		for index in meshes.size():
			var key := "%s_%d_%d" % [kind, variant, index]
			if not batches.has(key): batches[key] = {"mesh": meshes[index], "transforms": [], "colors": [], "tinted": kind in ["foliage", "rock"]}
			batches[key]["transforms"].append(Transform3D(planting_rotation(record), State.position_of(record)))
			batches[key]["colors"].append(prop_instance_color(record))
	for key in batches:
		var batch: Dictionary = batches[key]
		if not _groups.has(key):
			var node := MultiMeshInstance3D.new(); node.name = "PlantBatch_" + key
			var multi := MultiMesh.new(); multi.transform_format = MultiMesh.TRANSFORM_3D; multi.use_colors = bool(batch["tinted"]); multi.mesh = batch["mesh"]
			node.multimesh = multi
			if bool(batch["tinted"]): node.material_override = _prop_color_material(batch["mesh"])
			add_child(node); _groups[key] = node
		var node: MultiMeshInstance3D = _groups[key]
		var multi: MultiMesh = node.multimesh
		var transforms: Array = batch["transforms"]
		if multi.instance_count != transforms.size(): multi.instance_count = transforms.size()
		for index in transforms.size():
			multi.set_instance_transform(index, transforms[index])
			if multi.use_colors: multi.set_instance_color(index, batch["colors"][index])
	for key in _groups:
		if not batches.has(key): _groups[key].multimesh.instance_count = 0

func reset_records(records: Array) -> void:
	apply_records(records)

static func planting_rotation(record: Dictionary) -> Basis:
	if not str(record.get("kind", "")) in ["tree", "foliage"]: return Basis.IDENTITY
	return Basis(Vector3.UP, float(planting_turn(record)) * PI * 0.5)

static func planting_turn(record: Dictionary) -> int:
	return posmod(_variation_hash(record), PLANTING_TURN_COUNT)

static func prop_tint_slot(record: Dictionary) -> int:
	return posmod(floori(float(_variation_hash(record)) / float(PLANTING_TURN_COUNT)), PROP_TINTS.size())

static func prop_instance_color(record: Dictionary) -> Color:
	return PROP_TINTS[prop_tint_slot(record)] if str(record.get("kind", "")) in ["foliage", "rock"] else Color.WHITE

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
