extends RefCounted
class_name TreeWind

const WIND_SHADER = preload("res://shaders/tree_wind.gdshader")
const PERIOD := 12.0
const DEFAULT_STRENGTH := 0.16
const MAX_STRENGTH := 0.3

var instance: MeshInstance3D
var materials: Array[ShaderMaterial] = []
var phase := 0.0
var strength := DEFAULT_STRENGTH
var height := 1.0

func _init(target: MeshInstance3D, tree_phase: float = 0.0) -> void:
	instance = target
	phase = tree_phase
	height = maxf(target.mesh.get_aabb().end.y, 0.125)
	for surface in target.mesh.get_surface_count():
		var source := target.mesh.surface_get_material(surface) as StandardMaterial3D
		assert(source != null, "Wind expects baked palette materials")
		var material := ShaderMaterial.new()
		material.shader = WIND_SHADER
		material.set_shader_parameter("palette_color", source.albedo_color)
		target.set_surface_override_material(surface, material)
		materials.append(material)
	# The waveform's component bounds are <=1 and <=0.35. Grow conservatively
	# for the public strength range, even when the crown leans offscreen.
	target.custom_aabb = target.mesh.get_aabb().grow(MAX_STRENGTH)
	set_time(0.0)

func shear_at(seconds: float) -> Vector2:
	var t := TAU * fposmod(seconds, PERIOD) / PERIOD
	var x := 0.72 * sin(t + phase) + 0.20 * sin(2.0 * t + phase * 0.7) + 0.08 * sin(3.0 * t + phase * 1.3)
	var z := 0.25 * sin(t + phase + 0.8) + 0.10 * sin(2.0 * t + phase + 1.7)
	return Vector2(x, z) * clampf(strength, 0.0, MAX_STRENGTH) / height

func set_time(seconds: float) -> void:
	var shear := shear_at(seconds)
	for material in materials:
		material.set_shader_parameter("wind_shear", shear)

static func deformation(shear: Vector2) -> Basis:
	return Basis(Vector3.RIGHT, Vector3(shear.x, 1.0, shear.y), Vector3.BACK)
