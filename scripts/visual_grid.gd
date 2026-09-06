extends RefCounted
class_name VisualGrid

## One visible cell edge in world units. Native terrain and
## derived asset steps share this edge; merged surfaces span integer cells.
const UNIT := 0.125

static func quantized_box(center: Vector3, size: Vector3, unit: Vector3) -> Dictionary:
	var low := (center - size * 0.5).snapped(unit)
	var high := (center + size * 0.5).snapped(unit).max(low + unit)
	return {"center": (low + high) * 0.5, "size": high - low}
