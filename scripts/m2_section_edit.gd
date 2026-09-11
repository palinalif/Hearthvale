extends RefCounted

## Read-only section-edit math. Scene owns modal state; BuildingWorld owns
## the final transaction. A section keeps its ID and storey during edits.
const Massing = preload("res://scripts/m2_house_massing.gd")
const EDGES := ["left", "right", "front", "back"]

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
