extends RefCounted

## Pure alignment math for cottage detail moves. It never changes support walls;
## it only suggests tangent/height coordinates near authored neighbours.

const SNAP_THRESHOLD := 0.42
const PRECISION_THRESHOLD := 0.16

static func align(view: Dictionary, detail_id: String, surface_id: String, position: Vector3, precision: bool = false) -> Dictionary:
	var orientation := ""
	for surface_value in view.get("surfaces", []):
		var surface: Dictionary = surface_value
		if str(surface.get("id", "")) == surface_id:
			orientation = str(surface.get("orientation", ""))
			break
	if orientation not in ["front", "back", "left", "right"]:
		return {"position": position, "tangent": false, "height": false}
	var threshold := PRECISION_THRESHOLD if precision else SNAP_THRESHOLD
	var tangent_axis := 0 if orientation in ["front", "back"] else 2
	var result := position
	var best_tangent := threshold + 0.001
	var best_height := threshold + 0.001
	var tangent_source := ""
	var height_source := ""
	for detail_value in view.get("details", []):
		var other: Dictionary = detail_value
		if str(other.get("id", "")) == detail_id or not bool(other.get("visible", true)) or bool(other.get("needs_placement", false)):
			continue
		if str(other.get("anchor", {}).get("surface_id", "")) != surface_id:
			continue
		var other_position = other.get("resolved_position", null)
		if not other_position is Vector3:
			continue
		var tangent_delta := absf(position[tangent_axis] - (other_position as Vector3)[tangent_axis])
		if tangent_delta < best_tangent:
			best_tangent = tangent_delta
			result[tangent_axis] = (other_position as Vector3)[tangent_axis]
			tangent_source = str(other.get("id", ""))
		var height_delta := absf(position.y - (other_position as Vector3).y)
		if height_delta < best_height:
			best_height = height_delta
			result.y = (other_position as Vector3).y
			height_source = str(other.get("id", ""))
	return {
		"position": result,
		"tangent": best_tangent <= threshold,
		"height": best_height <= threshold,
		"tangent_source": tangent_source if best_tangent <= threshold else "",
		"height_source": height_source if best_height <= threshold else "",
	}
