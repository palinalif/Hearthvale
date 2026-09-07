extends SceneTree
## Actual Mobile renderer parity between bulk uploads and the former setters.
## Synthetic geometry isolation, not the integrated M1 art or a Thor playtest.
const Visual = preload("res://scripts/terrain_edit_preview.gd")
const Buffers = preload("res://scripts/terrain_preview_buffers.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	if RenderingServer.get_current_rendering_method() != "mobile" or DisplayServer.get_name() == "headless":
		print("PREVIEW_RENDER_UNAVAILABLE: actual Mobile renderer required")
		quit(2)
		return
	print("PREVIEW_RENDER_START " + JSON.stringify({"method": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(), "adapter": RenderingServer.get_video_adapter_name()}))
	var prefix := ".tools/terrain-ux/preview-render"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): prefix = argument.trim_prefix("--output=")
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(3, 5, 6)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.0
	var visual := Visual.new()
	world.add_child(visual)
	var changes: Array[Dictionary] = []
	var rim: Array[Vector3] = []
	for x in range(-12, 13):
		for z in range(-12, 13):
			if x * x + z * z > 144: continue
			changes.append({"cell": Vector3i(x, 0, z), "before": 2 if x < 0 else 0, "after": 0 if x < 0 else 2, "weight": maxf(0.01, 1.0 - Vector2(x, z).length() / 12.0)})
			if x * x + z * z > 110: rim.append(Vector3(x, 0.0, z) * 0.125)
	var removed := 0
	for change in changes:
		if int(change.after) == 0: removed += 1
	var plan := {"valid": true, "changes": changes, "add_count": changes.size() - removed, "remove_count": removed, "rim": rim, "normal": Vector3.UP, "cell_size": 0.125}
	plan["packed"] = Buffers.pack(plan)
	visual.visible = false
	for _i in 8: await RenderingServer.frame_post_draw
	var empty: PackedByteArray = root.get_texture().get_image().get_data()
	visual.show_plan(plan)
	for _i in 8: await RenderingServer.frame_post_draw
	var bulk := root.get_texture().get_image()
	check(bulk.save_png(prefix + "-bulk.png") == OK, "bulk capture saved")
	check(bulk.get_data() != empty, "geometry really renders")
	var face := Basis(Quaternion(Vector3.BACK, Vector3.UP)).scaled(Vector3.ONE * 0.125)
	var cube := Basis.IDENTITY.scaled(Vector3.ONE * 0.125 * 1.015)
	for i in rim.size():
		visual.reach.multimesh.set_instance_transform(i, Transform3D(face, rim[i] + Vector3.UP * 0.125 * 0.02))
		visual.reach.multimesh.set_instance_color(i, Color.WHITE)
	var offsets := [0, 0]
	for change in changes:
		var layer := 0 if int(change.after) == 0 else 1
		var mesh: MultiMesh = visual.removals.multimesh if layer == 0 else visual.additions.multimesh
		var position := (Vector3(change.cell) + Vector3.ONE * 0.5) * 0.125
		if layer == 0: position += Vector3.UP * 0.125 * 0.515
		mesh.set_instance_transform(offsets[layer], Transform3D(face if layer == 0 else cube, position))
		mesh.set_instance_color(offsets[layer], Color(1.0, 1.0, 1.0, lerpf(0.4, 1.0, sqrt(float(change.weight)))))
		offsets[layer] += 1
	for _i in 8: await RenderingServer.frame_post_draw
	var setters := root.get_texture().get_image()
	check(setters.save_png(prefix + "-setters.png") == OK, "setter capture saved")
	check(bulk.get_data() == setters.get_data(), "bulk and per-instance setters render identical pixels")
	print("sculpt_preview_render_test checks=%d failures=%d" % [checks, failures])
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)
