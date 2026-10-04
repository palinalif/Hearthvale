extends SceneTree

# Print the world-space AABB of every baked prop mesh so bake scale can be
# derived from the validated runtime contract instead of guessed.
func _init() -> void:
	var dir := DirAccess.open("res://assets/models/magicavoxel")
	var names: Array[String] = []
	for n in dir.get_files():
		if n.ends_with(".res"):
			names.append(n.get_basename())
	names.sort()
	for n in names:
		var m := load("res://assets/models/magicavoxel/%s.res" % n) as Mesh
		if m == null:
			print("MISSING\t%s" % n)
			continue
		var a := m.get_aabb()
		print("EXTENT\t%s\t%.4f\t%.4f\t%.4f" % [n, a.size.x, a.size.y, a.size.z])
	quit()
