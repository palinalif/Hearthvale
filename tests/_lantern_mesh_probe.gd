extends SceneTree
func _initialize() -> void:
	var mesh := load("res://assets/models/magicavoxel/hearthvale_prop_path_lantern.res") as ArrayMesh
	if mesh == null:
		print("LOAD FAILED")
		quit(1)
		return
	var aabb := mesh.get_aabb()
	print("aabb=", aabb)
	print("surfaces=", mesh.get_surface_count())
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i) as StandardMaterial3D
		print(i, " name=", m.resource_name, " albedo=", m.albedo_color, " emission=", m.emission_enabled, " energy=", m.emission_energy_multiplier)
	quit(0)
