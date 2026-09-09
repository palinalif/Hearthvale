extends "res://tests/m1_house_actions_render_test.gd"
## Keep the full integrated Mobile suite and guard the observed canvas overlap:
## an A texture could exist with correct bounds while panel ink covered it.
func _capture(name: String) -> Image:
	var result: Image = await super._capture(name)
	if scene._prompt_bar.is_visible_in_tree():
		for group in scene._prompt_row.get_children():
			_check_glyph_layout(group, scene._prompt_bar, name)
	if scene._mode_pill.is_visible_in_tree():
		_check_glyph_layout(scene._mode_label.get_parent(), scene._mode_pill, name + " mode")
	if scene._prompt_row.get_child_count() == 0: return result
	var key: Control = scene._prompt_row.get_child(0).get_child(0)
	if key.get_meta("controller_key", "") != "A" or not key.is_visible_in_tree(): return result
	var glyph: TextureRect = key.get_child(0)
	var bounds := Rect2i(glyph.get_global_rect())
	var ink_pixels := 0
	var ink_min := bounds.end
	var ink_max := bounds.position
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var pixel := result.get_pixel(x, y)
			if pixel.r > 0.65 and pixel.g > 0.65 and pixel.b > 0.55:
				ink_pixels += 1
				ink_min = ink_min.min(Vector2i(x, y))
				ink_max = ink_max.max(Vector2i(x, y))
	check(ink_pixels > 100, "cream A glyph remains visible above panel surfaces: " + name)
	check(ink_max.x - ink_min.x >= 20 and ink_max.y - ink_min.y >= 20, "A glyph has a full circular footprint, not a sliver: " + name)
	return result

func _check_glyph_layout(group: Control, surface: Control, name: String) -> void:
	var slot: Control = group.get_child(0)
	var surface_rect := surface.get_global_rect()
	var slot_rect := slot.get_global_rect()
	check(surface_rect.encloses(slot_rect) and group.get_global_rect().encloses(slot_rect), "glyph slot stays inside its prompt and surface: " + name)
	for glyph in slot.get_children():
		var glyph_rect: Rect2 = glyph.get_global_rect()
		check(glyph_rect.size == Vector2(32, 32) and slot_rect.encloses(glyph_rect), "full glyph rect stays inside its reserved slot: " + name)
		if group.get_child_count() > 1:
			var label: Control = group.get_child(1)
			check(glyph_rect.end.x + 8 <= label.get_global_rect().position.x, "glyph has clear space before adjacent label: " + name)
	if name.ends_with("mode") or name == "08-terrain-settings":
		print("GLYPH_LAYOUT ", name, " slot=", slot_rect, " surface=", surface_rect, " label=", group.get_child(1).get_global_rect() if group.get_child_count() > 1 else Rect2())
