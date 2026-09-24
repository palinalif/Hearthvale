extends SceneTree
## Xvfb + Mobile-renderer screenshot capture of the starter-valley waterfall.
## See docs/render-screenshots.md (Method A).
##
##   timeout 400 xvfb-run -a godot --max-fps 60 --renderer mobile --path . \
##       --script tools/waterfall_shot.gd -- --cam x,y,z --look x,y,z --out <png>
##
## Boots the real M2SceneStarterValley into a temp save (so the reservoir/river
## seed), aims a free camera, and saves a PNG.
##
## Fail-closed readiness: the single capture happens only after the terrain
## backend is ready, the ENTIRE native valley is meshed (the full patch, not
## just the startup mesh box), and the reservoir, river and plunge-pool water
## surfaces are fully sampled and uploaded. Unrelated ponds need not finish.
## On any timeout the script prints a diagnostic, saves no PNG, and exits nonzero.

const PremadeRiver = preload("res://scripts/premade_river.gd")
const BACKEND_READY_TIMEOUT_MS := 180000
const AREA_MESH_TIMEOUT_MS := 240000
const WATER_DRAIN_TIMEOUT_MS := 900000

var scene: Node
var _water_ready_frames := 0

func _initialize() -> void:
	call_deferred("_run")

func _capture() -> Image:
	for i in 4:
		await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

## Bounded poll on process_frame. Returns false on timeout.
func _wait_until(cond: Callable, timeout_ms: int, stage: String) -> bool:
	var started := Time.get_ticks_msec()
	var deadline := started + timeout_ms
	var next_report := started + 30000
	print("SHOT_WAIT %s" % stage)
	while not cond.call():
		var now := Time.get_ticks_msec()
		if now >= deadline:
			return false
		if now >= next_report:
			print("SHOT_WAIT %s elapsed_ms=%d" % [stage, now - started])
			_print_diagnostics()
			next_report = now + 30000
		# Offline capture only: the game budgets one 6 ms resample pass
		# per frame, but software Mobile renders at ~1 fps. Do several
		# ordinary budgeted passes between frames; never change gameplay's
		# water budgets or bypass the readiness predicate.
		if stage == "waterfall_water":
			var wv: Node = scene.get("water_visual")
			if wv != null and wv.has_method("_drain"):
				wv.call("_drain", 8)
		await process_frame
	print("SHOT_READY %s elapsed_ms=%d" % [stage, Time.get_ticks_msec() - started])
	return true

func _backend() -> Node:
	return scene.get("backend") if scene else null

func _backend_ready() -> bool:
	var b: Node = _backend()
	return b != null and b.has_method("is_ready") and b.is_ready()

## The whole native valley: the full patch AABB in voxel cells, exactly the
## area the backend's own init waits for with is_area_editable. (The backend's
## is_ready() only covers the smaller startup mesh box, which is why this is
## checked separately before any capture.)
func _valley_meshed() -> bool:
	var b: Node = _backend()
	if b == null: return false
	var terrain: Node = b.get("terrain")
	if terrain == null or not terrain.has_method("is_area_meshed"): return false
	var patch: Vector3i = b.get("patch_size")
	return terrain.is_area_meshed(AABB(Vector3.ZERO, Vector3(patch)))

## Match authored starter regions, not insertion-order IDs (which differ on
## restored saves). All three are visible from the waterfall cameras.
func _target_water_ids() -> Array[int]:
	var ids: Array[int] = []
	if scene == null: return ids
	var state: Object = scene.get("landscape_state")
	if state == null: return ids
	var reservoir: Dictionary = PremadeRiver.reservoir_region()
	var pool: Dictionary = PremadeRiver.plunge_pool_region()
	var found := {"reservoir": -1, "river": -1, "pool": -1}
	for region: Dictionary in state.get("water"):
		if PremadeRiver.matches_reservoir(region, reservoir):
			found["reservoir"] = int(region.get("id", -1))
		elif PremadeRiver.is_starter_river(region):
			found["river"] = int(region.get("id", -1))
		elif PremadeRiver.matches_pool(region, pool):
			found["pool"] = int(region.get("id", -1))
	if found["reservoir"] >= 0 and found["river"] >= 0 and found["pool"] >= 0:
		ids.assign([found["reservoir"], found["river"], found["pool"]])
	return ids

## A complete mesh is only safe after each of its source cells was sampled,
## including queued re-samples of cached cells. NAN is a valid cached sample.
func _water_local_ready() -> bool:
	var wv: Node = scene.get("water_visual") if scene else null
	if wv == null or wv.get("_rebuild_scheduled") == true: return false
	if not wv.has_method("_key") or wv.call("_key") != wv.get("_last_key"): return false
	var ids := _target_water_ids()
	if ids.size() != 3: return false
	var regions: Dictionary = wv.get("_region_by_id")
	var states: Dictionary = wv.get("_build_state")
	var nodes: Dictionary = wv.get("_region_nodes")
	var cache: Dictionary = wv.get("_cell_cache")
	var pending: Dictionary = wv.get("_pending_set")
	var dirty: Dictionary = wv.get("_dirty_regions")
	for id in ids:
		if not regions.has(id) or not states.has(id) or dirty.has(id) or not nodes.has(id): return false
		var state: Dictionary = states[id]
		var cells: Array = state.get("cells", [])
		if cells.is_empty() or int(state.get("index", -1)) != cells.size(): return false
		for cell: Vector2i in cells:
			if not cache.has(cell) or pending.has(cell): return false
	# Derivation may land directly in the plunge pool rather than the river:
	# the current starter fall is reservoir -> pool. Never assume a fixed pair.
	for fall: Dictionary in wv.active_waterfalls():
		if int(fall.get("upper_id", -1)) == ids[0] and int(fall.get("lower_id", -1)) in [ids[1], ids[2]]:
			return true
	return false

## Require several frames of stability after the scene's deferred carve/sync.
func _water_drained() -> bool:
	if _water_local_ready():
		_water_ready_frames += 1
	else:
		_water_ready_frames = 0
	return _water_ready_frames >= 3

func _print_diagnostics() -> void:
	var b: Node = _backend()
	print("DIAG backend=%s ready=%s" % [
		"null" if b == null else b.name,
		_backend_ready() if b != null else "n/a"])
	if b != null and b.has_method("stats"):
		var err: String = str(b.stats().get("error", ""))
		if err != "":
			print("DIAG backend_error=%s" % err)
	print("DIAG valley_meshed=%s" % _valley_meshed())
	var wv: Node = scene.get("water_visual") if scene else null
	if wv == null:
		print("DIAG water_visual=null")
	else:
		var pending: Array = wv.get("_pending_cells")
		var dirty: Dictionary = wv.get("_dirty_regions")
		var ids := _target_water_ids()
		print("DIAG water pending_cells=%d dirty_regions=%d rebuild_scheduled=%s target_ids=%s keys=%s" % [
			pending.size(), dirty.size(), wv.get("_rebuild_scheduled") == true,
			ids, wv.waterfall_keys()])
		var states: Dictionary = wv.get("_build_state")
		var cache: Dictionary = wv.get("_cell_cache")
		var queued: Dictionary = wv.get("_pending_set")
		for id in ids:
			var state: Dictionary = states.get(id, {})
			var cells: Array = state.get("cells", [])
			var missing := 0
			var stale := 0
			for cell: Vector2i in cells:
				if not cache.has(cell): missing += 1
				if queued.has(cell): stale += 1
			print("DIAG target id=%d built=%d/%d missing=%d pending=%d dirty=%s" % [
				id, int(state.get("index", 0)), cells.size(), missing, stale,
				dirty.has(id)])

func _fail(stage: String) -> void:
	print("SHOT_FAIL %s" % stage)
	_print_diagnostics()
	quit(1)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("CAPTURE_UNAVAILABLE headless")
		quit(2)
		return
	if RenderingServer.get_current_rendering_method() != "mobile":
		print("CAPTURE_UNAVAILABLE renderer=%s (Mobile required)" % RenderingServer.get_current_rendering_method())
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var ckpt := "/tmp/hv_wf_shot_ckpt"
	if DirAccess.dir_exists_absolute(ckpt):
		DirAccess.remove_absolute(ckpt)
	scene = load("res://scripts/m2_scene_starter_valley.gd").new()
	scene.checkpoint_root = ckpt
	root.add_child(scene)
	if not await _wait_until(_backend_ready, BACKEND_READY_TIMEOUT_MS, "backend"):
		_fail("backend_not_ready within %d ms" % BACKEND_READY_TIMEOUT_MS)
		return
	# The startup mesh box alone is not a valid shot: the full native valley
	# must be meshed first, bounded because the viewer streams it gradually.
	if not await _wait_until(_valley_meshed, AREA_MESH_TIMEOUT_MS, "valley_mesh"):
		_fail("valley_not_fully_meshed within %d ms" % AREA_MESH_TIMEOUT_MS)
		return
	# Wait for the three waterfall-area surfaces, not unrelated valley ponds.
	# The river is long and still needs a generous bounded build window.
	if not await _wait_until(_water_drained, WATER_DRAIN_TIMEOUT_MS, "waterfall_water"):
		_fail("waterfall_water_not_ready within %d ms" % WATER_DRAIN_TIMEOUT_MS)
		return
	var water_states: Dictionary = scene.water_visual.get("_build_state")
	for water_id in _target_water_ids():
		var water_state: Dictionary = water_states.get(water_id, {})
		print("SHOT_WATER id=%d cells=%d quads=%d" % [water_id, (water_state.get("cells", []) as Array).size(), (water_state.get("verts", PackedVector3Array()) as PackedVector3Array).size() / 4])
	var terrain_sampler: Callable = scene.call("_terrain_top_sampler")
	print("SHOT_POND_TOP center=%s lip=%s" % [terrain_sampler.call(Vector2(82.0, 145.0)), terrain_sampler.call(Vector2(82.0, 140.0))])
	var pond_cache: Dictionary = scene.water_visual.get("_cell_cache")
	for z in [140.0, 141.0, 142.0, 143.0, 144.0, 145.0, 146.0]:
		var cell := Vector2i(floori(82.0 / 0.125), floori(z / 0.125))
		print("SHOT_POND_ROW z=%.1f terrain=%s cache=%s" % [z, terrain_sampler.call(Vector2(82.0, z)), pond_cache.get(cell, "missing")])
	if "--pond-debug-red" in OS.get_cmdline_user_args():
		var pond_node: MeshInstance3D = scene.water_visual.get("_region_nodes").get(120)
		var debug_material := StandardMaterial3D.new()
		debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		debug_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		debug_material.albedo_color = Color.RED
		pond_node.material_override = debug_material
	if "--probe-river-cross-sections" in OS.get_cmdline_user_args():
		var river_state: Dictionary = water_states.get(_target_water_ids()[1], {})
		var river_cells: Array = river_state.get("cells", [])
		var river_footprint := {}
		for cell: Vector2i in river_cells:
			river_footprint[cell] = true
		for z in [90.0, 110.0, 120.0, 125.0, 130.0, 134.0, 136.0]:
			var center: float = load("res://scripts/m1_patch_generator.gd").river_center_x(z)
			var line := []
			for dx in range(-5, 6):
				var x := center + float(dx)
				var cell := Vector2i(floori(x / 0.125), floori(z / 0.125))
				var top: Variant = pond_cache.get(cell, NAN)
				line.append("%+d:%s/%s/%s" % [dx, river_footprint.has(cell), str(top), str(terrain_sampler.call(Vector2(x, z)))])
			print("SHOT_RIVER_ROW z=%.1f x=%.3f footprint/cache/terrain %s" % [z, center, " ".join(line)])
	if "--river-debug-red" in OS.get_cmdline_user_args():
		var river_ids := _target_water_ids()
		var river_id: int = river_ids[1] if river_ids.size() == 3 else -1
		var river_node: MeshInstance3D = scene.water_visual.get("_region_nodes").get(river_id)
		if river_node != null:
			var debug_material := StandardMaterial3D.new()
			debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			debug_material.cull_mode = BaseMaterial3D.CULL_DISABLED
			debug_material.albedo_color = Color.RED
			river_node.material_override = debug_material
			print("SHOT_RIVER_DEBUG id=%d" % river_id)
	if "--hide-legacy-river" in OS.get_cmdline_user_args():
		scene.river_water.visible = false
		print("SHOT_LEGACY_RIVER_HIDDEN")
	if scene.hud:
		scene.hud.visible = false
	var target := Vector3(82.0, 14.0, 139.0)
	var cam_pos := Vector3(56.0, 42.0, 112.0)
	for i in OS.get_cmdline_user_args().size():
		var a: String = OS.get_cmdline_user_args()[i]
		if a == "--look" and i + 1 < OS.get_cmdline_user_args().size():
			target = _vec3(OS.get_cmdline_user_args()[i + 1])
		if a == "--cam" and i + 1 < OS.get_cmdline_user_args().size():
			cam_pos = _vec3(OS.get_cmdline_user_args()[i + 1])
	var cam := Camera3D.new()
	cam.position = cam_pos
	var look := target - cam_pos
	var d := look.length()
	var pitch := asin(clampf(look.y / d, -1.0, 1.0)) if d > 0.001 else 0.0
	cam.rotation = Vector3(pitch, atan2(-look.x, -look.z), 0.0)
	cam.current = true
	root.add_child(cam)
	print("SHOT_CAM pos=%s look=%s" % [cam_pos, target])
	var img := await _capture()
	var out := "reports/screenshots/waterfall/shot.png"
	for i in OS.get_cmdline_user_args().size():
		if OS.get_cmdline_user_args()[i] == "--out" and i + 1 < OS.get_cmdline_user_args().size():
			out = OS.get_cmdline_user_args()[i + 1]
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	img.save_png(out)
	print("SHOT_OK %s" % out)
	quit(0)

func _vec3(s: String) -> Vector3:
	var p: Array = s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
