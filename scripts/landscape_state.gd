extends RefCounted
class_name LandscapeState

const LIMIT := 320
const TREE_LIMIT := 24
var records: Array = []
var next_id := 1

func document() -> Dictionary:
	return {"version": 1, "next_id": next_id, "records": records.duplicate(true)}

static func validate(value: Dictionary) -> bool:
	if not _integer(value.get("version", null)) or int(value["version"]) != 1 or not value.get("records", null) is Array: return false
	if value["records"].size() > LIMIT or not _integer(value.get("next_id", null)) or int(value["next_id"]) < 1: return false
	var ids := {}
	var trees := 0
	for record in value["records"]:
		if not record is Dictionary: return false
		if not str(record.get("kind", "")) in ["tree", "foliage", "rock"]: return false
		if not _integer(record.get("seed", null)) or not _integer(record.get("id", null)): return false
		var id := int(record.get("id", 0))
		if id < 1 or id >= int(value["next_id"]) or ids.has(id): return false
		ids[id] = true
		var p = record.get("position", null)
		if not p is Array or p.size() != 3: return false
		for number in p:
			if not (number is float or number is int) or not is_finite(float(number)): return false
		if float(p[0]) < 0 or float(p[0]) > 48 or float(p[2]) < 0 or float(p[2]) > 48 or float(p[1]) < 0 or float(p[1]) > 32: return false
		if record["kind"] == "tree": trees += 1
	return trees <= TREE_LIMIT

func restore(value: Dictionary) -> bool:
	if not validate(value): return false
	records = value["records"].duplicate(true)
	next_id = int(value["next_id"])
	return true

static func position_of(record: Dictionary) -> Vector3:
	var p: Array = record["position"]
	return Vector3(p[0], p[1], p[2])

func add(kind: String, point: Vector3, seed_value: int) -> bool:
	if not kind in ["tree", "foliage", "rock"] or records.size() >= LIMIT or not point.is_finite() or point.y <= 5.05 or point.y > 32 or point.x < 0 or point.x > 48 or point.z < 0 or point.z > 48: return false
	var trees := 0
	for other in records:
		if other["kind"] == "tree": trees += 1
		var separation := 2.8 if kind == "tree" and other["kind"] == "tree" else (0.5 if kind == "foliage" else 0.8)
		if Vector2(point.x, point.z).distance_to(Vector2(other["position"][0], other["position"][2])) < separation: return false
	if kind == "tree" and trees >= TREE_LIMIT: return false
	records.append({"id": next_id, "kind": kind, "position": [point.x, point.y, point.z], "seed": seed_value})
	next_id += 1
	return true

func erase_brush(point: Vector3, radius: float) -> bool:
	var kept: Array = []
	for record in records:
		var p := position_of(record)
		if Vector2(p.x, p.z).distance_to(Vector2(point.x, point.z)) > radius or absf(p.y - point.y) > 3.0: kept.append(record)
	var changed := kept.size() != records.size()
	records = kept
	return changed

func clear_edited_cells(cells: Array, cell_size: float) -> bool:
	# Roots intersect changed native cells, not the enclosing stroke rectangle.
	var lookup := {}
	for point: Vector3 in cells: lookup[Vector3i(floor(point / cell_size))] = true
	var kept: Array = []
	for record in records:
		var p := position_of(record)
		var root_cell := Vector3i(floor(p / cell_size))
		var reach := 2 if record["kind"] == "tree" else 1
		var affected := false
		for x in range(-reach, reach + 1):
			for z in range(-reach, reach + 1):
				for y in range(-1, 2):
					if lookup.has(root_cell + Vector3i(x, y, z)): affected = true
		if not affected: kept.append(record)
	var changed := kept.size() != records.size()
	records = kept
	return changed

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and absf(float(value)) <= 1000000000.0
