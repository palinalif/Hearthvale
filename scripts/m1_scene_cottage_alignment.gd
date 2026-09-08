extends "res://scripts/m1_scene_cottage_style.gd"

const WallAlignment = preload("res://scripts/wall_detail_alignment.gd")

var _alignment_tangent := false
var _alignment_height := false
var _alignment_tangent_source := ""
var _alignment_height_source := ""
var _alignment_guide: Label

func _ready() -> void:
	super._ready()
	_alignment_guide = Label.new()
	_alignment_guide.name = "CottageAlignmentGuide"
	_alignment_guide.add_theme_font_size_override("font_size", 18)
	_alignment_guide.add_theme_color_override("font_color", Color("#aee3b6"))
	_alignment_guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alignment_guide.visible = false
	hud.add_child(_alignment_guide)

func _read_detail_move(delta: float) -> void:
	super._read_detail_move(delta)
	if not detail_move_active or resize_locked:
		_clear_alignment()
		return
	var view: Dictionary = building_world.get_building(selected_building_id)
	var aligned: Dictionary = WallAlignment.align(view, selected_detail_id, detail_move_surface_id, detail_move_position, precision_mode)
	var aligned_position = aligned.get("position", detail_move_position)
	if aligned_position is Vector3:
		detail_move_position = aligned_position
	_alignment_tangent = bool(aligned.get("tangent", false))
	_alignment_height = bool(aligned.get("height", false))
	_alignment_tangent_source = str(aligned.get("tangent_source", ""))
	_alignment_height_source = str(aligned.get("height_source", ""))
	_update_alignment_hud()
	_update_presentation()

func _cancel_detail_move() -> void:
	super._cancel_detail_move()
	_clear_alignment()

func _commit_detail_move() -> bool:
	var ok := super._commit_detail_move()
	_clear_alignment()
	return ok

func _cycle_attachment_surface(direction: int) -> void:
	super._cycle_attachment_surface(direction)
	_clear_alignment()

func _update_alignment_hud() -> void:
	if not _alignment_guide:
		return
	var labels: Array[String] = []
	if _alignment_tangent:
		labels.append("centred with %s" % _alignment_tangent_source)
	if _alignment_height:
		labels.append("height matched to %s" % _alignment_height_source)
	_alignment_guide.visible = not labels.is_empty()
	if _alignment_guide.visible:
		_alignment_guide.text = "ALIGN  " + "  •  ".join(labels)
		_alignment_guide.position = Vector2(32, get_viewport().get_visible_rect().size.y - 118)

func _clear_alignment() -> void:
	_alignment_tangent = false
	_alignment_height = false
	_alignment_tangent_source = ""
	_alignment_height_source = ""
	if _alignment_guide:
		_alignment_guide.visible = false
