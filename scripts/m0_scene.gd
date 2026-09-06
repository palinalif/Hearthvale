extends Node3D
## Controller-first M0 presentation. Terrain data and history belong to the backend.

signal state_changed(state: String)

const PATCH_SIZE := Vector3i(48, 32, 48)
const BRUSH_STEPS := [1.5, 2.5, 4.0, 6.0]
const CURSOR_MIN := Vector3(0.5, 0.0, 0.5)
const CURSOR_MAX := Vector3(47.5, 31.0, 47.5)

@export var checkpoint_root := ""
@export var benchmark_seconds_override := 60.0

var backend: Node
var cursor := Vector3(3.0, 5.0, 24.0)
var brush_index := 1
var remove_mode := true
var preview_active := false
var menu_open := false
var debug_open := false
var connected := true
var camera_yaw := -1.1
var camera_pitch := 0.66
var camera_distance := 31.0
var frame_ms_samples: Array[float] = []
var _last_frame_usec := 0
var _benchmark_mode := false
var _capture_path := ""
var _capture_view := ""
var _quit_after_capture := false
var _fixture_active := false
var _fixture_done := false
var _fixture_result: Dictionary = {}
var _player_restored := true
var _restoring_player := false
var _restore_failed := false
var _pause_buttons: Dictionary = {}
var _world_dirty := false
var _ever_focused := false
var _shutting_down := false

var preview_mesh: MeshInstance3D
var cursor_mesh: MeshInstance3D
var camera: Camera3D
var hud: CanvasLayer
var status: Label
var cursor_info: Label
var debug_label: Label
var pause_panel: PanelContainer
var fixture_panel: PanelContainer
var fixture_label: Label
var fixture_return_button: Button
var fixture_quit_button: Button
var terrain_visual: Node3D
var _last_focus := true

func _ready() -> void:
	_parse_command_line()
	_setup_input_map()
	_build_lighting_and_world()
	_build_ui()
	_create_backend()
	# Headless controller tests have no focused desktop window. Seed this state
	# so the first frame is not mistaken for a focus loss; runtime focus changes
	# after this point still cancel previews and pause the game.
	_last_focus = get_window().has_focus()
	_ever_focused = _last_focus
	_update_camera(0.0)
	_update_cursor_visual()
	_set_status("Loading valley…")
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if backend and backend.has_signal("ready_changed"):
		backend.ready_changed.connect(_on_backend_ready)
	if backend and backend.has_method("is_ready") and backend.is_ready():
		_on_backend_ready(true)
	else:
		_build_terrain_presentation()
	_maybe_benchmark()

func _process(delta: float) -> void:
	if _shutting_down: return
	var now := Time.get_ticks_usec()
	if _last_frame_usec != 0:
		frame_ms_samples.append(float(now - _last_frame_usec) / 1000.0)
		if frame_ms_samples.size() > 240: frame_ms_samples.pop_front()
	_last_frame_usec = now
	if not menu_open and connected and not _fixture_active and not _benchmark_mode and not _restoring_player:
		_read_controller(delta)
		_update_camera(delta)
	_update_cursor_visual()
	_update_preview()
	_update_debug()
	var focused: bool = get_window().has_focus()
	if focused: _ever_focused = true
	if not _benchmark_mode and not focused and _last_focus: _cancel_preview_and_pause("Window focus lost")
	_last_focus = focused

func _notification(what: int) -> void:
	if _shutting_down: return
	if (what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT) and _ever_focused and not _benchmark_mode:
		if is_inside_tree():
			_cancel_preview_and_pause("Application suspended")
			if _world_dirty and backend and backend.has_method("is_ready") and backend.is_ready() and backend.has_method("save_world"): _save_world()

func _input(event: InputEvent) -> void:
	if _shutting_down: return
	if _restoring_player: return
	if _benchmark_mode and not _fixture_active: return
	# Dispatch physical events immediately; analog axes remain state-polled in
	# _read_controller for smooth camera and cursor movement.
	for action in ["m0_pause", "m0_accept", "m0_cancel", "m0_mode", "m0_debug", "m0_undo", "m0_redo", "m0_radius_decrease", "m0_radius_increase", "m0_height_down", "m0_height_up", "m0_focus"]:
		if event.is_action_pressed(action):
			var menu_before := menu_open
			_handle_action(action)
			if _fixture_active or not menu_before or action in ["m0_pause", "m0_accept", "m0_cancel", "m0_height_down", "m0_height_up"]:
				get_viewport().set_input_as_handled()
			return

func _handle_action(action: String) -> void:
	if _fixture_active:
		if not _fixture_done: return
		if _restore_failed:
			if action == "m0_accept":
				var failed_focus := get_viewport().gui_get_focus_owner()
				if failed_focus is Button: (failed_focus as Button).pressed.emit()
			return
		if action == "m0_height_down": _move_fixture_focus(1)
		elif action == "m0_height_up": _move_fixture_focus(-1)
		elif action == "m0_cancel": _return_from_fixture()
		elif action == "m0_accept":
			var fixture_focus := get_viewport().gui_get_focus_owner()
			if fixture_focus is Button: (fixture_focus as Button).pressed.emit()
		return
	if action == "m0_pause":
		_set_menu(not menu_open)
		return
	if menu_open:
		if action == "m0_height_down":
			_move_menu_focus(1)
		elif action == "m0_height_up":
			_move_menu_focus(-1)
		elif action == "m0_cancel":
			_set_menu(false)
		elif action == "m0_accept":
			var focused := get_viewport().gui_get_focus_owner()
			if focused is Button: (focused as Button).pressed.emit()
		return
	match action:
		"m0_accept": _commit_or_preview()
		"m0_cancel": _cancel_or_menu()
		"m0_mode":
			remove_mode = not remove_mode
			_set_status("Mode: %s" % ("REMOVE" if remove_mode else "ADD"))
		"m0_debug": debug_open = not debug_open
		"m0_undo": _undo()
		"m0_redo": _redo()
		"m0_radius_decrease": brush_index = maxi(0, brush_index - 1)
		"m0_radius_increase": brush_index = mini(BRUSH_STEPS.size() - 1, brush_index + 1)
		"m0_height_down": cursor.y = clampf(cursor.y - 1.0, CURSOR_MIN.y, CURSOR_MAX.y)
		"m0_height_up": cursor.y = clampf(cursor.y + 1.0, CURSOR_MIN.y, CURSOR_MAX.y)
		"m0_focus": _focus_cursor()

func _move_menu_focus(direction: int) -> void:
	var names := ["Save", "Reload", "Run 60s fixture", "Resume", "Quit"]
	var focused := get_viewport().gui_get_focus_owner()
	var index := names.find(focused.text if focused is Button else "Save")
	index = clampi(index + direction, 0, names.size() - 1)
	(_pause_buttons[names[index]] as Button).grab_focus()

func _move_fixture_focus(direction: int) -> void:
	var buttons := [fixture_return_button, fixture_quit_button]
	var focused := get_viewport().gui_get_focus_owner()
	var index := buttons.find(focused)
	index = clampi(index + direction, 0, buttons.size() - 1)
	buttons[index].grab_focus()

func _setup_input_map() -> void:
	_ensure_action("m0_accept"); _add_button("m0_accept", JOY_BUTTON_A); _add_key("m0_accept", KEY_ENTER)
	_ensure_action("m0_cancel"); _add_button("m0_cancel", JOY_BUTTON_B); _add_key("m0_cancel", KEY_ESCAPE)
	_ensure_action("m0_mode"); _add_button("m0_mode", JOY_BUTTON_X); _add_key("m0_mode", KEY_X)
	_ensure_action("m0_debug"); _add_button("m0_debug", JOY_BUTTON_Y); _add_key("m0_debug", KEY_F1)
	_ensure_action("m0_pause"); _add_button("m0_pause", JOY_BUTTON_START); _add_key("m0_pause", KEY_P)
	_ensure_action("m0_undo"); _add_button("m0_undo", JOY_BUTTON_LEFT_SHOULDER); _add_key("m0_undo", KEY_Z)
	_ensure_action("m0_redo"); _add_button("m0_redo", JOY_BUTTON_RIGHT_SHOULDER); _add_key("m0_redo", KEY_C)
	_ensure_action("m0_focus"); _add_button("m0_focus", JOY_BUTTON_RIGHT_STICK); _add_key("m0_focus", KEY_F)
	_ensure_action("m0_radius_decrease"); _add_button("m0_radius_decrease", JOY_BUTTON_DPAD_LEFT)
	_ensure_action("m0_radius_increase"); _add_button("m0_radius_increase", JOY_BUTTON_DPAD_RIGHT)
	_ensure_action("m0_height_up"); _add_button("m0_height_up", JOY_BUTTON_DPAD_UP); _add_key("m0_height_up", KEY_E)
	_ensure_action("m0_height_down"); _add_button("m0_height_down", JOY_BUTTON_DPAD_DOWN); _add_key("m0_height_down", KEY_Q)
	_ensure_action("m0_move_left"); _add_axis("m0_move_left", JOY_AXIS_LEFT_X, -1.0); _add_key("m0_move_left", KEY_A)
	_ensure_action("m0_move_right"); _add_axis("m0_move_right", JOY_AXIS_LEFT_X, 1.0); _add_key("m0_move_right", KEY_D)
	_ensure_action("m0_move_up"); _add_axis("m0_move_up", JOY_AXIS_LEFT_Y, -1.0); _add_key("m0_move_up", KEY_W)
	_ensure_action("m0_move_down"); _add_axis("m0_move_down", JOY_AXIS_LEFT_Y, 1.0); _add_key("m0_move_down", KEY_S)
	_ensure_action("m0_orbit_left"); _add_axis("m0_orbit_left", JOY_AXIS_RIGHT_X, -1.0); _add_key("m0_orbit_left", KEY_LEFT)
	_ensure_action("m0_orbit_right"); _add_axis("m0_orbit_right", JOY_AXIS_RIGHT_X, 1.0); _add_key("m0_orbit_right", KEY_RIGHT)
	_ensure_action("m0_orbit_up"); _add_axis("m0_orbit_up", JOY_AXIS_RIGHT_Y, -1.0); _add_key("m0_orbit_up", KEY_UP)
	_ensure_action("m0_orbit_down"); _add_axis("m0_orbit_down", JOY_AXIS_RIGHT_Y, 1.0); _add_key("m0_orbit_down", KEY_DOWN)
	_ensure_action("m0_zoom_out"); _add_axis("m0_zoom_out", JOY_AXIS_TRIGGER_LEFT, 1.0); _add_key("m0_zoom_out", KEY_MINUS)
	_ensure_action("m0_zoom_in"); _add_axis("m0_zoom_in", JOY_AXIS_TRIGGER_RIGHT, 1.0); _add_key("m0_zoom_in", KEY_EQUAL); _add_key("m0_zoom_in", KEY_KP_ADD)

func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action): InputMap.add_action(action)

func _add_key(action: String, key: Key) -> void:
	var input := InputEventKey.new(); input.keycode = key; InputMap.action_add_event(action, input)

func _add_button(action: String, button: JoyButton) -> void:
	var input := InputEventJoypadButton.new(); input.button_index = button; InputMap.action_add_event(action, input)

func _add_axis(action: String, axis: JoyAxis, value: float) -> void:
	var input := InputEventJoypadMotion.new(); input.axis = axis; input.axis_value = value; InputMap.action_add_event(action, input)

func _create_backend() -> void:
	var backend_script := load("res://scripts/terrain_backend.gd")
	if backend_script:
		backend = backend_script.new(); backend.name = "TerrainBackend"
		if not checkpoint_root.is_empty(): backend.set("checkpoint_root", checkpoint_root)
		add_child(backend)
	if backend == null: _set_status("Terrain backend unavailable")

func _build_lighting_and_world() -> void:
	var sun := DirectionalLight3D.new(); sun.name = "WarmStoneSun"; sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0); sun.light_color = Color("#ffd9a3"); sun.light_energy = 1.25; sun.shadow_enabled = true; add_child(sun)
	var env := WorldEnvironment.new(); var environment := Environment.new(); environment.background_mode = Environment.BG_SKY
	var sky := Sky.new(); var sky_mat := ProceduralSkyMaterial.new(); sky_mat.sky_top_color = Color("#143947"); sky_mat.sky_horizon_color = Color("#d29b70"); sky_mat.ground_bottom_color = Color("#161e24"); sky_mat.ground_horizon_color = Color("#6f5a51"); sky.sky_material = sky_mat; environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; environment.ambient_light_energy = 0.65; environment.fog_enabled = true; environment.fog_light_color = Color("#54656b"); environment.fog_density = 0.006; env.environment = environment; add_child(env)
	terrain_visual = Node3D.new(); terrain_visual.name = "TerrainPresentation"; add_child(terrain_visual); _build_water()
	camera = Camera3D.new(); camera.name = "OrbitCamera"; camera.current = true; camera.fov = 52.0; add_child(camera)

func _build_terrain_presentation() -> void:
	# Backend readiness is asynchronous; do not report an unavailable world
	# while the native terrain is still being built.
	var stat: Dictionary = backend.stats() if backend and backend.has_method("stats") else {}
	var error := str(stat.get("error", ""))
	_set_status("Native terrain error: %s" % error if not error.is_empty() else "Loading native valley…")

func _build_water() -> void:
	var water := MeshInstance3D.new(); water.name = "WaterTestSurface"; var plane := PlaneMesh.new(); plane.size = Vector2(12, 10); water.mesh = plane; water.position = Vector3(40, 6.3, 9)
	var material := ShaderMaterial.new(); material.shader = load("res://shaders/water.gdshader"); water.material_override = material; terrain_visual.add_child(water)

func _build_ui() -> void:
	hud = CanvasLayer.new(); hud.name = "HUD"; add_child(hud)
	var margin := MarginContainer.new(); margin.name = "SafeMargins"; margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); margin.add_theme_constant_override("margin_left", 28); margin.add_theme_constant_override("margin_top", 24); margin.add_theme_constant_override("margin_right", 28); margin.add_theme_constant_override("margin_bottom", 22); hud.add_child(margin)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 5); margin.add_child(column)
	status = Label.new(); status.add_theme_font_size_override("font_size", 26); status.add_theme_color_override("font_color", Color("#ffe2b4")); column.add_child(status)
	var controls := Label.new(); controls.text = "L cursor  •  R orbit  •  LT/RT zoom  •  A preview/commit  •  B cancel  •  X add/remove\nD-pad brush/height  •  LB/RB undo/redo  •  Start pause  •  Y debug  •  R3 focus"; controls.add_theme_font_size_override("font_size", 24); controls.add_theme_color_override("font_color", Color("#e1eee8")); column.add_child(controls)
	cursor_info = Label.new(); cursor_info.add_theme_font_size_override("font_size", 24); cursor_info.add_theme_color_override("font_color", Color("#9ff2de")); column.add_child(cursor_info)
	debug_label = Label.new(); debug_label.position = Vector2(28, 178); debug_label.custom_minimum_size = Vector2(820, 0); debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; debug_label.add_theme_font_size_override("font_size", 22); debug_label.add_theme_color_override("font_color", Color("#bce9e0")); hud.add_child(debug_label); _build_pause_panel()

func _build_pause_panel() -> void:
	pause_panel = PanelContainer.new(); pause_panel.name = "PauseMenu"; pause_panel.position = Vector2(430, 120); pause_panel.size = Vector2(420, 500); pause_panel.visible = false; hud.add_child(pause_panel)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 12); pause_panel.add_child(box)
	var title := Label.new(); title.text = "PAUSED\nWorld input suspended"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size", 30); box.add_child(title)
	for entry in ["Save", "Reload", "Run 60s fixture", "Resume", "Quit"]:
		var button := Button.new(); button.text = entry; button.focus_mode = Control.FOCUS_ALL; button.custom_minimum_size = Vector2(0, 58); button.add_theme_font_size_override("font_size", 26); box.add_child(button); button.pressed.connect(_pause_choice.bind(entry)); _pause_buttons[entry] = button
	_build_fixture_panel()

func _build_fixture_panel() -> void:
	fixture_panel = PanelContainer.new(); fixture_panel.name = "FixtureResult"; fixture_panel.position = Vector2(350, 100); fixture_panel.size = Vector2(580, 520); fixture_panel.visible = false; hud.add_child(fixture_panel)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 12); fixture_panel.add_child(box)
	fixture_label = Label.new(); fixture_label.text = "Running benchmark fixture…"; fixture_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; fixture_label.custom_minimum_size = Vector2(520, 190); fixture_label.add_theme_font_size_override("font_size", 25); box.add_child(fixture_label)
	fixture_return_button = Button.new(); fixture_return_button.text = "Return to valley"; fixture_return_button.focus_mode = Control.FOCUS_ALL; fixture_return_button.custom_minimum_size = Vector2(0, 58); fixture_return_button.add_theme_font_size_override("font_size", 26); fixture_return_button.pressed.connect(_return_from_fixture); box.add_child(fixture_return_button)
	fixture_quit_button = Button.new(); fixture_quit_button.text = "Quit"; fixture_quit_button.focus_mode = Control.FOCUS_ALL; fixture_quit_button.custom_minimum_size = Vector2(0, 58); fixture_quit_button.add_theme_font_size_override("font_size", 26); fixture_quit_button.pressed.connect(_quit_from_fixture); box.add_child(fixture_quit_button)

func _pause_choice(choice: String) -> void:
	match choice:
		"Save": _save_world()
		"Reload": _reload_world()
		"Run 60s fixture": _start_fixture()
		"Resume": _set_menu(false)
		"Quit": _save_then_quit()

func _read_controller(delta: float) -> void:
	var move := Vector2(Input.get_axis("m0_move_left", "m0_move_right"), Input.get_axis("m0_move_up", "m0_move_down"))
	if move.length() > 0.05:
		move = move.limit_length(1.0); var forward := Vector3(sin(camera_yaw), 0.0, cos(camera_yaw)); var right := Vector3(forward.z, 0.0, -forward.x); cursor += (right * move.x + forward * move.y) * delta * 12.0; cursor.x = clampf(cursor.x, CURSOR_MIN.x, CURSOR_MAX.x); cursor.z = clampf(cursor.z, CURSOR_MIN.z, CURSOR_MAX.z)
	var orbit_x := Input.get_axis("m0_orbit_left", "m0_orbit_right"); var orbit_y := Input.get_axis("m0_orbit_up", "m0_orbit_down"); camera_yaw += orbit_x * delta * 2.2; camera_pitch = clampf(camera_pitch + orbit_y * delta * 1.5, 0.15, 1.25)
	var zoom := Input.get_axis("m0_zoom_out", "m0_zoom_in"); camera_distance = clampf(camera_distance - zoom * delta * 18.0, 12.0, 52.0)

func _commit_or_preview() -> bool:
	if not backend or not backend.has_method("is_ready") or not backend.is_ready():
		_set_status("Terrain is still loading; edit unavailable")
		return false
	if preview_active:
		var ok: bool = backend.apply_sphere(cursor, BRUSH_STEPS[brush_index], remove_mode) if backend.has_method("apply_sphere") else false
		preview_active = false
		if ok: _world_dirty = true
		_set_status("Committed one %s sphere" % ("remove" if remove_mode else "add") if ok else "Commit failed; no terrain change")
		return ok
	preview_active = true
	_set_status("Preview: press A to commit, B to cancel")
	return true

func _cancel_or_menu() -> void:
	if preview_active:
		preview_active = false
		_set_status("Preview cancelled; terrain unchanged")
	else:
		_set_menu(true)

func _cancel_preview_and_pause(reason: String) -> void: preview_active = false; _set_status(reason); _set_menu(true)

func _set_menu(open: bool) -> void:
	menu_open = open; if pause_panel: pause_panel.visible = open
	if open:
		preview_active = false
		if _pause_buttons.has("Save"): (_pause_buttons["Save"] as Button).call_deferred("grab_focus")
	state_changed.emit("menu" if open else "world")

func _undo() -> bool:
	var ok: bool = backend.undo() if backend and backend.has_method("undo") else false
	if ok: _world_dirty = true
	_set_status("Undo complete" if ok else "Nothing to undo")
	return ok

func _redo() -> bool:
	var ok: bool = backend.redo() if backend and backend.has_method("redo") else false
	if ok: _world_dirty = true
	_set_status("Redo complete" if ok else "Nothing to redo")
	return ok

func _save_world() -> bool:
	var ok: bool = backend.save_world() if backend and backend.has_method("save_world") else false
	if ok: _world_dirty = false
	_set_status("World saved" if ok else "Save failed")
	return ok

func _reload_world() -> bool:
	var ok: bool = backend.load_world() if backend and backend.has_method("load_world") else false
	preview_active = false
	if ok: _world_dirty = false
	_set_status("World reloaded" if ok else "Reload failed")
	return ok

func _save_then_quit() -> void:
	preview_active = false
	if _world_dirty and not _save_world(): return
	_quit_cleanly()

func _start_fixture() -> void:
	if _fixture_active: return
	# Establish a complete player checkpoint even when the session was clean, so
	# returning from the isolated backend is always an exact load operation.
	if not _save_world():
		_set_status("Fixture aborted; player save failed")
		return
	preview_active = false
	_fixture_active = true
	_benchmark_mode = true
	_fixture_done = false
	_fixture_result = {}
	_restore_failed = false
	_set_menu(false)
	fixture_panel.visible = true
	fixture_label.text = "Running 60s fixture…\nWorld input is suspended."
	fixture_return_button.visible = false
	fixture_quit_button.visible = false
	_set_status("Running isolated fixture…")
	# Never reuse the player backend or its checkpoint root for benchmark data.
	var old_backend := backend
	backend = null
	if old_backend and is_instance_valid(old_backend): old_backend.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_create_backend_at("user://m0-menu-fixture-checkpoint")
	await _run_benchmark(false)

func _create_backend_at(root_path: String) -> void:
	var backend_script := load("res://scripts/terrain_backend.gd")
	if backend_script:
		backend = backend_script.new()
		backend.name = "TerrainBackend"
		backend.set("checkpoint_root", root_path)
		add_child(backend)

func _finish_fixture(result: Dictionary) -> void:
	_fixture_result = result
	_fixture_done = true
	fixture_panel.visible = true
	fixture_return_button.visible = true
	fixture_quit_button.visible = true
	fixture_return_button.grab_focus()
	var ok := bool(result.get("ok", false))
	fixture_label.text = "Fixture %s\nElapsed %.2fs  samples %s\nEdits %s  undo %s  redo %s  saves %s\nFrame p95/p99 %.2f / %.2f ms\n%s" % ["passed" if ok else "failed", result.get("actual_elapsed_seconds", 0.0), result.get("sample_count", 0), result.get("edits", 0), result.get("undos", 0), result.get("redos", 0), result.get("saves", 0), result.get("frame_ms_p95", 0.0), result.get("frame_ms_p99", 0.0), ", ".join(result.get("errors", []))]
	_set_status("Fixture complete" if ok else "Fixture failed")

func _return_from_fixture() -> void:
	if not _fixture_active or not _fixture_done or _restoring_player: return
	_fixture_active = false
	_benchmark_mode = false
	_restoring_player = true
	_player_restored = false
	_fixture_done = false
	fixture_panel.visible = false
	var fixture_backend := backend
	backend = null
	if fixture_backend and is_instance_valid(fixture_backend): fixture_backend.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_create_backend()
	var restore_deadline := Time.get_ticks_msec() + 15000
	while backend and backend.has_method("is_ready") and not backend.is_ready() and Time.get_ticks_msec() < restore_deadline:
		await get_tree().process_frame
	if backend and backend.is_ready():
		var loaded: bool = backend.load_world()
		var restore_error := str(backend.stats().get("error", ""))
		_player_restored = loaded
		_restoring_player = false
		if loaded:
			_set_status("Valley restored")
		else:
			_restore_failed = true
			_fixture_active = true
			_fixture_done = true
			fixture_panel.visible = true
			fixture_return_button.visible = false
			fixture_quit_button.visible = true
			fixture_quit_button.grab_focus()
			fixture_label.text = "Player restore failed\n%s\nQuit and recover from the saved checkpoint." % restore_error
			_set_status("Player restore failed")
	else:
		_restoring_player = false
		_restore_failed = true
		_fixture_active = true
		_fixture_done = true
		fixture_panel.visible = true
		fixture_return_button.visible = false
		fixture_quit_button.visible = true
		fixture_quit_button.grab_focus()
		fixture_label.text = "Player restore failed\nBackend did not become ready."
		_set_status("Player restore failed: backend not ready")

func _quit_from_fixture() -> void:
	if _fixture_active and _fixture_done and not _restoring_player:
		_fixture_active = false
		fixture_panel.visible = false
	_quit_cleanly()

func _quit_cleanly(exit_code: int = 0) -> void:
	var tree := get_tree()
	# Release the native terrain first while this controller remains alive to
	# await two frames for RID cleanup, then remove the root and quit.
	_shutting_down = true
	set_process(false)
	set_process_input(false)
	var backend_to_free := backend
	backend = null
	if backend_to_free and is_instance_valid(backend_to_free):
		backend_to_free.queue_free()
	await tree.process_frame
	await tree.process_frame
	queue_free()
	tree.quit(exit_code)

func _focus_cursor() -> void: camera_distance = 20.0; _set_status("Camera focused on cursor")

func _update_camera(_delta: float) -> void:
	if not camera: return
	var target := cursor + Vector3(0, 2.0, 0); var offset := Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch)) * camera_distance; camera.global_position = target + offset; camera.look_at(target, Vector3.UP)

func _update_cursor_visual() -> void:
	if cursor_mesh == null:
		cursor_mesh = MeshInstance3D.new(); cursor_mesh.name = "WorldCursor"; var ring := TorusMesh.new(); ring.inner_radius = 0.8; ring.outer_radius = 1.0; ring.rings = 24; ring.ring_segments = 8; cursor_mesh.mesh = ring; var mat := StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mat.no_depth_test = true; mat.albedo_color = Color("#58e4d0"); mat.emission_enabled = true; mat.emission = Color("#1d8d80"); cursor_mesh.material_override = mat; add_child(cursor_mesh)
	if preview_mesh == null:
		preview_mesh = MeshInstance3D.new(); preview_mesh.name = "SpherePreview"; var sphere := SphereMesh.new(); sphere.radius = 1.0; sphere.height = 2.0; sphere.radial_segments = 24; sphere.rings = 12; preview_mesh.mesh = sphere; var preview_mat := StandardMaterial3D.new(); preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; preview_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; preview_mat.no_depth_test = true; preview_mat.albedo_color = Color(0.2, 0.85, 0.7, 0.24); preview_mat.emission_enabled = true; preview_mat.emission = Color(0.1, 0.4, 0.3); preview_mesh.material_override = preview_mat; add_child(preview_mesh)
	cursor_mesh.position = cursor + Vector3(0, 0.04, 0); cursor_mesh.scale = Vector3.ONE * BRUSH_STEPS[brush_index]; var ring_material := cursor_mesh.material_override as StandardMaterial3D; ring_material.albedo_color = Color("#ffb36b") if not remove_mode else Color("#58e4d0"); preview_mesh.position = cursor; preview_mesh.scale = Vector3.ONE * BRUSH_STEPS[brush_index]; preview_mesh.visible = preview_active; cursor_info.text = "Cell %d, %d, %d   radius %.1f   %s" % [roundi(cursor.x), roundi(cursor.y), roundi(cursor.z), BRUSH_STEPS[brush_index], "REMOVE" if remove_mode else "ADD"]

func _update_preview() -> void:
	if cursor_mesh: cursor_mesh.visible = true

func _percentile(values: Array[float], q: float) -> float:
	if values.is_empty(): return 0.0
	var sorted := values.duplicate(); sorted.sort(); return sorted[clampi(int(ceil(float(sorted.size()) * q)) - 1, 0, sorted.size() - 1)]

func _monitor(name: int) -> float:
	var value := Performance.get_monitor(name); return float(value) if value != null and is_finite(float(value)) else -1.0

func _update_debug() -> void:
	debug_label.visible = debug_open
	if not debug_open: return
	var stat: Dictionary = backend.stats() if backend and backend.has_method("stats") else {"ready": false, "revision": 0}; var draw_calls := _monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME); var primitives := _monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME); var memory := _monitor(Performance.MEMORY_STATIC); var memory_text := "unavailable" if memory <= 0.0 else "%.1f MB" % (memory / 1048576.0)
	debug_label.text = "DEBUG\nRenderer: %s / %s  %dx%d\nFrame ms p95/p99: %.2f / %.2f  samples: %d\nDraw calls/primitives: %.0f / %.0f\nGodot static memory: %s\nBackend ready %s  rev %s  undo %s redo %s\nEdit %.2f ms  save %s  pending %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), get_viewport().size.x, get_viewport().size.y, _percentile(frame_ms_samples, 0.95), _percentile(frame_ms_samples, 0.99), frame_ms_samples.size(), draw_calls, primitives, memory_text, stat.get("ready", false), stat.get("revision", 0), stat.get("undo_count", 0), stat.get("redo_count", 0), stat.get("last_edit_ms", 0.0), stat.get("save_status", "never"), stat.get("pending", true)]

func _set_status(message: String) -> void:
	if status: status.text = "HEARTHVALE  /  M0   %s" % message

func _on_backend_ready(value: bool) -> void:
	if not value:
		_set_status("Valley backend error")
		return
	# A normal game session resumes its last valid checkpoint. Test and
	# benchmark roots intentionally start from the deterministic generated patch.
	if checkpoint_root.is_empty() and not _benchmark_mode and backend.has_method("load_world") and backend.load_world():
		_world_dirty = false
		_set_status("Valley reloaded")
	else:
		_set_status("Valley ready")

func _on_joy_connection_changed(_device: int, is_connected: bool) -> void:
	connected = is_connected
	if not is_connected: _cancel_preview_and_pause("Controller disconnected")
	else: _set_status("Controller reconnected; world paused")

func _parse_command_line() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--benchmark": _benchmark_mode = true
		elif arg == "--quit-after-capture": _quit_after_capture = true
		elif arg.begins_with("--capture="): _capture_path = arg.get_slice("=", 1)
		elif arg.begins_with("--capture-view="): _capture_view = arg.get_slice("=", 1)
	if _benchmark_mode and checkpoint_root.is_empty(): checkpoint_root = "user://m0-benchmark-checkpoint"

func _maybe_benchmark() -> void:
	if _benchmark_mode: _run_benchmark()
	elif not _capture_path.is_empty(): _capture_standalone()

func _apply_capture_view() -> void:
	if _capture_view == "water":
		cursor = Vector3(40, 7, 9); camera_yaw = 0.9; camera_pitch = 0.6; camera_distance = 24.0
	elif _capture_view == "preview":
		cursor = Vector3(3, 5, 24); camera_yaw = -1.1; camera_pitch = 0.66; camera_distance = 24.0; preview_active = true; _set_status("Preview: A commit / B cancel")
	_update_camera(0.0)
	_update_cursor_visual()

func _capture_standalone() -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while backend and backend.has_method("is_ready") and not backend.is_ready() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	if not backend or not backend.is_ready():
		print(JSON.stringify({"ok": false, "error": "native backend did not become ready"}))
		get_tree().quit(1)
		return
	_apply_capture_view()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var ok := get_viewport().get_texture().get_image().save_png(_capture_path) == OK
	print(JSON.stringify({"ok": ok, "capture": _capture_path, "renderer": RenderingServer.get_current_rendering_method()}))
	if _quit_after_capture:
		await _quit_cleanly(0 if ok else 1)

func _run_benchmark(auto_quit: bool = true) -> void:
	var seconds := benchmark_seconds_override
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--benchmark-seconds="): seconds = maxf(1.0, float(arg.get_slice("=", 1)))
	seconds = maxf(1.0, seconds)
	var deadline := Time.get_ticks_msec() + 60000
	while backend and backend.has_method("is_ready") and not backend.is_ready() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	if not backend or not backend.is_ready():
		var failed_result := {"ok": false, "requested_seconds": seconds, "actual_elapsed_seconds": 0.0, "sample_count": 0, "edits": 0, "undos": 0, "redos": 0, "saves": 0, "errors": ["native backend did not become ready"]}
		if not auto_quit:
			_finish_fixture(failed_result)
			return
		print(JSON.stringify(failed_result))
		await _quit_cleanly(1)
		return
	debug_open = true
	camera_yaw = -1.1
	camera_pitch = 0.66
	camera_distance = 31.0
	var route := [Vector3(3, 5, 24), Vector3(12, 6, 24), Vector3(32, 8, 10), Vector3(24, 9, 30)]
	var started := Time.get_ticks_usec()
	var last_edit := started - 2000000
	var timings: Array[float] = []
	var edit_count := 0
	var undo_count := 0
	var redo_count := 0
	var save_count := 0
	var edit_costs: Array[float] = []
	var last_frame := started
	var edit_remove := true
	var operation_errors: Array[String] = []
	while float(Time.get_ticks_usec() - started) / 1000000.0 < seconds:
		# Route phase derives from elapsed wallclock, making the camera fixture
		# independent of renderer frame rate.
		var phase := fmod(float(Time.get_ticks_usec() - started) / 1000000.0 * 0.12, float(route.size()))
		var route_index := floori(phase)
		var route_t := phase - float(route_index)
		cursor = route[route_index].lerp(route[(route_index + 1) % route.size()], route_t)
		_update_camera(0.0)
		var current := Time.get_ticks_usec()
		if current - last_edit >= 2000000:
			var op_started := Time.get_ticks_usec()
			# Alternate remove/add at a known solid roof cell so every timed edit
			# has an authoritative voxel delta, including long benchmark runs.
			if backend.apply_sphere(Vector3(24, 8, 24), 1.5, edit_remove): edit_count += 1
			else: operation_errors.append("edit failed")
			edit_remove = not edit_remove
			if backend.undo(): undo_count += 1
			else: operation_errors.append("undo failed")
			if backend.redo(): redo_count += 1
			else: operation_errors.append("redo failed")
			if backend.save_world(): save_count += 1
			else: operation_errors.append("save failed")
			edit_costs.append(float(Time.get_ticks_usec() - op_started) / 1000.0)
			last_edit = Time.get_ticks_usec()
		await get_tree().process_frame
		var after := Time.get_ticks_usec()
		timings.append(float(after - last_frame) / 1000.0)
		last_frame = after
	timings.sort()
	var elapsed := float(Time.get_ticks_usec() - started) / 1000000.0
	var final_stats: Dictionary = backend.stats()
	var backend_error := str(final_stats.get("error", ""))
	if not backend_error.is_empty(): operation_errors.append("backend: %s" % backend_error)
	var static_memory := _monitor(Performance.MEMORY_STATIC)
	var result := {"ok": operation_errors.is_empty(), "renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "resolution": "%sx%s" % [get_viewport().size.x, get_viewport().size.y], "requested_seconds": seconds, "actual_elapsed_seconds": elapsed, "sample_count": timings.size(), "frame_ms_p50": _percentile(timings, 0.50), "frame_ms_p95": _percentile(timings, 0.95), "frame_ms_p99": _percentile(timings, 0.99), "frame_ms_max": timings[-1] if not timings.is_empty() else 0.0, "draw_calls": _monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "triangles": _monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "godot_static_memory_bytes": static_memory if static_memory > 0.0 else null, "godot_static_memory_available": static_memory > 0.0, "native_gpu_memory": "not measured", "edits": edit_count, "undos": undo_count, "redos": redo_count, "saves": save_count, "edit_ms_p95": _percentile(edit_costs, 0.95), "errors": operation_errors, "backend": final_stats}
	var file := FileAccess.open("user://benchmark-%s.json" % RenderingServer.get_current_rendering_method(), FileAccess.WRITE)
	if file == null:
		operation_errors.append("benchmark file write failed")
		result["errors"] = operation_errors
		result["ok"] = false
	else:
		file.store_string(JSON.stringify(result))
		var write_error := file.get_error()
		file.close()
		if write_error != OK:
			operation_errors.append("benchmark file write failed")
			result["errors"] = operation_errors
			result["ok"] = false
	print(JSON.stringify(result))
	if not auto_quit:
		_finish_fixture(result)
		return
	if not _capture_path.is_empty():
		_apply_capture_view()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_capture_path)
	await _quit_cleanly(0 if bool(result.get("ok", false)) else 1)
