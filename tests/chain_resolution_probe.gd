extends SceneTree
## CI probe: verifies the deep scene-chain (m2_scene_water -> ... -> m1_scene)
## actually resolves after a headless import. Godot's headless import resolves
## the ~56-deep path-based `extends` chain racy, so a single import pass can
## leave the class cache half-built and the later export fails with
## "Could not resolve class". This probe forces a real load+instantiate; the
## APK build re-imports and re-probes until it passes.

func _init() -> void:
	var res: GDScript = load("res://scripts/m2_scene_water.gd")
	if res == null:
		push_error("chain probe: load failed")
		quit(1)
		return
	var inst = res.new()
	if inst == null:
		push_error("chain probe: instantiate failed")
		quit(1)
		return
	print("CHAIN_RESOLVED")
	quit(0)
