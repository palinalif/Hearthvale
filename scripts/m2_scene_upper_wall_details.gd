extends "res://scripts/m2_scene_multi_floor.gd"

## Final M2 integration layer for editable upper-storey facades. The M1 world
## setup is reproduced only to swap in the M2-aware BuildingWorld subclass;
## everything else stays on the established scene inheritance chain.
const M2BuildingWorldScript = preload("res://scripts/m2_building_world.gd")
const MassingSurfaces = preload("res://scripts/m2_massing_wall_surfaces.gd")

var _massing_surface_sync_revision := -1

func _build_world() -> void:
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-52, -28, 0); sun.light_color = Color("#fff0d5"); sun.light_energy = 1.25; sun.shadow_enabled = true; add_child(sun)
	var environment_node := WorldEnvironment.new(); var environment := Environment.new(); environment.background_mode = Environment.BG_COLOR; environment.background_color = Color("#c3d2c5"); environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color = Color("#c2d5e0"); environment.ambient_light_energy = 0.55; environment.fog_enabled = false; environment.fog_light_color = Color("#9aaeb7"); environment.fog_density = 0.003; environment_node.environment = environment; add_child(environment_node)
	river_water = MeshInstance3D.new(); river_water.name = "RiverWater"; river_water.mesh = _build_river_water_mesh(); river_water.position.y = 5.0
	var water_material := StandardMaterial3D.new(); water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; water_material.albedo_color = Color(0.30, 0.57, 0.56, 0.86); water_material.metallic = 0.05; water_material.roughness = 0.42; river_water.material_override = water_material; add_child(river_water)
	decor_root = Node3D.new(); decor_root.name = "GardenDecor"; add_child(decor_root)
	garden_visual = GardenVisualScript.new(); garden_visual.name = "M1GardenVisual"; garden_visual.set_wind_enabled(not test_mode); decor_root.add_child(garden_visual)
	camera = Camera3D.new(); camera.current = true; camera.fov = 52; add_child(camera)
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
