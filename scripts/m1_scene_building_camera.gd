extends "res://scripts/m1_scene_terrain_ux.gd"
## Building-edit camera layer. Terrain camera behavior remains inherited; while
## editing a cottage, orbit is anchored to the selected building rather than
## the movable edit cursor.

const BUILDING_CAMERA_MIN_DISTANCE := 3.5
const BUILDING_CAMERA_MAX_DISTANCE := 28.0
const BUILDING_CAMERA_MARGIN := 1.22

var _terrain_camera_state: Dictionary = {}

func _process(delta: float) -> void:
	if _shutting_down: return
	if (stroke_active or landscape_active) and (menu_open or tools_open or detail_open or _restoring):
		_cancel_current_edit("Sculpting cancelled")
	if not menu_open and not tools_open and not detail_open:
		_read_camera_and_cursor(delta)
	elif view_context == "building" and not menu_open and not _restoring:
		_read_building_overlay_camera(delta)
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

func _read_camera_and_cursor(delta: float) -> void:
	if view_context != "building":
		super._read_camera_and_cursor(delta)
		return
	var before_distance := camera_distance
	var zoom := Input.get_axis("m1_zoom_out", "m1_zoom_in")
	super._read_camera_and_cursor(delta)
	# The base camera intentionally keeps a broad terrain zoom range. Building
	# editing needs to get much closer to tiny details while still allowing the
	# whole miniature to fit on screen.
	camera_distance = clampf(before_distance - zoom * delta * 18.0, BUILDING_CAMERA_MIN_DISTANCE, BUILDING_CAMERA_MAX_DISTANCE)

func _read_building_overlay_camera(delta: float) -> void:
	var orbit_x := Input.get_axis("m1_orbit_left", "m1_orbit_right")
	var orbit_y := Input.get_axis("m1_orbit_up", "m1_orbit_down")
	camera_yaw += orbit_x * delta * 2.2
	camera_pitch = clampf(camera_pitch + orbit_y * delta * 1.5, 0.08, 1.40)
	var zoom := Input.get_axis("m1_zoom_out", "m1_zoom_in")
	camera_distance = clampf(camera_distance - zoom * delta * 18.0, BUILDING_CAMERA_MIN_DISTANCE, BUILDING_CAMERA_MAX_DISTANCE)
	if Input.is_action_just_pressed("m1_focus"):
		_focus_selected_building()

func _update_camera() -> void:
	if not camera: return
	var target := cursor + Vector3(0, 2, 0)
	if view_context == "building":
		target = _selected_building_camera_target()
	var offset := Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch)) * camera_distance
	camera.position = target + offset
	camera.look_at(target, Vector3.UP)

func _selected_building_camera_target() -> Vector3:
	if not building_world:
		return cottage_cursor
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty():
		return cottage_cursor
	var transform_value = view.get("transform", Transform3D.IDENTITY)
	var building_transform: Transform3D = transform_value if transform_value is Transform3D else Transform3D.IDENTITY
	var dims: Vector3 = resize_preview_dimensions if resize_active else view.get("dimensions", Vector3.ONE)
	return building_transform * Vector3(0.0, dims.y * 0.5, 0.0)

func _building_frame_distance() -> float:
	if not building_world:
		return 12.0
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty():
		return 12.0
	var dims: Vector3 = resize_preview_dimensions if resize_active else view.get("dimensions", Vector3.ONE)
	var transform_value = view.get("transform", Transform3D.IDENTITY)
	var building_transform: Transform3D = transform_value if transform_value is Transform3D else Transform3D.IDENTITY
	var scale := building_transform.basis.get_scale().abs()
	var world_dims := Vector3(dims.x * scale.x, dims.y * scale.y, dims.z * scale.z)
	var radius := maxf(0.5, world_dims.length() * 0.5)
	var half_fov := deg_to_rad(camera.fov * 0.5) if camera else deg_to_rad(26.0)
	var fit_distance := radius / maxf(0.2, sin(half_fov)) * BUILDING_CAMERA_MARGIN
	return clampf(fit_distance, 7.0, BUILDING_CAMERA_MAX_DISTANCE)

func _set_view_context(next_context: String, reason: String = "Context changed") -> bool:
	var normalized := "terrain" if next_context == "terrain" else "building"
	if normalized == view_context:
		return super._set_view_context(next_context, reason)
	if view_context == "terrain" and normalized == "building":
		_terrain_camera_state = {"yaw": camera_yaw, "pitch": camera_pitch, "distance": camera_distance}
	var changed := super._set_view_context(next_context, reason)
	if not changed:
		return false
	if normalized == "building":
		_focus_selected_building()
	elif not _terrain_camera_state.is_empty():
		camera_yaw = float(_terrain_camera_state.get("yaw", camera_yaw))
		camera_pitch = float(_terrain_camera_state.get("pitch", camera_pitch))
		camera_distance = float(_terrain_camera_state.get("distance", camera_distance))
		_terrain_camera_state.clear()
	return true

func _focus_selected_building() -> void:
	if view_context != "building":
		super._focus_selected_building()
		return
	var target := _selected_building_camera_target()
	cursor = target
	cottage_cursor = target
	# Reframe changes framing only. Keep the player's chosen yaw and pitch so R3
	# never snaps them back to an arbitrary presentation angle.
	camera_distance = _building_frame_distance()
