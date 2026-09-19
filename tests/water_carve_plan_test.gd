extends SceneTree
## Locks the pure carve plan (river slice 4a): the river/lake tool preview math
## — which cells are lowered to the bed level and which shore cells are banks.
## Headless, deterministic, no native module.

const Plan = preload("res://scripts/water_carve_plan.gd")
const Geometry = preload("res://scripts/water_region_geometry.gd")

var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _flat_sampler(height: float) -> Callable:
	return func(_p: Vector2) -> float: return height

func _whole_lake(level: float) -> Dictionary:
	return {"id": 1, "type": "lake", "level": level, "points": [[0.0, 0.0], [5.0, 0.0], [5.0, 5.0], [0.0, 5.0]]}

func _initialize() -> void:
	var world := 64.0

	# bed depth per type
	check(is_equal_approx(Plan.bed_depth(_whole_lake(3.0)), 0.75), "lake bed depth 0.75")
	check(is_equal_approx(Plan.bed_depth({"type": "stream", "level": 3.0, "width": 1.0, "flow": [1, 0], "points": [[0, 0], [5, 0]]}), 0.4), "stream bed depth 0.4")

	# flat floor below level: everything in the footprint carved to the bed, no banks
	var p1 := Plan.plan(_whole_lake(1.5), _flat_sampler(1.0), world)
	check(is_equal_approx(p1["bed_level"], 0.75), "bed level = level - 0.75")
	check(p1["cells"] > 1500, "footprint covers the floor (cells=%d)" % p1["cells"])
	check((p1["bed"] as Array).size() == p1["cells"], "all floor cells carved to bed (bed=%d)" % (p1["bed"] as Array).size())
	check((p1["banks"] as Array).is_empty(), "no banks when surroundings are below the level")

	# flat floor above level: carved + shore ring is banks
	var p2 := Plan.plan(_whole_lake(1.5), _flat_sampler(2.0), world)
	check((p2["bed"] as Array).size() == p2["cells"], "floor above level fully carved")
	check((p2["banks"] as Array).size() > 0, "shore ring produces banks (banks=%d)" % (p2["banks"] as Array).size())

	# deep floor already below the bed level: nothing to carve
	var p3 := Plan.plan(_whole_lake(1.5), _flat_sampler(0.2), world)
	check((p3["bed"] as Array).is_empty(), "deep floor is not re-carved")

	# determinism
	var a := Plan.plan(_whole_lake(1.5), _flat_sampler(2.0), world)
	var b := Plan.plan(_whole_lake(1.5), _flat_sampler(2.0), world)
	check(_digest(a) == _digest(b), "plan is deterministic")

	# stream: stroke footprint carved to the shallower stream bed
	var stream := {"id": 2, "type": "stream", "level": 1.5, "width": 1.0, "flow": [1.0, 0.0], "points": [[0.5, 2.5], [4.5, 2.5]]}
	var ps := Plan.plan(stream, _flat_sampler(2.0), world)
	check((ps["bed"] as Array).size() == ps["cells"] and ps["cells"] > 0, "stream footprint carved (bed=%d cells=%d)" % [(ps["bed"] as Array).size(), ps["cells"]])
	check(is_equal_approx(ps["bed_level"], 1.1), "stream bed level = 1.5 - 0.4")

	print("water_carve_plan_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _digest(plan: Dictionary) -> String:
	var text := ""
	for entry: Array in plan["bed"]:
		text += "b%d,%d;" % [entry[0].x, entry[0].y]
	for cell: Vector2i in plan["banks"]:
		text += "n%d,%d;" % [cell.x, cell.y]
	return text
