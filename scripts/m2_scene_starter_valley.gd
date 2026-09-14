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
	# Deliberately strong storybook-miniature daylight. The previous pass was too
	# subtle: this one creates a lower, warmer key with enough HDR headroom for
	# visible bloom, while keeping the ambient floor lower so the glow can read.
	for node in find_children("*", "DirectionalLight3D", true, false):
		var light := node as DirectionalLight3D
		light.rotation_degrees = Vector3(-31.0, -30.0, 0.0)
		light.light_color = Color("#ffcf96")
		light.light_energy = 1.55
		light.shadow_enabled = true
		light.shadow_opacity = 0.58
		light.light_angular_distance = 3.4
	for node in find_children("*", "WorldEnvironment", true, false):
		var world_environment := node as WorldEnvironment
		var environment := world_environment.environment
		if environment == null: continue
		environment.background_color = Color("#e0dcc8")
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color("#cfd3bd")
		environment.ambient_light_energy = 0.46

		# Strong filmic compression turns the boosted sun into creamy, luminous
		# highlights rather than simply clipping roofs and grass to white.
		environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		environment.tonemap_exposure = 0.99
		environment.tonemap_white = 1.10

		# Push native Mobile glow hard enough to be unmistakable. A lower threshold
		# lets sunlit grass, plaster, roofs and water all contribute to the halo.
		environment.glow_enabled = true
		environment.glow_normalized = true
		environment.glow_intensity = 0.92
		environment.glow_strength = 1.30
		environment.glow_mix = 0.07
		environment.glow_bloom = 0.42
		environment.glow_hdr_threshold = 0.38
		environment.glow_hdr_scale = 2.05

		# Warm scattering gives the air itself a sunlit quality, while keeping fog
		# density low enough that distant terrain stays readable rather than milky.
		environment.fog_enabled = true
		environment.fog_light_color = Color("#efd8b5")
		environment.fog_light_energy = 0.88
		environment.fog_density = 0.0023
		environment.fog_sun_scatter = 0.58
		environment.fog_aerial_perspective = 0.18

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
