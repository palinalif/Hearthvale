extends SceneTree
func _initialize() -> void:
	var a := CameraAttributesPractical.new()
	var names := []
	for p in ["dof_blur_near_enabled","dof_blur_near_distance","dof_blur_near_transition","dof_blur_far_enabled","dof_blur_far_distance","dof_blur_far_transition","dof_blur_amount","focus_distance","focus_tracking_enabled"]:
		names.append(p + "=" + str(a.get(p)))
	print("ATTRS:", " | ".join(names))
	var c := Camera3D.new()
	print("camera.attributes type:", c.attributes.get_class() if c.attributes else "null")
	print("APIOK")
	quit(0)
