extends "res://scripts/m2_scene_house_massing_interaction.gd"

## Joined roofs suppress the old rectangular cottage joinery. Players can opt
## back into exposed timber, but those beams are regenerated from the union roof
## so they follow real eaves/ridges instead of floating over removed roof planes.
const JoinedRoofBeamVisual = preload("res://scripts/m2_joined_roof_beam_visual.gd")

var _joined_roof_beams_button: Button

func _ready() -> void:
	super._ready()
	_install_joined_roof_beam_control()
	_refresh_joined_roof_beam_button()
	_refresh_massing_shells()

func _install_joined_roof_beam_control() -> void:
	if not _roof_decor_picker or not _roof_decor_remove_button: return
	var box: VBoxContainer = _catalogue_box(_roof_decor_picker)
	_joined_roof_beams_button = Button.new()
	_joined_roof_beams_button.name = "JoinedRoofBeamsAction"
	_joined_roof_beams_button.text = "Exposed roof beams: Off"
	_joined_roof_beams_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_joined_roof_beams_button.custom_minimum_size = Vector2(450, 36)
	_joined_roof_beams_button.focus_mode = Control.FOCUS_ALL
	_joined_roof_beams_button.pressed.connect(_toggle_joined_roof_beams)
	box.add_child(_joined_roof_beams_button)
	box.move_child(_joined_roof_beams_button, _roof_decor_remove_button.get_index())
	var remove_index: int = _roof_decor_buttons.find(_roof_decor_remove_button)
	if remove_index >= 0: _roof_decor_buttons.insert(remove_index, _joined_roof_beams_button)
	else: _roof_decor_buttons.append(_joined_roof_beams_button)
	_roof_decor_picker.custom_minimum_size = Vector2(500, 478)

func _open_roof_decor_picker() -> void:
	super._open_roof_decor_picker()
	_refresh_joined_roof_beam_button()

func _toggle_joined_roof_beams() -> void:
	var index: int = building_world._building_index(selected_building_id)
	if index < 0: return
	var before: Dictionary = building_world._copy(building_world._document)
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[index]
	var enabled: bool = not bool(building.get("joined_roof_beams", false))
	building["joined_roof_beams"] = enabled
	buildings[index] = building
	var changed: bool = building_world._record_change(before)
	if not changed: return
	_record_history("building")
	_presentation_key = ""
	_update_presentation()
	_refresh_joined_roof_beam_button()
	var view: Dictionary = building_world.get_building(selected_building_id)
	var joined: bool = HouseMassing.sections_for(view).size() > 1
	if joined: _set_status("Exposed joined-roof beams %s" % ("enabled" if enabled else "disabled"))
	else: _set_status("Roof beams %s • visible when this house has joined portions" % ("enabled" if enabled else "disabled"))

func _refresh_joined_roof_beam_button() -> void:
	if not _joined_roof_beams_button or not building_world: return
	var view: Dictionary = building_world.get_building(selected_building_id)
	var enabled: bool = bool(view.get("joined_roof_beams", false)) if not view.is_empty() else false
	_joined_roof_beams_button.text = "Exposed roof beams: %s" % ("On" if enabled else "Off")

func _set_native_shell_visible(visual: Node3D, visible: bool) -> void:
	super._set_native_shell_visible(visual, visible)
	# EaveJoinery is authored for the original rectangle and was the source of
	# the unsupported floating beams on L/T/U roofs.
	var legacy_joinery := visual.get_node_or_null("EaveJoinery") as Node3D
	if legacy_joinery: legacy_joinery.visible = visible

func _refresh_massing_shell_for_visual(visual: Node3D, view: Dictionary) -> void:
	super._refresh_massing_shell_for_visual(visual, view)
	# The shell refresh restores native nodes. Reapply the active single-roof
	# choice afterward, so it cannot resurrect a gable over a custom preview.
	if HouseMassing.sections_for(view).size() == 1:
		_refresh_roof_overlay_for_visual(visual, view)
	_refresh_joined_roof_beams_for_visual(visual, view)

func _refresh_joined_roof_beams_for_visual(visual: Node3D, view: Dictionary) -> void:
	var joined: bool = HouseMassing.sections_for(view).size() > 1
	var enabled: bool = bool(view.get("joined_roof_beams", false))
	var existing := visual.get_node_or_null("M2JoinedRoofBeams") as Node3D
	if not joined or not enabled:
		if existing:
			visual.remove_child(existing)
			existing.queue_free()
		return
	if not existing:
		existing = JoinedRoofBeamVisual.new()
		existing.name = "M2JoinedRoofBeams"
		visual.add_child(existing)
	existing.show_view(view)

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if _roof_decor_picker_open: _refresh_joined_roof_beam_button()