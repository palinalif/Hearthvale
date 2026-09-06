extends SceneTree

const Backend = preload("res://scripts/terrain_backend.gd")
const PatchGenerator = preload("res://scripts/patch_generator.gd")

var failures := 0
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _init() -> void:
	var backend: Node = Backend.new()
	root.add_child(backend)
	await _wait_ready(backend, 16000)
	check(backend.is_ready(), "sculpt backend ready")
	if not backend.is_ready():
		print("sculpt_test checks=%d failures=%d" % [checks, failures + 1])
		quit(1)

	# A held brush integrates time rather than frame count and advances its
	# local front, so it keeps building after the initial sphere is filled.
	var hold_center := Vector3(24.0, 5.0, 24.0)
	var baseline := _bytes(backend)
	check(backend.begin_stroke("raise", hold_center, {"radius": 1.5, "strength": 1.0, "falloff": 0.7}), "begin held raise")
	for _i in 30: backend.update_stroke(hold_center, 1.0 / 60.0)
	var early_raise := _bytes(backend)
	for _i in 30: backend.update_stroke(hold_center, 1.0 / 60.0)
	var mid_raise := _bytes(backend)
	for _i in 60: backend.update_stroke(hold_center, 1.0 / 60.0)
	var late_raise := _bytes(backend)
	check(early_raise == baseline, "brief held raise remains fractional")
	check(mid_raise != baseline, "held raise makes gradual progress")
	check(late_raise != mid_raise, "held raise advances beyond initial sphere")
	check(backend.end_stroke(), "end held raise")
	check(backend.stats().undo_count == 1, "held raise is one undo transaction")
	check(backend.undo(), "held raise undo")
	check(_bytes(backend) == baseline, "held raise undo exact")
	check(backend.redo(), "held raise redo")
	var raised := _bytes(backend)
	check(raised == late_raise, "held raise redo exact")

	# Connected movement samples the whole path, including its midpoint.
	check(backend.undo(), "drag setup undo")
	var drag_base := _bytes(backend)
	check(backend.begin_stroke("raise", Vector3(18.0, 5.0, 24.0), {"radius": 1.2, "strength": 40.0, "falloff": 0.5}), "begin connected drag")
	backend.update_stroke(Vector3(30.0, 5.0, 24.0), 0.7)
	check(backend.end_stroke(), "end connected drag")
	check(_bytes(backend) != drag_base, "connected drag changed terrain")
	check(backend.voxel_at(Vector3i(24, 12, 24)) != 0, "connected drag has no midpoint gap")
	check(backend.undo(), "connected drag undo")
	check(_bytes(backend) == drag_base, "connected drag undo exact")

	# Digging is volumetric and can progress into the tunnel roof/wall.
	var cave_base := _bytes(backend)
	var cave_sample: int = backend.voxel_at(Vector3i(24, 8, 24))
	check(backend.begin_stroke("dig", Vector3(24.0, 8.0, 24.0), {"radius": 1.5, "strength": 2.0, "falloff": 0.6}), "begin cave dig")
	for _i in 90: backend.update_stroke(Vector3(24.0, 8.0, 24.0), 1.0 / 60.0)
	check(backend.voxel_at(Vector3i(24, 8, 24)) == 0 or cave_sample == 0, "cave roof dig changes volumetric cell")
	check(backend.cancel_stroke(), "cancel cave dig")
	check(_bytes(backend) == cave_base, "cancel restores cave exactly")

	# A centreline query in a cave must distinguish the floor below the cursor
	# from the ceiling above it.  This fixture has an air pocket between two
	# separate solids on the exact sampled x/z column; neighbouring columns are
	# intentionally irrelevant to the result.
	var cave_planes_base := _bytes(backend)
	for y in range(backend.patch_size.y):
		backend.voxels.set_voxel(0, 20, y, 20, PatchGenerator.CHANNEL_TYPE)
	for y in range(4):
		backend.voxels.set_voxel(1, 20, y, 20, PatchGenerator.CHANNEL_TYPE)
	for y in range(10, 13):
		backend.voxels.set_voxel(1, 20, y, 20, PatchGenerator.CHANNEL_TYPE)
	backend.terrain.get_voxel_tool().paste(Vector3i.ZERO, backend.voxels, 1)
	var cave_floor_plane: Dictionary = backend.sample_surface_plane(Vector3(20.0, 8.0, 20.0), Vector3.UP, 5.0)
	var cave_ceiling_plane: Dictionary = backend.sample_surface_plane(Vector3(20.0, 8.0, 20.0), Vector3.DOWN, 5.0)
	check(bool(cave_floor_plane.get("valid", false)) and absf(float((cave_floor_plane.get("point", Vector3.ZERO) as Vector3).y) - 4.0) < 0.01, "cave floor samples centreline below cursor")
	check(bool(cave_ceiling_plane.get("valid", false)) and absf(float((cave_ceiling_plane.get("point", Vector3.ZERO) as Vector3).y) - 10.0) < 0.01, "cave ceiling samples nearest underside above cursor")
	check(not backend.begin_stroke("level", Vector3(20.0, 8.0, 20.0), {"radius": 2.0, "strength": 4.0}, {"valid": true, "point": Vector3(20.0, 8.0, 20.0), "normal": Vector3.RIGHT}), "level rejects horizontal wall reference")
	check(not backend.begin_stroke("slope", Vector3(20.0, 8.0, 20.0), {"radius": 2.0, "strength": 4.0}, {"valid": true, "point": Vector3(20.0, 8.0, 20.0), "normal": Vector3.DOWN}), "slope rejects underside reference")
	backend.voxels.set_channel_from_byte_array(PatchGenerator.CHANNEL_TYPE, cave_planes_base)
	backend.terrain.get_voxel_tool().paste(Vector3i.ZERO, backend.voxels, 1)

	# Flatten samples one center height and keeps it immutable while moving.
	var plane: Dictionary = backend.sample_surface_plane(Vector3(10.0, 10.0, 10.0), Vector3.UP, 3.0)
	check(bool(plane.get("valid", false)), "surface plane sample valid")
	var level_base := _bytes(backend)
	check(backend.begin_stroke("level", Vector3(10.0, 10.0, 10.0), {"radius": 4.0, "strength": 40.0, "falloff": 0.7}, plane), "begin fixed level")
	var level_reference: Dictionary = backend.get_stroke_state().reference
	backend.update_stroke(Vector3(15.0, 10.0, 10.0), 0.6)
	check(backend.get_stroke_state().reference == level_reference, "level reference remains fixed")
	check(backend.end_stroke(), "end fixed level")
	check(_bytes(backend) != level_base, "level modifies local terrain")
	check(backend.undo(), "level undo")
	check(_bytes(backend) == level_base, "level undo exact")

	# A fitted local plane exposes slope data and remains fixed throughout a
	# moving slope stroke.
	var slope: Dictionary = backend.sample_surface_plane(Vector3(16.0, 11.0, 16.0), Vector3.UP, 4.0)
	check(bool(slope.get("valid", false)), "slope plane sample valid")
	check(backend.begin_stroke("slope", Vector3(16.0, 11.0, 16.0), {"radius": 2.5, "strength": 20.0, "falloff": 0.7}, slope), "begin fixed slope")
	var slope_reference: Dictionary = backend.get_stroke_state().reference
	backend.update_stroke(Vector3(20.0, 11.0, 16.0), 0.6)
	check(backend.get_stroke_state().reference == slope_reference, "slope reference remains fixed")
	check(backend.end_stroke(), "end fixed slope")
	check(backend.undo(), "slope undo")

	# A caller supplied sloped normal is sufficient to build the immutable
	# plane reference; the backend must derive the plane coefficients instead
	# of silently treating an omitted slope as horizontal.
	var supplied_slope := {"valid": true, "point": Vector3(16.0, 11.0, 16.0), "normal": Vector3(-0.6, 0.8, 0.0)}
	check(backend.begin_stroke("slope", Vector3(16.0, 11.0, 16.0), {"radius": 2.0, "strength": 1.0, "falloff": 0.5}, supplied_slope), "begin supplied normal slope")
	var supplied_reference: Dictionary = backend.get_stroke_state().reference
	check(absf(float(supplied_reference.get("slope_x", 0.0)) - 0.75) < 0.001 and absf(float(supplied_reference.get("slope_z", 0.0))) < 0.001, "supplied normal derives slope coefficients")
	check(backend.cancel_stroke(), "cancel supplied normal slope")

	# Smooth is local surface geometry work, not a global pass.
	var smooth_base := _bytes(backend)
	check(backend.begin_stroke("smooth", Vector3(15.5, 10.0, 12.0), {"radius": 4.0, "strength": 20.0, "falloff": 0.5}), "begin local smooth")
	for _i in 90: backend.update_stroke(Vector3(15.5, 10.0, 12.0), 1.0 / 60.0)
	check(backend.end_stroke(), "end local smooth")
	check(_bytes(backend) != smooth_base, "smooth modifies local terrain")
	check(backend.stats().history_bytes < 48 * 32 * 48 * 2 * 2, "sculpt history is bounded local patch")
	check(backend.undo(), "smooth undo")
	check(_bytes(backend) == smooth_base, "smooth undo exact")

	# Invalid bounds and conflicting operations are rejected safely.
	check(not backend.begin_stroke("raise", Vector3(-1.0, 4.0, 4.0), {"radius": 2.0, "strength": 1.0}), "invalid stroke center rejected")
	check(not backend.begin_stroke("unknown", Vector3(10.0, 10.0, 10.0), {"radius": 2.0, "strength": 1.0}), "invalid stroke tool rejected")
	check(backend.begin_stroke("raise", Vector3(20.0, 5.0, 20.0), {"radius": 1.0, "strength": 1.0}), "begin conflict test stroke")
	check(not backend.apply_sphere(Vector3(20.0, 5.0, 20.0), 1.0, false), "stamp rejected during sculpt")
	check(backend.cancel_stroke(), "cancel conflict test stroke")

	# Level follows the local exposed boundary through a gap larger than one
	# voxel and stops at the fixed target without building a floating shell.
	var adversarial_base := _bytes(backend)
	# Keep the tall test column contiguous with the generated ground. This
	# exercises a >3 voxel height gap without allowing level to manufacture a
	# floating shell in the air between two disconnected masses.
	for y in range(10, 18): backend.voxels.set_voxel(1, 4, y, 4, PatchGenerator.CHANNEL_TYPE)
	backend.terrain.get_voxel_tool().paste(Vector3i.ZERO, backend.voxels, 1)
	var gap_plane := {"valid": true, "point": Vector3(4.0, 12.0, 4.0), "normal": Vector3.UP, "slope_x": 0.0, "slope_z": 0.0}
	check(backend.begin_stroke("level", Vector3(4.0, 16.0, 4.0), {"radius": 1.5, "strength": 40.0, "falloff": 0.5}, gap_plane), "begin level height gap")
	for _i in 60: backend.update_stroke(Vector3(4.0, 16.0, 4.0), 1.0 / 60.0)
	check(backend.end_stroke(), "end level height gap")
	check(backend._column_surface_y(backend.voxels, 4, 4) == 12.0, "level closes height gap at target without overshoot")
	check(backend.undo(), "height gap undo")
	check(_bytes(backend) != adversarial_base, "height gap setup remains until reset")
	backend.voxels.set_channel_from_byte_array(PatchGenerator.CHANNEL_TYPE, adversarial_base)
	backend.terrain.get_voxel_tool().paste(Vector3i.ZERO, backend.voxels, 1)

	# A horizontal normal digs an explicit wall ray. Once x8..10 are removed,
	# the newly exposed void at x7 must stop the front before x0..3.
	for x in range(0, 21):
		for y in range(4, 7):
			for z in range(9, 12): backend.voxels.set_voxel(0, x, y, z, PatchGenerator.CHANNEL_TYPE)
	for x in range(0, 4): backend.voxels.set_voxel(1, x, 5, 10, PatchGenerator.CHANNEL_TYPE)
	for x in range(8, 11): backend.voxels.set_voxel(1, x, 5, 10, PatchGenerator.CHANNEL_TYPE)
	backend.terrain.get_voxel_tool().paste(Vector3i.ZERO, backend.voxels, 1)
	var wall_base := _bytes(backend)
	var wall_before_full: Object = backend._clone_buffer(backend.voxels)
	var wall_plane: Dictionary = backend.sample_surface_plane(Vector3(11.0, 5.0, 10.0), Vector3.RIGHT, 3.0)
	check(bool(wall_plane.get("valid", false)), "centerline wall plane valid")
	if bool(wall_plane.get("valid", false)):
		var wall_point: Vector3 = wall_plane["point"]
		check(absf(wall_point.y - 5.0) <= 0.51 and absf(wall_point.z - 10.0) <= 0.51 and wall_point.x >= 7.0 and wall_point.x <= 12.0, "wall sample stays on cursor line")
	check(backend.begin_stroke("dig", Vector3(11.0, 5.0, 10.0), {"radius": 1.25, "strength": 4.0, "falloff": 0.4, "surface_normal": Vector3(1.0, 0.0, 0.0)}), "begin horizontal wall dig")
	for _i in 60: backend.update_stroke(Vector3(11.0, 5.0, 10.0), 1.0 / 60.0)
	check(backend.end_stroke(), "end horizontal wall dig")
	for x in range(8, 11): check(backend.voxel_at(Vector3i(x, 5, 10)) == 0, "horizontal dig removes wall ray")
	for x in range(0, 4): check(backend.voxel_at(Vector3i(x, 5, 10)) != 0, "horizontal dig stops before solid behind void")
	for x in range(4, 8): check(backend.voxel_at(Vector3i(x, 5, 10)) == 0, "horizontal dig leaves exposed void")
	var wall_after_full: Object = backend._clone_buffer(backend.voxels)
	check(_outside_region_equal(wall_before_full, wall_after_full, Vector3i(7, 4, 9), Vector3i(13, 7, 12)), "horizontal dig changes only its bounded patch")
	check(backend.undo(), "horizontal wall dig undo")
	check(_bytes(backend) == wall_base, "horizontal wall dig undo exact")
	backend.voxels.set_channel_from_byte_array(PatchGenerator.CHANNEL_TYPE, adversarial_base)
	backend.terrain.get_voxel_tool().paste(Vector3i.ZERO, backend.voxels, 1)

	# A local ground fixture plus a disconnected floating lump proves that the
	# raise front follows the attached surface and does not jump to y20.
	for x in range(6, 11):
		for z in range(6, 11):
			for y in range(32): backend.voxels.set_voxel(0, x, y, z, PatchGenerator.CHANNEL_TYPE)
			for y in range(8): backend.voxels.set_voxel(1, x, y, z, PatchGenerator.CHANNEL_TYPE)
	for y in range(20, 22): backend.voxels.set_voxel(1, 8, y, 8, PatchGenerator.CHANNEL_TYPE)
	backend.terrain.get_voxel_tool().paste(Vector3i.ZERO, backend.voxels, 1)
	var floating_base := _bytes(backend)
	var floating_before_full: Object = backend._clone_buffer(backend.voxels)
	check(backend.begin_stroke("raise", Vector3(8.0, 8.0, 8.0), {"radius": 1.5, "strength": 4.0, "falloff": 0.5}), "begin raise attached front")
	for _i in 30: backend.update_stroke(Vector3(8.0, 8.0, 8.0), 1.0 / 60.0)
	check(backend.end_stroke(), "end raise attached front")
	check(backend.voxel_at(Vector3i(8, 8, 8)) != 0 and backend.voxel_at(Vector3i(8, 9, 8)) != 0, "raise advances attached front two cells")
	for y in range(10, 20): check(backend.voxel_at(Vector3i(8, y, 8)) == 0, "raise creates no disconnected cells")
	check(backend.voxel_at(Vector3i(8, 20, 8)) != 0 and backend.voxel_at(Vector3i(8, 21, 8)) != 0 and backend.voxel_at(Vector3i(8, 22, 8)) == 0, "raise leaves distant lump and air above it")
	var floating_after_full: Object = backend._clone_buffer(backend.voxels)
	check(_outside_region_equal(floating_before_full, floating_after_full, Vector3i(6, 7, 6), Vector3i(11, 11, 11)), "raise changes only its bounded patch")
	check(backend.undo(), "attached front raise undo")
	check(_bytes(backend) == floating_base, "attached front raise undo exact")
	backend.voxels.set_channel_from_byte_array(PatchGenerator.CHANNEL_TYPE, adversarial_base)
	backend.terrain.get_voxel_tool().paste(Vector3i.ZERO, backend.voxels, 1)

	# Construct an incline, capture its center hit and fitted normal, then add a
	# local bump. Slope moves the bump toward that immutable captured plane.
	var incline_base := _bytes(backend)
	for x in range(14, 19):
		for z in range(14, 19):
			for y in range(32): backend.voxels.set_voxel(0, x, y, z, PatchGenerator.CHANNEL_TYPE)
			var top := 8 + (x - 14)
			for y in range(top): backend.voxels.set_voxel(1, x, y, z, PatchGenerator.CHANNEL_TYPE)
	backend.terrain.get_voxel_tool().paste(Vector3i.ZERO, backend.voxels, 1)
	var incline_plane: Dictionary = backend.sample_surface_plane(Vector3(16.0, 10.0, 16.0), Vector3.UP, 3.0)
	check(bool(incline_plane.get("valid", false)), "constructed incline sample valid")
	check(incline_plane.get("point", Vector3.ZERO) == Vector3(16.0, 10.0, 16.0), "surface hit keeps exact center point and height")
	var incline_normal: Vector3 = incline_plane.get("normal", Vector3.UP)
	check(absf(incline_normal.x) > 0.25, "constructed incline has fitted nonhorizontal normal")
	for y in range(10, 14): backend.voxels.set_voxel(1, 17, y, 16, PatchGenerator.CHANNEL_TYPE)
	backend.terrain.get_voxel_tool().paste(Vector3i.ZERO, backend.voxels, 1)
	var slope_target := float((incline_plane["point"] as Vector3).y) + float(incline_plane.get("slope_x", 0.0))
	var slope_before_error := absf(backend._column_surface_y(backend.voxels, 17, 16) - slope_target)
	var slope_fixture_base := _bytes(backend)
	check(backend.begin_stroke("slope", Vector3(16.0, 10.0, 16.0), {"radius": 3.0, "strength": 40.0, "falloff": 0.6}, incline_plane), "begin incline slope")
	for _i in 120: backend.update_stroke(Vector3(16.0, 10.0, 16.0), 1.0 / 60.0)
	check(backend.end_stroke(), "end incline slope")
	var slope_after_error := absf(backend._column_surface_y(backend.voxels, 17, 16) - slope_target)
	check(slope_after_error < slope_before_error and backend._column_surface_y(backend.voxels, 17, 16) <= slope_target + 0.5, "slope reduces surface error without overshoot")
	check(backend.undo(), "incline slope undo")
	check(_bytes(backend) == slope_fixture_base, "incline slope undo exact")
	backend.voxels.set_channel_from_byte_array(PatchGenerator.CHANNEL_TYPE, incline_base)
	backend.terrain.get_voxel_tool().paste(Vector3i.ZERO, backend.voxels, 1)

	# Alternating local surfaces must become less rough under smooth, while the
	# untouched world remains byte-for-byte unchanged outside the brush patch.
	var smooth_fixture_base := _bytes(backend)
	for x in range(14, 19):
		for z in range(14, 19):
			for y in range(32): backend.voxels.set_voxel(0, x, y, z, PatchGenerator.CHANNEL_TYPE)
			var top := 8 if (x + z) % 2 == 0 else 12
			for y in range(top): backend.voxels.set_voxel(1, x, y, z, PatchGenerator.CHANNEL_TYPE)
	backend.terrain.get_voxel_tool().paste(Vector3i.ZERO, backend.voxels, 1)
	var smooth_fixture_base_after_setup := _bytes(backend)
	var rough_before := _surface_roughness(backend, 15, 17)
	var smooth_before_full: Object = backend._clone_buffer(backend.voxels)
	check(backend.begin_stroke("smooth", Vector3(16.0, 10.0, 16.0), {"radius": 3.0, "strength": 40.0, "falloff": 0.5}), "begin roughness smooth")
	for _i in 120: backend.update_stroke(Vector3(16.0, 10.0, 16.0), 1.0 / 60.0)
	check(backend.end_stroke(), "end roughness smooth")
	var rough_after := _surface_roughness(backend, 15, 17)
	check(rough_after < rough_before, "smooth reduces local surface roughness")
	var smooth_after_full: Object = backend._clone_buffer(backend.voxels)
	check(_outside_region_equal(smooth_before_full, smooth_after_full, Vector3i(13, 7, 13), Vector3i(20, 14, 20)), "smooth changes only its bounded patch")
	check(backend.undo(), "roughness smooth undo")
	check(_bytes(backend) == smooth_fixture_base_after_setup, "roughness smooth undo exact")
	backend.voxels.set_channel_from_byte_array(PatchGenerator.CHANNEL_TYPE, adversarial_base)
	backend.terrain.get_voxel_tool().paste(Vector3i.ZERO, backend.voxels, 1)

	# Fixed timestep integration produces the same result at 30 and 60 fps.
	var backend30: Node = Backend.new(); root.add_child(backend30)
	var backend60: Node = Backend.new(); root.add_child(backend60)
	await _wait_ready(backend30, 16000); await _wait_ready(backend60, 16000)
	check(backend30.is_ready() and backend60.is_ready(), "timing comparison backends ready")
	var timing_settings := {"radius": 1.6, "strength": 4.0, "falloff": 0.7}
	check(backend30.begin_stroke("raise", hold_center, timing_settings), "begin 30fps stroke")
	check(backend60.begin_stroke("raise", hold_center, timing_settings), "begin 60fps stroke")
	for _i in 30: backend30.update_stroke(hold_center, 1.0 / 30.0)
	for _i in 60: backend60.update_stroke(hold_center, 1.0 / 60.0)
	check(backend30.end_stroke() and backend60.end_stroke(), "end timing strokes")
	check(_bytes(backend30) == _bytes(backend60), "30fps and 60fps sculpt equivalent")

	# The same moving path is sampled at two frame rates. Fixed timestep
	# integration must preserve both the connected path and elapsed strength.
	check(backend30.undo() and backend60.undo(), "reset moving timing strokes")
	var moving_settings := {"radius": 1.6, "strength": 20.0, "falloff": 0.7}
	check(backend30.begin_stroke("raise", Vector3(18.0, 5.0, 24.0), moving_settings), "begin moving 30fps stroke")
	check(backend60.begin_stroke("raise", Vector3(18.0, 5.0, 24.0), moving_settings), "begin moving 60fps stroke")
	for i in range(1, 31):
		backend30.update_stroke(Vector3(18.0 + 12.0 * float(i) / 30.0, 5.0, 24.0), 1.0 / 30.0)
	for i in range(1, 61):
		backend60.update_stroke(Vector3(18.0 + 12.0 * float(i) / 60.0, 5.0, 24.0), 1.0 / 60.0)
	check(backend30.end_stroke() and backend60.end_stroke(), "end moving timing strokes")
	check(_bytes(backend30) == _bytes(backend60), "moving 30fps and 60fps sculpt equivalent")

	backend.queue_free(); backend30.queue_free(); backend60.queue_free()
	await process_frame
	print("sculpt_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _wait_ready(backend: Node, timeout_ms: int) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not backend.is_ready() and Time.get_ticks_msec() < deadline:
		await process_frame

func _bytes(backend: Node) -> PackedByteArray:
	return backend.voxels.get_channel_as_byte_array(PatchGenerator.CHANNEL_TYPE)

func _outside_region_equal(before: Object, after: Object, region_min: Vector3i, region_max: Vector3i) -> bool:
	for x in 48:
		for y in 32:
			for z in 48:
				if x >= region_min.x and x < region_max.x and y >= region_min.y and y < region_max.y and z >= region_min.z and z < region_max.z:
					continue
				if before.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE) != after.get_voxel(x, y, z, PatchGenerator.CHANNEL_TYPE):
					return false
	return true

func _surface_roughness(backend: Node, min_x: int, max_x: int) -> float:
	var roughness := 0.0
	for x in range(min_x, max_x + 1):
		for z in range(15, 18):
			var height: float = backend._column_surface_y(backend.voxels, x, z)
			for neighbour in [Vector2i(x + 1, z), Vector2i(x, z + 1)]:
				if neighbour.x <= max_x and neighbour.y <= 17:
					roughness += absf(height - backend._column_surface_y(backend.voxels, neighbour.x, neighbour.y))
	return roughness
