extends RefCounted

## Read-only section-edit math. Scene owns modal state; BuildingWorld owns
## the final transaction. A section keeps its ID and storey during edits.
const Massing = preload("res://scripts/m2_house_massing.gd")
const EDGES := ["left", "right", "front", "back"]

# The local axis the named edge moves along, and the sign of that edge
# relative to the section centre. left/front are the -axis edges, and a
# resize always moves the named edge while the opposite edge stays fixed.
static func edge_axis(edge: String) -> int:
	return 0 if edge == "left" or edge == "right" else 2


static func edge_sign(edge: String) -> float:
	return -1.0 if edge == "left" or edge == "front" else 1.0


# The pointer-driven amount for a named edge, in resize_edge units (a hit at
# the centre is a half-size amount; hits past the face grow the section).
# The camera ray is swept across a plane that faces the camera and passes
# through the edge's own face: the hit's section coordinate is where the
# face should land, so the opposite edge stays fixed. Passing the plane
# through the face (not the centre) keeps the mapping accurate when the
# camera views the section obliquely: on a centre plane the hit mixes the
# dragged axis with the other horizontal one, so a pointer at the handle
# reads far from the face. INF means the ray does not cross the plane
# (parallel or behind the camera), so callers keep the last candidate.
static func drag_amount(view: Dictionary, item: Dictionary, edge: String, origin: Vector3, direction: Vector3) -> float:
	var transform_value = view.get("transform", Transform3D.IDENTITY)
	var transform: Transform3D = transform_value if transform_value is Transform3D else Transform3D.IDENTITY
	var size: Vector3 = item["size"]
	var offset: Vector3 = item["offset"]
	var axis := edge_axis(edge)
	var sign := edge_sign(edge)
	# The section `offset` is its centre in x/z (see `Massing.section_rect`),
	# so the dragged face sits at offset[axis] +/- size[axis] / 2.
	var face := offset[axis] + sign * size[axis] * 0.5
	var face_point := offset
	face_point[axis] = face
	face_point.y = offset.y + size.y * 0.5
	var plane_point := transform * face_point
	var normal := (plane_point - origin).normalized()
	var denom := direction.dot(normal)
	if absf(denom) < 0.00001:
		return INF
	var t := (plane_point - origin).dot(normal) / denom
	if t <= 0.0:
		return INF
	var local := transform.affine_inverse() * (origin + direction * t)
	return sign * (local[axis] - face)


static func section(view: Dictionary, id: String) -> Dictionary:
	for item in Massing.sections_for(view):
		if str(item["id"]) == id: return item.duplicate(true)
	return {}

static func resize_edge(original: Dictionary, edge: String, amount: float) -> Dictionary:
	if original.is_empty() or edge not in EDGES or not is_finite(amount): return {}
	var result: Dictionary = original.duplicate(true)
	var size: Vector3 = result["size"]
	var offset: Vector3 = result["offset"]
	var axis := 0 if edge in ["left", "right"] else 2
	var sign_value := -1.0 if edge in ["left", "front"] else 1.0
	# A full local unit keeps both the centre and dimensions on Massing.CELL.
	var requested := snappedf(amount, Massing.CELL * 2.0)
	var main := str(original.get("id", "")) == "core"
	var next := clampf(size[axis] + requested, 4.0 if main else Massing.MIN_PORTION_SIZE, 32.0 if main else Massing.MAX_PORTION_SIZE)
	offset[axis] += sign_value * (next - size[axis]) * 0.5
	size[axis] = next
	result["size"] = size
	result["offset"] = offset
	return result

static func replacement(view: Dictionary, id: String, candidate: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = Massing.sections_for(view)
	for index in result.size():
		if str(result[index]["id"]) == id:
			result[index] = candidate.duplicate(true)
			return result
	return []

static func invalid_reason(view: Dictionary, id: String, candidate: Dictionary) -> String:
	var original := section(view, id)
	if original.is_empty() or candidate.is_empty() or str(candidate.get("id", "")) != id: return "Section no longer exists"
	if Massing.section_level(original) != Massing.section_level(candidate): return "Cannot change a section's floor"
	var size: Vector3 = candidate.get("size", Vector3.ZERO)
	var position: Vector3 = candidate.get("offset", Vector3.ZERO)
	if not size.is_finite() or not position.is_finite(): return "Invalid section dimensions"
	if size.y != (original["size"] as Vector3).y: return "Keep the existing floor height"
	var main := id == "core"
	if minf(size.x, size.z) < (4.0 if main else Massing.MIN_PORTION_SIZE) or maxf(size.x, size.z) > (32.0 if main else Massing.MAX_PORTION_SIZE): return "Section is too small or too large"
	var all_sections := replacement(view, id, candidate)
	# Validate every upper section, not just the edited floor. Shrinking a
	# lower wing must not leave a different section suspended above it.
	for item in all_sections:
		var level := Massing.section_level(item)
		if level > 0 and not Massing._is_supported_by_level(all_sections, Massing.section_rect(item), level - 1):
			return "Floor %d needs support below" % (level + 1)
	var ground := Massing.sections_on_level(all_sections, 0)
	var reached: Dictionary = {}
	if not ground.is_empty(): reached[str(ground[0]["id"])] = true
	for pass_index in ground.size():
		for item in ground:
			if reached.has(str(item["id"])): continue
			for other in ground:
				if reached.has(str(other["id"])) and Massing._rects_join(Massing.section_rect(item), Massing.section_rect(other)):
					reached[str(item["id"])] = true
					break
	if reached.size() != ground.size(): return "Keep the ground-floor sections connected"
	return ""
