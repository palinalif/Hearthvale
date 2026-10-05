extends SceneTree
func _init() -> void:
	var e := Environment.new()
	for i in [0, 1, 2]:
		e.glow_blend_mode = i
		print("set ", i, " -> get ", e.glow_blend_mode)
	var pi: Variant = e.get_property_list()
	for p in pi:
		if p.name == "glow_blend_mode":
			print("usage hint: ", p.usage, " enum: ", p.class_index)
			print("enumeration: ", p.enumeration)
	quit()
