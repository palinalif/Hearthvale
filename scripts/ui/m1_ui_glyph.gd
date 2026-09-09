extends Control
## Small, resolution-independent silhouettes; their adjacent labels carry meaning.
var symbol := "raise":
	set(value):
		if symbol == value: return
		symbol = value
		queue_redraw()

func _init() -> void:
	custom_minimum_size = Vector2(38, 38)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var ink := Color("#edc27c")
	var soft := Color("#92b68c")
	match symbol:
		"foliage", "tree", "clear_planting":
			draw_line(Vector2(19, 30), Vector2(19, 15), ink, 2.5, true)
			draw_colored_polygon(PackedVector2Array([Vector2(7, 23), Vector2(19, 6), Vector2(31, 23)]), soft)
			if symbol == "foliage": draw_circle(Vector2(10, 24), 5, soft)
			if symbol == "clear_planting": draw_line(Vector2(7, 31), Vector2(31, 7), ink, 3, true)
		"cottage":
			draw_rect(Rect2(10, 17, 19, 15), soft)
			draw_polyline(PackedVector2Array([Vector2(5, 18), Vector2(19, 6), Vector2(33, 18)]), ink, 3, true)
			draw_rect(Rect2(17, 23, 5, 9), Color("#253b32"))
		"smooth":
			draw_polyline(PackedVector2Array([Vector2(5, 25), Vector2(11, 20), Vector2(18, 18), Vector2(25, 20), Vector2(33, 25)]), ink, 3, true)
			draw_line(Vector2(8, 30), Vector2(30, 30), soft, 2, true)
		"level", "slope":
			draw_line(Vector2(6, 27), Vector2(32, 14 if symbol == "slope" else 27), ink, 3, true)
			draw_line(Vector2(6, 33), Vector2(32, 33), soft, 2, true)
		_:
			var down := symbol == "dig"
			var tip := 26.0 if down else 8.0
			var shoulder := 19.0 if down else 15.0
			draw_line(Vector2(19, 10 if down else 25), Vector2(19, tip), ink, 3, true)
			draw_polyline(PackedVector2Array([Vector2(12, shoulder), Vector2(19, tip), Vector2(26, shoulder)]), ink, 3, true)
			draw_polyline(PackedVector2Array([Vector2(5, 32), Vector2(12, 29), Vector2(26, 29), Vector2(33, 32)]), soft, 2, true)
