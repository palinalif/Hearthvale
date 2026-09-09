extends "res://scripts/m2_scene_catalogue.gd"
## Desktop input adapter layered over the shared controller-first scene.
## Mouse actions are handled after Control nodes so clicking menus never edits
## the world behind them.

const PC_ORBIT_SENSITIVITY := 0.007
const PC_WHEEL_STEP := 2.5
const PCInputGlyph = preload("res://scripts/ui/m1_input_glyph.gd")

var _pc_prompt_mode := false
var _mouse_orbiting := false

func _ready() -> void:
	# The desktop export carries this feature tag. Editor-driven Mobile render
	# harnesses run on Windows too, so the host OS alone cannot choose prompts.
	_pc_prompt_mode = OS.has_feature("pc_playtest")
	PCInputGlyph.set_keyboard_mouse_mode(_pc_prompt_mode)
	super._ready()
	get_window().title = "Hearthvale — M2 Playtest"

func _exit_tree() -> void:
	PCInputGlyph.set_keyboard_mouse_mode(false)
	super._exit_tree()

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.2):
		_set_pc_prompt_mode(false)
	elif event is InputEventKey or event is InputEventMouse:
		_set_pc_prompt_mode(true)

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_orbiting = button.pressed
			get_viewport().set_input_as_handled()
			return
		if button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if not menu_open and not tools_open and not detail_open:
				var direction := 1.0 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				var low := BUILDING_CAMERA_MIN_DISTANCE if view_context == "building" and not building_placement_active else 3.5
				var high := BUILDING_CAMERA_MAX_DISTANCE if view_context == "building" and not building_placement_active else 52.0
				camera_distance = clampf(camera_distance - direction * PC_WHEEL_STEP, low, high)
				get_viewport().set_input_as_handled()
				return
		if button.pressed and button.button_index == MOUSE_BUTTON_MIDDLE and not menu_open:
			_focus_selected_building()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _mouse_orbiting and not menu_open:
			camera_yaw -= motion.relative.x * PC_ORBIT_SENSITIVITY
			camera_pitch = clampf(camera_pitch - motion.relative.y * PC_ORBIT_SENSITIVITY, 0.08, 1.40)
			get_viewport().set_input_as_handled()
			return
		if not menu_open and not tools_open and not detail_open:
			if view_context == "building" and not building_placement_active:
				edit_pointer = motion.position
				_clamp_edit_pointer()
			else:
				_aim_terrain_from_mouse(motion.position)

	super._input(event)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton: return
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT: return
	var action := InputEventAction.new()
	action.action = "m1_accept"
	action.pressed = button.pressed
	action.strength = 1.0 if button.pressed else 0.0
	super._input(action)
	get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: _mouse_orbiting = false
	super._notification(what)

func _set_pc_prompt_mode(enabled: bool) -> void:
	if _pc_prompt_mode == enabled: return
	_pc_prompt_mode = enabled
	PCInputGlyph.set_keyboard_mouse_mode(enabled)
	if _prompt_row:
		_prompt_row.set_meta("signature", "")
	_refresh_controller_hud()

func _aim_terrain_from_mouse(screen_position: Vector2) -> void:
	if not camera or not backend or not backend.has_method("voxel_at") or not backend.is_ready(): return
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var scale_value := maxf(0.1, float(backend.voxel_scale))
	var patch_cells: Vector3i = backend.patch_size
	var world_max := Vector3(patch_cells) * scale_value - Vector3.ONE * scale_value * 0.5
	var step := scale_value * 0.45
	var previous := origin
	for index in 320:
		var point := origin + direction * step * float(index)
		var cell := Vector3i(floori(point.x / scale_value), floori(point.y / scale_value), floori(point.z / scale_value))
		if cell.x >= 0 and cell.x < patch_cells.x and cell.y >= 0 and cell.y < patch_cells.y and cell.z >= 0 and cell.z < patch_cells.z:
			if int(backend.voxel_at(cell)) != 0:
				cursor = previous.clamp(Vector3(scale_value * 0.5, 0.0, scale_value * 0.5), world_max)
				terrain_cursor = cursor
				_preview_key = ""
				return
		previous = point
