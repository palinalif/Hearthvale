extends "res://scripts/terrain_backend.gd"
## Read-only adapter over the real sculpt integrators. Never add to the tree.
## The preview gives each eligible column one cell of credit, not an invented
## end-of-stroke volume. Falloff still controls how soon that cell changes.
## Native voxel data is borrowed for reads only; all writes are intercepted.

const ColumnIndex = preload("res://scripts/sculpt_column_index.gd")

class ReadRegion extends RefCounted:
	var source: Object
	var origin: Vector3i
	func _init(buffer: Object, minimum: Vector3i) -> void:
		source = buffer
		origin = minimum
	func get_voxel(x: int, y: int, z: int, channel: int) -> int:
		return int(source.get_voxel(x + origin.x, y + origin.y, z + origin.z, channel))
	func set_voxel(_value: int, _x: int, _y: int, _z: int, _channel: int) -> void:
		pass

var _idle_key: Array = []
var _idle_fronts: Dictionary = {}
var _planned: Array[Dictionary] = []
var _weights: Dictionary = {}
var query_count := 0
var _add_count := 0
var _remove_count := 0
var last_query_ms := 0.0
var last_snapshot_bytes := 0
var _column_index: RefCounted
var _index_center := Vector3.ZERO
var _index_radius := 0.0
var _index_queries_enabled := false

func _ready() -> void:
	push_error("SculptNextLayer is a read-only query, not a live terrain node")

func plan(source: Node, tool: String, world_center: Vector3, settings: Dictionary, reference: Dictionary = {}) -> Dictionary:
	if source == null or not source.is_ready() or not world_center.is_finite():
		return {"valid": false, "changes": [], "rim": []}
	var started := Time.get_ticks_usec()
	query_count += 1
	_column_index = null
	_index_queries_enabled = false
	last_snapshot_bytes = 0
	_clear_stroke()
	_planned.clear()
	_weights.clear()
	patch_size = source.patch_size
	voxel_scale = source.voxel_scale
	voxels = source.voxels
	_backend_ready = true
	# Clone only ephemeral edit metadata. Never begin/cancel a real stroke,
	# touch its accumulators/history, or clone a 72 MiB terrain buffer.
	if bool(source.get("_stroke_active")):
		for property in ["_stroke_tool", "_stroke_settings", "_stroke_reference", "_stroke_normal", "_stroke_front_axis", "_stroke_front_sign", "_stroke_fronts", "_stroke_front_cache_center", "_stroke_front_columns", "_stroke_front_influence", "_smooth_targets", "_smooth_targets_dirty"]:
			var value = source.get(property)
			if value is Dictionary or value is Array or value is PackedFloat64Array:
				value = value.duplicate()
			set(property, value)
		_stroke_active = true
	elif not begin_stroke(tool, world_center, settings, reference):
		return {"valid": false, "changes": [], "rim": []}
	if _stroke_tool in [SCULPT_TOOL_LEVEL, SCULPT_TOOL_SLOPE, SCULPT_TOOL_SMOOTH]:
		_stroke_front_axis = 1
		_stroke_front_sign = 1
	var center := _world_to_cell(world_center)
	var radius: float = _stroke_settings["radius"]
	_index_center = center
	_index_radius = radius
	_index_queries_enabled = true
	var idle := not bool(source.get("_stroke_active"))
	if idle:
		var cache_key: Array = [voxels.get_instance_id(), source.get("_revision"), _stroke_tool, _stroke_front_axis, _stroke_front_sign, floori(center[_stroke_front_axis]), radius]
		if cache_key != _idle_key or _idle_fronts.size() > 20000:
			_idle_fronts.clear()
			_idle_key = cache_key
		_stroke_fronts = _idle_fronts.duplicate()
	# Zero time populates the exact frontier/targets without giving edit credit.
	_integrate_stroke_sample(center, 0.0)
	if idle: _idle_fronts = _stroke_fronts.duplicate()
	var columns: Array[Vector3i] = _stroke_front_columns
	var influences: PackedFloat64Array = _stroke_front_influence
	if _stroke_tool in [SCULPT_TOOL_LEVEL, SCULPT_TOOL_SLOPE]:
		columns = _vertical_columns(center, radius)
		influences = PackedFloat64Array()
		influences.resize(columns.size())
		for i in columns.size():
			influences[i] = pow(maxf(0.0, 1.0 - _column_distance(columns[i], center) / radius), lerpf(1.0, 4.0, float(_stroke_settings["falloff"])))
	var rim: Array[Vector3] = []
	var normal := Vector3.ZERO
	normal[_stroke_front_axis] = float(_stroke_front_sign)
	var nearest := world_center
	var nearest_distance := INF
	for i in columns.size():
		var column := columns[i]
		var distance := _column_distance(column, center)
		var surface := float(_stroke_fronts.get(column, -1.0))
		if surface < 0.0: continue
		var point := Vector3(_column_cell(column, int(surface))) + Vector3.ONE * 0.5
		var boundary := surface
		if _stroke_tool == SCULPT_TOOL_RAISE and _stroke_front_sign < 0: boundary += 1.0
		if _stroke_tool == SCULPT_TOOL_DIG and _stroke_front_sign > 0: boundary += 1.0
		point[_stroke_front_axis] = boundary
		point *= voxel_scale
		if distance < nearest_distance:
			nearest = point
			nearest_distance = distance
		if distance >= maxf(0.0, radius - 1.5): rim.append(point)
		if influences[i] <= 0.0: continue
		_weights[column] = influences[i]
		var credit := 1.0
		if _stroke_tool == SCULPT_TOOL_SMOOTH:
			credit = 1.0 if _smooth_targets[i] > surface else -1.0
		_stroke_accumulated[column] = credit
	_planned.clear()
	_add_count = 0
	_remove_count = 0
	_integrate_stroke_sample(center, 0.0)
	last_query_ms = (Time.get_ticks_usec() - started) / 1000.0
	return {"valid": true, "changes": _planned.duplicate(), "add_count": _add_count, "remove_count": _remove_count, "rim": rim, "normal": normal, "center": nearest, "cell_size": voxel_scale, "query_ms": last_query_ms}

func _clone_region(source: Object, region_min: Vector3i, _region_max: Vector3i) -> Object:
	return ReadRegion.new(source, region_min)

func _write_region(_local: Object, _region_min: Vector3i) -> void:
	pass

func _record_stroke_change(position: Vector3i, current: int, desired: int) -> void:
	if desired == 0: _remove_count += 1
	else: _add_count += 1
	var column := position
	column[_stroke_front_axis] = 0
	_planned.append({"cell": position, "before": current, "after": desired, "weight": float(_weights.get(column, 1.0))})

func _index() -> RefCounted:
	if _column_index != null: return _column_index
	var index := ColumnIndex.new()
	if not index.capture(voxels, patch_size, _index_center, _index_radius, _stroke_front_axis): return null
	_column_index = index
	last_snapshot_bytes = index.copied_bytes
	return index

func _ensure_front(column: Vector3i, center: Vector3) -> void:
	if _stroke_fronts.has(column): return
	var index := _index()
	if index == null:
		super._ensure_front(column, center)
		return
	# Same outward-first search and contiguous-front rule as TerrainBackend;
	# only replace the per-cell scan with native runs. Parity tests compare
	# these seeds against the unmodified backend in every direction.
	var coordinate := floori(center[_stroke_front_axis])
	var reach := ceili(float(_stroke_settings["radius"])) + 1
	var found: int = index.first(_column_cell(column, coordinate), _stroke_front_sign, reach, true)
	if found < 0:
		found = index.first(_column_cell(column, coordinate - _stroke_front_sign), -_stroke_front_sign, reach - 1, true)
	if found < 0:
		_stroke_fronts[column] = clampi(coordinate, 0, patch_size[_stroke_front_axis] - 1)
		return
	if _stroke_tool == SCULPT_TOOL_RAISE:
		var empty: int = index.first(_column_cell(column, found + _stroke_front_sign), _stroke_front_sign, patch_size[_stroke_front_axis], false)
		_stroke_fronts[column] = empty if empty >= 0 else (patch_size[_stroke_front_axis] if _stroke_front_sign > 0 else -1)
	else:
		_stroke_fronts[column] = found

func _surface_y_near(source: Object, x: int, z: int, center_y: float, reach: float) -> float:
	# Level and Smooth use vertical columns regardless of the reference mode.
	if not _index_queries_enabled or _stroke_front_axis != 1 or source != voxels:
		return super._surface_y_near(source, x, z, center_y, reach)
	if x < 0 or z < 0 or x >= patch_size.x or z >= patch_size.z: return -1.0
	var index := _index()
	if index == null: return super._surface_y_near(source, x, z, center_y, reach)
	var start := clampi(floori(center_y), 0, patch_size.y - 1)
	var limit := ceili(maxf(reach, 1.0))
	var solid := start
	if int(source.get_voxel(x, start, z, 0)) == 0:
		solid = index.first(Vector3i(x, start - 1, z), -1, limit - 1, true)
		if solid >= 0: return float(solid + 1)
		solid = index.first(Vector3i(x, start + 1, z), 1, limit - 1, true)
		if solid < 0: return -1.0
	var empty: int = index.first(Vector3i(x, solid + 1, z), 1, patch_size.y, false)
	return float(empty if empty >= 0 else patch_size.y)
