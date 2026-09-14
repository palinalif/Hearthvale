extends RefCounted
## Clamp the physical camera to the native map without translating the subject.
## Kept separate from map generation so loaded worlds use their actual extent.
const DEFAULT_EXTENT := Vector3(64.0, 32.0, 64.0)
const EDGE_MARGIN := 0.25

static func frame(target: Vector3, offset: Vector3, extent: Vector3) -> Dictionary:
	if not extent.is_finite() or extent.x <= 0.0 or extent.z <= 0.0:
		extent = DEFAULT_EXTENT
	if not target.is_finite():
		target = Vector3(extent.x * 0.5, 8.0, extent.z * 0.5)
	if not offset.is_finite():
		offset = Vector3(0.0, 8.0, 0.0)
	# Do not translate an in-bounds focus: building edit cameras must continue
	# looking at the selected home, and terrain cursors can reach the last cell.
	target.x = clampf(target.x, 0.0, extent.x)
	target.z = clampf(target.z, 0.0, extent.z)
	var margin := minf(EDGE_MARGIN, minf(extent.x, extent.z) * 0.1)
	var position := target + offset
	position.x = clampf(position.x, margin, extent.x - margin)
	position.z = clampf(position.z, margin, extent.z - margin)
	# Avoid a degenerate look_at for invalid restored or synthetic camera states.
	if position.distance_squared_to(target) < 0.000001:
		position.y = target.y + 0.25
	return {"target": target, "position": position}
