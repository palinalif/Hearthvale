extends Node3D
## Three batched, depth-tested layers. No per-cell scene nodes and no x-ray
## removal highlight that would falsely target a distant wall through a cave.
const ADD_COLOR := Color("#b1e6be")
const REMOVE_COLOR := Color("#efaa70")
var reach: MultiMeshInstance3D
var additions: MultiMeshInstance3D
var removals: MultiMeshInstance3D
var last_build_ms := 0.0
var change_count := 0

func _ready() -> void:
	_ensure_nodes()

func _ensure_nodes() -> void:
	if reach: return
	reach = _batch("BrushReach", false, Color("#cfdfdd"), 0)
	removals = _batch("RemoveHatching", false, REMOVE_COLOR, 1)
	additions = _batch("AddGhosts", true, ADD_COLOR, 2)

func _batch(label: String, cube: bool, color: Color, pattern: int) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.mesh = BoxMesh.new() if cube else QuadMesh.new()
	if cube: (instances.mesh as BoxMesh).size = Vector3.ONE
	else: (instances.mesh as QuadMesh).size = Vector2.ONE
	node.multimesh = instances
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color;
uniform int pattern = 0;
void fragment() {
	vec2 p = abs(UV - vec2(0.5));
	float edge = max(p.x, p.y);
	bool mark = edge > 0.43;
	if (pattern == 1) { mark = mark || fract((UV.x + UV.y) * 3.0) < 0.23; }
	if (pattern == 2) { mark = mark || (min(p.x, p.y) < 0.045 && max(p.x, p.y) < 0.20); }
	if (!mark) { discard; }
	ALBEDO = tint.rgb;
	ALPHA = tint.a * COLOR.a;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tint", Color(color, 0.32 if pattern == 0 else 0.82))
	material.set_shader_parameter("pattern", pattern)
	node.material_override = material
	add_child(node)
	return node

func show_plan(plan: Dictionary) -> void:
	_ensure_nodes()
	var started := Time.get_ticks_usec()
	var unit: float = plan.get("cell_size", 0.125)
	var normal: Vector3 = plan.get("normal", Vector3.UP)
	var face_basis := Basis(Quaternion(Vector3.BACK, normal))
	var changes: Array = plan.get("changes", [])
	var plus: Array[Transform3D] = []
	var minus: Array[Transform3D] = []
	var plus_weights: Array[float] = []
	var minus_weights: Array[float] = []
	for change in changes:
		var cell: Vector3i = change["cell"]
		var center := (Vector3(cell) + Vector3.ONE * 0.5) * unit
		var weight := lerpf(0.4, 1.0, sqrt(clampf(float(change["weight"]), 0.0, 1.0)))
		if int(change["after"]) == 0:
			minus.append(Transform3D(face_basis.scaled(Vector3.ONE * unit), center + normal * unit * 0.515))
			minus_weights.append(weight)
		else:
			plus.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * unit * 1.015), center))
			plus_weights.append(weight)
	var border: Array[Transform3D] = []
	for point in plan.get("rim", []):
		border.append(Transform3D(face_basis.scaled(Vector3.ONE * unit), point + normal * unit * 0.02))
	_update_batch(reach, border, [])
	_update_batch(removals, minus, minus_weights)
	_update_batch(additions, plus, plus_weights)
	change_count = changes.size()
	visible = bool(plan.get("valid", false))
	last_build_ms = (Time.get_ticks_usec() - started) / 1000.0

func _update_batch(node: MultiMeshInstance3D, transforms: Array[Transform3D], weights: Array[float]) -> void:
	var mesh := node.multimesh
	# Grow in chunks and reuse storage across edit ticks; no allocation for an
	# unchanged plan. At most one candidate per native brush column is drawn.
	if transforms.size() > mesh.instance_count:
		mesh.instance_count = ceili(float(transforms.size()) / 256.0) * 256
	mesh.visible_instance_count = transforms.size()
	for i in transforms.size():
		mesh.set_instance_transform(i, transforms[i])
		mesh.set_instance_color(i, Color(1, 1, 1, weights[i] if i < weights.size() else 1.0))
	node.visible = not transforms.is_empty()
