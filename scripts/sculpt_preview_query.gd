extends "res://scripts/sculpt_next_layer.gd"
## Keep all actual edit decisions in the original integrators. Only their
## read-only seeding probes are accelerated, on an isolated worker snapshot.
const Runs = preload("res://scripts/sculpt_occupancy_runs.gd")
var _runs: RefCounted

func plan(source: Object, tool: String, world_center: Vector3, settings: Dictionary, reference: Dictionary = {}) -> Dictionary:
	_runs = null
	if source == null or not source.is_ready() or not world_center.is_finite(): return {"valid": false}
	var active := bool(source.get("_stroke_active"))
	var effective_tool := String(source.get("_stroke_tool")) if active else _normalize_sculpt_tool(tool)
	var axis := int(source.get("_stroke_front_axis")) if active else _dominant_axis(_settings_normal(settings))
	if effective_tool in ["level", "slope", "smooth"]: axis = 1
	var started := Time.get_ticks_usec()
	var runs := Runs.new()
	if runs.build(source.voxels.buffer, source.voxels.origin, axis): _runs = runs
	var result: Dictionary = super.plan(source, tool, world_center, settings, reference)
	last_query_ms = (Time.get_ticks_usec() - started) / 1000.0
	result["query_ms"] = last_query_ms
	return result

func _ensure_front(column: Vector3i, center: Vector3) -> void:
	if _runs == null:
		super._ensure_front(column, center)
		return
	if _stroke_fronts.has(column): return
	var coordinate := floori(center[_stroke_front_axis])
	var limit := patch_size[_stroke_front_axis]
	var reach := ceili(float(_stroke_settings["radius"])) + 1
	var found := int(_runs.first(_column_cell(column, coordinate), _stroke_front_sign, reach, true))
	if found < 0:
		found = int(_runs.first(_column_cell(column, coordinate - _stroke_front_sign), -_stroke_front_sign, reach - 1, true))
	if found < 0:
		_stroke_fronts[column] = clampi(coordinate, 0, limit - 1)
	elif _stroke_tool == SCULPT_TOOL_RAISE:
		# Native seeding walks to the exposed end of this contiguous mass;
		# never bridge an intervening void to the next disconnected mass.
		var air := int(_runs.first(_column_cell(column, found + _stroke_front_sign), _stroke_front_sign, limit, false))
		_stroke_fronts[column] = air if air >= 0 else (limit if _stroke_front_sign > 0 else -1)
	else:
		_stroke_fronts[column] = found

func _surface_y_near(source: Object, x: int, z: int, center_y: float, reach: float) -> float:
	if _runs == null or _runs.axis != 1: return super._surface_y_near(source, x, z, center_y, reach)
	if x < 0 or z < 0 or x >= patch_size.x or z >= patch_size.z: return -1.0
	var start := clampi(floori(center_y), 0, patch_size.y - 1)
	var limit := ceili(maxf(reach, 1.0))
	var found := start
	if int(source.get_voxel(x, start, z, 0)) == 0:
		found = int(_runs.first(Vector3i(x, start - 1, z), -1, limit - 1, true))
		if found >= 0: return float(found + 1)
		found = int(_runs.first(Vector3i(x, start + 1, z), 1, limit - 1, true))
		if found < 0: return -1.0
	var air := int(_runs.first(Vector3i(x, found, z), 1, patch_size.y, false))
	return float(air) if air >= 0 else float(patch_size.y)
