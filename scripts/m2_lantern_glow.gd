extends Node
class_name M2LanternGlow
## Warm glow for one placed path lantern.
##
## A lantern is presented as a single merged ArrayMesh, so the glow drives the
## *surface materials* of the lamp rather than looking for named child meshes.
##
## Which surfaces glow is not a guess: the canonical MagicaVoxel bake records
## the emissive surfaces of each authored asset in its `.asset.json` receipt,
## and this node lights exactly those. For the authored path lantern that is the
## glass and the flame; the stone base and the timber never emit. The legacy
## procedural lantern has no receipt, so a fixed surface-index fallback keeps
## that presentation glowing.
##
## Materials are applied as per-node surface *overrides*, so the shared authored
## asset is never mutated: every lantern owns its glow and detach() is exact.
##
## Daylight baseline is constant (the shipped world has no night cycle), and a
## VisualLightingProfile can retune it for dusk/night captures through
## apply_profile().

## Legacy procedural lantern layout: 0 post, 1 housing, 2 glass, 3 cap.
const LEGACY_GLASS_SURFACE_INDEX := 2

const DAYLIGHT_EMISSIVE_SCALE := 0.55
const DAYLIGHT_LIGHT_ENERGY := 0.45
const LIGHT_RANGE := 2.75
const LIGHT_SHADOW := false

## Emissive scale applied to the authored emissive surface materials.
var emissive_scale := DAYLIGHT_EMISSIVE_SCALE
## Energy of the flame point light.
var light_energy := DAYLIGHT_LIGHT_ENERGY

var _mesh: MeshInstance3D
var _surfaces: Array = []
var _light: OmniLight3D

static func attach(mesh: MeshInstance3D, flame_local: Vector3, lamp_colour: Color) -> Node:
	if mesh == null or not is_instance_valid(mesh): return null
	var glow := M2LanternGlow.new()
	glow._mesh = mesh
	mesh.add_child(glow)
	glow._surfaces = glow._capture_surfaces()
	glow._setup_flame(glow._flame_point(flame_local), lamp_colour)
	glow._apply()
	return glow

## Emissive surface indices for a lantern mesh: the authored asset's receipt
## when there is one, otherwise the legacy procedural glass surface.
static func glow_surfaces(mesh: Mesh, receipt: Dictionary) -> Array[int]:
	var array := mesh as ArrayMesh
	if array == null: return []
	var authored := M2VoxelEmissive.emissive_surfaces(receipt, array)
	if not authored.is_empty(): return authored
	var legacy: Array[int] = []
	if array.get_surface_count() > LEGACY_GLASS_SURFACE_INDEX:
		legacy.append(LEGACY_GLASS_SURFACE_INDEX)
	return legacy

## Retune the glow for a lighting profile (dusk/night). Null restores the
## constant daylight look the shipped world uses.
func apply_profile(profile: Resource) -> void:
	if profile == null:
		emissive_scale = DAYLIGHT_EMISSIVE_SCALE
		light_energy = DAYLIGHT_LIGHT_ENERGY
	else:
		emissive_scale = float(profile.get("lamp_emissive_scale"))
		light_energy = float(profile.get("lamp_light_energy"))
	_apply()

## Drop the glow's nodes and hand the lantern materials back untouched.
func detach() -> void:
	_restore_surfaces()
	if _light != null and is_instance_valid(_light): _light.queue_free()
	_light = null
	if _mesh != null and is_instance_valid(_mesh): _mesh.remove_child(self)
	queue_free()

func _setup_flame(flame_local: Vector3, lamp_colour: Color) -> void:
	_light = OmniLight3D.new()
	_light.name = "LanternGlow"
	_light.position = flame_local
	_light.light_color = lamp_colour
	_light.light_energy = light_energy
	_light.omni_range = LIGHT_RANGE
	_light.shadow_enabled = LIGHT_SHADOW
	_mesh.add_child(_light)

## Capture the emissive surfaces as per-node material overrides.
func _capture_surfaces() -> Array:
	var captured: Array = []
	var mesh := _mesh.mesh as ArrayMesh
	if mesh == null: return captured
	for index in glow_surfaces(mesh, M2VoxelEmissive.load_receipt(
			M2VoxelEmissive.receipt_path(M2LanternAssets.ASSET))):
		var authored := mesh.surface_get_material(index) as StandardMaterial3D
		if authored == null: continue
		var override := authored.duplicate() as StandardMaterial3D
		_mesh.set_surface_override_material(index, override)
		captured.append({
			"index": index,
			"material": override,
			"emission": authored.emission,
			"energy": authored.emission_energy_multiplier,
			"albedo": authored.albedo_color,
			"had_emission": authored.emission_enabled,
		})
	return captured

## Seat the flame light in the authored emitter volume.
func _flame_point(fallback: Vector3) -> Vector3:
	var mesh := _mesh.mesh as ArrayMesh
	var glowing := glow_surfaces(mesh, M2VoxelEmissive.load_receipt(
			M2VoxelEmissive.receipt_path(M2LanternAssets.ASSET)))
	return M2VoxelEmissive.centroid(mesh, glowing, fallback)

## A surface with no emission of its own glows in its own albedo colour; a
## surface that already emitted keeps its authored colour.
func _apply() -> void:
	for captured in _surfaces:
		var material := captured["material"] as StandardMaterial3D
		if material == null or not is_instance_valid(material): continue
		var glow_colour: Color = captured["emission"]
		if not bool(captured["had_emission"]): glow_colour = captured["albedo"]
		material.emission = glow_colour
		material.emission_enabled = emissive_scale > 0.0
		material.emission_energy_multiplier = maxf(0.0, float(captured["energy"]) * emissive_scale)
	if _light != null and is_instance_valid(_light):
		_light.light_energy = light_energy

func _restore_surfaces() -> void:
	for captured in _surfaces:
		_mesh.set_surface_override_material(int(captured["index"]), null)
	_surfaces = []
