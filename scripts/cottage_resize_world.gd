extends "res://scripts/building_world.gd"
## One-sided bounds editing on the existing authoritative model. Same schema,
## generation, identities, history and recovery; no second source of truth.

func preview_handle_resize(building_id: String, dimensions: Vector3, sides: Vector3, expected_revision: int) -> Dictionary:
	if expected_revision != get_revision() or not _valid_dimensions(dimensions): return {}
	if not _valid_handle_sides(sides): return {}
	var index := _building_index(building_id)
	if index < 0: return {}
	var recipe: Dictionary = _copy(_document["buildings"][index])
	var original := _as_vec(recipe["dimensions"])
	for axis in 3:
		if is_zero_approx(sides[axis]) and not is_equal_approx(original[axis], dimensions[axis]): return {}
	var shift := Vector3((dimensions.x - original.x) * sides.x * 0.5, 0.0, (dimensions.z - original.z) * sides.z * 0.5)
	var transform_value := _as_transform(recipe["transform"])
	var saved_transform: Dictionary = recipe["transform"]
	saved_transform["position"] = _vec(transform_value.origin + transform_value.basis * shift)
	recipe["dimensions"] = _vec(dimensions)
	# A local origin moves when only one edge moves. Rebase authored positions
	# along their wall; its normal is still resolved against that SAME wall.
	# This includes moved-then-suppressed exclusion positions and orphan records.
	for value in recipe["details"]:
		var detail: Dictionary = value
		var anchor: Dictionary = detail.get("anchor", {})
		if str(anchor.get("policy", "")) not in ["surface_local", "fixed_local"]: continue
		var position := _as_vec(anchor["local_position"]) - shift
		anchor["local_position"] = _vec(position)
		var overrides: Dictionary = detail.get("override", {})
		if overrides.has("local_position"): overrides["local_position"] = _vec(position)
	_reflow_automatic_windows(recipe)
	_refresh_buckets(recipe)
	var view := _resolved_building(recipe)
	var needs: Array[String] = []
	for detail in view["details"]:
		if bool(detail.get("needs_placement", false)): needs.append(str(detail["id"]))
	return {"recipe": recipe, "view": view, "needs_placement": needs, "revision": get_revision()}

func commit_handle_resize(building_id: String, dimensions: Vector3, sides: Vector3, expected_revision: int) -> bool:
	var preview := preview_handle_resize(building_id, dimensions, sides, expected_revision)
	if preview.is_empty(): return false
	var index := _building_index(building_id)
	if _as_vec(_document["buildings"][index]["dimensions"]).is_equal_approx(dimensions): return false
	var before: Dictionary = _copy(_document)
	_document["buildings"][index] = preview["recipe"]
	return _record_change(before)

static func _valid_handle_sides(sides: Vector3) -> bool:
	if sides == Vector3.UP: return true
	return sides.y == 0.0 and sides != Vector3.ZERO and sides.x in [-1.0, 0.0, 1.0] and sides.z in [-1.0, 0.0, 1.0]

static func handle_dimensions(original: Vector3, requested: Vector3, world_scale: Vector3, sides: Vector3, precision: bool) -> Vector3:
	# A one-sided width/depth change uses paired visible cells: the moving
	# origin then advances by a whole cell, preserving the existing renderer's
	# grid phase and manually placed window centres. Height keeps the base fixed.
	var steps := Vector3(0.25 / world_scale.x, 0.125 / world_scale.y, 0.25 / world_scale.z)
	if not precision: steps *= 2.0
	var result := original
	for axis in 3:
		if is_zero_approx(sides[axis]): continue
		var lower := ceili((MIN_DIMENSIONS[axis] - original[axis]) / steps[axis])
		var upper := floori((MAX_DIMENSIONS[axis] - original[axis]) / steps[axis])
		var cells := clampi(roundi((requested[axis] - original[axis]) / steps[axis]), lower, upper)
		result[axis] = original[axis] + cells * steps[axis]
	return result

func move_building(building_id: String, origin: Vector3, expected_revision: int) -> bool:
	var view := get_building(building_id)
	if view.is_empty(): return false
	var target: Transform3D = view["transform"]
	target.origin = origin
	return move_building_transform(building_id, target, expected_revision)

func move_building_transform(building_id: String, target: Transform3D, expected_revision: int) -> bool:
	# Transform the existing record atomically. IDs, local anchors, suppressions,
	# material choices and all other cottages remain byte-for-byte unchanged.
	if expected_revision != get_revision() or not target.origin.is_finite(): return false
	var index := _building_index(building_id)
	if index < 0: return false
	var recipe: Dictionary = _document["buildings"][index]
	var transform_data: Dictionary = recipe["transform"]
	var encoded := _transform_from_transform(target, target.origin)
	if not _valid_transform_data(encoded): return false
	if _as_transform(transform_data).is_equal_approx(target): return false
	var before: Dictionary = _copy(_document)
	recipe["transform"] = encoded
	return _record_change(before)
