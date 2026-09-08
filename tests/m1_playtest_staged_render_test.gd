extends "res://tests/m1_playtest_repair_render_test.gd"
## CI's CPU-only Mobile adapter renders initial terrain frames so slowly that
## native main-thread mesh uploads miss their unchanged 45-second deadline.
## Only defer 3D drawing during bootstrap; native terrain generation, meshing,
## readiness checks and ALL inherited render/pixel assertions remain real.
## This is a capture-harness optimization, NOT a Thor performance result.

func _run() -> void:
	root.disable_3d = true
	print("COTTAGE_STAGED_BOOTSTRAP: native processing active; 3D draw deferred")
	await super._run()

func _capture(name: String) -> Image:
	root.disable_3d = false
	check(scene.backend.is_ready() and bool(scene.backend.get("_initial_mesh_ready")), "native terrain fully ready before capture")
	check(not root.disable_3d and RenderingServer.render_loop_enabled, "actual rendering enabled for " + name)
	return await super._capture(name)

func _finish() -> void:
	root.disable_3d = false
	super._finish()
