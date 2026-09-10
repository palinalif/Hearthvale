extends "res://scripts/m2_scene_upper_wall_details.gd"

## Keep every home action readable without allowing its content minimum to grow
## the panel into the controller prompts. Scroll the existing stack so button
## identities, callbacks, visual order and controller navigation stay intact.
const HOME_OPTIONS_PROMPT_GAP := 12.0
var _home_options_scroll: ScrollContainer
var _home_options_default_top := 0.0

func _ready() -> void:
	super._ready()
	_compact_home_options_for_storeys()

func _compact_home_options_for_storeys() -> void:
	if not _building_panel or is_instance_valid(_home_options_scroll): return
	var margin := _building_panel.get_child(0) as MarginContainer
	var box := margin.get_child(0) as VBoxContainer
	_home_options_default_top = _building_panel.position.y
	_home_options_scroll = ScrollContainer.new()
	_home_options_scroll.name = "HomeOptionsScroll"
	_home_options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_home_options_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_home_options_scroll.follow_focus = true
	_home_options_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_home_options_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.remove_child(box)
	margin.add_child(_home_options_scroll)
	_home_options_scroll.add_child(box)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	for button in _building_buttons:
		button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 42.0)
	_building_panel.custom_minimum_size.y = 0.0
	get_viewport().size_changed.connect(_layout_home_options)
	_building_panel.visibility_changed.connect(_layout_home_options)
	if _prompt_bar:
		_prompt_bar.item_rect_changed.connect(_layout_home_options)
	_layout_home_options()

func _layout_home_options() -> void:
	if not is_instance_valid(_home_options_scroll): return
	var bottom := get_viewport().get_visible_rect().end.y - HOME_OPTIONS_PROMPT_GAP
	if _prompt_bar:
		bottom = minf(bottom, _prompt_bar.position.y - HOME_OPTIONS_PROMPT_GAP)
	# Retain the normal position, but allow a shorter window to move the panel
	# up rather than leave a nearly unusable scroll area below the tool card.
	_building_panel.position.y = minf(_home_options_default_top, maxf(HOME_OPTIONS_PROMPT_GAP, bottom - 160.0))
	_building_panel.size.y = maxf(0.0, bottom - _building_panel.position.y)
	_reveal_home_option_focus.call_deferred()

func _reveal_home_option_focus() -> void:
	if not is_instance_valid(_home_options_scroll) or not _building_panel.is_visible_in_tree(): return
	var focus := get_viewport().gui_get_focus_owner()
	if focus and _home_options_scroll.is_ancestor_of(focus):
		_home_options_scroll.ensure_control_visible(focus)
