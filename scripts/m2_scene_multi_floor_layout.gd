extends "res://scripts/m2_scene_upper_wall_details.gd"

## Bound both growing home menus without shrinking their actions. Keep the
## original stacks so button identities, callbacks and visual order survive.
const HOME_OPTIONS_PROMPT_GAP := 12.0
var _home_options_scroll: ScrollContainer
var _house_shape_options_scroll: ScrollContainer
var _bounded_home_option_panels: Array[Dictionary] = []
var _home_options_reveal_pending := false

func _ready() -> void:
	super._ready()
	_compact_home_options_for_storeys()

func _compact_home_options_for_storeys() -> void:
	if not _building_panel or is_instance_valid(_home_options_scroll): return
	_home_options_scroll = _bound_home_option_panel(_building_panel, _building_buttons, "HomeOptionsScroll")
	if _house_shape_picker:
		_house_shape_options_scroll = _bound_home_option_panel(_house_shape_picker, _house_shape_buttons, "HouseShapeScroll")
	get_viewport().size_changed.connect(_layout_home_options)
	if _prompt_bar:
		_prompt_bar.item_rect_changed.connect(_layout_home_options)
	_layout_home_options()

func _bound_home_option_panel(panel: PanelContainer, buttons: Array[Button], scroll_name: String) -> ScrollContainer:
	var margin := panel.get_child(0) as MarginContainer
	var box := margin.get_child(0) as VBoxContainer
	var scroll := ScrollContainer.new()
	scroll.name = scroll_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.remove_child(box)
	margin.add_child(scroll)
	scroll.add_child(box)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	box.resized.connect(_queue_home_option_reveal)
	scroll.resized.connect(_queue_home_option_reveal)
	for button in buttons:
		button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 42.0)
		button.focus_entered.connect(_queue_home_option_reveal)
	_bounded_home_option_panels.append({"panel": panel, "scroll": scroll, "top": panel.position.y})
	panel.custom_minimum_size.y = 0.0
	panel.visibility_changed.connect(_layout_home_options)
	return scroll

func _catalogue_box(panel: PanelContainer) -> VBoxContainer:
	# Preserve the existing catalogue accessor after wrapping a picker.
	var content := panel.get_child(0).get_child(0)
	if content is ScrollContainer: return content.get_child(0) as VBoxContainer
	return super._catalogue_box(panel)

func _layout_home_options() -> void:
	if _bounded_home_option_panels.is_empty(): return
	var bottom := get_viewport().get_visible_rect().end.y - HOME_OPTIONS_PROMPT_GAP
	if _prompt_bar:
		bottom = minf(bottom, _prompt_bar.position.y - HOME_OPTIONS_PROMPT_GAP)
	for entry in _bounded_home_option_panels:
		var panel: PanelContainer = entry["panel"]
		var default_top: float = entry["top"]
		# Retain the normal position, but move up in shorter windows instead
		# of leaving a nearly unusable scroll area below the tool card.
		panel.position.y = minf(default_top, maxf(HOME_OPTIONS_PROMPT_GAP, bottom - 160.0))
		panel.size.y = maxf(0.0, bottom - panel.position.y)
	_queue_home_option_reveal()

func _queue_home_option_reveal() -> void:
	if _home_options_reveal_pending or not is_inside_tree(): return
	_home_options_reveal_pending = true
	_reveal_home_option_after_layout.call_deferred()

func _reveal_home_option_after_layout() -> void:
	# Focus can change before nested containers finish resizing. Recheck on
	# the next frame, using the current focus rather than a stale button.
	await get_tree().process_frame
	_home_options_reveal_pending = false
	_reveal_home_option_focus()

func _reveal_home_option_focus() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if not focus: return
	for entry in _bounded_home_option_panels:
		var panel: PanelContainer = entry["panel"]
		var scroll: ScrollContainer = entry["scroll"]
		if is_instance_valid(scroll) and panel.is_visible_in_tree() and scroll.is_ancestor_of(focus):
			scroll.ensure_control_visible(focus)
			return
