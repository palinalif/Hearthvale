extends RefCounted
class_name VisualGrid

## Structural visible cell edge. Merged surfaces span integer cubic cells.
const UNIT := 0.125
## Derived cottage roof tiles/edges, joinery, shutters, trim and planters only.
const COTTAGE_DETAIL_UNIT := UNIT * 0.5

static func quantized_box(center: Vector3, size: Vector3, unit: Vector3) -> Dictionary:
	var low := (center - size * 0.5).snapped(unit)
	var high := (center + size * 0.5).snapped(unit).max(low + unit)
	return {"center": (low + high) * 0.5, "size": high - low}
