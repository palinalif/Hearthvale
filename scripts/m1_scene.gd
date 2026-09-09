extends Node3D
## Controller-first M1 playtest: one cottage recipe beside a volumetric bank.

const PATCH_SIZE := Vector3i(48, 32, 48)
const BUILDING_ID := "building-1"
const M1PatchGenerator = preload("res://scripts/m1_patch_generator.gd")
const BuildingWorldScript = preload("res://scripts/building_world.gd")
const CottageVisualScript = preload("res://scripts/cottage_visual.gd")
const BrushPreviewScript = preload("res://scripts/brush_preview.gd")
const CursorReticleScript = preload("res://scripts/m1_cursor_reticle.gd")
const LandscapeScript = preload("res://scripts/landscape_state.gd")
const Grid = preload("res://scripts/visual_grid.gd")
const Flora = preload("res://scripts/vegetation_mesh.gd")

const GardenVisualScript = preload("res://scripts/m1_garden_visual.gd")

@export var checkpoint_root := "user://m1_checkpoints"
@export var test_mode := false

var backend: Node
var building_world: RefCounted
var cottage_visual: Node3D
var cottage_visuals: Dictionary = {}
var brush_preview: Node3D
var preview_cells: Array[Vector3i] = []
var preview_center := Vector3.ZERO
var _preview_key := ""
var cursor := Vector3(32.0, 8.0, 28.0)
var terrain_cursor := Vector3(32.0, 8.0, 28.0)
var cottage_cursor := Vector3(22.0, 10.0, 18.0)
var camera_yaw := -1.1
var camera_pitch := 0.66
var camera_distance := 36.0
var brush_radius := 2.0
var brush_strength := 6.0
var brush_falloff := 0.45
var height_snap_enabled := false
var reference_mode := "ground"
var sculpt_tool := "raise"
var view_context := "terrain"
var precision_mode := false
var menu_open := false
var tools_open := false
var detail_open := false
var selected_detail_id := ""
var selected_surface_id := ""
var selected_building_id := BUILDING_ID
var detail_move_active := false
var detail_move_position := Vector3.ZERO
var detail_move_surface_id := ""
var resize_active := false
var resize_locked := false
var resize_dimensions := Vector3.ZERO
var resize_preview_dimensions := Vector3.ZERO
var resize_accumulator := Vector3.ZERO
var resize_axis := "width"
var stroke_active := false
var stroke_reference: Dictionary = {}
var stroke_surface_normal := Vector3.UP
var stroke_aim_offset := Vector3.ZERO
var keep_reference := false
var status_text := "Loading cottage…"
var last_frame_costs: Dictionary = {}
var _last_focus := true
var _shutting_down := false
var _pause_buttons: Dictionary = {}
var _tool_buttons: Dictionary = {}
var _presentation_key := ""
var _history_tags: Array[String] = []
var _redo_tags: Array[String] = []
var _building_dirty := false
var _restoring := false
var _player_restored := false
var _review_menu_after_ready := false
var _review_clean := false
var _review_edited := false
var _blocked_until_accept_release := false

var camera: Camera3D
var hud: CanvasLayer
var status_label: Label
var context_label: Label
var target_label: Label
var debug_label: Label
var pause_panel: PanelContainer
var tools_panel: PanelContainer
var decor_root: Node3D
var resize_handles: Node3D
var reference_plane: MeshInstance3D
var terrain_hit_marker: MeshInstance3D
var cursor_reticle: Node3D
var river_water: MeshInstance3D
var garden_visual: Node3D
var landscape_state := LandscapeScript.new()
var landscape_active := false
var _landscape_before: Dictionary = {}
var _landscape_history: Array[Dictionary] = []
var _landscape_redo: Array[Dictionary] = []
var _plant_elapsed := 0.0
var _plant_last := Vector3.INF
var _plant_sequence := 0

var _terrain_target_valid := false
var _terrain_target_point := Vector3.ZERO
var _terrain_target_normal := Vector3.UP
var _terrain_action_labels: Array[String] = ["Raise", "Dig", "Level", "Slope", "Smooth", "Foliage brush", "Tree brush", "Clear planting", "Radius +", "Radius -", "Strength +", "Strength -", "Falloff +", "Falloff -", "Height snap: off", "Reference: ground", "Reference: wall", "Reference: ceiling", "Resample reference", "Keep reference"]
var _cottage_action_labels: Array[String] = ["Move selected window", "Support: next", "Support: previous", "Replace selected", "Suppress / restore", "Reattach selected", "Add flower box", "Add shutter", "Delete selected surface", "Material: warm plaster", "Miniature scale", "Duplicate cottage", "Close"]

func _ready() -> void:
	get_window().title = "Hearthvale — M1"
	_setup_input_map()
	_apply_review_args()
	_build_world()
	_build_ui()
	if _review_clean: hud.visible = false
	_create_backend()
	_last_focus = get_window().has_focus()
	_update_camera()
	_set_status(status_text)
	if backend and backend.has_signal("ready_changed"): backend.ready_changed.connect(_on_backend_ready)
	if backend and backend.has_signal("changed"): backend.changed.connect(_on_backend_changed)
	if Input.has_signal("joy_connection_changed"): Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if building_world and building_world.has_signal("changed"): building_world.changed.connect(_on_building_changed)
	if backend and backend.has_method("is_ready") and backend.is_ready(): _on_backend_ready(true)

func _process(delta: float) -> void:
	if _shutting_down: return
	if (stroke_active or landscape_active) and (menu_open or tools_open or detail_open or _restoring):
		_cancel_current_edit("Sculpting cancelled")
	if not menu_open and not tools_open and not detail_open:
		_read_camera_and_cursor(delta)
	if detail_move_active and not menu_open and not tools_open and not detail_open:
		_read_detail_move(delta)
	var phase_started := Time.get_ticks_usec()
	if stroke_active and backend and backend.has_method("update_stroke"):
		backend.update_stroke(cursor + stroke_aim_offset, delta)
	last_frame_costs["sculpt_ms"] = (Time.get_ticks_usec() - phase_started) / 1000.0
	if landscape_active: _update_plant_stroke(delta)
	_update_camera()
	phase_started = Time.get_ticks_usec()
	_update_brush_preview()
	_update_cursor_reticle()
	last_frame_costs["preview_ms"] = (Time.get_ticks_usec() - phase_started) / 1000.0
	_update_presentation()
	_update_debug_overlay()
	var focused := get_window().has_focus()
	if not focused and _last_focus: _cancel_current_edit("Window focus lost")
	_last_focus = focused

func _notification(what: int) -> void:
	if _shutting_down: return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_cancel_current_edit("Application suspended")
		_set_menu(true)
		if _world_is_dirty(): _save_all()

func _input(event: InputEvent) -> void:
	if _shutting_down: return
	if _blocked_until_accept_release:
		if event.is_action_released("m1_accept"):
			_blocked_until_accept_release = false
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_accept"):
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("m1_pause"):
		_set_menu(not menu_open)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("m1_view") and not menu_open:
		_set_view_context("terrain" if view_context == "building" else "building", "Context changed")
		get_viewport().set_input_as_handled()
		return
	if menu_open:
		_handle_menu_input(event)
		return
	if tools_open or detail_open:
		_handle_overlay_input(event)
		return
	if view_context == "building" and event.is_action_pressed("m1_cycle_left"):
		if resize_active:
			resize_axis = "depth" if resize_axis == "width" else "width"
			_set_status("Resize %s: left stick, D-pad up/down height" % resize_axis)
			get_viewport().set_input_as_handled(); return
		_cycle_building(-1); get_viewport().set_input_as_handled(); return
	if view_context == "building" and event.is_action_pressed("m1_cycle_right"):
		if resize_active:
			resize_axis = "depth" if resize_axis == "width" else "width"
			_set_status("Resize %s: left stick, D-pad up/down height" % resize_axis)
			get_viewport().set_input_as_handled(); return
		_cycle_building(1); get_viewport().set_input_as_handled(); return
	if event.is_action_pressed("m1_precision"):
		precision_mode = not precision_mode
		_set_status("Precision %s" % ("ON" if precision_mode else "OFF"))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("m1_tools"):
		_open_actions_for_context()
		var buttons: Array = _visible_action_buttons()
		if not buttons.is_empty(): (buttons[0] as Button).grab_focus()
		get_viewport().set_input_as_handled()
		return
	if view_context == "terrain":
		if event.is_action_pressed("m1_cancel"):
			_cancel_current_edit("Stroke cancelled")
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("m1_accept"):
			if _terrain_target_valid:
				if sculpt_tool in ["foliage", "tree", "clear_planting"]: _begin_plant_stroke()
				else: _begin_stroke()
			else: _set_status("No terrain target under cursor")
			get_viewport().set_input_as_handled()
		elif event.is_action_released("m1_accept"):
			if landscape_active: _end_plant_stroke()
			else: _end_stroke()
			get_viewport().set_input_as_handled()
	else:
		if event.is_action_pressed("m1_accept"):
			if detail_move_active:
				_commit_detail_move()
			elif resize_active: _commit_resize()
			else: _begin_resize()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("m1_cancel"):
			if detail_move_active: _cancel_detail_move()
			elif resize_active: _cancel_resize()
			else: _set_menu(true)
			get_viewport().set_input_as_handled()
		elif resize_active and event.is_action_pressed("m1_height_up"):
			var height_step := 0.25 if precision_mode else 1.0
			resize_accumulator.y = minf(resize_accumulator.y + height_step, BuildingWorldScript.MAX_DIMENSIONS.y)
			resize_preview_dimensions.y = snappedf(resize_accumulator.y, height_step)
			get_viewport().set_input_as_handled()
		elif resize_active and event.is_action_pressed("m1_height_down"):
			var height_step := 0.25 if precision_mode else 1.0
			resize_accumulator.y = maxf(resize_accumulator.y - height_step, BuildingWorldScript.MIN_DIMENSIONS.y)
			resize_preview_dimensions.y = snappedf(resize_accumulator.y, height_step)
			get_viewport().set_input_as_handled()
	if event.is_action_pressed("m1_undo"): _undo()
	if event.is_action_pressed("m1_redo"): _redo()

func _setup_input_map() -> void:
	_ensure_action("m1_accept"); _button("m1_accept", JOY_BUTTON_A); _key("m1_accept", KEY_ENTER)
	_ensure_action("m1_cancel"); _button("m1_cancel", JOY_BUTTON_B); _key("m1_cancel", KEY_ESCAPE)
	_ensure_action("m1_pause"); _button("m1_pause", JOY_BUTTON_START); _key("m1_pause", KEY_P)
	_ensure_action("m1_tools"); _button("m1_tools", JOY_BUTTON_X); _key("m1_tools", KEY_X)
	_ensure_action("m1_precision"); _button("m1_precision", JOY_BUTTON_LEFT_STICK); _key("m1_precision", KEY_F)
	_ensure_action("m1_view"); _button("m1_view", JOY_BUTTON_BACK); _key("m1_view", KEY_TAB)
	_ensure_action("m1_undo"); _button("m1_undo", JOY_BUTTON_LEFT_SHOULDER); _key("m1_undo", KEY_Z)
	_ensure_action("m1_redo"); _button("m1_redo", JOY_BUTTON_RIGHT_SHOULDER); _key("m1_redo", KEY_C)
	_ensure_action("m1_move_left"); _axis("m1_move_left", JOY_AXIS_LEFT_X, -1.0); _key("m1_move_left", KEY_A)
	_ensure_action("m1_move_right"); _axis("m1_move_right", JOY_AXIS_LEFT_X, 1.0); _key("m1_move_right", KEY_D)
	_ensure_action("m1_move_up"); _axis("m1_move_up", JOY_AXIS_LEFT_Y, -1.0); _key("m1_move_up", KEY_W)
	_ensure_action("m1_move_down"); _axis("m1_move_down", JOY_AXIS_LEFT_Y, 1.0); _key("m1_move_down", KEY_S)
	_ensure_action("m1_orbit_left"); _axis("m1_orbit_left", JOY_AXIS_RIGHT_X, -1.0); _key("m1_orbit_left", KEY_LEFT)
	_ensure_action("m1_orbit_right"); _axis("m1_orbit_right", JOY_AXIS_RIGHT_X, 1.0); _key("m1_orbit_right", KEY_RIGHT)
	_ensure_action("m1_orbit_up"); _axis("m1_orbit_up", JOY_AXIS_RIGHT_Y, -1.0); _key("m1_orbit_up", KEY_UP)
	_ensure_action("m1_orbit_down"); _axis("m1_orbit_down", JOY_AXIS_RIGHT_Y, 1.0); _key("m1_orbit_down", KEY_DOWN)
	_ensure_action("m1_zoom_in"); _axis("m1_zoom_in", JOY_AXIS_TRIGGER_RIGHT, 1.0); _key("m1_zoom_in", KEY_EQUAL)
	_ensure_action("m1_zoom_out"); _axis("m1_zoom_out", JOY_AXIS_TRIGGER_LEFT, 1.0); _key("m1_zoom_out", KEY_MINUS)
	_ensure_action("m1_height_up"); _button("m1_height_up", JOY_BUTTON_DPAD_UP); _key("m1_height_up", KEY_E)
	_ensure_action("m1_height_down"); _button("m1_height_down", JOY_BUTTON_DPAD_DOWN); _key("m1_height_down", KEY_Q)
	_ensure_action("m1_cycle_left"); _button("m1_cycle_left", JOY_BUTTON_DPAD_LEFT); _key("m1_cycle_left", KEY_BRACKETLEFT)
	_ensure_action("m1_cycle_right"); _button("m1_cycle_right", JOY_BUTTON_DPAD_RIGHT); _key("m1_cycle_right", KEY_BRACKETRIGHT)
	_ensure_action("m1_debug"); _button("m1_debug", JOY_BUTTON_Y); _key("m1_debug", KEY_F1)
	_ensure_action("m1_focus"); _button("m1_focus", JOY_BUTTON_RIGHT_STICK); _key("m1_focus", KEY_G)

func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action): InputMap.add_action(action)
	if action.begins_with("m1_move_") or action.begins_with("m1_orbit_"):
		InputMap.action_set_deadzone(action, 0.18)
	elif action.begins_with("m1_zoom_"):
		InputMap.action_set_deadzone(action, 0.05)
func _button(action: String, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new(); event.button_index = button; InputMap.action_add_event(action, event)
func _axis(action: String, axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new(); event.axis = axis; event.axis_value = value; InputMap.action_add_event(action, event)
func _key(action: String, key: Key) -> void:
	var event := InputEventKey.new(); event.keycode = key; InputMap.action_add_event(action, event)

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
	building_world = BuildingWorldScript.new()
	cottage_visual = CottageVisualScript.new(); cottage_visual.name = "CottageVisual"; add_child(cottage_visual); cottage_visuals[BUILDING_ID] = cottage_visual
	brush_preview = BrushPreviewScript.new()
	brush_preview.name = "BrushPreview"
	# BrushPreview geometry is expressed in native cells; map it to the same
	# world-space voxel edge as the terrain and authored visual details.
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

func _build_river_water_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for z_index in M1PatchGenerator.PATCH_SIZE.z + 1:
		var world_z := float(z_index) * M1PatchGenerator.VOXEL_SCALE
		var center := M1PatchGenerator.river_center_x(world_z)
		var half_width := M1PatchGenerator.river_half_width(world_z)
		vertices.append(Vector3(center - half_width, 0, world_z))
		vertices.append(Vector3(center + half_width, 0, world_z))
		normals.append(Vector3.UP); normals.append(Vector3.UP)
		uvs.append(Vector2(0, world_z * 0.25)); uvs.append(Vector2(1, world_z * 0.25))
		if z_index < M1PatchGenerator.PATCH_SIZE.z:
			var base := z_index * 2
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals; arrays[Mesh.ARRAY_TEX_UV] = uvs; arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _refresh_river_water_from_terrain() -> void:
	if not river_water or not backend or not backend.has_method("voxel_at") or not backend.is_ready(): return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var unit := M1PatchGenerator.VOXEL_SCALE
	var water_cell_y := floori(5.0 / unit) - 1
	var support_cell_y := floori(3.0 / unit)
	for z in M1PatchGenerator.PATCH_SIZE.z:
		var best_start := -1; var best_end := -1; var run_start := -1
		for x in range(floori(37.5 / unit), M1PatchGenerator.PATCH_SIZE.x + 1):
			var qualifies: bool = x < M1PatchGenerator.PATCH_SIZE.x and int(backend.voxel_at(Vector3i(x, water_cell_y, z))) == 0 and int(backend.voxel_at(Vector3i(x, support_cell_y, z))) != 0
			if qualifies and run_start < 0: run_start = x
			if not qualifies and run_start >= 0:
				if x - run_start > best_end - best_start: best_start = run_start; best_end = x
				run_start = -1
		if best_start < 0: continue
		var base := vertices.size()
		var x0 := float(best_start) * unit; var x1 := float(best_end) * unit
		var z0 := float(z) * unit; var z1 := float(z + 1) * unit
		vertices.append_array(PackedVector3Array([Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x0, 0, z1), Vector3(x1, 0, z1)]))
		for unused in 4: normals.append(Vector3.UP)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	if vertices.is_empty(): return
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals; arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	river_water.mesh = mesh

func _create_backend() -> void:
	var backend_script := load("res://scripts/terrain_backend.gd")
	if not backend_script:
		_set_status("Terrain backend unavailable")
		return
	backend = backend_script.new()
	backend.name = "TerrainBackend"
	backend.set("checkpoint_root", checkpoint_root)
	backend.set("initial_generator", M1PatchGenerator)
	backend.set("generator_id", M1PatchGenerator.GENERATOR_ID)
	backend.set("require_building_document", true)
	# Keep the same world bounds; native grid and asset cells share one edge.
	backend.set("patch_size", M1PatchGenerator.PATCH_SIZE)
	backend.set("voxel_scale", M1PatchGenerator.VOXEL_SCALE)
	if test_mode: backend.set("initialization_budget_override_ms", 90000)
	add_child(backend)
	if garden_visual and garden_visual.has_method("attach_backend"):
		garden_visual.attach_backend(backend)

func _update_brush_preview() -> void:
	if not brush_preview:
		return
	var visible_now: bool = backend != null and backend.has_method("is_ready") and backend.is_ready() and view_context == "terrain" and not menu_open and not tools_open and not detail_open and not _restoring and not _shutting_down
	brush_preview.visible = visible_now
	if not visible_now:
		if reference_plane: reference_plane.visible = false
		if terrain_hit_marker: terrain_hit_marker.visible = false
		if cursor_reticle and cursor_reticle.has_method("set_target_visible"): cursor_reticle.set_target_visible(false)
		_terrain_target_valid = false
		return
	var scale_value := float(backend.get("voxel_scale")) if backend.get("voxel_scale") != null else 1.0
	if scale_value <= 0.0:
		scale_value = 1.0
	# Keep the sampled target in authored world coordinates.  Native-cell
	# snapping is only a cache aid; the backend receives this same raw point
	# when a stroke begins and while it advances.
	var target_center: Vector3 = cursor
	var snapped_center := Vector3(snappedf(target_center.x, scale_value), snappedf(target_center.y, scale_value), snappedf(target_center.z, scale_value))
	var remove := sculpt_tool == "dig"
	var preview_normal := _active_reference_normal()
	var sample_center: Vector3 = backend.get_stroke_preview_center(cursor + stroke_aim_offset) if stroke_active else target_center
	var sample_normal := stroke_surface_normal if stroke_active else preview_normal
	var surface_sample: Dictionary = backend.sample_surface_plane(sample_center, sample_normal, brush_radius + 1.0) if backend.has_method("sample_surface_plane") else {}
	var display_center: Vector3 = target_center
	if bool(surface_sample.get("valid", false)) and surface_sample.get("point", null) is Vector3:
		display_center = surface_sample["point"]
	else:
		var local_surface := _find_local_surface(sample_center, sample_normal, scale_value)
		if bool(local_surface.get("valid", false)) and local_surface.get("point", null) is Vector3:
			surface_sample = local_surface
			display_center = local_surface["point"]
	var target_valid := bool(surface_sample.get("valid", false)) and surface_sample.get("point", null) is Vector3
	_terrain_target_valid = target_valid
	if target_valid:
		_terrain_target_point = display_center
		_terrain_target_normal = surface_sample.get("normal", Vector3.UP) if surface_sample.get("normal", Vector3.UP) is Vector3 else Vector3.UP
	else:
		preview_center = Vector3.ZERO
		preview_cells.clear()
		brush_preview.visible = false
		if reference_plane: reference_plane.visible = false
		if terrain_hit_marker: terrain_hit_marker.visible = false
		if cursor_reticle and cursor_reticle.has_method("set_target_visible"): cursor_reticle.set_target_visible(false)
		_set_status("No terrain target under cursor")
		return
	var revision := int(backend.stats().get("revision", -1)) if backend.has_method("stats") else -1
	var key := "%d|%s|%s|%s|%.3f|%s|%s|%s|%s|%s|%d" % [revision, str(snapped_center), str(display_center), str(preview_normal), brush_radius, str(remove), sculpt_tool, reference_mode, str(keep_reference), str(stroke_reference), get_instance_id()]
	if key == _preview_key:
		return
	_preview_key = key
	preview_center = display_center
	# Keep aiming feedback cheap: the authoritative terrain preview API clones a
	# bounded native buffer and is reserved for one-shot transactions.  A live
	# sculpt stroke uses the faint volume as its influence cue; actual changed
	# cells are reported only after the native stroke commits.
	preview_cells = _build_influence_cells(display_center, brush_radius / scale_value, remove, scale_value)
	var native_center := display_center / scale_value
	var native_radius := brush_radius / scale_value
	if brush_preview.has_method("update_geometry"):
		brush_preview.update_geometry(native_center, native_radius, remove, preview_cells)
	_update_reference_guides(display_center, surface_sample)
	if cursor_reticle and cursor_reticle.has_method("update_target"):
		cursor_reticle.update_target(display_center, _terrain_target_normal, brush_radius, sculpt_tool, camera, true)

func _update_cursor_reticle() -> void:
	if not cursor_reticle or not cursor_reticle.has_method("update_target"):
		return
	var visible_now := not menu_open and not tools_open and not detail_open and not _restoring and not _shutting_down
	if not visible_now:
		if cursor_reticle.has_method("set_target_visible"): cursor_reticle.set_target_visible(false)
		return
	if view_context == "building" and not menu_open and not tools_open and not detail_open and not _restoring and not _shutting_down:
		cursor_reticle.update_target(cottage_cursor, Vector3.UP, 1.2, "cottage", camera, true)
		return
	var point := _terrain_target_point if _terrain_target_valid else (cursor + stroke_aim_offset if stroke_active else cursor)
	var normal := _terrain_target_normal if _terrain_target_valid else Vector3.UP
	cursor_reticle.update_target(point, normal, brush_radius, sculpt_tool, camera, _terrain_target_valid)

func _find_local_surface(center: Vector3, normal: Vector3, scale_value: float) -> Dictionary:
	var result: Dictionary = {"valid": false}
	if not backend or not backend.has_method("voxel_at"):
		return result
	var native_center := center / scale_value
	var base := Vector3i(floori(native_center.x), floori(native_center.y), floori(native_center.z))
	var radius := ceili(brush_radius / scale_value) + 3
	var best_distance := INF
	var best_cell := Vector3i.ZERO
	var best_face := Vector3i.UP
	var patch: Vector3i = backend.get("patch_size") if backend.get("patch_size") is Vector3i else Vector3i(96, 64, 96)
	# Preserve the previous eight-world-unit recovery reach after refinement.
	var vertical_reach := ceili(8.0 / scale_value)
	var min_y: int = maxi(0, base.y - vertical_reach)
	var max_y: int = mini(patch.y - 1, base.y + vertical_reach)
	# Recovery when the direct surface probe misses: seven columns per axis,
	# including the exact centre, rather than a radius-cubed search every frame.
	var stride := maxi(1, ceili(radius / 3.0))
	for dx in [0, -stride, stride, -2 * stride, 2 * stride, -radius, radius]:
		var x: int = base.x + int(dx)
		if x < 0 or x >= patch.x: continue
		for dz in [0, -stride, stride, -2 * stride, 2 * stride, -radius, radius]:
			var z: int = base.z + int(dz)
			if z < 0 or z >= patch.z: continue
			for y in range(min_y, max_y + 1):
				var cell := Vector3i(x, y, z)
				if backend.voxel_at(cell) == 0:
					continue
				var face := Vector3i.ZERO
				if absf(normal.y) >= maxf(absf(normal.x), absf(normal.z)):
					face = Vector3i.UP if normal.y >= 0.0 else Vector3i.DOWN
				elif absf(normal.x) >= absf(normal.z):
					face = Vector3i.RIGHT if normal.x >= 0.0 else Vector3i.LEFT
				else:
					face = Vector3i.BACK if normal.z >= 0.0 else Vector3i.FORWARD
				var neighbor := cell + face
				if neighbor.x < 0 or neighbor.y < 0 or neighbor.z < 0 or neighbor.x >= patch.x or neighbor.y >= patch.y or neighbor.z >= patch.z:
					continue
				if backend.voxel_at(neighbor) != 0:
					continue
				var point := Vector3(cell) * scale_value + Vector3.ONE * scale_value * 0.5
				if face == Vector3i.UP:
					point.y += scale_value * 0.5
				elif face == Vector3i.DOWN:
					point.y -= scale_value * 0.5
				elif face == Vector3i.RIGHT:
					point.x += scale_value * 0.5
				elif face == Vector3i.LEFT:
					point.x -= scale_value * 0.5
				elif face == Vector3i.BACK:
					point.z += scale_value * 0.5
				else:
					point.z -= scale_value * 0.5
				var distance := point.distance_squared_to(center)
				if distance < best_distance:
					best_distance = distance
					best_cell = cell
					best_face = face
	if best_distance == INF:
		return result
	var best_point := Vector3(best_cell) * scale_value + Vector3.ONE * scale_value * 0.5
	if best_face == Vector3i.UP:
		best_point.y += scale_value * 0.5
	elif best_face == Vector3i.DOWN:
		best_point.y -= scale_value * 0.5
	elif best_face == Vector3i.RIGHT:
		best_point.x += scale_value * 0.5
	elif best_face == Vector3i.LEFT:
		best_point.x -= scale_value * 0.5
	elif best_face == Vector3i.BACK:
		best_point.z += scale_value * 0.5
	else:
		best_point.z -= scale_value * 0.5
	result["valid"] = true
	result["point"] = best_point
	result["normal"] = Vector3(best_face)
	return result

func _build_influence_cells(center: Vector3, native_radius: float, remove: bool, scale_value: float) -> Array[Vector3i]:
	# A sparse surface highlight accompanies the full influence outline. Keep
	# target feedback bounded as native resolution increases; do not scan a cube.
	var result: Array[Vector3i] = []
	if not backend or not backend.has_method("voxel_at"): return result
	var base := Vector3i(floor(center / scale_value))
	var normal := _active_reference_normal()
	var axis := normal.abs().max_axis_index()
	var tangent_a := (axis + 1) % 3; var tangent_b := (axis + 2) % 3
	var direction := Vector3i.ZERO; direction[axis] = 1 if normal[axis] >= 0 else -1
	# Show exact cells at the aim point; the ghost carries the full brush radius.
	for a in range(-1, 2):
		for b in range(-1, 2):
			if Vector2(a, b).length() > native_radius: continue
			var cell := base; cell[tangent_a] += a; cell[tangent_b] += b
			var found := false
			for depth in range(3):
				for sign_value in [1, -1]:
					var candidate: Vector3i = cell + direction * depth * sign_value
					if backend.voxel_at(candidate) != 0 and backend.voxel_at(candidate + direction) == 0:
						result.append(candidate if remove else candidate + direction); found = true; break
				if found: break
	return result

func _update_reference_guides(center: Vector3, sample_override: Dictionary = {}) -> void:
	if not reference_plane or not terrain_hit_marker:
		return
	var sample: Dictionary = sample_override if not sample_override.is_empty() else (backend.sample_surface_plane(center, _reference_normal(), brush_radius + 1.0) if backend.has_method("sample_surface_plane") else {})
	var point = sample.get("point", null)
	var valid: bool = bool(sample.get("valid", false)) and point is Vector3
	terrain_hit_marker.visible = valid
	if valid: terrain_hit_marker.position = point
	var reference: Dictionary = stroke_reference if not stroke_reference.is_empty() else sample
	var reference_point = reference.get("point", point)
	var normal = reference.get("normal", Vector3.UP)
	if sculpt_tool == "level": normal = Vector3.UP
	var show_plane: bool = sculpt_tool in ["level", "slope"] and reference_point is Vector3 and normal is Vector3 and normal.length_squared() > 0.001 and (not stroke_reference.is_empty() or valid)
	reference_plane.visible = show_plane
	if show_plane:
		reference_plane.position = reference_point
		reference_plane.rotation = Quaternion(Vector3.UP, normal.normalized()).get_euler()
		var plane_mesh := reference_plane.mesh as PlaneMesh
		if plane_mesh: plane_mesh.size = Vector2(brush_radius * 2.0, brush_radius * 2.0)

func _on_backend_ready(ready: bool) -> void:
	if not ready: _set_status("Native terrain error"); return
	if _player_restored or _restoring: return
	_restoring = true
	var loaded_ok: bool = backend.load_world() if backend.has_method("load_world") else false
	if loaded_ok:
		var loaded_document: Dictionary = backend.get("loaded_building_document")
		if loaded_document.is_empty() or not BuildingWorldScript.validate_document(loaded_document) or not _load_cottage_document(loaded_document):
			_restoring = false
			_set_menu(true)
			_set_status("Checkpoint cottage design is invalid; reload blocked")
			return
		_building_dirty = false
		_set_status("Cottage and riverbank restored")
	else:
		var backend_stats: Dictionary = backend.stats() if backend.has_method("stats") else {}
		var load_error := str(backend_stats.get("error", ""))
		if not load_error.is_empty() and load_error != "no valid checkpoint":
			_set_menu(true)
			_set_status("Checkpoint load failed; reload blocked")
		else: _set_status("Cottage and riverbank ready")
	_refresh_river_water_from_terrain()
	_restore_landscape(backend.get("loaded_building_document") if loaded_ok else {})
	_player_restored = true
	_restoring = false
	if _review_edited:
		var review_view: Dictionary = building_world.get_building(BUILDING_ID)
		var review_detail: Dictionary = review_view["details"][0]
		building_world.move_detail(BUILDING_ID, str(review_detail["id"]), str(review_detail["anchor"]["surface_id"]), Vector3(-4.0, 3.5, -7.02))
		building_world.resize(BUILDING_ID, Vector3(23, 8, 12))
	if _review_menu_after_ready:
		view_context = "building"
		detail_open = true
		tools_panel.visible = true
		_update_action_buttons()
		var buttons: Array = _visible_action_buttons()
		if not buttons.is_empty(): (buttons[0] as Button).grab_focus()
	if garden_visual and garden_visual.has_method("refresh_terrain"):
		garden_visual.refresh_terrain()
	_update_presentation()

func _apply_review_args() -> void:
	var review_run := false
	var review_arguments: Array = []
	review_arguments.append_array(OS.get_cmdline_args())
	review_arguments.append_array(OS.get_cmdline_user_args())
	for argument in review_arguments:
		if str(argument).begins_with("--review-"): review_run = true
		match str(argument):
			"--review-close":
				view_context = "building"
				cursor = cottage_cursor
				camera_distance = 16.0
			"--review-cottage":
				view_context = "building"
				cursor = cottage_cursor
				camera_distance = 36.0
			"--review-near": camera_distance = 12.0
			"--review-far": camera_distance = 52.0
			"--review-terrain":
				view_context = "terrain"
				cursor = terrain_cursor
			"--review-dig":
				view_context = "terrain"
				sculpt_tool = "dig"
				cursor = terrain_cursor
			"--review-occluded":
				view_context = "terrain"
				cursor = Vector3(23.0, 13.0, 20.0)
			"--review-front": camera_yaw = -2.1
			"--review-clean": _review_clean = true
			"--review-edited": _review_edited = true
			"--review-menu": _review_menu_after_ready = true
	if review_run:
		checkpoint_root = "user://m1-review-%s" % Time.get_ticks_usec()
		test_mode = true

func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if connected or _shutting_down:
		return
	_cancel_current_edit("Controller disconnected")
	_set_menu(true)
	_set_status("Controller disconnected; world paused")

func _on_backend_changed() -> void:
	_refresh_river_water_from_terrain()
	if garden_visual and garden_visual.has_method("refresh_terrain"):
		garden_visual.refresh_terrain()
	_update_presentation()

func _on_building_changed() -> void:
	if not _restoring: _building_dirty = true
	_update_presentation()

func _read_camera_and_cursor(delta: float) -> void:
	var move := Vector2(Input.get_axis("m1_move_left", "m1_move_right"), Input.get_axis("m1_move_up", "m1_move_down"))
	if move.length() > 0.05:
		var magnitude := minf(move.length(), 1.0); move = move.normalized() * pow(magnitude, 1.45)
		if resize_active and view_context == "building":
			var resize_speed: float = 3.5
			var snap_step: float = 1.0
			if precision_mode:
				resize_speed = 1.2
				snap_step = 0.25
			if resize_axis == "width":
				resize_accumulator.x = clampf(resize_accumulator.x + move.x * delta * resize_speed * pow(magnitude, 0.85), BuildingWorldScript.MIN_DIMENSIONS.x, BuildingWorldScript.MAX_DIMENSIONS.x)
				resize_preview_dimensions.x = snappedf(resize_accumulator.x, snap_step)
			else:
				resize_accumulator.z = clampf(resize_accumulator.z - move.y * delta * resize_speed * pow(magnitude, 0.85), BuildingWorldScript.MIN_DIMENSIONS.z, BuildingWorldScript.MAX_DIMENSIONS.z)
				resize_preview_dimensions.z = snappedf(resize_accumulator.z, snap_step)
			_set_status("Resize preview: %.1f × %.1f × %.1f  •  A commit / B cancel" % [resize_preview_dimensions.x, resize_preview_dimensions.y, resize_preview_dimensions.z])
		else:
			if not detail_move_active:
				var speed := lerpf(2.5, 10.0, pow(magnitude, 0.85)); if precision_mode: speed *= 0.35
				var forward := Vector3(sin(camera_yaw), 0, cos(camera_yaw)); var right := Vector3(forward.z, 0, -forward.x); cursor += (right * move.x + forward * move.y) * delta * speed; cursor.x = clampf(cursor.x, 0.5, 47.5); cursor.z = clampf(cursor.z, 0.5, 47.5)
	var orbit_x := Input.get_axis("m1_orbit_left", "m1_orbit_right"); var orbit_y := Input.get_axis("m1_orbit_up", "m1_orbit_down"); camera_yaw += orbit_x * delta * 2.2; camera_pitch = clampf(camera_pitch + orbit_y * delta * 1.5, 0.15, 1.25); var zoom := Input.get_axis("m1_zoom_out", "m1_zoom_in"); camera_distance = clampf(camera_distance - zoom * delta * 18.0, 8, 52)
	if not detail_move_active and not resize_active and Input.is_action_just_pressed("m1_height_up"): cursor.y = clampf(cursor.y + 1.0, 0.0, 31.0)
	if not detail_move_active and not resize_active and Input.is_action_just_pressed("m1_height_down"): cursor.y = clampf(cursor.y - 1.0, 0.0, 31.0)
	if Input.is_action_just_pressed("m1_focus"):
		_focus_selected_building()
	if Input.is_action_just_pressed("m1_debug") and debug_label:
		debug_label.visible = not debug_label.visible
	if view_context == "terrain": terrain_cursor = cursor
	else: cottage_cursor = cursor

func _read_detail_move(delta: float) -> void:
	if detail_move_active and not resize_locked:
		var stick := Vector2(Input.get_axis("m1_move_left", "m1_move_right"), Input.get_axis("m1_move_up", "m1_move_down"))
		if stick.length() > 0.05:
			var magnitude := minf(stick.length(), 1.0)
			var speed := (0.9 if precision_mode else 3.0) * pow(magnitude, 1.45)
			var view: Dictionary = building_world.get_building(selected_building_id)
			var tangent_axis := "x"
			for surface_value in view.get("surfaces", []):
				var surface: Dictionary = surface_value
				if str(surface.get("id", "")) == detail_move_surface_id:
					tangent_axis = "x" if str(surface.get("orientation", "front")) in ["front", "back"] else "z"
					break
			if tangent_axis == "x": detail_move_position.x += stick.x * delta * speed
			else: detail_move_position.z += stick.x * delta * speed
			detail_move_position.y -= stick.y * delta * speed
			detail_move_position.x = clampf(detail_move_position.x, -16.0, 16.0)
			detail_move_position.z = clampf(detail_move_position.z, -16.0, 16.0)
			detail_move_position.y = clampf(detail_move_position.y, 0.5, 16.0)
			_update_presentation()

func _update_camera() -> void:
	if not camera: return
	var target := cursor + Vector3(0, 2, 0); var offset := Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch)) * camera_distance; camera.position = target + offset; camera.look_at(target, Vector3.UP)

func _set_view_context(next_context: String, reason: String = "Context changed") -> bool:
	var normalized := "terrain" if next_context == "terrain" else "building"
	if normalized == view_context:
		_set_status("Terrain mode" if normalized == "terrain" else "Cottage mode")
		return false
	_cancel_current_edit(reason)
	if view_context == "terrain": terrain_cursor = cursor
	else: cottage_cursor = cursor
	view_context = normalized
	cursor = terrain_cursor if normalized == "terrain" else cottage_cursor
	tools_open = false
	detail_open = false
	if tools_panel: tools_panel.visible = false
	if normalized == "terrain":
		_set_status("Terrain mode • %s • A hold / release, B cancel" % sculpt_tool.capitalize())
	else:
		_set_status("Cottage mode • A resize, X actions")
	_update_action_buttons()
	_preview_key = ""
	return true

func _set_sculpt_tool(tool: String) -> bool:
	var normalized := tool.to_lower()
	if normalized not in ["raise", "dig", "level", "slope", "smooth"]:
		return false
	sculpt_tool = normalized
	if view_context != "terrain":
		_set_view_context("terrain", "Terrain tool selected")
	else:
		_cancel_current_edit("Terrain tool selected")
		tools_open = false
		detail_open = false
		if tools_panel: tools_panel.visible = false
	_set_status("Terrain mode • %s • A hold / release, B cancel" % sculpt_tool.capitalize())
	_preview_key = ""
	return true

func _open_actions_for_context() -> void:
	_cancel_current_edit("Actions opened")
	if view_context == "building":
		detail_open = true
		tools_open = false
	else:
		tools_open = true
		detail_open = false
	if tools_panel: tools_panel.visible = true
	_update_action_buttons()
	var buttons := _visible_action_buttons()
	if not buttons.is_empty(): (buttons[0] as Button).grab_focus()
	_set_status("Cottage actions • D-pad choose / A select" if view_context == "building" else "Terrain tools • D-pad choose / A select")

func _visible_action_labels() -> Array[String]:
	return _terrain_action_labels if view_context == "terrain" else _cottage_action_labels

func _visible_action_buttons() -> Array:
	var result: Array = []
	for label in _visible_action_labels():
		if _tool_buttons.has(label): result.append(_tool_buttons[label])
	return result

func _update_action_buttons() -> void:
	var visible_labels := _visible_action_labels()
	for label in _tool_buttons.keys():
		var button: Button = _tool_buttons[label]
		button.visible = visible_labels.has(str(label))
		button.disabled = not button.visible

func _begin_stroke() -> void:
	if view_context != "terrain":
		_set_status("Switch to Terrain mode to sculpt")
		return
	if stroke_active or resize_active or detail_move_active or menu_open or tools_open or detail_open:
		return
	if not _terrain_target_valid:
		_set_status("No terrain target under cursor")
		return
	if not backend or not backend.has_method("begin_stroke"):
		_set_status("Terrain backend unavailable")
		return
	var stroke_center := _terrain_target_point if _terrain_target_valid else cursor
	stroke_aim_offset = stroke_center - cursor
	var reference := {}
	if sculpt_tool in ["level", "slope"] and backend.has_method("sample_surface_plane"):
		if keep_reference and not stroke_reference.is_empty(): reference = stroke_reference.duplicate(true)
		else: reference = backend.sample_surface_plane(stroke_center, _reference_normal(), brush_radius + 1.0)
		reference = _snap_reference(reference)
		if sculpt_tool == "level" and not reference.is_empty(): reference["normal"] = Vector3.UP
	var facing := _reference_normal()
	var settings := {"radius": brush_radius, "strength": brush_strength * (0.25 if precision_mode else 1.0), "falloff": brush_falloff, "surface_normal": facing}
	_landscape_before = landscape_state.document()
	if backend.begin_stroke(sculpt_tool, stroke_center, settings, reference):
		stroke_active = true; stroke_reference = reference; stroke_surface_normal = facing; _set_status("Sculpting %s… release A to finish" % sculpt_tool)

func resample_reference() -> void:
	if backend and backend.has_method("sample_surface_plane"):
		var candidate: Dictionary = backend.sample_surface_plane(cursor, _reference_normal(), brush_radius + 1.0)
		if bool(candidate.get("valid", false)): stroke_reference = _snap_reference(candidate); _preview_key = ""; _set_status("Reference sampled")

func _snap_reference(reference: Dictionary) -> Dictionary:
	var result := reference.duplicate(true)
	if height_snap_enabled and result.get("point", null) is Vector3:
		var point: Vector3 = result["point"]
		point.y = snappedf(point.y, 1.0)
		result["point"] = point
	return result

func _end_stroke() -> void:
	if not stroke_active: return
	var final_target: Vector3 = backend.get_stroke_preview_center(cursor + stroke_aim_offset)
	var ok: bool = backend.end_stroke() if backend and backend.has_method("end_stroke") else false
	if sculpt_tool in ["raise", "dig"]:
		cursor = final_target; terrain_cursor = cursor
	stroke_active = false; stroke_aim_offset = Vector3.ZERO
	if ok:
		landscape_state.clear_edited_cells(backend.get_last_edit_cells(), float(backend.voxel_scale))
		garden_visual.apply_records(landscape_state.records)
		_record_history("terrain")
	_landscape_before.clear()
	_set_status("Stroke committed" if ok else "Stroke unchanged")

func _begin_resize() -> void:
	if detail_move_active: return
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty(): return
	resize_dimensions = view["dimensions"]; resize_preview_dimensions = resize_dimensions; resize_accumulator = resize_dimensions; resize_active = true; resize_locked = false; resize_axis = "width"; _set_status("Resize width: left stick, D-pad left/right axis, up/down height")

func _commit_resize() -> bool:
	if not resize_active: return false
	var ok: bool = building_world.resize(selected_building_id, resize_preview_dimensions)
	resize_active = false
	if ok: _record_history("building")
	_set_status("Cottage resized" if ok else "Resize rejected")
	return ok

func _cancel_resize() -> void:
	resize_active = false; resize_preview_dimensions = resize_dimensions; resize_accumulator = resize_dimensions; _set_status("Resize cancelled")

func _begin_detail_move() -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	var details: Array = view.get("details", [])
	if selected_detail_id.is_empty() and not details.is_empty(): selected_detail_id = str(details[0].get("id", ""))
	for detail_value in details:
		var detail: Dictionary = detail_value
		if str(detail.get("id", "")) != selected_detail_id: continue
		var anchor: Dictionary = detail.get("anchor", {})
		detail_move_surface_id = str(anchor.get("surface_id", ""))
		var local = anchor.get("local_position", detail.get("resolved_position", Vector3.ZERO))
		if local is Vector3: detail_move_position = local
		detail_move_active = true
		resize_locked = false
		detail_open = false
		tools_open = false
		tools_panel.visible = false
		_set_status("Move %s: left stick fine move, A commit / B cancel" % selected_detail_id)
		_update_presentation()
		return

func _commit_detail_move() -> bool:
	if not detail_move_active: return false
	var ok: bool = building_world.move_detail(selected_building_id, selected_detail_id, detail_move_surface_id, detail_move_position)
	detail_move_active = false
	if ok: _record_history("building")
	_set_status("Detail moved" if ok else "Move rejected")
	_update_presentation()
	return ok

func _cancel_detail_move() -> void:
	if not detail_move_active: return
	detail_move_active = false
	_set_status("Move cancelled")
	_update_presentation()

func _cancel_current_edit(reason: String) -> void:
	var accept_was_down: bool = stroke_active or landscape_active or Input.is_action_pressed("m1_accept")
	if landscape_active:
		landscape_state.restore(_landscape_before)
		garden_visual.reset_records(landscape_state.records)
		landscape_active = false
	_landscape_before.clear()
	if stroke_active and backend and backend.has_method("cancel_stroke"): backend.cancel_stroke()
	stroke_active = false
	stroke_aim_offset = Vector3.ZERO
	if resize_active: _cancel_resize()
	if detail_move_active: _cancel_detail_move()
	if accept_was_down: _blocked_until_accept_release = true
	_set_status(reason)

func _reference_normal() -> Vector3:
	if reference_mode == "ceiling": return Vector3.DOWN
	if reference_mode == "wall": return Vector3(sin(camera_yaw), 0.0, cos(camera_yaw)).normalized()
	return Vector3.UP

func _active_reference_normal() -> Vector3:
	if stroke_active and stroke_surface_normal.length_squared() > 0.001:
		return stroke_surface_normal.normalized()
	return _reference_normal()

func _undo() -> void:
	if stroke_active or landscape_active or resize_active or detail_move_active: _set_status("Finish or cancel the current edit first"); return
	if _history_tags.is_empty(): _set_status("Nothing to undo"); return
	var tag: String = str(_history_tags.back())
	var ok: bool = true if tag == "landscape" else (building_world.undo() if tag == "building" else (backend and backend.has_method("undo") and backend.undo()))
	if ok:
		_history_tags.pop_back(); _redo_tags.append(tag)
		var entry: Dictionary = _landscape_history.pop_back()
		_landscape_redo.append(entry); landscape_state.restore(entry["before"])
		garden_visual.reset_records(landscape_state.records); _building_dirty = true
	_set_status("Undo complete" if ok else "Nothing to undo")

func _redo() -> void:
	if stroke_active or landscape_active or resize_active or detail_move_active: _set_status("Finish or cancel the current edit first"); return
	if _redo_tags.is_empty(): _set_status("Nothing to redo"); return
	var tag: String = str(_redo_tags.back())
	var ok: bool = true if tag == "landscape" else (building_world.redo() if tag == "building" else (backend and backend.has_method("redo") and backend.redo()))
	if ok:
		_redo_tags.pop_back(); _history_tags.append(tag)
		var entry: Dictionary = _landscape_redo.pop_back()
		_landscape_history.append(entry); landscape_state.restore(entry["after"])
		garden_visual.reset_records(landscape_state.records); _building_dirty = true
	_set_status("Redo complete" if ok else "Nothing to redo")

func _record_history(tag: String) -> void:
	_history_tags.append(tag)
	var after := landscape_state.document()
	_landscape_history.append({"before": after.duplicate(true) if _landscape_before.is_empty() else _landscape_before.duplicate(true), "after": after})
	_building_dirty = true
	_redo_tags.clear(); _landscape_redo.clear()
	if _history_tags.size() > 50: _history_tags.pop_front(); _landscape_history.pop_front()

func _update_presentation() -> void:
	if not cottage_visual or not building_world: return
	var revision: int = building_world.get_revision()
	if cottage_visual.has_method("request_revision"): cottage_visual.request_revision(revision)
	var key := "%d|%s|%s|%s" % [revision, str(resize_preview_dimensions if resize_active else Vector3.ZERO), selected_detail_id if detail_move_active else "", str(detail_move_position) if detail_move_active else ""]
	if key != _presentation_key:
		var presentation: Dictionary = building_world.get_building(selected_building_id)
		if resize_active:
			var resize_preview: Dictionary = building_world.preview_resize(selected_building_id, resize_preview_dimensions)
			if not resize_preview.is_empty():
				presentation["dimensions"] = resize_preview.get("dimensions", resize_preview_dimensions)
				presentation["details"] = resize_preview.get("details", presentation.get("details", []))
		if detail_move_active:
			var moved_details: Array = presentation.get("details", [])
			for i in moved_details.size():
				var moved: Dictionary = moved_details[i]
				if str(moved.get("id", "")) == selected_detail_id:
					moved["resolved_position"] = detail_move_position
					var moved_anchor: Dictionary = moved.get("anchor", {})
					moved_anchor["surface_id"] = detail_move_surface_id
					moved_anchor["local_position"] = detail_move_position
					moved["anchor"] = moved_anchor
					moved_details[i] = moved
			presentation["details"] = moved_details
		if not presentation.is_empty():
			cottage_visual.apply_building(presentation, revision)
			var seen: Dictionary = {}
			for building_value in building_world.get_buildings():
				var other_view: Dictionary = building_value
				var other_id := str(other_view.get("id", ""))
				if other_id.is_empty(): continue
				seen[other_id] = true
				var other_visual: Node3D = cottage_visuals.get(other_id)
				if not other_visual:
					other_visual = CottageVisualScript.new()
					other_visual.name = "CottageVisual_%s" % other_id
					add_child(other_visual)
					cottage_visuals[other_id] = other_visual
				if other_visual.has_method("request_revision"): other_visual.request_revision(revision)
				if other_id == selected_building_id and not presentation.is_empty(): other_visual.apply_building(presentation, revision)
				else: other_visual.apply_building(other_view, revision)
			for existing_id in cottage_visuals.keys():
				if not seen.has(existing_id):
					var stale_visual: Node3D = cottage_visuals[existing_id]
					if is_instance_valid(stale_visual): stale_visual.queue_free()
					cottage_visuals.erase(existing_id)
		_presentation_key = key
	if target_label:
		if view_context == "terrain":
			var mode_name := sculpt_tool.capitalize()
			var target_text := "%s target (%.1f, %.1f, %.1f)  •  radius %.1f" % [mode_name, preview_center.x, preview_center.y, preview_center.z, brush_radius] if _terrain_target_valid else "%s • NO TERRAIN TARGET" % mode_name
			if sculpt_tool in ["level", "slope"] and stroke_reference.get("point", null) is Vector3:
				target_text += "  •  locked y %.1f" % (stroke_reference["point"] as Vector3).y
			target_label.text = "%s  •  str %.1f falloff %.1f  %s  •  A hold/release B cancel  R3 refocus" % [target_text, brush_strength, brush_falloff, "PRECISION" if precision_mode else "NORMAL"]
		else:
			var cottage_text := "Cottage %s" % selected_building_id
			if detail_move_active: cottage_text = "Move %s at (%.1f, %.1f, %.1f)" % [selected_detail_id, detail_move_position.x, detail_move_position.y, detail_move_position.z]
			target_label.text = "%s  •  A resize  B cancel  •  sticks move/orbit  R3 refocus" % cottage_text
	_update_resize_handles()

func _update_resize_handles() -> void:
	if not resize_handles:
		return
	var show_handles: bool = resize_active and not menu_open and not tools_open and not detail_open and not _restoring
	resize_handles.visible = show_handles
	if not show_handles:
		return
	var view: Dictionary = building_world.get_building(selected_building_id)
	var transform_value = view.get("transform", Transform3D.IDENTITY)
	var building_transform: Transform3D = transform_value if transform_value is Transform3D else Transform3D.IDENTITY
	var dims := resize_preview_dimensions
	var authored_positions := [Vector3(dims.x * 0.5 + 0.5, dims.y * 0.5, 0), Vector3(0, dims.y * 0.5, dims.z * 0.5 + 0.5), Vector3(0, dims.y + 0.5, 0)]
	for index in mini(authored_positions.size(), resize_handles.get_child_count()):
		(resize_handles.get_child(index) as Node3D).position = building_transform * authored_positions[index]

func _update_debug_overlay() -> void:
	if not debug_label or not debug_label.visible:
		return
	var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var static_memory := Performance.get_monitor(Performance.MEMORY_STATIC)
	var memory_text := "unavailable" if static_memory <= 0.0 else "%.1f MB" % (static_memory / 1048576.0)
	var native_stats: Dictionary = backend.stats() if backend and backend.has_method("stats") else {}
	var renderer := RenderingServer.get_current_rendering_method()
	var adapter := RenderingServer.get_video_adapter_name()
	debug_label.text = "FPS %.0f  process %.2f ms\n%s / %s  %dx%d  draw %d  triangles %d\nStatic memory %s  sculpt %.2f ms\nNative mesh acknowledgement unavailable" % [Engine.get_frames_per_second(), process_ms, renderer, adapter, get_viewport().size.x, get_viewport().size.y, draw_calls, primitives, memory_text, float(native_stats.get("last_edit_ms", -1.0))]

func _build_ui() -> void:
	hud = CanvasLayer.new(); add_child(hud)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); margin.add_theme_constant_override("margin_left", 28); margin.add_theme_constant_override("margin_top", 24); hud.add_child(margin)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 5); margin.add_child(column)
	status_label = Label.new(); status_label.add_theme_font_size_override("font_size", 26); column.add_child(status_label)
	context_label = Label.new(); context_label.text = "COTTAGE • Select/Back: Terrain ↔ Cottage • X actions"; context_label.add_theme_font_size_override("font_size", 20); column.add_child(context_label)
	target_label = Label.new(); target_label.add_theme_font_size_override("font_size", 22); target_label.add_theme_color_override("font_color", Color("#ffe0a8")); column.add_child(target_label)
	debug_label = Label.new(); debug_label.position = Vector2(28, 285); debug_label.add_theme_font_size_override("font_size", 20); debug_label.visible = false; hud.add_child(debug_label)
	_build_pause_panel(); _build_tools_panel()

func _build_pause_panel() -> void:
	pause_panel = PanelContainer.new(); pause_panel.position = Vector2(430, 120); pause_panel.size = Vector2(430, 460); pause_panel.visible = false; hud.add_child(pause_panel)
	var box := VBoxContainer.new(); pause_panel.add_child(box); var title := Label.new(); title.text = "PAUSED\nWorld input suspended"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size", 28); box.add_child(title)
	for label in ["Save", "Reload", "Resume", "Quit"]:
		var button := Button.new(); button.text = label; button.focus_mode = Control.FOCUS_ALL; button.custom_minimum_size = Vector2(0, 56); button.add_theme_font_size_override("font_size", 24); button.pressed.connect(_pause_choice.bind(label)); box.add_child(button); _pause_buttons[label] = button

func _build_tools_panel() -> void:
	tools_panel = PanelContainer.new(); tools_panel.position = Vector2(330, 80); tools_panel.size = Vector2(560, 560); tools_panel.visible = false; hud.add_child(tools_panel)
	var scroll := ScrollContainer.new(); scroll.follow_focus = true; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; tools_panel.add_child(scroll)
	var box := VBoxContainer.new(); scroll.add_child(box); var title := Label.new(); title.text = "ACTIONS"; title.add_theme_font_size_override("font_size", 24); box.add_child(title)
	var all_labels: Array[String] = []
	all_labels.append_array(_terrain_action_labels)
	for label in _cottage_action_labels:
		if not all_labels.has(label): all_labels.append(label)
	for label in all_labels:
		var button := Button.new(); button.text = label; button.focus_mode = Control.FOCUS_ALL; button.custom_minimum_size = Vector2(0, 42); button.pressed.connect(_tool_choice.bind(label)); box.add_child(button); _tool_buttons[label] = button
	_update_action_buttons()

func _handle_menu_input(event: InputEvent) -> void:
	if event.is_action_pressed("m1_cancel"): _set_menu(false); get_viewport().set_input_as_handled(); return
	if event.is_action_pressed("m1_accept"):
		var focus := get_viewport().gui_get_focus_owner(); if focus is Button: (focus as Button).pressed.emit(); get_viewport().set_input_as_handled(); return
	if event.is_action_pressed("m1_height_down"): _move_focus(_pause_buttons.values(), 1); get_viewport().set_input_as_handled(); return
	if event.is_action_pressed("m1_height_up"): _move_focus(_pause_buttons.values(), -1); get_viewport().set_input_as_handled(); return

func _handle_overlay_input(event: InputEvent) -> void:
	if event.is_action_pressed("m1_cancel"): tools_open = false; detail_open = false; tools_panel.visible = false; _set_status("Actions closed"); get_viewport().set_input_as_handled(); return
	if event.is_action_pressed("m1_accept"):
		var focus := get_viewport().gui_get_focus_owner(); if focus is Button: (focus as Button).pressed.emit(); get_viewport().set_input_as_handled(); return
	if tools_open and event.is_action_pressed("m1_height_down"):
		_move_focus(_visible_action_buttons(), 1); get_viewport().set_input_as_handled(); return
	if tools_open and event.is_action_pressed("m1_height_up"):
		_move_focus(_visible_action_buttons(), -1); get_viewport().set_input_as_handled(); return
	if detail_open and event.is_action_pressed("m1_cycle_left"): _select_detail(-1); get_viewport().set_input_as_handled(); return
	if detail_open and event.is_action_pressed("m1_cycle_right"): _select_detail(1); get_viewport().set_input_as_handled(); return

func _move_focus(values: Array, direction: int) -> void:
	if values.is_empty(): return
	var focus := get_viewport().gui_get_focus_owner(); var index := values.find(focus); index = posmod(index + direction, values.size()); (values[index] as Button).grab_focus()

func _select_detail(direction: int) -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	var details: Array = view.get("details", [])
	var ids: Array[String] = []
	var labels: Array[String] = []
	for detail_value in details:
		var detail: Dictionary = detail_value
		var detail_id := str(detail.get("id", ""))
		if detail_id.is_empty(): continue
		ids.append(detail_id)
		labels.append(str(detail.get("kind", "detail")))
	if ids.is_empty(): return
	var index := ids.find(selected_detail_id)
	selected_detail_id = ids[posmod(index + direction, ids.size())]
	var selected_index := ids.find(selected_detail_id)
	for detail_value in details:
		var selected_detail: Dictionary = detail_value
		if str(selected_detail.get("id", "")) == selected_detail_id:
			selected_surface_id = str(selected_detail.get("anchor", {}).get("surface_id", ""))
			break
	_set_status("Selected %s %s" % [labels[selected_index] if selected_index >= 0 else "detail", selected_detail_id])

func _cycle_surface(direction: int) -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	var ids: Array[String] = []
	for surface_value in view.get("surfaces", []):
		var surface: Dictionary = surface_value
		if str(surface.get("kind", "wall")) == "wall" and not bool(surface.get("deleted", false)): ids.append(str(surface.get("id", "")))
	if ids.is_empty(): return
	var index := ids.find(selected_surface_id)
	selected_surface_id = ids[posmod(index + direction, ids.size())]
	_set_status("Support surface %s" % selected_surface_id)

func _cycle_building(direction: int) -> void:
	var buildings: Array[Dictionary] = building_world.get_buildings()
	if buildings.is_empty(): return
	var ids: Array[String] = []
	for building_value in buildings: ids.append(str(building_value.get("id", "")))
	var index := ids.find(selected_building_id)
	selected_building_id = ids[posmod(index + direction, ids.size())]
	selected_detail_id = ""
	_set_status("Selected cottage %s" % selected_building_id)
	_focus_selected_building()
	_update_presentation()

func _focus_selected_building() -> void:
	if view_context == "terrain":
		_cancel_current_edit("Terrain focus reset")
		terrain_cursor = Vector3(32.0, 8.0, 28.0)
		cursor = terrain_cursor
		_terrain_target_valid = false
		_terrain_target_point = Vector3.ZERO
	else:
		var view: Dictionary = building_world.get_building(selected_building_id)
		var transform_value = view.get("transform", Transform3D.IDENTITY)
		if transform_value is Transform3D:
			cursor = transform_value * Vector3(0, 2, 0)
		cursor.x = clampf(cursor.x, 0.5, 47.5)
		cursor.y = clampf(cursor.y, 0.5, 31.5)
		cursor.z = clampf(cursor.z, 0.5, 47.5)
		cottage_cursor = cursor
	camera_yaw = -1.1
	camera_pitch = 0.66
	camera_distance = 36.0

func _pause_choice(choice: String) -> void:
	match choice:
		"Save": _save_all()
		"Reload": _reload_all()
		"Resume": _set_menu(false)
		"Quit": _quit_cleanly()

func _tool_choice(choice: String) -> void:
	if choice in ["Foliage brush", "Tree brush", "Clear planting"]:
		if view_context != "terrain": return
		_cancel_current_edit("Planting tool selected")
		sculpt_tool = {"Foliage brush": "foliage", "Tree brush": "tree", "Clear planting": "clear_planting"}[choice]
		reference_mode = "ground"
		tools_open = false; detail_open = false; tools_panel.visible = false
		_set_status(choice + " • A hold and move / release to commit • B cancel")
		return
	if choice in ["Raise", "Dig", "Level", "Slope", "Smooth"]:
		if view_context != "terrain":
			_set_status("Terrain tool unavailable in Cottage mode")
			return
		_set_sculpt_tool(choice)
		if sculpt_tool in ["level", "slope", "smooth"]: reference_mode = "ground"
		tools_open = false; detail_open = false; tools_panel.visible = false; _set_status("Terrain mode • %s • A hold / release, B cancel" % sculpt_tool.capitalize()); return
	if choice in ["Radius +", "Radius -", "Strength +", "Strength -", "Falloff +", "Falloff -", "Height snap: off", "Reference: ground", "Reference: wall", "Reference: ceiling", "Resample reference", "Keep reference"]:
		if view_context != "terrain":
			_set_status("Terrain settings unavailable in Cottage mode")
			return
		match choice:
			"Radius +": brush_radius = minf(8.0, brush_radius + (0.25 if precision_mode else 1.0))
			"Radius -": brush_radius = maxf(0.25, brush_radius - (0.25 if precision_mode else 1.0))
			"Strength +": brush_strength = minf(16.0, brush_strength + (0.5 if precision_mode else 2.0))
			"Strength -": brush_strength = maxf(0.5, brush_strength - (0.5 if precision_mode else 2.0))
			"Falloff +": brush_falloff = minf(1.0, brush_falloff + 0.1)
			"Falloff -": brush_falloff = maxf(0.0, brush_falloff - 0.1)
			"Height snap: off":
				height_snap_enabled = not height_snap_enabled
				if _tool_buttons.has("Height snap: off"):
					(_tool_buttons["Height snap: off"] as Button).text = "Height snap: on" if height_snap_enabled else "Height snap: off"
			"Reference: ground": reference_mode = "ground"
			"Reference: wall": reference_mode = "wall"
			"Reference: ceiling": reference_mode = "ceiling"
			"Resample reference": resample_reference()
			"Keep reference": keep_reference = not keep_reference
		tools_open = false; detail_open = false; tools_panel.visible = false
		_set_status("Brush %.1f / strength %.1f / falloff %.1f / snap %s / %s%s" % [brush_radius, brush_strength, brush_falloff, "on" if height_snap_enabled else "off", reference_mode, " / keep" if keep_reference else ""])
		_update_presentation()
		return
	if view_context != "building":
		_set_status("Cottage action unavailable in Terrain mode")
		return
	var view: Dictionary = building_world.get_building(selected_building_id); var details: Array = view.get("details", [])
	if selected_detail_id.is_empty() and not details.is_empty(): selected_detail_id = str(details[0]["id"])
	var selected_detail: Dictionary = {}
	for detail_value in details:
		var candidate: Dictionary = detail_value
		if str(candidate.get("id", "")) == selected_detail_id: selected_detail = candidate; break
	if selected_surface_id.is_empty() and not selected_detail.is_empty(): selected_surface_id = str(selected_detail.get("anchor", {}).get("surface_id", ""))
	var operation_ok := false
	match choice:
		"Miniature scale":
			if building_world.has_method("set_miniature_scale"):
				operation_ok = building_world.set_miniature_scale(selected_building_id)
				if operation_ok: _set_status("Miniature cottage scale applied")
			else:
				_set_status("Miniature scale API unavailable")
		"Move selected window":
			_begin_detail_move()
		"Support: next":
			_cycle_surface(1)
			return
		"Support: previous":
			_cycle_surface(-1)
			return
		"Replace selected":
			if not selected_detail_id.is_empty(): operation_ok = building_world.replace_detail(selected_building_id, selected_detail_id, "window_round")
		"Suppress / restore":
			if not selected_detail_id.is_empty(): operation_ok = building_world.suppress_detail(selected_building_id, selected_detail_id, bool(selected_detail.get("visible", true)))
		"Reattach selected":
			if not selected_detail_id.is_empty():
				var reattach_surface := ""
				for surface_value in view.get("surfaces", []):
					var surface: Dictionary = surface_value
					var surface_id := str(surface.get("id", ""))
					if surface_id == selected_surface_id and not bool(surface.get("deleted", false)):
						reattach_surface = surface_id
						break
				if reattach_surface.is_empty():
					for surface_value in view.get("surfaces", []):
						var surface: Dictionary = surface_value
						if not bool(surface.get("deleted", false)):
							reattach_surface = str(surface.get("id", ""))
							break
				var selected_anchor: Dictionary = selected_detail.get("anchor", {})
				var old_local = selected_anchor.get("local_position", Vector3(0, 4, -7.02))
				if selected_detail.get("resolved_position", null) is Vector3: old_local = selected_detail["resolved_position"]
				if not reattach_surface.is_empty() and old_local is Vector3: operation_ok = building_world.reattach_detail(selected_building_id, selected_detail_id, reattach_surface, old_local)
		"Add flower box", "Add shutter":
			var selected_anchor: Dictionary = selected_detail.get("anchor", {})
			var surface_id := str(selected_anchor.get("surface_id", ""))
			if surface_id.is_empty():
				for surface_value in view.get("surfaces", []):
					var surface: Dictionary = surface_value
					if not bool(surface.get("deleted", false)): surface_id = str(surface.get("id", "")); break
			if not surface_id.is_empty():
				var p: Vector3 = selected_detail.get("resolved_position", Vector3(0, 3.3, -view["dimensions"].z * 0.5 - 0.02))
				var kind := "shutter" if choice == "Add shutter" else "flower_box"
				if kind == "shutter":
					var horizontal_axis := 0
					for surface: Dictionary in view.get("surfaces", []):
						if surface["id"] == surface_id and str(surface.get("orientation", "")) in ["left", "right"]: horizontal_axis = 2
					p[horizontal_axis] += 2.2
				else: p.y -= 2.0
				operation_ok = not building_world.add_detail(selected_building_id, kind, surface_id, p, kind + "_wood").is_empty()
		"Delete selected surface":
			var delete_surface_id := str(selected_detail.get("anchor", {}).get("surface_id", ""))
			if delete_surface_id.is_empty():
				var surfaces: Array = view.get("surfaces", [])
				if not surfaces.is_empty(): delete_surface_id = str(surfaces[0].get("id", ""))
			if not delete_surface_id.is_empty(): operation_ok = building_world.delete_surface(selected_building_id, delete_surface_id)
		"Material: warm plaster": operation_ok = building_world.set_material(selected_building_id, "warm_plaster")
		"Duplicate cottage":
			var duplicate_id: String = building_world.duplicate_building(selected_building_id, Vector3(0, 0, 18))
			if not duplicate_id.is_empty():
				selected_building_id = duplicate_id
				selected_detail_id = ""
				selected_surface_id = ""
				operation_ok = true
			if operation_ok: _focus_selected_building()
			_set_status("Cottage duplicated" if not duplicate_id.is_empty() else "Duplicate rejected")
		"Close": tools_open = false; detail_open = false; tools_panel.visible = false
	if choice != "Move selected window":
		if operation_ok: _record_history("building")
		tools_open = false; detail_open = false; tools_panel.visible = false
		_update_action_buttons()
		_update_presentation()

func _set_menu(open: bool) -> void:
	menu_open = open; pause_panel.visible = open
	if open:
		tools_open = false
		detail_open = false
		if tools_panel: tools_panel.visible = false
		_cancel_current_edit("Paused")
		(_pause_buttons["Save"] as Button).grab_focus()
	else:
		_update_action_buttons()
		_set_status("Terrain mode" if view_context == "terrain" else "Cottage mode")

func _save_all() -> bool:
	if landscape_active:
		_set_status("Finish or cancel planting before saving"); return false
	var ok := false
	if backend and backend.has_method("save_world"):
		var document: Dictionary = building_world.get_document()
		document["landscape"] = landscape_state.document()
		ok = backend.save_world(document)
	_set_status("World saved" if ok else "Save failed (cottage design kept in memory)")
	if ok: _building_dirty = false
	return ok

func _world_is_dirty() -> bool:
	if _building_dirty: return true
	if backend and backend.has_method("stats"):
		return bool((backend.stats() as Dictionary).get("dirty", false))
	return false

func _reload_all() -> bool:
	var ok: bool = backend and backend.has_method("load_world") and backend.load_world()
	if ok:
		_history_tags.clear()
		_redo_tags.clear(); _landscape_history.clear(); _landscape_redo.clear()
		var loaded_document = backend.get("loaded_building_document")
		if not loaded_document is Dictionary or not BuildingWorldScript.validate_document(loaded_document) or not _load_cottage_document(loaded_document):
			_set_status("Reload failed: cottage design missing or invalid")
			return false
		_restore_landscape(loaded_document)
		_building_dirty = false
		_set_status("World and cottage reloaded")
		_update_presentation()
	else: _set_status("Reload failed")
	return ok

func _set_status(message: String) -> void:
	status_text = message
	if status_label: status_label.text = "HEARTHVALE / M1   %s" % message
	if context_label:
		context_label.text = ("TERRAIN • Select/Back: Cottage ↔ Terrain • X tools • A hold/release • B cancel" if view_context == "terrain" else "COTTAGE • Select/Back: Terrain ↔ Cottage • X actions • A resize • B cancel")

func _quit_cleanly() -> void:
	if _shutting_down: return
	_cancel_current_edit("Quit")
	if _world_is_dirty() and not _save_all():
		_set_status("Save failed; quit cancelled")
		_set_menu(true)
		return
	_shutting_down = true; set_process(false); set_process_input(false); var tree := get_tree(); var old_backend := backend; backend = null; if old_backend: old_backend.queue_free(); await tree.process_frame; await tree.process_frame; queue_free(); tree.quit()

func _restore_landscape(document: Dictionary) -> void:
	if document.has("landscape") and landscape_state.restore(document["landscape"]):
		garden_visual.reset_records(landscape_state.records)
		return
	landscape_state = LandscapeScript.new()
	var rng := RandomNumberGenerator.new(); rng.seed = 1042
	for point in [Vector3(10, 8, 9), Vector3(31, 8, 10), Vector3(12, 8, 29), Vector3(34, 8, 31), Vector3(9, 8, 37), Vector3(34, 8, 17), Vector3(27, 8, 35), Vector3(7, 8, 20)]:
		var ground := _plant_ground(point, true)
		if not ground.is_empty(): landscape_state.add("tree", ground["point"], rng.randi_range(0, 2))
	# Plant in loose drifts instead of an even procedural dusting. The cottage
	# frontage and the central sculpting lawn remain calm, readable spaces.
	var cluster_centers := [Vector2(9, 13), Vector2(11, 33), Vector2(17, 31), Vector2(29, 9), Vector2(33, 14), Vector2(33, 34), Vector2(36, 24)]
	for cluster: Vector2 in cluster_centers:
		for sample in 12:
			var angle := rng.randf_range(0.0, TAU)
			var radius := sqrt(rng.randf()) * rng.randf_range(1.2, 3.4)
			var point := Vector3(cluster.x + cos(angle) * radius, 8, cluster.y + sin(angle) * radius)
			if point.x > 17 and point.x < 28 and point.z > 13 and point.z < 25: continue
			var ground := _plant_ground(point, true)
			if not ground.is_empty(): landscape_state.add("foliage", ground["point"], rng.randi_range(0, Flora.variant_count("foliage") - 1))
	for point in [Vector3(37, 7, 7), Vector3(37, 7, 12), Vector3(37, 7, 30), Vector3(36, 7, 38), Vector3(32, 8, 37), Vector3(13, 8, 34), Vector3(8, 8, 16)]:
		var ground := _plant_ground(point, true)
		if not ground.is_empty(): landscape_state.add("rock", ground["point"], rng.randi_range(0, 2))
	garden_visual.reset_records(landscape_state.records)

func _plant_ground(point: Vector3, from_top: bool = false) -> Dictionary:
	if not backend or not backend.is_ready(): return {}
	var unit := float(backend.voxel_scale)
	point.x = snappedf(point.x, Grid.UNIT); point.z = snappedf(point.z, Grid.UNIT)
	var x := floori(point.x / unit); var z := floori(point.z / unit)
	if x < 1 or z < 1 or point.x >= 47 or point.z >= 47: return {}
	var surface := -1
	var closest := INF
	var reach := ceili(2.0 / unit)
	var low := 0 if from_top else maxi(0, floori(point.y / unit) - reach)
	var high := int(backend.patch_size.y) - 2 if from_top else mini(int(backend.patch_size.y) - 2, floori(point.y / unit) + reach)
	for y in range(high, low - 1, -1):
		if backend.voxel_at(Vector3i(x, y, z)) == 0: continue
		if backend.voxel_at(Vector3i(x, y + 1, z)) != 0: continue
		var distance := absf((y + 1) * unit - point.y)
		if not from_top and distance > 2.0: continue
		if distance < closest: closest = distance; surface = y
		if from_top: break
	if surface < 0: return {}
	var p := Vector3(point.x, (surface + 1) * unit, point.z)
	if p.y <= 5.05: return {}
	for building: Dictionary in building_world.get_buildings():
		var local: Vector3 = (building["transform"] as Transform3D).affine_inverse() * p
		var dims: Vector3 = building["dimensions"]
		if absf(local.x) < dims.x * 0.5 + 1.0 and absf(local.z) < dims.z * 0.5 + 1.0: return {}
	return {"point": p}

func _begin_plant_stroke() -> void:
	if landscape_active or stroke_active or menu_open or tools_open or detail_open or view_context != "terrain": return
	_landscape_before = landscape_state.document()
	landscape_active = true; _plant_elapsed = 0.0; _plant_last = Vector3.INF; _plant_sequence = 0
	_paint_plant_sample()

func _update_plant_stroke(delta: float) -> void:
	_plant_elapsed += delta
	while _plant_elapsed >= 0.15:
		_plant_elapsed -= 0.15
		_paint_plant_sample()

func _paint_plant_sample() -> void:
	var center := _terrain_target_point if _terrain_target_valid else cursor
	if sculpt_tool == "tree" and center.distance_to(_plant_last) < 2.8: return
	if sculpt_tool == "clear_planting":
		landscape_state.erase_brush(center, brush_radius)
	else:
		var rng := RandomNumberGenerator.new(); rng.seed = int(_landscape_before.get("next_id", 1)) * 7919 + _plant_sequence * 97
		for sample_index in (1 if sculpt_tool == "tree" else 5):
			var angle := rng.randf_range(0, TAU)
			var radius := sqrt(rng.randf()) * brush_radius if sculpt_tool != "tree" else 0.0
			var ground := _plant_ground(center + Vector3(cos(angle) * radius, 0, sin(angle) * radius))
			if not ground.is_empty(): landscape_state.add(sculpt_tool, ground["point"], rng.randi_range(0, Flora.variant_count(sculpt_tool) - 1))
	_plant_last = center; _plant_sequence += 1
	garden_visual.apply_records(landscape_state.records)

func _end_plant_stroke() -> void:
	if not landscape_active: return
	landscape_active = false
	if landscape_state.document() != _landscape_before:
		_record_history("landscape")
		_set_status("Planting committed • LB undo")
	else: _set_status("No planting change: move to clear ground or clear existing planting")
	_landscape_before.clear()

func _load_cottage_document(document: Dictionary) -> bool:
	# The checkpoint envelope owns landscape; building history owns cottages.
	# Keep the two authoritative components separate after deserialization.
	var cottage := document.duplicate(true)
	cottage.erase("landscape")
	return building_world.load_document(cottage)
