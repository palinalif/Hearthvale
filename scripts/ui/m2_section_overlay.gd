## Read-only overlay for one section edit. The scene owns selection, validity
## and the final transaction; this node only paints them.
class_name M2SectionOverlay
extends Control

const COLORS := {
	"left": Color(1, 0.85, 0.35, 0.9),
	"front": Color(0.35, 0.9, 1, 0.9),
	"right": Color(0.85, 0.35, 1, 0.9),
	"back": Color(0.9, 0.55, 0.2, 0.9),
}
# Non-color cues: the ghost is a dashed outline of the original section, the
# selected handle grows into a boxed cross, and a thin connector line joins the
# pointer to that handle, so edge identity and pointer state are readable
# without relying on colour alone.
var lines: Array = []
var points: Array = []
var ghost: Array = []
var selected := "none"
var valid := true
var pointer := Vector2(-9999, -9999)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func update_lines(new_lines: Array, new_points: Array = [], new_selected := "none", new_valid := true) -> void:
	update_view(new_lines, new_points, new_selected, new_valid, [], Vector2(-9999, -9999))


func update_view(new_lines: Array, new_points: Array, new_selected: String, new_valid: bool, new_ghost: Array, new_pointer: Vector2) -> void:
	lines = new_lines
	points = new_points
	ghost = new_ghost
	selected = new_selected
	valid = new_valid
	pointer = new_pointer
	queue_redraw()


func _draw() -> void:
	# The dashed ghost of the original section is drawn first so the live
	# proposal always reads as the primary shape. CanvasItem only offers solid
	# draw_line, so the dash pattern is emitted as short segments here.
	for line in ghost:
		var a: Vector2 = line[0]
		var b: Vector2 = line[1]
		var direction := b - a
		var length := direction.length()
		if length < 4.0:
			draw_line(a, b, Color(1, 1, 1, 0.38), 1, true)
			continue
		var step := direction / length
		var t := 0.0
		while t < length:
			var end := minf(t + 6.0, length)
			draw_line(a + step * t, a + step * end, Color(1, 1, 1, 0.38), 1, true)
			t = end + 5.0
	for line in lines:
		var a: Vector2 = line[0]
		var b: Vector2 = line[1]
		draw_line(a, b, Color(0.9, 0.95, 1, 0.9), 2 if valid else 1, valid)
	for point in points:
		var p: Vector2 = point["position"]
		var is_selected := str(point.get("edge", "none")) == selected
		var box := Rect2(p - Vector2(8, 8), Vector2(16, 16))
		draw_rect(box, Color(1, 1, 1, 0.25 if not is_selected else 0.5), true)
		draw_rect(box, COLORS.get(str(point.get("edge", "")), Color.WHITE), false, 2 if is_selected else 1)
		# A cross on the selected handle doubles its size and adds a shape cue.
		if is_selected:
			draw_line(p + Vector2(-5, 0), p + Vector2(5, 0), Color(1, 1, 1, 0.95), 2)
			draw_line(p + Vector2(0, -5), p + Vector2(0, 5), Color(1, 1, 1, 0.95), 2)
	if pointer.x >= 0 and selected != "none":
		for point in points:
			if str(point.get("edge", "none")) != selected: continue
			var p: Vector2 = point["position"]
			if p.distance_to(pointer) > 24: draw_line(pointer, p, Color(1, 1, 1, 0.5), 1, true)
			break
