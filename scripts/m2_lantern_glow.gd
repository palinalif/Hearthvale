extends Node
class_name M2LanternGlow
## Warm glow for one placed path lantern.
##
## A lantern is presented as a single merged ArrayMesh, so the glow drives the
## *surface materials* of the lamp rather than looking for named child meshes.
##
## The authored MagicaVoxel lantern groups one surface per palette
## (`palette_1` … `palette_6`), and only the glass (`palette_5`) and the flame
## (`palette_6`) are authored to emit — see `emissive_palette_indices` in
## `assets/models/magicavoxel/hearthvale_prop_path_lantern.asset.json`. The
## stone base and the timber are never emissive. The legacy procedural lantern
## merged its surfaces in a fixed order, so a surface-index fallback keeps that
## presentation glowing while the authored asset is driven by palette role.
##
## Daylight baseline is constant (the shipped world has no night cycle), and a
## VisualLightingProfile can retune it for dusk/night captures through
## apply_profile().

const GLASS_PALETTE_INDEX := 5
const FLAME_PALETTE_INDEX := 6
const GLASS_PALETTE_MATERIAL := "palette_%d" % GLASS_PALETTE_INDEX
const FLAME_PALETTE_MATERIAL := "palette_%d" % FLAME_PALETTE_INDEX

## Legacy procedural lantern layout: 0 post, 1 housing, 2 glass, 3 cap.
const LEGACY_GLASS_SURFACE_INDEX := 2

const DAYLIGHT_EMISSIVE_SCALE := 0.55
## The flame is the emitter, so it reads hotter than the glass it lights.
const FLAME_EMISSIVE_BOOST := 2.0
const DAYLIGHT_LIGHT_ENERGY := 0.45
const LIGHT_RANGE := 2.75
const LIGHT_SHADOW := false

## Emissive scale applied to the authored glass surface material.
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
	glow._capture_surfaces()
	glow._setup_flame(glow._flame_point(flame_local), lamp_colour)
	glow._apply()
	return glow

## Surface indices of the emissive roles for a lantern mesh, keyed "glass" and
## "flame"; a role is -1 when that mesh has no such surface.
static func emissive_surface_indices(mesh: Mesh) -> Dictionary:
	var roles := {"glass": -1, "flame": -1}
	var array := mesh as ArrayMesh
	if array == null: return roles
	for index in array.get_surface_count():
		var material := array.surface_get_material(index) as StandardMaterial3D
		if material == null: continue
		if material.resource_name == FLAME_PALETTE_MATERIAL: roles["flame"] = index
		elif material.resource_name == GLASS_PALETTE_MATERIAL: roles["glass"] = index
	if int(roles["glass"]) < 0 and array.get_surface_count() > LEGACY_GLASS_SURFACE_INDEX:
		roles["glass"] = LEGACY_GLASS_SURFACE_INDEX
	return roles

## Local-space centre of a surface's vertices, used to seat the flame light in
## the authored flame volume. Returns `fallback` for an empty/absent surface.
static func surface_centroid(mesh: Mesh, surface_index: int, fallback: Vector3) -> Vector3:
	var array := mesh as ArrayMesh
	if array == null or surface_index < 0 or surface_index >= array.get_surface_count():
		return fallback
	var data := array.surface_get_arrays(surface_index)
	var vertices: PackedVector3Array = data[ArrayMesh.ARRAY_VERTEX]
	if vertices.is_empty(): return fallback
	var sum := Vector3.ZERO
	for vertex in vertices: sum += vertex
	return sum / float(vertices.size())

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

## Capture the emissive-eligible surfaces as per-node material overrides.
## The authored asset's own materials are never mutated, so every lantern keeps
## its own glow state and detach() is exact by construction.
func _capture_surfaces() -> void:
	_surfaces = []
	var mesh := _mesh.mesh as ArrayMesh
	if mesh == null: return
	var roles := emissive_surface_indices(mesh)
	for role in ["glass", "flame"]:
		var index := int(roles[role])
		if index < 0: continue
		var authored := mesh.surface_get_material(index) as StandardMaterial3D
		if authored == null: continue
		var override := authored.duplicate() as StandardMaterial3D
		_mesh.set_surface_override_material(index, override)
		_surfaces.append({
			"role": role,
			"index": index,
			"material": override,
			"emission": authored.emission,
			"energy": authored.emission_energy_multiplier,
			"albedo": authored.albedo_color,
			"had_emission": authored.emission_enabled,
		})

## Seat the flame light in the authored flame volume when that surface exists.
func _flame_point(fallback: Vector3) -> Vector3:
	var mesh := _mesh.mesh as ArrayMesh
	var flame_index := int(emissive_surface_indices(mesh)["flame"])
	return surface_centroid(mesh, flame_index, fallback)

## A surface with no emission of its own glows in its own albedo colour; a
## surface that already emitted keeps its authored colour.
func _apply() -> void:
	for captured in _surfaces:
		var material := captured["material"] as StandardMaterial3D
		if material == null or not is_instance_valid(material): continue
		var glow_colour: Color = captured["emission"]
		if not bool(captured["had_emission"]): glow_colour = captured["albedo"]
		var scale := emissive_scale
		if String(captured["role"]) == "flame": scale *= FLAME_EMISSIVE_BOOST
		material.emission = glow_colour
		material.emission_enabled = scale > 0.0
		material.emission_energy_multiplier = maxf(0.0, float(captured["energy"]) * scale)
	if _light != null and is_instance_valid(_light):
		_light.light_energy = light_energy

func _restore_surfaces() -> void:
	for captured in _surfaces:
		_mesh.set_surface_override_material(int(captured["index"]), null)
	_surfaces = []
