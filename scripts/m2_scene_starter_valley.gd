extends "res://scripts/m2_scene_style_preview_stability.gd"
## Starter content is a one-time new-world bootstrap, never a save migration.
## Old worlds gain space and scenery without acquiring unwanted houses/props.
const StarterHamlet = preload("res://scripts/m2_starter_hamlet.gd")
const ValleySurround = preload("res://scripts/m2_valley_surround.gd")
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
	# Clear-air miniature lighting: one warm shadowed key plus two extremely soft
	# unshadowed fills. This pass keeps the glow but restores deeper grounding and
	# stronger plane separation, especially on roofs viewed from above.
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
		environment.background_color = Color("#ddd9c9")
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color("#cbd4ca")
		environment.ambient_light_energy = 0.24

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

		# Keep the air clear and let the fill lights + glow provide softness.
		environment.fog_enabled = false

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
	var already_restored := _player_restored
	super._on_backend_ready(ready)
	if not ready or already_restored or not _player_restored or not backend: return
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
	_diagnose_water()

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

func _on_backend_changed() -> void:
	super._on_backend_changed()
	if not is_instance_valid(_valley_surround) or _surround_refresh_pending: return
	if not _valley_surround.affected_by(backend.get_last_edit_bounds()): return
	# Do not rebuild scenery on each tick of a held brush. Coalesce to the end
	# of a stroke; border undo/redo and checkpoint loads refresh once as well.
	_surround_refresh_pending = true

func _process(delta: float) -> void:
	super._process(delta)
	if _shutting_down or not _surround_refresh_pending or stroke_active or _restoring: return
	_surround_refresh_pending = false
	if is_instance_valid(_valley_surround) and backend and backend.is_ready():
		_valley_surround.rebuild(backend)
