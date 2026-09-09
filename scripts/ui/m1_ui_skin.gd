extends RefCounted
## Presentation tokens only. The HUD owns this theme; no project-wide override.
const INK := Color("#f3edda")
const MUTED := Color("#b9c5b3")
const AMBER := Color("#edc27c")
const MOSS := Color("#253b32")

static func panel(fill: Color, edge: Color, radius: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style

static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", INK)
	var surface := panel(Color("#20332ff5"), Color("#617465"))
	surface.shadow_color = Color(0.04, 0.08, 0.06, 0.25)
	surface.shadow_size = 5
	surface.shadow_offset = Vector2(0, 3)
	theme.set_stylebox("panel", "PanelContainer", surface)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var fill := MOSS
		if state == "hover": fill = Color("#3e5542")
		if state == "pressed": fill = Color("#52664b")
		if state == "disabled": fill = Color("#26372f")
		var button := panel(fill, Color("#50644e"), 7)
		button.content_margin_left = 12
		button.content_margin_right = 12
		button.content_margin_top = 6
		button.content_margin_bottom = 6
		theme.set_stylebox(state, "Button", button)
	var focus := panel(Color(0, 0, 0, 0), AMBER, 7)
	focus.set_border_width_all(3)
	theme.set_stylebox("focus", "Button", focus)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(state, "Button", INK)
	theme.set_color("font_disabled_color", "Button", Color("#849182"))
	theme.set_constant("outline_size", "Button", 0)
	return theme

static func badge(key: Label) -> void:
	key.add_theme_stylebox_override("normal", panel(Color("#405345"), Color("#83917a"), 5))
	key.add_theme_color_override("font_color", INK)
	key.add_theme_font_size_override("font_size", 14)
	key.custom_minimum_size = Vector2(29, 28)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var box := key.get_theme_stylebox("normal") as StyleBoxFlat
	box.content_margin_left = 7
	box.content_margin_right = 7
