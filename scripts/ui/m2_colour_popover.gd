extends PanelContainer

## Compact object-anchored palette. The caller owns preview/commit/history.
const BACKGROUND := Color("#34453e")
var row: HBoxContainer
var pointer := PackedVector2Array()

func _init() -> void:
	visible = false
	z_index = 20
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := StyleBoxFlat.new()
	background.bg_color = BACKGROUND
	background.set_corner_radius_all(10)
	background.set_content_margin_all(10)
	add_theme_stylebox_override("panel", background)
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

func add_choice(button: Button, colour: Color, label: String) -> void:
	button.reparent(row)
	button.text = ""
	button.tooltip_text = ""
	button.accessibility_name = label
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(48, 48)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	button.icon = ImageTexture.create_from_image(image)
	var normal := StyleBoxFlat.new()
	normal.bg_color = BACKGROUND
	normal.set_content_margin_all(6)
	normal.set_corner_radius_all(6)
	button.add_theme_stylebox_override("normal", normal)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = Color("#fff2d4")
	focus.set_border_width_all(3)
	button.add_theme_stylebox_override("focus", focus)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = BACKGROUND.lightened(0.16)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)

func place_near(target: Rect2, available: Rect2) -> void:
	reset_size()
	var centre := target.get_center()
	var candidates: Array[Vector2] = [
		Vector2(centre.x - size.x * 0.5, target.position.y - size.y - 18),
		Vector2(centre.x - size.x * 0.5, target.end.y + 18),
		Vector2(target.end.x + 18, centre.y - size.y * 0.5),
		Vector2(target.position.x - size.x - 18, centre.y - size.y * 0.5),
	]
	var best := candidates[0]
	var best_score := INF
	for candidate in candidates:
		var clamped := candidate.clamp(available.position, (available.end - size).max(available.position))
		var overlap := Rect2(clamped, size).intersection(target.grow(8))
		var score := overlap.get_area() * 1000 + clamped.distance_squared_to(candidate)
		if score < best_score:
			best_score = score
			best = clamped
	position = best
	var tip := centre - position
	var base := tip.clamp(Vector2(12, 12), (size - Vector2(12, 12)).max(Vector2(12, 12)))
	if tip.y > size.y:
		base.y = size.y
		pointer = PackedVector2Array([base + Vector2(-7, 0), base + Vector2(7, 0), Vector2(base.x, minf(tip.y, size.y + 14))])
	elif tip.y < 0:
		base.y = 0
		pointer = PackedVector2Array([base + Vector2(-7, 0), base + Vector2(7, 0), Vector2(base.x, maxf(tip.y, -14))])
	else:
		base.x = 0 if tip.x < 0 else size.x
		pointer = PackedVector2Array([base + Vector2(0, -7), base + Vector2(0, 7), base + Vector2(-14 if tip.x < 0 else 14, 0)])
	queue_redraw()

func _draw() -> void:
	if pointer.size() == 3: draw_colored_polygon(pointer, BACKGROUND)
