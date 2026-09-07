extends RefCounted
## Exact next-layer preview for an already-active sculpt stroke. The live
## backend has already done the expensive surface/frontier discovery for the
## current sample; this reads that state and predicts one eligible cell per
## column without replaying the integrator or mutating terrain.
const SmoothNeighbourhood = preload("res://scripts/smooth_neighbourhood.gd")

static func plan(source: Object, world_center: Vector3) -> Dictionary:
	if source == null or not bool(source.get("_stroke_active")) or not world_center.is_finite():
		return {}
	var started := Time.get_ticks_usec()
	var tool := String(source.get("_stroke_tool"))
	var settings: Dictionary = source.get("_stroke_settings")
	var fronts: Dictionary = source.get("_stroke_fronts")
	var axis := int(source.get("_stroke_front_axis"))
	var sign := int(source.get("_stroke_front_sign"))
	var voxel_scale := float(source.get("voxel_scale"))
	if voxel_scale <= 0.0:
		return {}
	var center := world_center / voxel_scale
	var radius := float(settings.get("radius", 0.0))
	if radius <= 0.0:
		return {}
	var material := int(settings.get("material", 2))
	var columns: Array[Vector3i] = []
	var influences := PackedFloat64Array()
	var smooth_targets := PackedFloat64Array()
	if tool in ["raise", "dig", "smooth"]:
		columns.assign(source.get("_stroke_front_columns"))
		influences = source.get("_stroke_front_influence").duplicate()
	else:
		columns = source._vertical_columns(center, radius)
		influences.resize(columns.size())
		var exponent := lerpf(1.0, 4.0, float(settings.get("falloff", 0.45)))
		for i in columns.size():
			var distance := Vector2(float(columns[i].x) - center.x, float(columns[i].z) - center.z).length()
			influences[i] = pow(maxf(0.0, 1.0 - distance / radius), exponent)
	if columns.is_empty() or influences.size() != columns.size():
		return {}
	if tool == "smooth":
		if bool(source.get("_smooth_targets_dirty")):
			smooth_targets = SmoothNeighbourhood.means(columns, fronts)
		else:
			smooth_targets = source.get("_smooth_targets").duplicate()
		if smooth_targets.size() != columns.size():
			return {}
	var changes: Array[Dictionary] = []
	var rim: Array[Vector3] = []
	var add_count := 0
	var remove_count := 0
	var normal := Vector3.ZERO
	normal[axis] = float(sign)
	if tool in ["level", "slope", "smooth"]:
		normal = Vector3.UP
	var nearest := world_center
	var nearest_distance := INF
	for i in columns.size():
		var column := columns[i]
		var surface := float(fronts.get(column, -1.0))
		if surface < 0.0:
			continue
		var distance := _column_distance(column, center, axis)
		var point := Vector3(_column_cell(column, int(surface), axis)) + Vector3.ONE * 0.5
		var boundary := surface
		if tool == "raise" and sign < 0: boundary += 1.0
		if tool == "dig" and sign > 0: boundary += 1.0
		point[axis] = boundary
		point *= voxel_scale
		if distance < nearest_distance:
			nearest = point
			nearest_distance = distance
		if distance >= maxf(0.0, radius - 1.5):
			rim.append(point)
		var weight := influences[i]
		if weight <= 0.0:
			continue
		var candidate := Vector3i.ZERO
		var desired := -1
		if tool == "raise":
			candidate = _column_cell(column, int(surface), axis)
			desired = material
		elif tool == "dig":
			candidate = _column_cell(column, int(surface), axis)
			desired = 0
		elif tool == "smooth":
			var difference := smooth_targets[i] - surface
			if absf(difference) <= 0.500001:
				continue
			var direction := 1 if difference > 0.0 else -1
			candidate = Vector3i(column.x, int(surface) - (1 if direction < 0 else 0), column.z)
			desired = material if direction > 0 else 0
		else:
			var probe := Vector3i(column.x, int(surface), column.z)
			var target_y := _target_height(tool, source.get("_stroke_reference"), probe, center)
			if target_y > surface + 0.5:
				candidate = probe
				desired = material
			elif target_y < surface - 0.5:
				candidate = Vector3i(column.x, int(surface) - 1, column.z)
				desired = 0
			else:
				continue
		if candidate.x < 0 or candidate.y < 0 or candidate.z < 0 or candidate.x >= source.patch_size.x or candidate.y >= source.patch_size.y or candidate.z >= source.patch_size.z:
			continue
		# The frontier is authoritative for occupancy here: Raise points at the
		# next air cell; Dig/removal points at the current connected solid cell.
		# Level/Slope/Smooth use the same exposed boundary invariant. Avoid one
		# GDScript->native voxel lookup per displayed cell.
		changes.append({"cell": candidate, "after": desired, "weight": weight})
		if desired == 0: remove_count += 1
		else: add_count += 1
	return {"valid": true, "changes": changes, "add_count": add_count, "remove_count": remove_count, "rim": rim, "normal": normal, "center": nearest, "cell_size": voxel_scale, "query_ms": (Time.get_ticks_usec() - started) / 1000.0, "live_frontier": true}

static func _column_cell(column: Vector3i, coordinate: int, axis: int) -> Vector3i:
	if axis == 0: return Vector3i(coordinate, column.y, column.z)
	if axis == 1: return Vector3i(column.x, coordinate, column.z)
	return Vector3i(column.x, column.y, coordinate)

static func _column_distance(column: Vector3i, center: Vector3, axis: int) -> float:
	if axis == 1: return Vector2(float(column.x) - center.x, float(column.z) - center.z).length()
	if axis == 0: return Vector2(float(column.y) - center.y, float(column.z) - center.z).length()
	return Vector2(float(column.x) - center.x, float(column.y) - center.y).length()

static func _target_height(tool: String, reference: Dictionary, position: Vector3i, center: Vector3) -> float:
	if tool == "level":
		var level_point: Vector3 = reference.get("point", center)
		return level_point.y
	var point: Vector3 = reference.get("point", center)
	return point.y + float(reference.get("slope_x", 0.0)) * (float(position.x) - point.x) + float(reference.get("slope_z", 0.0)) * (float(position.z) - point.z)
