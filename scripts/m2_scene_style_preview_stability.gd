extends "res://scripts/m2_scene_path_erase.gd"

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

func _input(event: InputEvent) -> void:
	# Some physical pads expose the hat buttons reliably as JoypadButton events
	# even when an action-map translation is missed. Placement owns left/right,
	# so accept the raw buttons here as a narrow fallback instead of letting the
	# idle-building handler interpret them as cottage cycling.
	if building_placement_active and event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if button.pressed and button.button_index in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
			_rotate_building_preview(-1 if button.button_index == JOY_BUTTON_DPAD_LEFT else 1)
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _read_camera_and_cursor(delta: float) -> void:
	# Free placement used the raw render-frame delta for translation. A single
	# long frame (notably on CI/startup, but also after a mobile hitch) could move
	# the preview several metres and turn an otherwise valid A confirmation into
	# an overlap/out-of-bounds rejection. Cap only placement-frame integration;
	# ordinary terrain/building navigation keeps the real delta unchanged.
	if building_placement_active:
		super._read_camera_and_cursor(minf(delta, 1.0 / 30.0))
		return
	super._read_camera_and_cursor(delta)
