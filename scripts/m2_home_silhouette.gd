extends Control
class_name M2HomeSilhouette

var shape_id := "classic_gable"

func _init(value := "classic_gable") -> void:
	shape_id = value
	custom_minimum_size = Vector2(88, 48)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var fill := Color("#d8c9a5")
	var edge := Color("#405345")
	var points := PackedVector2Array()
	match shape_id:
		"longhouse": points = PackedVector2Array([Vector2(2, 25), Vector2(15, 13), Vector2(73, 13), Vector2(86, 25), Vector2(82, 25), Vector2(82, 41), Vector2(6, 41), Vector2(6, 25)])
		"tall_gable": points = PackedVector2Array([Vector2(23, 22), Vector2(44, 2), Vector2(65, 22), Vector2(62, 22), Vector2(62, 44), Vector2(26, 44), Vector2(26, 22)])
		_: points = PackedVector2Array([Vector2(12, 24), Vector2(30, 7), Vector2(58, 7), Vector2(76, 24), Vector2(70, 24), Vector2(70, 42), Vector2(18, 42), Vector2(18, 24)])
	draw_colored_polygon(points, fill)
	draw_polyline(points + PackedVector2Array([points[0]]), edge, 2.0, true)
	draw_rect(Rect2(38, 28, 12, 14), edge, false, 2.0)
