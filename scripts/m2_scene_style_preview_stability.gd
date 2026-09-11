extends "res://scripts/m2_scene_build_browser.gd"

## Keep the controller style picker live without rebuilding the same cottage
## presentation on every idle frame. The inherited picker applies a preview
## immediately when focus changes; subsequent presentation ticks only need to
## reapply it when the selected preview or authoritative revision changes.
var _style_preview_render_signature := ""

func _begin_style_picker(mode: String) -> void:
	_style_preview_render_signature = ""
	super._begin_style_picker(mode)

func _apply_style_preview() -> void:
	if _style_picker_detail_id.is_empty() or not building_world:
		_style_preview_render_signature = ""
		return
	var signature := str([
		selected_building_id,
		_style_picker_detail_id,
		_style_preview_asset,
		_style_preview_colour,
		building_world.get_revision(),
	])
	if signature == _style_preview_render_signature:
		return
	super._apply_style_preview()
	_style_preview_render_signature = signature

func _end_style_picker() -> void:
	_style_preview_render_signature = ""
	super._end_style_picker()
