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
	var packed: Dictionary = plan.get("packed", {})
	# Synchronous compatibility route for direct tests; gameplay supplies
	# already packed CPU buffers from its isolated preview worker.
	if packed.is_empty(): packed = preload("res://scripts/terrain_preview_buffers.gd").pack(plan)
	var nodes := [reach, removals, additions]
	for i in nodes.size():
		var node: MultiMeshInstance3D = nodes[i]
		var count := int(packed["counts"][i])
		var mesh := node.multimesh
		if mesh.instance_count != count: mesh.instance_count = count
		mesh.custom_aabb = packed["bounds"]
		if count > 0: mesh.buffer = packed["buffers"][i]
		mesh.visible_instance_count = count
		node.visible = count > 0
	change_count = packed["cells"].size()
	visible = bool(plan.get("valid", false))
	last_build_ms = (Time.get_ticks_usec() - started) / 1000.0
