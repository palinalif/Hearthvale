extends SceneTree

const PatchGenerator = preload("res://scripts/patch_generator.gd")
class CountingBackend extends "res://scripts/terrain_backend.gd":
	var probes := 0
	func _surface_y_near(source: Object, x: int, z: int, center_y: float, reach: float) -> float:
		probes += 1
		return super._surface_y_near(source, x, z, center_y, reach)

var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var backend := CountingBackend.new()
	root.add_child(backend)
	var deadline := Time.get_ticks_msec() + 20000
	while not backend.is_ready() and Time.get_ticks_msec() < deadline: await process_frame
	check(backend.is_ready(), "native backend ready")
	if not backend.is_ready():
		backend.queue_free()
		quit(1)
		return
	var center := Vector3(24, 12, 24)
	_fixture(backend)
	var baseline := _bytes(backend)
	check(backend.begin_stroke("smooth", center, {"radius": 4.0, "strength": 8.0, "falloff": 0.5}), "begin spike smoothing")
	backend.update_stroke(center, 1.0 / 60.0)
	var first_probes := backend.probes
	check(first_probes > 0, "first tick samples native surface")
	for _i in 119: backend.update_stroke(center, 1.0 / 60.0)
	check(backend.probes == first_probes, "stationary brush never repeats surface searches")
	check(backend.voxel_at(Vector3i(24, 10, 24)) == 0, "two-cell spike settles to surrounding ground")
	var settled := _bytes(backend)
	for _i in 120: backend.update_stroke(center, 1.0 / 60.0)
	check(_bytes(backend) == settled, "settled surface does not chatter")
	check(backend.end_stroke(), "stroke commits")
	check(backend.stats().undo_count == 1, "one stroke one undo")
	check(backend.undo() and _bytes(backend) == baseline, "exact undo")
	check(backend.redo() and _bytes(backend) == settled, "exact redo")
	check(backend.undo(), "reset spike")
	check(backend.begin_stroke("smooth", center, {"radius": 4.0, "strength": 8.0}), "begin cancel")
	for _i in 60: backend.update_stroke(center, 1.0 / 60.0)
	check(backend.cancel_stroke() and _bytes(backend) == baseline, "cancel restores all changes")

	var timed_results: Array[PackedByteArray] = []
	for fps in [30, 60]:
		check(backend.begin_stroke("smooth", center, {"radius": 4.0, "strength": 8.0}), "begin timed stroke %d" % fps)
		for _i in fps: backend.update_stroke(center, 1.0 / float(fps))
		backend.end_stroke()
		timed_results.append(_bytes(backend))
		backend.undo()
	check(timed_results[0] == timed_results[1], "same held target at 30/60 fps")

	# A thin roof atop a void is removed locally, then retired. Smoothing may
	# not jump to the disconnected floor during the rest of the held stroke.
	_fixture(backend)
	for x in range(20, 29):
		for z in range(20, 29):
			for y in range(4, 10): backend.voxels.set_voxel(0, x, y, z, PatchGenerator.CHANNEL_TYPE)
	backend.voxels.set_voxel(2, 24, 10, 24, PatchGenerator.CHANNEL_TYPE)
	backend.voxels.set_voxel(0, 24, 11, 24, PatchGenerator.CHANNEL_TYPE)
	backend.terrain.get_voxel_tool().paste(Vector3i.ZERO, backend.voxels, 1)
	var cave_before := _bytes(backend)
	check(backend.begin_stroke("smooth", center, {"radius": 4.0, "strength": 8.0}), "begin thin cave roof")
	for _i in 180: backend.update_stroke(center, 1.0 / 60.0)
	check(backend.voxel_at(Vector3i(24, 10, 24)) == 0, "thin roof removed")
	for y in range(4): check(backend.voxel_at(Vector3i(24, y, 24)) != 0, "disconnected cave floor preserved %d" % y)
	check(backend.cancel_stroke() and _bytes(backend) == cave_before, "cave cancel exact")
	backend.queue_free()
	await process_frame
	print("sculpt_smoothing_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _fixture(backend: Node) -> void:
	backend.voxels.fill(0, PatchGenerator.CHANNEL_TYPE)
	backend.voxels.fill_area(2, Vector3i.ZERO, Vector3i(48, 10, 48), PatchGenerator.CHANNEL_TYPE)
	backend.voxels.set_voxel(2, 24, 10, 24, PatchGenerator.CHANNEL_TYPE)
	backend.voxels.set_voxel(2, 24, 11, 24, PatchGenerator.CHANNEL_TYPE)
	backend.terrain.get_voxel_tool().paste(Vector3i.ZERO, backend.voxels, 1)

func _bytes(backend: Node) -> PackedByteArray:
	return backend.voxels.get_channel_as_byte_array(PatchGenerator.CHANNEL_TYPE)
