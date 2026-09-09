extends RefCounted
## Licensed controller art is presentation only; action routing stays in the scene.
const ROOT := "res://assets/ui/kenney_input_prompts/xbox_series/"
const FILES := {"A": "button_a", "B": "button_b", "X": "button_x", "Y": "button_y", "LS": "stick_l", "RS": "stick_r", "L3": "stick_l_press", "R3": "stick_r_press", "LB": "lb", "RB": "rb", "LT": "lt", "RT": "rt", "D-PAD": "dpad", "UP": "dpad_up", "▲": "dpad_up", "▼": "dpad_down", "UP/DOWN": "dpad_vertical", "LEFT/RIGHT": "dpad_horizontal", "◀▶": "dpad_horizontal"}
const SHORT := {"Navigate": "", "Row": "", "Move / Resize": "Edit", "Done / choose tool": "Choose", "Adjust (hold repeats)": "Adjust", "Drag handle": "Drag", "Grab handle": "Grab", "Finish resizing": "Done", "Finish editing": "Done", "Point at handles": "Point", "Free move": "Move", "Choose detail": "Choose", "Cottage options": "Options", "Detail options": "Options"}
static var _ink_material: ShaderMaterial
static var keyboard_mouse_mode := false

const PC_KEYS := {
	"A": "LMB / Enter", "B": "Esc", "X": "X", "Y": "E",
	"LS": "WASD", "RS": "RMB drag", "L3": "F", "R3": "G",
	"LB": "Z", "RB": "C", "LT": "Wheel", "RT": "Wheel",
	"LT/RT": "Wheel", "RT/LT": "Wheel", "D-PAD": "Arrow keys",
	"UP": "E", "▲": "E", "▼": "Q", "▲▼": "↑ / ↓",
	"UP/DOWN": "↑ / ↓", "LEFT/RIGHT": "← / →", "◀▶": "[ / ]"
}

static func ink_material() -> ShaderMaterial:
	if _ink_material: return _ink_material
	var shader := Shader.new()
	# Kenney directional D-pads use red to mark the active direction. Translate
	# that source mark into our muted amber; all other ink uses warm cream.
	shader.code = "shader_type canvas_item;\nvoid fragment() { vec4 t = texture(TEXTURE, UV); float accent = step(t.g * 1.4 + 0.01, t.r); COLOR = vec4(mix(vec3(0.953, 0.929, 0.855), vec3(0.82, 0.71, 0.52), accent), t.a); }"
	_ink_material = ShaderMaterial.new()
	_ink_material.shader = shader
	return _ink_material

static func set_keyboard_mouse_mode(enabled: bool) -> void:
	keyboard_mouse_mode = enabled

static func _pc_key(key: String, action: String) -> String:
	if action in ["Terrain", "Building"]: return "Tab"
	if action == "Roof -": return "Z"
	if action == "Roof +": return "C"
	return str(PC_KEYS.get(key, key))

static func control(key: String, action: String = "") -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 0)
	if keyboard_mouse_mode:
		var cap := Label.new()
		cap.text = _pc_key(key, action)
		cap.add_theme_font_size_override("font_size", 14)
		cap.add_theme_color_override("font_color", Color("#fff4c7"))
		cap.add_theme_color_override("font_outline_color", Color("#17231c"))
		cap.add_theme_constant_override("outline_size", 4)
		cap.custom_minimum_size = Vector2(28, 28)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(cap)
		row.set_meta("controller_key", key)
		return row
	var keys: Array = ["LT", "RT"] if key in ["LT/RT", "RT/LT"] else [key]
	# Reserve the whole slot before the nested containers perform their first
	# layout. Neither a label nor a sibling may consume the glyph's ink area.
	row.custom_minimum_size = Vector2(32 * keys.size(), 32)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for part in keys:
		if not FILES.has(part): continue
		var glyph := TextureRect.new()
		# Keep glyph ink above panel surfaces in the Mobile canvas pass.
		glyph.z_index = 1
		glyph.texture = load(ROOT + "xbox_" + str(FILES[part]) + ".svg")
		glyph.material = ink_material()
		glyph.custom_minimum_size = Vector2(32, 32)
		glyph.size = Vector2(32, 32)
		glyph.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(glyph)
	row.set_meta("controller_key", key)
	return row

static func prompt(key: String, action: String) -> HBoxContainer:
	var group := HBoxContainer.new()
	group.add_theme_constant_override("separation", 8)
	group.add_child(control(key, action))
	if str(SHORT.get(action, action)).is_empty(): return group
	var label := Label.new()
	label.text = str(SHORT.get(action, action))
	label.add_theme_font_size_override("font_size", 16)
	group.add_child(label)
	return group
