extends "res://scripts/m1_scene_playtest_repair.gd"
## Follow-up to the physically tested ca5185dc candidate. Preserve its accepted
## cottage interaction and keep these two remaining navigation fixes isolated.

func _move_focus(values: Array, direction: int) -> void:
	var buttons: Array[Button] = []
	for value in values:
		if value is Button and is_instance_valid(value):
			var button := value as Button
			if not button.is_queued_for_deletion() and button.is_visible_in_tree() and not button.disabled and button.focus_mode != Control.FOCUS_NONE:
				buttons.append(button)
	# Needs placement was appended to this array but inserted BEFORE Close in
	# the actual VBox. Use the same order the player sees (and the stick uses).
	if values == _building_buttons:
		buttons.sort_custom(func(a: Button, b: Button) -> bool: return a.get_index() < b.get_index())
	if buttons.is_empty(): return
	var index := buttons.find(get_viewport().gui_get_focus_owner())
	if index < 0: index = 0 if direction >= 0 else buttons.size() - 1
	else: index = posmod(index + direction, buttons.size())
	buttons[index].grab_focus()

const TERRAIN_CAMERA_HEIGHT_SPEED := 3.0
var _terrain_camera_goal_y := NAN

func _ground_on_navigation_column(point: Vector3) -> Dictionary:
	# Navigation only, never active sculpting. Follow the FIRST ground below
	# this exact column, not the highest/nearest peak in the brush footprint.
	# Inside solid ground, climb only that connected solid span. A cave floor
	# remains a floor; an overhead roof across air is not a navigation target.
	if not backend or not backend.is_ready() or not point.is_finite(): return {}
	var unit: float = backend.voxel_scale
	var patch: Vector3i = backend.patch_size
	var cell := Vector3i((point / unit).floor())
	if cell.x < 0 or cell.z < 0 or cell.x >= patch.x or cell.z >= patch.z: return {}
	cell.y = clampi(cell.y, 0, patch.y - 1)
	if backend.voxel_at(cell) != 0:
		while cell.y + 1 < patch.y and backend.voxel_at(cell + Vector3i.UP) != 0:
			cell.y += 1
	else:
		while cell.y >= 0 and backend.voxel_at(cell) == 0:
			cell.y -= 1
		if cell.y < 0: return {}
	var target := Vector3(point.x, float(cell.y + 1) * unit, point.z)
	return {"valid": true, "point": target}

func _read_camera_and_cursor(delta: float) -> void:
	var before := cursor
	super._read_camera_and_cursor(delta)
	if view_context != "terrain" or building_placement_active: return
	if not _free_camera_valid:
		_free_camera_y = before.y + 2.0
		_free_camera_valid = true
	if is_nan(_terrain_camera_goal_y): _terrain_camera_goal_y = _free_camera_y
	if stroke_active:
		# Changing terrain is not a camera navigation command. Horizontal pan,
		# orbit and zoom still pass through the established controller path.
		_terrain_camera_goal_y = _free_camera_y
		return
	var travelled := Vector2(cursor.x - before.x, cursor.z - before.z).length_squared() > 0.000001
	if travelled and reference_mode == "ground" and not landscape_active:
		var ground := _ground_on_navigation_column(cursor)
		if not ground.is_empty():
			cursor.y = (ground["point"] as Vector3).y
			terrain_cursor = cursor
	# Only player travel or explicit elevation/reframe input sets a new goal.
	# A stroke's final frontier is retained for aim, NOT adopted by the camera.
	var explicit_height := not is_equal_approx(cursor.y, before.y)
	if travelled or explicit_height or Input.is_action_just_pressed("m1_focus"):
		_terrain_camera_goal_y = cursor.y + 2.0
	var eased := lerpf(_free_camera_y, _terrain_camera_goal_y, 1.0 - exp(-5.0 * maxf(delta, 0.0)))
	_free_camera_y = move_toward(_free_camera_y, eased, TERRAIN_CAMERA_HEIGHT_SPEED * maxf(delta, 0.0))

func _update_camera() -> void:
	if not camera: return
	if view_context != "terrain" or building_placement_active:
		super._update_camera()
		return
	if not _free_camera_valid:
		_free_camera_y = cursor.y + 2.0
		_free_camera_valid = true
		_terrain_camera_goal_y = _free_camera_y
	var target := Vector3(cursor.x, _free_camera_y, cursor.z)
	var offset := Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch)) * camera_distance
	camera.position = target + offset
	camera.look_at(target, Vector3.UP)

func _begin_stroke() -> void:
	super._begin_stroke()
	if stroke_active: _terrain_camera_goal_y = _free_camera_y

func _end_stroke() -> void:
	super._end_stroke()
	_terrain_camera_goal_y = _free_camera_y

func _cancel_current_edit(reason: String) -> void:
	super._cancel_current_edit(reason)
	_terrain_camera_goal_y = _free_camera_y

func _set_view_context(next_context: String, reason: String = "Context changed") -> bool:
	var changed := super._set_view_context(next_context, reason)
	if changed: _terrain_camera_goal_y = _free_camera_y
	return changed
