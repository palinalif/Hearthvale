extends Control
## Geometry-drawn targets: no icon font fallback and no input-owning Controls.
var handles: Array = []
var edges: Array = []
var hovered := ""
var grabbed := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func set_layout(next_handles: Array, next_edges: Array, next_hovered: String, next_grabbed: String) -> void:
	if handles == next_handles and edges == next_edges and hovered == next_hovered and grabbed == next_grabbed: return
	handles = next_handles
	edges = next_edges
	hovered = next_hovered
	grabbed = next_grabbed
	queue_redraw()

func _draw() -> void:
	for edge in edges:
		draw_line(edge[0], edge[1], Color(1.0, 0.82, 0.43, 0.40), 1.5, true)
	for handle in handles:
		var point: Vector2 = handle["screen"]
		var selected: bool = str(handle["id"]) in [hovered, grabbed]
		var colour := Color("#fff4c7") if selected else Color("#ffd069")
		var radius := 13.0 if selected else 10.0
		draw_line(handle["anchor_screen"], point, colour, 2.0, true)
		var polygon := PackedVector2Array([point + Vector2(0, -radius), point + Vector2(radius, 0), point + Vector2(0, radius), point + Vector2(-radius, 0)])
		draw_colored_polygon(polygon, Color("#24392e"))
		polygon.append(polygon[0])
		draw_polyline(polygon, colour, 2.5 if selected else 1.5, true)
		var direction: Vector2 = handle["arrow"]
		if direction.length_squared() < 0.01: direction = Vector2.UP
		direction = direction.normalized() * 6.0
		draw_line(point - direction, point + direction, colour, 2.0, true)
		var tip := point + direction
		var wing := direction.normalized().orthogonal() * 3.0
		draw_line(tip, point + wing, colour, 2.0, true)
		draw_line(tip, point - wing, colour, 2.0, true)
