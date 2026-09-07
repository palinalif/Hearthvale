extends SceneTree
const Native = preload("res://scripts/terrain_backend.gd")
const Query = preload("res://scripts/sculpt_next_layer.gd")
var checks := 0
var failures := 0
var source: Node
var query: Node

class SinkTool extends RefCounted:
	func paste(_origin: Vector3i, _buffer: Object, _mask: int) -> void: pass
class SinkTerrain extends Node:
	var sink := SinkTool.new()
	func get_voxel_tool() -> RefCounted: return sink

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	source = Native.new()
	source.voxels = ClassDB.instantiate("VoxelBuffer")
	source.voxels.create(48, 32, 48)
	source._backend_ready = true
	source.terrain = SinkTerrain.new()
	query = Query.new()
	for tool in ["raise", "dig", "level", "slope", "smooth"]:
		for falloff in [0.0, 0.45, 1.0]:
			_fixture()
			_compare(tool, Vector3(24, 10, 24), Vector3.UP, falloff)
	for normal in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK, Vector3.DOWN]:
		for tool in ["raise", "dig"]:
			source.voxels.fill(0, 0)
			var axis: int = normal.abs().max_axis_index()
			var low := Vector3i.ZERO
			var high := Vector3i(48, 32, 48)
			var center := Vector3(24, 16, 24)
			if normal[axis] > 0: high[axis] = int(center[axis])
			else: low[axis] = int(center[axis])
			source.voxels.fill_area(2, low, high, 0)
			_compare(tool, center, normal, 0.45)
	_fixture()
	var center := Vector3(24, 10, 24)
	var settings := {"radius": 3.0, "strength": 2.0, "falloff": 0.45}
	check(source.begin_stroke("dig", center, settings), "start active preview fixture")
	source.update_stroke(center, 0.6)
	var bytes_before := _bytes()
	var fronts: Dictionary = source._stroke_fronts.duplicate(true)
	var residuals: Dictionary = source._stroke_accumulated.duplicate(true)
	var mutations: int = source._stroke_mutations
	var history: int = source.stats().undo_count
	var plan: Dictionary = query.plan(source, "dig", center, settings)
	check(bool(plan.valid), "active plan valid")
	check(_bytes() == bytes_before, "active query never writes native terrain")
	check(source._stroke_fronts == fronts and source._stroke_accumulated == residuals, "active query never consumes front or credit")
	check(source._stroke_mutations == mutations and source.stats().undo_count == history, "active query leaves history untouched")
	source.cancel_stroke()
	# Digging a thin roof must never preview a disconnected floor below it.
	source.voxels.fill(0, 0)
	source.voxels.fill_area(2, Vector3i.ZERO, Vector3i(48, 4, 48), 0)
	source.voxels.set_voxel(2, 24, 10, 24, 0)
	settings.radius = 0.25
	center.y = 11
	check(source.begin_stroke("dig", center, settings), "start cave fixture")
	source.update_stroke(center, 0.6)
	plan = query.plan(source, "dig", center, settings)
	check(plan.changes.is_empty(), "retired dig front shows no distant floor")
	check(source.voxel_at(Vector3i(24, 3, 24)) == 2, "cave floor intact")
	source.cancel_stroke()
	# A truly flat region is settled, rather than a false remove highlight.
	source.voxels.fill(0, 0)
	source.voxels.fill_area(2, Vector3i.ZERO, Vector3i(48, 10, 48), 0)
	settings.radius = 4.0
	plan = query.plan(source, "smooth", Vector3(24, 10, 24), settings)
	check(plan.changes.is_empty(), "settled smoothing predicts no edits")
	check(not query.plan(source, "invalid", center, settings).valid, "reject invalid tool")
	check(not query.plan(source, "dig", Vector3.INF, settings).valid, "reject invalid target")
	# Fine-grid cost probe, not a Thor performance claim. No mesh threads or
	# full-world copy are involved in these read-only queries.
	source.voxels = ClassDB.instantiate("VoxelBuffer")
	source.patch_size = Vector3i(160, 96, 160)
	source.voxel_scale = 0.125
	source.voxels.create(160, 96, 160)
	source.voxels.fill_area(2, Vector3i.ZERO, Vector3i(160, 48, 160), 0)
	for radius in [2.0, 8.0]:
		settings.radius = radius
		plan = query.plan(source, "dig", Vector3(10, 6, 10), settings)
		check(bool(plan.valid) and plan.changes.size() > 9, "full footprint, not sparse nine-cell sample")
		print("PREVIEW_QUERY radius=%.1f cells=%d cpu_ms=%.3f" % [radius, plan.changes.size(), float(query.last_query_ms)])
	source.terrain.free()
	source.free()
	query.free()
	print("sculpt_next_layer_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _fixture() -> void:
	source.voxels.fill(0, 0)
	source.voxels.fill_area(2, Vector3i.ZERO, Vector3i(48, 10, 48), 0)
	source.voxels.fill_area(2, Vector3i(23, 10, 23), Vector3i(25, 12, 25), 0)
	source.voxels.fill_area(0, Vector3i(25, 8, 24), Vector3i(27, 10, 26), 0)

func _bytes() -> PackedByteArray:
	return source.voxels.get_channel_as_byte_array(0)

func _compare(tool: String, center: Vector3, normal: Vector3, falloff: float) -> void:
	var settings := {"radius": 3.0, "strength": 2.0, "falloff": falloff, "surface_normal": normal}
	var reference := {"valid": true, "point": center, "normal": Vector3.UP, "slope_x": 0.25 if tool == "slope" else 0.0, "slope_z": 0.0}
	var before := _bytes()
	var plan: Dictionary = query.plan(source, tool, center, settings, reference)
	check(bool(plan.valid), "valid %s/%s/%.2f" % [tool, normal, falloff])
	check(_bytes() == before and not source._stroke_active, "idle preview read-only")
	var expected: Object = source._clone_buffer(source.voxels)
	var seen := {}
	for change in plan.changes:
		var cell: Vector3i = change.cell
		check(not seen.has(cell), "at most one candidate per cell")
		seen[cell] = true
		expected.set_voxel(int(change.after), cell.x, cell.y, cell.z, 0)
	check(source.begin_stroke(tool, center, settings, reference), "native reference stroke starts")
	source._integrate_stroke_sample(center, 0.0)
	var columns: Array[Vector3i] = source._stroke_columns(center, 3.0) if tool in ["raise", "dig"] else source._vertical_columns(center, 3.0)
	for i in columns.size():
		var column := columns[i]
		if source._column_distance(column, center) >= 3.0: continue
		var credit := 1.0
		if tool == "smooth": credit = 1.0 if float(source._smooth_targets[i]) > float(source._stroke_fronts[column]) else -1.0
		source._stroke_accumulated[column] = credit
	source._integrate_stroke_sample(center, 0.0)
	check(_bytes() == expected.get_channel_as_byte_array(0), "all predicted cells equal native next-layer edits %s" % tool)
	var after := _bytes()
	if source.end_stroke():
		check(source.undo() and _bytes() == before, "exact undo after preview")
		check(source.redo() and _bytes() == after, "exact redo after preview")
		source.undo()
