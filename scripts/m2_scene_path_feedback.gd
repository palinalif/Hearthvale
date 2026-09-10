extends "res://scripts/m2_scene_composition.gd"
## Playtest interaction correction: B dismisses only the live prospective path
## point first. Confirmed route points remain intact; a second B exits once no
## point is actively being placed.

var path_point_active := false

func _begin_path_placement() -> void:
	super._begin_path_placement()
	if not path_placement_active: return
	path_point_active = true
	_path_preview_signature = ""
	_update_brush_preview()
	_update_path_validity()
	_update_path_preview()
	_refresh_controller_hud()

func _input(event: InputEvent) -> void:
	if path_placement_active and not menu_open:
		if event.is_action_pressed("m1_cancel"):
			if path_point_active:
				_pause_path_point()
			else:
				_cancel_path_placement("Path placement finished")
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_accept") and not path_point_active:
			_resume_path_point()
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _pause_path_point() -> void:
	if not path_placement_active or not path_point_active: return
	path_point_active = false
	path_placement_valid = false
	path_placement_reason = "Point placement paused"
	_path_preview_signature = ""
	if cursor_reticle: cursor_reticle.set_target_visible(false)
	_update_path_preview()
	_set_status("Point placement stopped • A continue / X finish / B exit")
	_refresh_controller_hud()

func _resume_path_point() -> void:
	if not path_placement_active or path_point_active: return
	path_point_active = true
	_path_preview_signature = ""
	_update_brush_preview()
	_update_path_validity()
	_update_path_preview()
	_set_status("%s • A add point / X finish / B stop point" % _path_style_name())
	_refresh_controller_hud()

func _update_path_validity() -> void:
	if path_placement_active and not path_point_active:
		path_placement_valid = false
		path_placement_reason = "Point placement paused"
		return
	super._update_path_validity()

func _update_path_preview() -> void:
	if not path_placement_active or path_point_active:
		super._update_path_preview()
		return
	if not path_visual: return
	var signature := "paused|%s|%.3f|%s|%d" % [path_style_id, path_width, JSON.stringify(path_points), _terrain_revision()]
	if signature == _path_preview_signature: return
	_path_preview_signature = signature
	if path_points.is_empty():
		path_visual.hide_preview()
	else:
		path_visual.show_preview(path_style_id, path_width, path_points, true, "Point placement paused")

func _update_brush_preview() -> void:
	super._update_brush_preview()
	if path_placement_active and not path_point_active and cursor_reticle:
		cursor_reticle.set_target_visible(false)

func _update_presentation() -> void:
	super._update_presentation()
	if not path_placement_active or not target_label: return
	if path_point_active:
		target_label.text = "%s • %d point%s • %s\nA add point  X finish  B stop point  LB remove point  RS orbit" % [_path_style_name(), path_points.size(), "" if path_points.size() == 1 else "s", path_placement_reason]
	else:
		target_label.text = "%s • %d confirmed point%s\nA continue placing  X finish  B exit  LB remove point  RS orbit" % [_path_style_name(), path_points.size(), "" if path_points.size() == 1 else "s"]

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if not path_placement_active or menu_open or not _prompt_row: return
	if path_point_active:
		_set_prompts([["A", "Add point"], ["X", "Finish"], ["B", "Stop point"], ["LB", "Remove point"], ["RS", "Orbit"], ["LT/RT", "Zoom"]])
	else:
		_set_prompts([["A", "Continue"], ["X", "Finish"], ["B", "Exit"], ["LB", "Remove point"], ["RS", "Orbit"], ["LT/RT", "Zoom"]])

func _commit_path() -> bool:
	var ok := super._commit_path()
	if not path_placement_active: path_point_active = false
	return ok

func _cancel_path_placement(reason: String = "Path cancelled") -> void:
	path_point_active = false
	super._cancel_path_placement(reason)
