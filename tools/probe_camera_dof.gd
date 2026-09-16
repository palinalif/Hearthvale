extends SceneTree

# Confirm the real DOF attribute subclass in THIS build.
#   * does CameraAttributesPractical / CameraAttributesPhysical exist?
#   * full property list of CameraAttributesPractical (the DOF one)
#   * can a Camera3D accept an attributes value? (set + read back)
# Tokens: SUBS <cls>=<bool>, PRACT <prop>, SETATTR <ok>/<err>

func _init() -> void:
	for sub in ["CameraAttributesPractical", "CameraAttributesPhysical"]:
		print("SUBS " + sub + "=" + str(ClassDB.class_exists(sub)))
	print("SUBS_DONE")
	if ClassDB.class_exists("CameraAttributesPractical"):
		var pract = ClassDB.instantiate("CameraAttributesPractical")
		print("PRACT_TYPE " + str(pract.get_class()))
		for entry in pract.get_property_list():
			print("PRACT " + String(entry["name"]))
		print("PRACT_DONE")
		# Try attaching to a Camera3D via the `attributes` property.
		var cam := Camera3D.new()
		var before = cam.get("attributes")
		print("SETATTR_BEFORE " + str(before))
		cam.set("attributes", pract)
		var after = cam.get("attributes")
		print("SETATTR_AFTER type=" + str(after.get_class() if after else "null") + " ok=" + str(after == pract))
	print("SETATTR_DONE")
	quit(0)
