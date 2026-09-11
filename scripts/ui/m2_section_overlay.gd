extends Control

var segments: Array = []
var handles: Array = []
var active_edge := ""
var valid := true

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func update_lines(lines: Array, points: Array, edge: String, allowed: bool) -> void:
	segments = lines
	handles = points
	active_edge = edge
	valid = allowed
	queue_redraw()

func _draw() -> void:
	var colour := Color("#ffcf73") if valid else Color("#f77d71")
	for line in segments: draw_line(line[0], line[1], colour, 2.0, true)
	for handle in handles:
		var selected := str(handle["edge"]) == active_edge
		var at: Vector2 = handle["position"]
		draw_circle(at, 10.0 if selected else 6.0, Color("#26362f"))
		draw_arc(at, 9.0 if selected else 5.0, 0, TAU, 24, colour, 3.0, true)
		if selected:
			draw_line(at - Vector2(4, 0), at + Vector2(4, 0), colour, 2)
			draw_line(at - Vector2(0, 4), at + Vector2(0, 4), colour, 2)
