extends Node3D
class_name M1CursorReticle

## Renderer-only aiming feedback for the M1 terrain tools. The footprint is a
## thin diamond so it stays legible at miniature scale without becoming a
## second, thick brush volume. A low-alpha duplicate remains visible through
## occlusion, while the bright line is depth-tested against the terrain.

const VALID_COLOR := Color("#ffd27a")
const INVALID_COLOR := Color("#ff8d76")
const OCCLUDED_ALPHA := 0.28
const MIN_SCREEN_PIXELS := 18.0
const FOOTPRINT_RATIO := 0.72
const CENTER_RATIO := 0.34
const CENTER_OUTLINE := 0.08
const DARK_OUTLINE := Color("#40352d")

var _depth_mesh: MeshInstance3D
var _occluded_mesh: MeshInstance3D
var _center_mesh: MeshInstance3D
var _occluded_center_mesh: MeshInstance3D
var _center_outline_mesh: MeshInstance3D
var _occluded_center_outline_mesh: MeshInstance3D
var _depth_material: StandardMaterial3D
var _occluded_material: StandardMaterial3D
var _center_material: StandardMaterial3D
var _occluded_center_material: StandardMaterial3D
var _center_outline_material: StandardMaterial3D
var _occluded_center_outline_material: StandardMaterial3D
var _diamond_cache: Dictionary = {}
var _center_cache: Dictionary = {}
var _center_outline_cache: Dictionary = {}

func _ready() -> void:
	_ensure_nodes()

func set_target_visible(visible_target: bool) -> void:
	_ensure_nodes()
	visible = visible_target

func update_target(world_point: Vector3, world_normal: Vector3, radius: float, tool: String, camera: Camera3D, valid: bool = true) -> void:
	_ensure_nodes()
	if camera == null or not world_point.is_finite():
		set_target_visible(false)
		return
	var normal := world_normal.normalized() if world_normal.is_finite() and world_normal.length_squared() > 0.001 else Vector3.UP
	var world_radius := _readable_world_radius(camera, world_point, radius)
	var footprint_radius := maxf(world_radius * FOOTPRINT_RATIO, 0.08)
	var center_radius := maxf(world_radius * CENTER_RATIO, 0.08)
	position = world_point + normal * 0.035
	rotation = Quaternion(Vector3.UP, normal).get_euler()
	var footprint_key := "%.2f" % footprint_radius
	var center_key := "%.2f" % center_radius
	var outline_key := "%.2f" % (center_radius + CENTER_OUTLINE)
	if not _diamond_cache.has(footprint_key): _diamond_cache[footprint_key] = _diamond_mesh(footprint_radius)
	if not _center_cache.has(center_key): _center_cache[center_key] = _diamond_mesh(center_radius)
	if not _center_outline_cache.has(outline_key): _center_outline_cache[outline_key] = _diamond_mesh(center_radius + CENTER_OUTLINE)
	_depth_mesh.mesh = _diamond_cache[footprint_key]
	_occluded_mesh.mesh = _diamond_cache[footprint_key]
	_center_mesh.mesh = _center_cache[center_key]
	_occluded_center_mesh.mesh = _center_cache[center_key]
	_center_outline_mesh.mesh = _center_outline_cache[outline_key]
	_occluded_center_outline_mesh.mesh = _center_outline_cache[outline_key]
	var screen_right := camera.global_transform.basis.x.normalized()
	var screen_up := camera.global_transform.basis.y.normalized()
	var billboard_normal := screen_right.cross(screen_up).normalized()
	var billboard_transform := Transform3D(Basis(screen_right, billboard_normal, screen_up), world_point + normal * 0.06)
	_center_mesh.global_transform = billboard_transform
	_occluded_center_mesh.global_transform = billboard_transform
	_center_outline_mesh.global_transform = billboard_transform
	_occluded_center_outline_mesh.global_transform = billboard_transform
	var color := VALID_COLOR if valid else INVALID_COLOR
	_depth_material.albedo_color = color
	_center_material.albedo_color = color
	_center_outline_material.albedo_color = DARK_OUTLINE
	_occluded_material.albedo_color = Color(color, OCCLUDED_ALPHA)
	_occluded_center_material.albedo_color = Color(color, OCCLUDED_ALPHA)
	_occluded_center_outline_material.albedo_color = Color(DARK_OUTLINE, OCCLUDED_ALPHA)
	_depth_mesh.visible = valid
	_occluded_mesh.visible = valid
	_center_outline_mesh.visible = true
	_occluded_center_outline_mesh.visible = true
	_center_mesh.visible = true
	_occluded_center_mesh.visible = true
	visible = true

func _readable_world_radius(camera: Camera3D, point: Vector3, requested_radius: float) -> float:
	var safe_radius := maxf(requested_radius, 0.25)
	var viewport_height := maxf(float(camera.get_viewport().get_visible_rect().size.y), 1.0)
	var distance := maxf(camera.global_position.distance_to(point), 1.0)
	var fov_radians := deg_to_rad(camera.fov)
	var minimum_world_diameter := 2.0 * distance * tan(fov_radians * 0.5) * MIN_SCREEN_PIXELS / viewport_height
	return maxf(safe_radius, minimum_world_diameter)

func _ensure_nodes() -> void:
	if _depth_mesh != null:
		return
	_depth_material = _make_material(VALID_COLOR, false, 0.95)
	_occluded_material = _make_material(Color(VALID_COLOR, OCCLUDED_ALPHA), true, 0.35)
	_center_material = _make_material(VALID_COLOR, true, 1.0)
	_occluded_center_material = _make_material(Color(VALID_COLOR, OCCLUDED_ALPHA), true, 0.35)
	_center_outline_material = _make_material(DARK_OUTLINE, true, 1.0)
	_center_outline_material.render_priority = 1
	_occluded_center_outline_material = _make_material(Color(DARK_OUTLINE, OCCLUDED_ALPHA), true, 0.35)
	_depth_mesh = _line_node("Footprint", _depth_material)
	_occluded_mesh = _line_node("OccludedFootprint", _occluded_material)
	_center_mesh = _line_node("CenterDiamond", _center_material)
	_occluded_center_mesh = _line_node("OccludedCenterDiamond", _occluded_center_material)
	_center_outline_mesh = _line_node("CenterDiamondOutline", _center_outline_material)
	_occluded_center_outline_mesh = _line_node("OccludedCenterDiamondOutline", _occluded_center_outline_material)
	_center_mesh.top_level = true
	_occluded_center_mesh.top_level = true
	_center_outline_mesh.top_level = true
	_occluded_center_outline_mesh.top_level = true
	_depth_mesh.visible = false
	_occluded_mesh.visible = false
	_center_mesh.visible = false
	_occluded_center_mesh.visible = false
	_center_outline_mesh.visible = false
	_occluded_center_outline_mesh.visible = false

func _line_node(node_name: String, material: StandardMaterial3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.material_override = material
	add_child(node)
	return node

func _make_material(color: Color, no_depth_test: bool, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = no_depth_test
	material.albedo_color = Color(color, alpha)
	material.render_priority = 2 if no_depth_test else 1
	return material

func _diamond_mesh(radius: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var points := PackedVector3Array([
		Vector3(0, 0, -radius), Vector3(radius, 0, 0),
		Vector3(0, 0, radius), Vector3(-radius, 0, 0),
		Vector3(0, 0, -radius),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	return mesh
