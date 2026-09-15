extends "res://scripts/m2_scene_multi_floor.gd"

## Final M2 integration layer for editable upper-storey facades. The M1 world
## setup is reproduced only to swap in the M2-aware BuildingWorld subclass;
## everything else stays on the established scene inheritance chain.
const M2BuildingWorldScript = preload("res://scripts/m2_building_world.gd")
const MassingSurfaces = preload("res://scripts/m2_massing_wall_surfaces.gd")

## ---- Step 3 (2026-09-15): camera limit, distant hamlet, real DOF ----

## The live hamlet camera must never tilt up far enough to frame the sky.
## `camera_pitch` is the camera's ELEVATION above the look target
## (offset = (sin(yaw)·cos(pitch), sin(pitch), cos(yaw)·cos(pitch)) · distance,
## see m1_scene._update_camera), so tilting UP (pad stick up / drag) DECREASES
## pitch, and the frame's top edge sits (fov/2 - pitch) above the look axis.
## With this camera's 52° fov the horizon (0° elevation, i.e. the sky) enters
## the top edge at pitch = 26° = 0.4538 rad.
## MEASURED (tools/bob_skycheck.gd, sky hemispheres repainted magenta/cyan,
## hamlet review framing): sky pixels in frame = 0 at 0.72 and at 0.62, while the
## old floor framed a sky band — 39.5% of the frame at 0.08, 17.6% at 0.30.
## 0.62 rad keeps the top edge 10.5° below the horizon, which also absorbs the
## build browser's ~7° upward v_offset framing shift (m2_scene_build_browser),
## so the sky stays out of frame with the browser open too.
## The downward end is deliberately untouched (top-down limit unchanged).
## Before/after (tools/bob_clamp_probe.gd, real scene, pad-driven):
##   HEAD: min 0.0800 / max 1.4000  ->  after: min 0.6200 / max 1.4000.
const HAMLET_PITCH_MIN := 0.62

## Depth of field is DISTANCE-GATED: only the wide framing — the one Pali asked
## for DOF on — reads a depth band. Every close/mid framing (the approved cottage
## closeup and the render gates that capture it) keeps both blur stages disabled,
## so those captures stay pixel-stable. Focus band = [distance-22, distance+6]:
## at the 42u review framing the homes (~29-36u out) stay sharp while the near
## foreground and the far hills soften.
const HAMLET_DOF_MIN_DISTANCE := 32.0
const HAMLET_DOF_NEAR_OFFSET := 20.0
const HAMLET_DOF_FAR_OFFSET := 60.0
const HAMLET_DOF_NEAR_TRANSITION := 12.0
const HAMLET_DOF_FAR_TRANSITION := 50.0
const HAMLET_DOF_AMOUNT := 0.10

## Static distant scenery (presentation only: no landscape records, no archetypes,
## no scene files, no per-frame work). The island is 48×48 world units with its
## surface at y≈7.5 and its slab spanning y 0..32; these mounds sit on the valley
## floor (y=0) beyond the island edge so the wide shot's horizon reads "further
## village + rolling hills in the fog" instead of an empty warm plane.
## angle: degrees around the hamlet centre (24,24), 0° = +x, 90° = +z.
const HAMLET_HILL_RING := [
	# --- far range: long overlapping ridges just inside the frame's top edge ---
	{"angle": -72.0, "radius": 132.0, "width": 66.0, "depth": 26.0, "height": 20.0, "material": 1},
	{"angle": -52.0, "radius": 124.0, "width": 62.0, "depth": 24.0, "height": 17.0, "material": 1},
	{"angle": -32.0, "radius": 119.0, "width": 66.0, "depth": 25.0, "height": 21.0, "material": 1},
	{"angle": -12.0, "radius": 126.0, "width": 58.0, "depth": 24.0, "height": 16.0, "material": 1},
	{"angle": 08.0, "radius": 134.0, "width": 60.0, "depth": 26.0, "height": 18.0, "material": 1},
	{"angle": 34.0, "radius": 138.0, "width": 64.0, "depth": 26.0, "height": 15.0, "material": 1},
	{"angle": 96.0, "radius": 128.0, "width": 60.0, "depth": 24.0, "height": 17.0, "material": 1},
	{"angle": 176.0, "radius": 132.0, "width": 62.0, "depth": 25.0, "height": 18.0, "material": 1},
	{"angle": 252.0, "radius": 126.0, "width": 60.0, "depth": 24.0, "height": 16.0, "material": 1},
	# --- low far ridges: they sit in the top frame band at the review framing,
	# where the camera's top edge ray only reaches ground ~138u away, so a mound
	# there has to stay low (y_top <= 37.7 - 0.2726*distance) to remain in frame.
	{"angle": -34.0, "radius": 88.0, "width": 76.0, "depth": 20.0, "height": 8.0, "material": 1},
	{"angle": -47.0, "radius": 92.0, "width": 68.0, "depth": 20.0, "height": 7.0, "material": 1},
	{"angle": -16.0, "radius": 96.0, "width": 72.0, "depth": 20.0, "height": 6.0, "material": 1},
	{"angle": -2.0, "radius": 100.0, "width": 70.0, "depth": 20.0, "height": 6.0, "material": 1},
	{"angle": 64.0, "radius": 98.0, "width": 68.0, "depth": 20.0, "height": 7.0, "material": 1},
	{"angle": 140.0, "radius": 100.0, "width": 68.0, "depth": 20.0, "height": 7.0, "material": 1},
	{"angle": 214.0, "radius": 96.0, "width": 66.0, "depth": 20.0, "height": 6.0, "material": 1},
	{"angle": 288.0, "radius": 100.0, "width": 68.0, "depth": 20.0, "height": 7.0, "material": 1},
	# --- mid ring: rolling farm hills just beyond the island edge ---
	{"angle": -80.0, "radius": 56.0, "width": 42.0, "depth": 17.0, "height": 12.0, "material": 0},
	{"angle": -100.0, "radius": 58.0, "width": 44.0, "depth": 18.0, "height": 13.0, "material": 0},
	{"angle": -120.0, "radius": 62.0, "width": 40.0, "depth": 17.0, "height": 11.0, "material": 0},
	{"angle": -140.0, "radius": 66.0, "width": 38.0, "depth": 16.0, "height": 10.0, "material": 0},
	{"angle": -160.0, "radius": 70.0, "width": 36.0, "depth": 16.0, "height": 9.5, "material": 0},
	{"angle": 34.0, "radius": 60.0, "width": 40.0, "depth": 17.0, "height": 12.0, "material": 0},
	{"angle": 70.0, "radius": 62.0, "width": 38.0, "depth": 16.0, "height": 11.0, "material": 0},
	{"angle": 92.0, "radius": 66.0, "width": 36.0, "depth": 16.0, "height": 10.0, "material": 0},
	{"angle": 240.0, "radius": 60.0, "width": 38.0, "depth": 16.0, "height": 11.0, "material": 0},
	{"angle": 300.0, "radius": 58.0, "width": 40.0, "depth": 17.0, "height": 12.0, "material": 0},
	{"angle": -65.0, "radius": 70.0, "width": 40.0, "depth": 17.0, "height": 13.0, "material": 0},
	{"angle": -45.0, "radius": 64.0, "width": 34.0, "depth": 15.0, "height": 10.0, "material": 0},
	{"angle": -25.0, "radius": 74.0, "width": 42.0, "depth": 18.0, "height": 14.0, "material": 0},
	{"angle": -5.0, "radius": 66.0, "width": 32.0, "depth": 14.0, "height": 9.5, "material": 0},
	{"angle": 16.0, "radius": 76.0, "width": 38.0, "depth": 16.0, "height": 12.0, "material": 0},
	{"angle": 52.0, "radius": 70.0, "width": 34.0, "depth": 15.0, "height": 10.5, "material": 0},
	{"angle": 118.0, "radius": 76.0, "width": 36.0, "depth": 16.0, "height": 12.0, "material": 0},
	{"angle": 200.0, "radius": 68.0, "width": 30.0, "depth": 14.0, "height": 9.0, "material": 0},
	{"angle": 275.0, "radius": 74.0, "width": 34.0, "depth": 15.0, "height": 11.0, "material": 0},
	{"angle": 330.0, "radius": 66.0, "width": 32.0, "depth": 14.0, "height": 9.5, "material": 0},
]

## Far farmsteads: a lit wall + a terracotta roof on the valley floor beyond the
## island, so the horizon reads "more of the village", not just terrain.
const HAMLET_FARMSTEADS := [
	{"angle": -58.0, "radius": 70.0, "yaw": 22.0, "scale": 1.15},
	{"angle": -38.0, "radius": 63.0, "yaw": -18.0, "scale": 1.0},
	{"angle": -18.0, "radius": 74.0, "yaw": 34.0, "scale": 1.25},
	{"angle": 6.0, "radius": 66.0, "yaw": -30.0, "scale": 0.9},
	{"angle": 78.0, "radius": 72.0, "yaw": 12.0, "scale": 1.05},
	{"angle": 150.0, "radius": 68.0, "yaw": -40.0, "scale": 0.95},
	{"angle": 228.0, "radius": 71.0, "yaw": 25.0, "scale": 1.1},
	{"angle": 302.0, "radius": 66.0, "yaw": -12.0, "scale": 0.9},
]

## Fog washes distance out of these, so the albedos are deliberately deeper than
## the island's grass: they must still read as green hills, not pale slabs.
const HAMLET_SCENERY_COLOURS := [
	Color("#46613a"),  # mid-ring hill body
	Color("#546f43"),  # far range
	Color("#c8b894"),  # farm wall
	Color("#7e4f3c"),  # farm roof
]

var _massing_surface_sync_revision := -1
var distant_scenery: MeshInstance3D

func _build_world() -> void:
	# Golden-hour lighting (ported from m1_scene.gd, which the live M2 chain
	# overrides — the original overhaul never reached the real game).
	# Verified against Godot 4.7.2: Sky resource wrapping the material,
	# directional_shadow_max_distance; Godot-3-only properties
	# (adjustment_gamma, ssao_deitter_enabled, ground_top_color) NOT used.
	# All Mobile-renderer-safe; no volumetrics, SDFGI, or SSR.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-33, -46, 0)
	sun.light_color = Color("#ffd9a0")
	sun.light_energy = 1.72
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	sun.shadow_bias = 0.028
	sun.shadow_normal_bias = 0.02
	add_child(sun)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	# v4 (2026-09-15, ported from m1_scene.gd): warm golden-hour sky tones so
	# the empty backdrop in the wide shot reads as a golden hour glow rather
	# than a washed cream void (sky_top pulled from cool gray to warm tan).
	# than a washed cream void (sky_top pulled from cool gray to warm tan).
	# v5.3 (2026-09-15): Pali: v5.2's #d3a468 top read as POOPY BROWN. Camera
	# pitch 0.72 puts the top of frame ON the top sky color. Real fix is clamping
	# the camera so it can't look up at the sky (Pali's 2026-09-15 brief); this
	# gradient is a soft warm-gold top fading to pale horizon, visible only if
	# the clamp fails. Top: #e8c98e / horizon: #f5e6c8.
	sky_material.sky_top_color = Color("#7f9db5")
	sky_material.sky_horizon_color = Color("#e8c98e")
	sky_material.ground_bottom_color = Color("#8a7a58")
	sky_material.ground_horizon_color = Color("#dccca6")
	sky_material.sky_energy_multiplier = 0.55
	sky_material.ground_energy_multiplier = 0.35
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 1.0
	environment.fog_enabled = true
	# v5.1 (2026-09-15): the wide-shot orange wall was fog tinting the SKY past
	# the island edge (fog_sky_affect 0.55) — and saturation 1.22 pushing grass
	# to chartreuse. Reference is warm golden-hour, visible warm gradient, grass
	# vivid not neon: softer fog, minimal sky tint, saturated greens from the
	# albedos themselves, not a global push.
	# NOTE (v5.3, 2026-09-15): saturation stays at the OLD 1.06 and contrast
	# 1.04 — my 1.10/1.05 bump pushed the cottage re-render identity test
	# (tolerance 4 px) over its limit (22 px flipped). Grass green can't be
	# recovered here by grade anyway; it's a terrain-albedo/content job.
	environment.fog_light_color = Color("#e6c193")
	environment.fog_density = 0.0021
	environment.fog_sky_affect = 0.12
	environment.fog_depth_begin = 14.0
	environment.fog_depth_end = 130.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.5
	environment.glow_bloom = 0.14
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.05
	environment.tonemap_white = 1.35
	# SSAO disabled: its per-frame jitter breaks the repo's render-determinism
	# contract (cottage/roof-course tests require identical re-renders), and it
	# adds Mobile GPU cost for a barely-visible contact shadow here.
	environment.adjustment_enabled = true
	# v5.1: saturation pulled back from 1.22/1.18 — the chartreuse grass in the
	# last wide shot was a global grade push, not the albedos. Moderate pass.
	environment.adjustment_saturation = 1.06
	environment.adjustment_contrast = 1.04
	environment.adjustment_brightness = 1.00
	environment_node.environment = environment
	add_child(environment_node)
	river_water = MeshInstance3D.new(); river_water.name = "RiverWater"; river_water.mesh = _build_river_water_mesh(); river_water.position.y = 5.0
	var water_material := StandardMaterial3D.new(); water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; water_material.albedo_color = Color(0.30, 0.57, 0.56, 0.86); water_material.metallic = 0.05; water_material.roughness = 0.42; river_water.material_override = water_material; add_child(river_water)
	decor_root = Node3D.new(); decor_root.name = "GardenDecor"; add_child(decor_root)
	garden_visual = GardenVisualScript.new(); garden_visual.name = "M1GardenVisual"; garden_visual.set_wind_enabled(not test_mode); decor_root.add_child(garden_visual)
	camera = Camera3D.new(); camera.current = true; camera.fov = 52; camera.attributes = _build_camera_attributes(); add_child(camera)
	# Static distant scenery: one merged mesh (4 colour surfaces) beyond the
	# island so the wide shot has a horizon. Never rebuilt, never animated.
	distant_scenery = _build_distant_scenery(); add_child(distant_scenery)
	resize_handles = Node3D.new(); resize_handles.name = "ResizeHandles"; resize_handles.visible = false; add_child(resize_handles)
	for axis_name in ["width", "depth", "height"]:
		var handle := MeshInstance3D.new(); handle.name = "Handle_%s" % axis_name
		var handle_mesh := BoxMesh.new(); handle_mesh.size = Vector3(0.22, 0.22, 0.22); handle.mesh = handle_mesh
		var handle_material := StandardMaterial3D.new(); handle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; handle_material.albedo_color = Color(1.0, 0.70, 0.28, 0.82); handle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; handle.material_override = handle_material
		resize_handles.add_child(handle)
	building_world = M2BuildingWorldScript.new()
	cottage_visual = CottageVisualScript.new(); cottage_visual.name = "CottageVisual"; add_child(cottage_visual); cottage_visuals[BUILDING_ID] = cottage_visual
	brush_preview = BrushPreviewScript.new()
	brush_preview.name = "BrushPreview"
	brush_preview.scale = Vector3.ONE * M1PatchGenerator.VOXEL_SCALE
	brush_preview.visible = false
	add_child(brush_preview)
	reference_plane = MeshInstance3D.new()
	reference_plane.name = "ReferencePlane"
	var plane_mesh := PlaneMesh.new(); plane_mesh.size = Vector2(8, 8); reference_plane.mesh = plane_mesh
	var plane_material := StandardMaterial3D.new(); plane_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; plane_material.albedo_color = Color(0.42, 0.82, 0.88, 0.16); plane_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; reference_plane.material_override = plane_material; reference_plane.visible = false; add_child(reference_plane)
	terrain_hit_marker = MeshInstance3D.new(); terrain_hit_marker.name = "TerrainHitMarker"
	var marker_mesh := SphereMesh.new(); marker_mesh.radius = 0.12; marker_mesh.height = 0.24; marker_mesh.radial_segments = 12; marker_mesh.rings = 6; terrain_hit_marker.mesh = marker_mesh
	var marker_material := StandardMaterial3D.new(); marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; marker_material.albedo_color = Color(0.55, 0.92, 0.96, 0.82); marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; marker_material.no_depth_test = true; terrain_hit_marker.material_override = marker_material; terrain_hit_marker.visible = false; add_child(terrain_hit_marker)
	cursor_reticle = CursorReticleScript.new()
	cursor_reticle.name = "M1CursorReticle"
	cursor_reticle.visible = false
	add_child(cursor_reticle)

func _apply_house_shape_preset(preset_id: String) -> bool:
	var index: int = building_world._building_index(selected_building_id)
	if index < 0: return false
	var before: Dictionary = building_world._copy(building_world._document)
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[index]
	if preset_id == "rectangle":
		building.erase("massing_sections")
		building.erase("massing_preset")
	else:
		var view: Dictionary = building_world.get_building(selected_building_id)
		building["massing_sections"] = _serialize_sections(HouseMassing.preset_sections(view, preset_id))
		building["massing_preset"] = preset_id
	if not _sync_surface_record(building):
		building_world._document = before
		_set_status("House shape has too many editable wall runs")
		return false
	building_world._refresh_buckets(building)
	buildings[index] = building
	var ok: bool = building_world._record_change(before)
	_close_house_shape_picker(false)
	if ok:
		_record_history("building")
		_presentation_key = ""
		_update_presentation()
		_set_status("House shape: %s" % HouseMassing.shape_name(building_world.get_building(selected_building_id)))
	else:
		_set_status("House shape unchanged")
	return ok

func _commit_portion_placement() -> bool:
	if not portion_placement_active: return false
	_update_portion_preview()
	if not portion_valid:
		_set_status("Cannot add portion: %s" % portion_reason)
		return false
	var index: int = building_world._building_index(selected_building_id)
	if index < 0: return false
	var committed_level: int = portion_level
	var before: Dictionary = building_world._copy(building_world._document)
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[index]
	var view: Dictionary = building_world.get_building(selected_building_id)
	var sections: Array[Dictionary] = HouseMassing.sections_for(view)
	var portion_id: String = building_world._allocate_id("portion")
	sections.append(_candidate_portion(portion_id))
	building["massing_sections"] = _serialize_sections(sections)
	building["massing_preset"] = "custom"
	if not _sync_surface_record(building):
		building_world._document = before
		_clear_portion_placement()
		_set_status("Cannot add portion: too many editable wall runs")
		return false
	building_world._refresh_buckets(building)
	buildings[index] = building
	var ok: bool = building_world._record_change(before)
	_clear_portion_placement()
	if ok:
		_record_history("building")
		_presentation_key = ""
		_update_presentation()
		if committed_level > 0:
			var updated: Dictionary = building_world.get_building(selected_building_id)
			var floor_portions: int = HouseMassing.sections_on_level(HouseMassing.sections_for(updated), committed_level).size()
			_set_status("Floor %d portion joined • %d portions on this floor" % [committed_level + 1, floor_portions])
		else:
			_set_status("House portion joined • %d total portions" % HouseMassing.sections_for(building_world.get_building(selected_building_id)).size())
	else:
		_set_status("House portion could not be saved")
	return ok

func _remove_last_portion() -> bool:
	var index: int = building_world._building_index(selected_building_id)
	if index < 0: return false
	var view: Dictionary = building_world.get_building(selected_building_id)
	var sections: Array[Dictionary] = HouseMassing.sections_for(view)
	if sections.size() <= 1:
		_set_status("This house has no added portions")
		return false
	var before: Dictionary = building_world._copy(building_world._document)
	sections.pop_back()
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[index]
	if sections.size() <= 1:
		building.erase("massing_sections")
		building.erase("massing_preset")
	else:
		building["massing_sections"] = _serialize_sections(sections)
		building["massing_preset"] = "custom"
	if not _sync_surface_record(building):
		building_world._document = before
		return false
	building_world._refresh_buckets(building)
	buildings[index] = building
	var ok: bool = building_world._record_change(before)
	_close_house_shape_picker(false)
	if ok:
		_record_history("building")
		_presentation_key = ""
		_update_presentation()
		_set_status("Removed last house portion")
	return ok

func _sync_surface_record(building: Dictionary) -> bool:
	return MassingSurfaces.sync_building(building_world, building)

func _sync_loaded_massing_surfaces() -> void:
	if not building_world: return
	var revision: int = building_world.get_revision()
	if revision == _massing_surface_sync_revision: return
	_massing_surface_sync_revision = revision
	var buildings: Array = building_world._document.get("buildings", [])
	var changed := false
	for index in buildings.size():
		var building: Dictionary = buildings[index]
		var before_surfaces: String = JSON.stringify(building.get("surfaces", []))
		if not _sync_surface_record(building): continue
		building_world._refresh_buckets(building)
		buildings[index] = building
		changed = changed or before_surfaces != JSON.stringify(building.get("surfaces", []))
	if changed:
		building_world._document["next_id"] = building_world._next_id
		_presentation_key = ""

func _update_presentation() -> void:
	_sync_loaded_massing_surfaces()
	super._update_presentation()

func _begin_new_attachment(kind: String) -> void:
	_sync_loaded_massing_surfaces()
	super._begin_new_attachment(kind)
	if detail_move_active:
		_set_status("Place %s • D-pad ←/→ cycles walls/floors • A place / B cancel" % kind.replace("_", " "))

func _cycle_attachment_surface(direction: int) -> void:
	super._cycle_attachment_surface(direction)
	if not detail_move_active: return
	var label: String = WallPlacement.surface_label(building_world.get_building(selected_building_id), detail_move_surface_id)
	_set_status("Support: %s • left stick move • A commit / B cancel" % label)

func _update_presentation_target_label() -> void:
	pass

## ---- Step 3 (2026-09-15): live DOF, live pitch limit, distant scenery ----

## The live input clamp. `_read_camera_and_cursor` is resolved on the live chain
## (m2_scene_house_editing -> ... -> this file -> ... -> m1_scene); every link
## applies its own per-file pitch clamp through super, and this override is the
## most-derived one that runs AFTER them in the normal path, so the floor below
## is the effective limit the player can reach. Verified with
## tools/bob_clamp_probe.gd (min 0.0800 before -> 0.5500 after; max 1.4000
## unchanged). m2_scene_house_editing (portion placement) and m2_scene_pc_input
## (mouse drag) clamp outside this path and carry the same 0.55 floor.
func _read_camera_and_cursor(delta: float) -> void:
	super._read_camera_and_cursor(delta)
	_enforce_hamlet_pitch_limit()

func _enforce_hamlet_pitch_limit() -> void:
	if camera_pitch < HAMLET_PITCH_MIN:
		camera_pitch = HAMLET_PITCH_MIN

## Real depth of field on the LIVE camera.
## m1_scene.gd's `_update_depth_of_field` is NEVER reached on the live chain:
## the live camera transform is produced further up the chain (m1_scene_cottage_style
## -> m1_scene_building_camera / m1_scene_thor_retest / m1_scene_playtest_repair,
## whose `view_context` branches do their own camera math and do not call the
## m1_scene version). Proved with tools/bob_dof_proof.gd: after detaching the
## attributes and calling `_update_camera()`, they stayed detached, i.e. nothing
## live called m1_scene's helper. So the live DOF is driven from this override,
## which runs after the whole `_update_camera` cascade (every link calls super and
## this is one of the most-derived definitions reached).
func _update_camera() -> void:
	super._update_camera()
	_apply_hamlet_depth_of_field()

func _apply_hamlet_depth_of_field() -> void:
	if not camera: return
	var attributes := camera.attributes as CameraAttributesPractical
	if attributes == null:
		attributes = _build_camera_attributes()
		camera.attributes = attributes
	if camera_distance < HAMLET_DOF_MIN_DISTANCE:
		# Close/mid framings (the approved cottage closeup and the close-up
		# render gates): both stages off, so the DOF pass is skipped entirely and
		# those captures stay exactly as sharp/stable as before it was wired.
		attributes.dof_blur_near_enabled = false
		attributes.dof_blur_far_enabled = false
		return
	attributes.dof_blur_near_enabled = true
	attributes.dof_blur_near_distance = maxf(4.0, camera_distance - HAMLET_DOF_NEAR_OFFSET)
	attributes.dof_blur_near_transition = HAMLET_DOF_NEAR_TRANSITION
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_far_distance = camera_distance + HAMLET_DOF_FAR_OFFSET
	attributes.dof_blur_far_transition = HAMLET_DOF_FAR_TRANSITION
	attributes.dof_blur_amount = HAMLET_DOF_AMOUNT

func _build_camera_attributes() -> CameraAttributesPractical:
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_near_enabled = camera_distance > HAMLET_DOF_MIN_DISTANCE
	attributes.dof_blur_far_enabled = camera_distance > HAMLET_DOF_MIN_DISTANCE
	attributes.dof_blur_amount = HAMLET_DOF_AMOUNT
	if attributes.dof_blur_near_enabled:
		attributes.dof_blur_near_distance = maxf(4.0, camera_distance - HAMLET_DOF_NEAR_OFFSET)
		attributes.dof_blur_near_transition = HAMLET_DOF_NEAR_TRANSITION
		attributes.dof_blur_far_distance = camera_distance + HAMLET_DOF_FAR_OFFSET
		attributes.dof_blur_far_transition = HAMLET_DOF_FAR_TRANSITION
	return attributes

## One merged static mesh for the whole distant ring: 4 colour surfaces, 4 draw
## calls, no shadow pass, no per-frame update. Hardcoded (deterministic) so the
## render-determinism gates are unaffected.
func _build_distant_scenery() -> MeshInstance3D:
	var surfaces: Array[Dictionary] = []
	for _colour in HAMLET_SCENERY_COLOURS:
		surfaces.append({"vertices": [] as Array[Vector3], "normals": [] as Array[Vector3], "indices": [] as Array[int]})
	var centre := Vector2(24.0, 24.0)
	for ridge_value in HAMLET_HILL_RING:
		var ridge: Dictionary = ridge_value
		var angle := deg_to_rad(float(ridge["angle"]))
		var radius := float(ridge["radius"])
		var point := centre + Vector2(cos(angle), sin(angle)) * radius
		_append_mound(surfaces, int(ridge.get("material", 0)), Vector3(point.x, 0.0, point.y), float(ridge["width"]), float(ridge["depth"]), float(ridge["height"]), Basis(Vector3.UP, angle))
	for farm_value in HAMLET_FARMSTEADS:
		var farm: Dictionary = farm_value
		var angle := deg_to_rad(float(farm["angle"]))
		var radius := float(farm["radius"])
		var point := centre + Vector2(cos(angle), sin(angle)) * radius
		_append_farmstead(surfaces, Vector3(point.x, 0.0, point.y), float(farm.get("scale", 1.0)), Basis(Vector3.UP, deg_to_rad(float(farm.get("yaw", 0.0)))))
	var mesh := ArrayMesh.new()
	var geometry_added := false
	for index in surfaces.size():
		var surface: Dictionary = surfaces[index]
		if (surface["vertices"] as Array).is_empty(): continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(surface["vertices"])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(surface["normals"])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(surface["indices"])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.albedo_color = HAMLET_SCENERY_COLOURS[index]
		material.roughness = 0.95
		material.specular = 0.0
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
		geometry_added = true
	var node := MeshInstance3D.new()
	node.name = "DistantHamlet"
	node.mesh = mesh if geometry_added else null
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

## Three stacked boxes = a stepped mound silhouette. Cheap, voxel-consistent, and
## legible as a rolling hill once the fog gets to it.
func _append_mound(surfaces: Array, material_index: int, base_center: Vector3, width: float, depth: float, height: float, basis: Basis) -> void:
	var layers := [
		{"height": 0.38, "width": 1.0, "depth": 1.0},
		{"height": 0.28, "width": 0.76, "depth": 0.80},
		{"height": 0.20, "width": 0.52, "depth": 0.58},
		{"height": 0.14, "width": 0.28, "depth": 0.34},
	]
	var y := 0.0
	for layer_value in layers:
		var layer: Dictionary = layer_value
		var layer_height: float = height * float(layer["height"])
		_append_box(surfaces, material_index, Vector3(base_center.x, y + layer_height * 0.5, base_center.z),
			Vector3(width * float(layer["width"]), layer_height, depth * float(layer["depth"])), basis)
		y += layer_height

func _append_farmstead(surfaces: Array, base_center: Vector3, scale_value: float, basis: Basis) -> void:
	var wall := Vector3(6.0, 3.4, 4.4) * scale_value
	var roof := Vector3(6.8, 1.5, 5.0) * scale_value
	_append_box(surfaces, 2, Vector3(base_center.x, wall.y * 0.5, base_center.z), wall, basis)
	_append_box(surfaces, 3, Vector3(base_center.x, wall.y + roof.y * 0.5, base_center.z), roof, basis)

func _append_box(surfaces: Array, material_index: int, center: Vector3, size: Vector3, basis: Basis) -> void:
	if material_index < 0 or material_index >= surfaces.size(): return
	var surface: Dictionary = surfaces[material_index]
	var vertices: Array = surface["vertices"]
	var normals: Array = surface["normals"]
	var indices: Array = surface["indices"]
	var half := size * 0.5
	var faces := [
		[Vector3.UP, [Vector3(-half.x, half.y, -half.z), Vector3(half.x, half.y, -half.z), Vector3(half.x, half.y, half.z), Vector3(-half.x, half.y, half.z)]],
		[Vector3.DOWN, [Vector3(-half.x, -half.y, half.z), Vector3(half.x, -half.y, half.z), Vector3(half.x, -half.y, -half.z), Vector3(-half.x, -half.y, -half.z)]],
		[Vector3.FORWARD, [Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z), Vector3(half.x, half.y, -half.z), Vector3(-half.x, half.y, -half.z)]],
		[Vector3.BACK, [Vector3(half.x, -half.y, half.z), Vector3(-half.x, -half.y, half.z), Vector3(-half.x, half.y, half.z), Vector3(half.x, half.y, half.z)]],
		[Vector3.LEFT, [Vector3(-half.x, -half.y, half.z), Vector3(-half.x, -half.y, -half.z), Vector3(-half.x, half.y, -half.z), Vector3(-half.x, half.y, half.z)]],
		[Vector3.RIGHT, [Vector3(half.x, -half.y, -half.z), Vector3(half.x, -half.y, half.z), Vector3(half.x, half.y, half.z), Vector3(half.x, half.y, -half.z)]],
	]
	for face in faces:
		var normal: Vector3 = basis * (face[0] as Vector3)
		var base := vertices.size()
		for corner in face[1]:
			vertices.append(center + basis * (corner as Vector3))
			normals.append(normal)
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	surface["vertices"] = vertices
	surface["normals"] = normals
	surface["indices"] = indices
	surfaces[material_index] = surface
