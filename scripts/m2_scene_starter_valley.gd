extends "res://scripts/m2_scene_style_preview_stability.gd"
## Starter content is a one-time new-world bootstrap, never a save migration.
## Old worlds gain space and scenery without acquiring unwanted houses/props.
const StarterHamlet = preload("res://scripts/m2_starter_hamlet.gd")
const ValleySurround = preload("res://scripts/m2_valley_surround.gd")
const PremadePonds = preload("res://scripts/premade_ponds.gd")
const WaterState = preload("res://scripts/landscape_state.gd")
const WaterRegion = preload("res://scripts/water_region_geometry.gd")
const WaterExcavation = preload("res://scripts/water_terrain_excavation.gd")
# The mountain ring peaks at ~49 m; keeping orbit pitch below this keeps the
# camera under the peaks in the default framing instead of seeing over them.
const VALLEY_MAX_PITCH := 1.15
@export var starter_hamlet_enabled := true
# Existing tool regressions author their own empty-world fixtures. Dedicated
# starter integration/capture tests explicitly opt into the production seed.
@export var starter_hamlet_in_tests := false
var _valley_surround: Node3D
var _starter_seeded := false
var _surround_refresh_pending := false

func _ready() -> void:
	super._ready()
	_apply_cozy_valley_lighting()

func _apply_cozy_valley_lighting() -> void:
	# Cozy valley lighting: a warm shadowed key plus two soft unshadowed fills,
	# a golden-hour procedural sky for ambient/reflections/background, and warm
	# distance haze. Stronger plane separation than the flat clear-air pass.
	for node in find_children("*", "DirectionalLight3D", true, false):
		var light := node as DirectionalLight3D
		if light.name in ["CozySkyFill", "CozyWarmRim"]: continue
		light.rotation_degrees = Vector3(-34.0, -32.0, 0.0)
		light.light_color = Color("#ffd4a3")
		light.light_energy = 1.38
		light.shadow_enabled = true
		light.shadow_opacity = 0.78
		# Mobile does not use directional PCSS, so keep this modest rather than
		# relying on angular distance as the main source of softness.
		light.light_angular_distance = 0.6

	_ensure_directional_fill(
		"CozySkyFill",
		Vector3(-58.0, 148.0, 0.0),
		Color("#d8e5e2"),
		0.13
	)
	_ensure_directional_fill(
		"CozyWarmRim",
		Vector3(-28.0, 92.0, 0.0),
		Color("#ffd0a0"),
		0.10
	)

	for node in find_children("*", "WorldEnvironment", true, false):
		var world_environment := node as WorldEnvironment
		var environment := world_environment.environment
		if environment == null: continue
		# Restore the sky. The flat cream background from the "clear-air" pass made
		# the near-mirror water (roughness 0.16) reflect a flat #ddd9c9 wall, which
		# read as silver ponds on device, and the frame lost its sky entirely.
		# The procedural sky uses the canonical M2 look: blue-grey zenith into a
		# warm golden horizon. Sky-sourced ambient + reflections let water, grass
		# and roofs pick up the same gradient the reference shots use.
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color("#d8e1e5")
		sky_material.sky_horizon_color = Color("#f2d9a4")
		sky_material.ground_bottom_color = Color("#c3b795")
		sky_material.ground_horizon_color = Color("#e0d3b2")
		sky_material.sky_energy_multiplier = 0.55
		sky_material.ground_energy_multiplier = 0.35
		var sky := Sky.new()
		sky.sky_material = sky_material
		environment.sky = sky
		environment.background_mode = Environment.BG_SKY
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_sky_contribution = 1.0
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

		# Keep the creamy shoulder from the earlier passes, but stop compressing the
		# whole frame into the same pale value range.
		environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		environment.tonemap_exposure = 1.03
		environment.tonemap_white = 1.42

		# Tight highlight glow instead of screen-wide bloom. Nudge it harder while
		# keeping the threshold high enough that the whole frame stays clear.
		environment.glow_enabled = true
		environment.glow_normalized = true
		environment.glow_intensity = 1.02
		environment.glow_strength = 1.28
		environment.glow_mix = 0.025
		environment.glow_bloom = 0.02
		environment.glow_hdr_threshold = 0.84
		environment.glow_hdr_scale = 2.50
		environment.set("glow_levels/1", 0.80)
		environment.set("glow_levels/2", 0.62)
		environment.set("glow_levels/3", 0.28)
		environment.set("glow_levels/4", 0.06)
		environment.set("glow_levels/5", 0.0)
		environment.set("glow_levels/6", 0.0)
		environment.set("glow_levels/7", 0.0)

		# Warm distance haze: softens the far hills and separates the village from
		# the backdrop, as in the reference frames. Same canonical M2 values.
		environment.fog_enabled = true
		environment.fog_light_color = Color("#ead7b3")
		environment.fog_density = 0.0038
		environment.fog_sky_affect = 0.8
		environment.fog_depth_begin = 18.0
		environment.fog_depth_end = 150.0

	# Push the miniature-camera cue slightly further while keeping the playable
	# village crisp and reserving most of the blur for distant hills.
	if camera != null:
		var attributes := CameraAttributesPractical.new()
		attributes.dof_blur_far_enabled = true
		attributes.dof_blur_far_distance = 40.0
		attributes.dof_blur_far_transition = 18.0
		attributes.dof_blur_near_enabled = false
		attributes.dof_blur_amount = 0.070
		camera.attributes = attributes

func _ensure_directional_fill(fill_name: String, rotation: Vector3, color: Color, energy: float) -> void:
	var fill := get_node_or_null(NodePath(fill_name)) as DirectionalLight3D
	if fill == null:
		fill = DirectionalLight3D.new()
		fill.name = fill_name
		add_child(fill)
	fill.rotation_degrees = rotation
	fill.light_color = color
	fill.light_energy = energy
	fill.shadow_enabled = false
	fill.light_specular = 0.25

func _on_backend_ready(ready: bool) -> void:
	if not ready or not backend: return
	super._on_backend_ready(ready)
	if not _player_restored: return
	# A world with no saved checkpoint gets the full hamlet; a loaded save keeps
	# exactly what it has. Gate on the loaded document, not on _player_restored:
	# a fresh world already contains the player shell (building-1), and both
	# fresh and restored worlds report _player_restored=true here.
	var saved: Dictionary = backend.loaded_building_document
	var error := str(backend.stats().get("error", ""))
	var seed_allowed := starter_hamlet_enabled and (not test_mode or starter_hamlet_in_tests)
	if seed_allowed and saved.is_empty() and error in ["", "no valid checkpoint"]:
		_seed_starter_hamlet()
	if _valley_surround == null:
		_valley_surround = ValleySurround.new()
		_valley_surround.name = "ValleySurround"
		add_child(_valley_surround)
	_valley_surround.rebuild(backend)
	# The starter river is a water region (not a bespoke mesh) so it shares the
	# presentation path, materials and editability with player-authored water.
	# Runs for both fresh (seeded) and existing (restored) worlds; idempotent.
	_ensure_premade_river()
	_ensure_premade_ponds()

func _seed_starter_hamlet() -> bool:
	if _starter_seeded or not backend.loaded_building_document.is_empty(): return false
	var documents := StarterHamlet.documents(building_world)
	if documents.is_empty():
		push_error("Starter hamlet validation failed; existing world left intact")
		return false
	var before: Dictionary = building_world.get_document()
	_restoring = true
	if not building_world.load_document(documents["buildings"]):
		_restoring = false
		return false
	# Both components were validated before publishing either. Keep a rollback
	# anyway, so a future landscape-schema change cannot leave half a starter.
	if not landscape_state.restore(documents["landscape"]):
		building_world.load_document(before)
		_restoring = false
		return false
	_starter_seeded = true
	_restore_landscape({"landscape": documents["landscape"]})
	_restoring = false
	_building_dirty = true
	if not test_mode:
		cursor = Vector3(24.0,8.0,27.0)
		terrain_cursor = cursor
		camera_yaw = -1.9
		camera_pitch = 0.74
		camera_distance = 32.0
	_set_status("Welcome to Hearthvale - a little village to make your own")
	_update_presentation()
	_update_camera()
	return true

func _ensure_premade_ponds() -> void:
	# The ponds are water regions (lake polygons), exactly like the river, so
	# they share the presentation path, materials and editability with
	# player-authored water. Deterministic and idempotent: fixed outlines on
	# the flat village green, added once per world. The bed is excavated with
	# the same plan the water tool commits with, so each pond is one shallow
	# depression with a shelf at the water level: the water sits 0.5 m below
	# the surrounding green, and the village plateau is never carved.
	for pond: Dictionary in PremadePonds.regions():
		var present := false
		for existing: Dictionary in landscape_state.water:
			present = present or PremadePonds.matches(existing, pond)
		if present:
			# Region already saved; make sure its terrain is at the bed.
			if not PremadePonds.already_carved(_terrain_top_sampler(), pond):
				_carve_pond(pond)
			continue
		if not _ensure_premade_pond(pond):
			push_error("Premade pond could not be added; leaving the world as-is")

func _ensure_premade_pond(pond: Dictionary) -> bool:
	if PremadePonds.already_carved(_terrain_top_sampler(), pond): return true
	if landscape_state.add_water("lake", pond["level"], pond["points"]) < 1: return false
	return _carve_pond(pond)

func _carve_pond(pond: Dictionary) -> bool:
	var cells: Array = WaterRegion.footprint_cells(pond, WaterState.EDITABLE_WORLD_SIZE)
	var excavation: Dictionary = WaterExcavation.plan_bed(backend, pond, WaterState.EDITABLE_WORLD_SIZE)
	if not bool(excavation.get("ok", false)): return false
	var changes: Array = excavation.get("changes", [])
	if changes.size() > 0 and (not backend.has_method("apply_voxel_changes")
			or not backend.apply_voxel_changes(changes)):
		return false
	# Plants cannot live in the pond; reuse the water tool's footprint rule.
	if landscape_state.clear_records_in_path_cells(cells):
		if garden_visual: garden_visual.reset_records(landscape_state.records)
	_sync_water_visual()
	return true

func _terrain_top_sampler() -> Callable:
	var patch: Vector3i = backend.get("patch_size")
	return func(c: Vector2) -> float:
		var x := clampi(floori(c.x / 0.125), 0, patch.x - 1)
		var z := clampi(floori(c.y / 0.125), 0, patch.z - 1)
		for y in range(patch.y - 1, -1, -1):
			if int(backend.voxel_at(Vector3i(x, y, z))) != 0:
				return float(y + 1) * 0.125
		return NAN

func _on_backend_changed() -> void:
	super._on_backend_changed()
	if not is_instance_valid(_valley_surround) or _surround_refresh_pending: return
	if not _valley_surround.affected_by(backend.get_last_edit_bounds()): return
	# Do not rebuild scenery on each tick of a held brush. Coalesce to the end
	# of a stroke; border undo/redo and checkpoint loads refresh once as well.
	_surround_refresh_pending = true

func _process(delta: float) -> void:
	super._process(delta)
	camera_pitch = minf(camera_pitch, VALLEY_MAX_PITCH)
	if _shutting_down or not _surround_refresh_pending or stroke_active or _restoring: return
	_surround_refresh_pending = false
	if is_instance_valid(_valley_surround) and backend and backend.is_ready():
		_valley_surround.rebuild(backend)
