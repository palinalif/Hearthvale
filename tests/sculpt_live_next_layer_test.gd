extends SceneTree
const Native = preload("res://scripts/terrain_backend.gd")
const Reference = preload("res://scripts/sculpt_next_layer.gd")
const Live = preload("res://scripts/sculpt_live_next_layer.gd")
var checks := 0
var failures := 0

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
	var source := Native.new()
	source.patch_size = Vector3i(48, 32, 48)
	source.voxel_scale = 1.0
	source.voxels = ClassDB.instantiate("VoxelBuffer")
	source.voxels.create(48, 32, 48)
	source._backend_ready = true
	source.terrain = SinkTerrain.new()
	var reference := Reference.new()
	var center := Vector3(24, 10, 24)
	for tool in ["raise", "dig", "level", "slope", "smooth"]:
		for falloff in [0.0, 0.45, 1.0]:
			_fixture(source)
			var settings := {"radius": 3.0, "strength": 2.0, "falloff": falloff, "surface_normal": Vector3.UP}
			var plane := {"valid": true, "point": center + Vector3(0, 1 if tool == "level" else 0, 0), "normal": Vector3.UP, "slope_x": 0.25 if tool == "slope" else 0.0, "slope_z": 0.0}
			check(source.begin_stroke(tool, center, settings, plane), "begin %s %.2f" % [tool, falloff])
			# Populate exactly the same active frontier/targets the gameplay backend
			# exposes before either read-only planner gets edit credit.
			source._integrate_stroke_sample(center, 0.0)
			var before: PackedByteArray = source.voxels.get_channel_as_byte_array(0)
			var fronts: Dictionary = source._stroke_fronts.duplicate(true)
			var accum: Dictionary = source._stroke_accumulated.duplicate(true)
			var reference_plan: Dictionary = reference.plan(source, tool, center, settings, plane)
			var live_plan: Dictionary = Live.plan(source, center)
			check(bool(reference_plan.get("valid", false)) and bool(live_plan.get("valid", false)), "both planners valid %s %.2f" % [tool, falloff])
			check(_signature(reference_plan.get("changes", [])) == _signature(live_plan.get("changes", [])), "live next-layer cells match integrator preview %s %.2f" % [tool, falloff])
			check(int(reference_plan.get("add_count", -1)) == int(live_plan.get("add_count", -2)) and int(reference_plan.get("remove_count", -1)) == int(live_plan.get("remove_count", -2)), "live add/remove counts match %s %.2f" % [tool, falloff])
			check(source.voxels.get_channel_as_byte_array(0) == before, "live parity check is read-only %s" % tool)
			check(source._stroke_fronts == fronts and source._stroke_accumulated == accum, "live planner leaves active state untouched %s" % tool)
			source.cancel_stroke()

	# Horizontal raise/dig use the same live frontier path and must preserve
	# wall-facing cell coordinates rather than assuming vertical terrain.
	for normal in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK, Vector3.DOWN]:
		for tool in ["raise", "dig"]:
			source.voxels.fill(0, 0)
			var axis: int = normal.abs().max_axis_index()
			var low := Vector3i.ZERO
			var high := Vector3i(48, 32, 48)
			var wall_center := Vector3(24, 16, 24)
			if normal[axis] > 0: high[axis] = int(wall_center[axis])
			else: low[axis] = int(wall_center[axis])
			source.voxels.fill_area(2, low, high, 0)
			var settings := {"radius": 3.0, "strength": 2.0, "falloff": 0.45, "surface_normal": normal}
			check(source.begin_stroke(tool, wall_center, settings), "begin wall %s %s" % [tool, normal])
			source._integrate_stroke_sample(wall_center, 0.0)
			var a: Dictionary = reference.plan(source, tool, wall_center, settings)
			var b: Dictionary = Live.plan(source, wall_center)
			check(_signature(a.get("changes", [])) == _signature(b.get("changes", [])), "wall-facing live parity %s %s" % [tool, normal])
			source.cancel_stroke()

	source.terrain.free()
	source.free()
	reference.free()
	print("sculpt_live_next_layer_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _fixture(source: Node) -> void:
	source.voxels.fill(0, 0)
	source.voxels.fill_area(2, Vector3i.ZERO, Vector3i(48, 10, 48), 0)
	source.voxels.fill_area(2, Vector3i(23, 10, 23), Vector3i(25, 12, 25), 0)
	source.voxels.fill_area(0, Vector3i(25, 8, 24), Vector3i(27, 10, 26), 0)

func _signature(changes: Array) -> Array[String]:
	var result: Array[String] = []
	for value in changes:
		var change: Dictionary = value
		result.append("%s:%d" % [str(change.get("cell", Vector3i.ZERO)), int(change.get("after", -1))])
	result.sort()
	return result
