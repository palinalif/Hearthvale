extends "res://scripts/m2_scene_path_terrain_ownership.gd"

## Controller-facing path eraser. X toggles paint/erase while the path tool is
## idle; erase strokes reuse the same painted-cell brush and terrain ownership
## reconciliation as direct erases, so packed-earth cuts restore safely.
var path_erase_mode := false

func _choose_path_style(style_id: String) -> void:
	path_erase_mode = false
	super._choose_path_style(style_id)

func _input(event: InputEvent) -> void:
	if path_placement_active and not path_painting and not menu_open and event.is_action_pressed("m1_tools"):
		path_erase_mode = not path_erase_mode
		_path_preview_signature = ""
		_set_status("Path eraser • hold A erase" if path_erase_mode else "%s • hold A paint" % _path_style_name())
		_update_path_preview()
		_refresh_controller_hud()
		get_viewport().set_input_as_handled()
		return
	super._input(event)

func _commit_path_stroke() -> bool:
	if not path_erase_mode:
		return super._commit_path_stroke()
	if not path_painting:
		return false
	if path_cells.is_empty():
		_cancel_path_stroke("Empty erase stroke cancelled")
		return false
	if JSON.stringify(landscape_state.document()) != _path_before_serialized or _terrain_revision() != _path_terrain_revision or building_world.get_revision() != _path_building_revision:
		_cancel_path_stroke("World changed; erase stroke cancelled")
		return false
	return _commit_path_erase_stroke()

func _commit_path_erase_stroke() -> bool:
	var brush_cells := path_cells.size()
	path_painting = false
	var erased := erase_painted_path_cells(path_cells)
	path_cells.clear()
	_path_last_sample = Vector2(NAN, NAN)
	if path_visual:
		path_visual.hide_preview()
	_path_preview_signature = ""
	if not erased:
		_set_status("Path eraser • nothing under brush")
		_reset_path_baseline()
		_update_path_validity()
		_update_path_preview()
		_refresh_controller_hud()
		return false
	_set_status("Path eraser • %d brush cells cleared • LB undo" % brush_cells)
	_update_path_validity()
	_update_path_preview()
	_refresh_controller_hud()
	return true

func _update_presentation() -> void:
	super._update_presentation()
	if path_placement_active and target_label:
		var mode_name := "ERASE" if path_erase_mode else _path_style_name()
		var action_name := "erase" if path_erase_mode else "paint"
		target_label.text = "%s • %.3f m brush • %s\nD-pad L/R size  X paint/erase  Hold A %s  release commit  B cancel/close" % [mode_name, path_width, path_placement_reason, action_name]

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if path_placement_active and not menu_open and _prompt_row:
		_set_prompts([["A", "Hold to erase" if path_erase_mode else "Hold to paint"], ["D-PAD L/R", "Brush size"], ["X", "Paint/erase"], ["B", "Cancel/close"], ["LB", "Undo"], ["RS", "Orbit"]])
