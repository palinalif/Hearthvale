extends SceneTree
## In-scene drift-localisation probe: replicates the failing
## "unchanged recipe renders identically" capture, then diffs the two
## in-memory buffers and reports WHERE (screen region) the bytes moved.
var scene: Node
var a: Image
var b: Image

func _capture() -> Image:
	for i in 4: await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _region(x: int, y: int, w: int, h: int) -> String:
	# Coarse 8x8 grid so we can name the region in words.
	var cols := 8
	var row := int(y / (720.0 / 8.0))
	var col := int(x / (1280.0 / float(cols)))
	var names := [
		"TOP-LEFT", "TOP-CENTRE-L", "TOP-CENTRE", "TOP-RIGHT",
		"UPPER-MID-L", "UPPER-MID", "UPPER-MID-R", "UPPER-R",
		"MID-L", "MID-CENTRE", "MID-R", "MID-R2",
		"LOWER-MID-L", "LOWER-MID", "LOWER-MID-R", "LOWER-R",
		"BOTTOM-L", "BOTTOM-C", "BOTTOM-C2", "BOTTOM-R",
	]
	var idx := row * 8 + col
	if idx < names.size(): return names[idx]
	return "row%d-col%d" % [row, col]

func ready() -> void:
	root.size = Vector2i(1280, 720)
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://drift-probe-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 120000
	while (not scene._player_restored or not scene.backend or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not scene._player_restored:
		print("DRIFT_PROBE scene-not-ready")
		quit(2)
		return
	scene.set_process(false)
	scene._set_view_context("building")
	scene._update_presentation()
	scene.hud.visible = false
	scene.camera_yaw = PI * 1.20
	scene.camera_pitch = 0.40
	scene.camera_distance = 16.0
	scene._update_camera()
	# Is wind actually off in this state?
	var wind_on := false
	for v : Node in scene.cottage_visuals.values():
		pass
	if "garden_visual" in scene:
		var g = scene.garden_visual
		if g != null and "wind_enabled" in g:
			wind_on = bool(g.wind_enabled)
	print("DRIFT_PROBE wind_enabled=%s" % str(wind_on))
	a = await _capture()
	await create_timer(2.0).timeout
	b = await _capture()
	var da := a.get_data()
	var db := b.get_data()
	var w := a.get_width()
	var h := a.get_height()
	if da.size() != db.size():
		print("DRIFT_PROBE size-mismatch a=%d b=%d" % [da.size(), db.size()])
		quit(1)
	var diff_regions := {}
	var total := 0
	for off in range(0, da.size(), 4):
		if da[off] != db[off] or da[off+1] != db[off+1] or da[off+2] != db[off+2] or da[off+3] != db[off+3]:
			total += 1
			var px := off / 4
			var x := px % w
			var y := px / w
			var r := _region(x, y, 1, 1)
			diff_regions[r] = int(diff_regions.get(r, 0)) + 1
		if off > 1280 * 720 * 4: break
	print("DRIFT_PROBE total_diff_pixels=%d" % total)
	if diff_regions.is_empty():
		print("DRIFT_PROBE NO-DIFF-AT-ALL")
	else:
		var sorted: Array = diff_regions.keys().duplicate()
		sorted.sort_custom(func(x, y): return int(diff_regions[x]) > int(diff_regions[y]))
		for r in sorted:
			print("DRIFT_PROBE region=%s pixels=%d" % [r, diff_regions[r]])
	quit(0)
