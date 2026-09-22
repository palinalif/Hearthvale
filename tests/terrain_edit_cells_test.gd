extends SceneTree
## Sparse stroke metadata must scale with changed cells, not the enclosing box.
const Backend = preload("res://scripts/terrain_backend.gd")
var checks := 0
var failures := 0

class CountingBuffer:
	extends RefCounted
	var source: Object
	var reads := 0
	func get_voxel(x: int, y: int, z: int, channel: int) -> int:
		reads += 1
		return source.get_voxel(x, y, z, channel)

class FakeTerrain:
	extends Node
	func get_voxel_tool() -> Object: return self
	func paste(_at: Vector3i, _buffer: Object, _mask: int) -> void: pass

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)

func _initialize() -> void:
	var backend := Backend.new()
	backend.patch_size = Vector3i(96, 64, 96)
	backend.voxel_scale = 0.125
	backend.voxels = ClassDB.instantiate("VoxelBuffer")
	backend.voxels.create(96, 64, 96)
	backend.terrain = FakeTerrain.new()
	backend._backend_ready = true
	backend._stroke_active = true
	var edits := [Vector3i(1, 1, 1), Vector3i(94, 62, 94)]
	for cell: Vector3i in edits:
		backend._record_stroke_change(cell, 0, 1)
		backend.voxels.set_voxel(1, cell.x, cell.y, cell.z, 0)
	# A touched cell returned to its original value must not clear planting.
	var restored := Vector3i(48, 32, 48)
	backend._record_stroke_change(restored, 0, 1)
	backend._record_stroke_change(restored, 1, 0)
	check(backend.end_stroke(), "sparse stroke commits once")
	var command: Dictionary = backend._last_edit_command
	var before := CountingBuffer.new()
	var after := CountingBuffer.new()
	before.source = command["before"]
	after.source = command["after"]
	command["before"] = before
	command["after"] = after
	var start := Time.get_ticks_usec()
	var cells := backend.get_last_edit_cells()
	check(cells.size() == 2, "only net changes reported")
	for cell: Vector3i in edits:
		check(cells.has((Vector3(cell) + Vector3.ONE * 0.5) * 0.125), "world-space cell center preserved")
	check(backend.get_last_edit_cells() == cells, "both release consumers see the same edit")
	check(before.reads + after.reads == 0, "release never rescans history buffers")
	print("edit_cells_probe reads=%d elapsed_ms=%.3f" % [before.reads + after.reads, (Time.get_ticks_usec() - start) / 1000.0])
	command["before"] = before.source
	command["after"] = after.source
	check(backend.undo() and backend.get_last_edit_cells() == cells, "undo retains exact affected cells")
	check(backend.redo() and backend.get_last_edit_cells() == cells, "redo retains exact affected cells")
	check(backend._history_bytes == backend._stack_bytes(backend._undo), "sparse metadata included in history budget")
	check(backend.column_top_y(Vector2i(94, 94)) == 62, "native column query finds a detached overhang")
	check(backend.column_top_y(Vector2i(48, 48)) == -1, "native column query returns empty for an air column")
	backend.voxels.set_voxel(65535, 3, 63, 4, 0)
	check(backend.column_top_y(Vector2i(3, 4)) == 63, "native column query reads full material width at the world ceiling")
	backend.voxels.set_voxel(0, 3, 63, 4, 0)
	backend.voxels.set_voxel(256, 3, 0, 4, 0)
	check(backend.column_top_y(Vector2i(3, 4)) == 0, "native column query refreshes edits and reads the bottom row")
	check(backend.column_top_y(Vector2i(-1, 0)) == -1, "native column query rejects outside-world columns")
	backend.terrain.free()
	backend.free()
	print("terrain_edit_cells_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
