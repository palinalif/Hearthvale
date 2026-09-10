extends SceneTree

const Massing = preload("res://scripts/m2_house_massing.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	var base_view := {"dimensions": Vector3(10, 6, 8), "roof_profile": "gentle_gable"}
	var core: Array[Dictionary] = Massing.sections_for(base_view)
	check(core.size() == 1 and Massing.section_level(core[0]) == 0, "legacy rectangular house resolves to one ground-floor core section")
	check(Massing.floor_count(base_view) == 1, "legacy house remains one floor")

	var l_sections := Massing.preset_sections(base_view, "l_shape")
	var t_sections := Massing.preset_sections(base_view, "t_shape")
	var u_sections := Massing.preset_sections(base_view, "u_shape")
	check(l_sections.size() == 2, "L preset uses two connected masses")
	check(t_sections.size() == 2, "T preset uses a stem and crossbar")
	check(u_sections.size() == 3, "U preset uses a back mass and two arms")

	var l_view := base_view.duplicate(true)
	l_view["massing_sections"] = l_sections
	var l_faces := Massing.boundary_faces(l_view)
	var independent_face_count := 0
	for section in l_sections:
		var size: Vector3 = section["size"]
		independent_face_count += roundi((size.x * 2.0 + size.z * 2.0) / Massing.CELL)
	check(l_faces.size() < independent_face_count, "shared section walls disappear from the exterior perimeter")

	var field := Massing.occupancy(l_view)
	var roof := Massing.roof_tiles(l_view)
	check(not field.is_empty() and roof.size() == (field["cells"] as Dictionary).size(), "joined roof covers the union footprint exactly once")
	var min_height := INF
	var max_height := -INF
	for tile in roof:
		var center: Vector3 = tile["center"]
		min_height = minf(min_height, center.y)
		max_height = maxf(max_height, center.y)
	check(max_height - min_height >= Massing.CELL * 0.5, "joined roof field rises toward interior ridges")

	var existing := Massing.sections_for(base_view)
	var edge_candidate := {"id": "edge", "level": 0, "offset": Vector3(7, 0, 0), "size": Vector3(4, 6, 4)}
	var detached_candidate := {"id": "far", "level": 0, "offset": Vector3(14, 0, 0), "size": Vector3(4, 6, 4)}
	var corner_candidate := {"id": "corner", "level": 0, "offset": Vector3(7, 0, 6), "size": Vector3(4, 6, 4)}
	check(Massing.can_add_portion(existing, edge_candidate), "ground portion sharing a real wall is accepted")
	check(not Massing.can_add_portion(existing, detached_candidate), "detached ground portion is rejected")
	check(not Massing.can_add_portion(existing, corner_candidate), "corner-only contact is not considered a joined house")

	var upper := {"id": "upper", "level": 1, "offset": Vector3(0, 6, 0), "size": Vector3(6, 6, 4)}
	var unsupported_upper := {"id": "unsupported", "level": 1, "offset": Vector3(5, 6, 0), "size": Vector3(4, 6, 4)}
	check(Massing.can_add_portion(existing, upper), "supported second-floor portion is accepted")
	check(not Massing.can_add_portion(existing, unsupported_upper), "upper portion extending beyond support below is rejected")
	existing.append(upper)
	var second_upper := {"id": "upper-wing", "level": 1, "offset": Vector3(3, 6, 0), "size": Vector3(4, 6, 4)}
	check(Massing.can_add_portion(existing, second_upper), "second-floor portions can join into their own L/T-style floor shape")
	existing.append(second_upper)
	var third_floor := {"id": "tower", "level": 2, "offset": Vector3(-1, 12, 0), "size": Vector3(3, 6, 3)}
	check(Massing.can_add_portion(existing, third_floor), "third floor can stack on supported second-floor massing")

	var stacked_view := base_view.duplicate(true)
	stacked_view["massing_sections"] = existing
	check(Massing.floor_count(stacked_view) == 2, "partial upper massing reports two occupied floors")
	var stacked_field: Dictionary = Massing.occupancy(stacked_view)
	var height_values: Array = (stacked_field["cells"] as Dictionary).values()
	check(height_values.any(func(value): return is_equal_approx(float(value), 6.0)) and height_values.any(func(value): return is_equal_approx(float(value), 12.0)), "occupancy keeps both lower exposed roof level and upper wall top")
	var stacked_roof: Array[Dictionary] = Massing.roof_tiles(stacked_view)
	check(stacked_roof.any(func(tile): return is_equal_approx(float(tile.get("base_height", 0.0)), 6.0)) and stacked_roof.any(func(tile): return is_equal_approx(float(tile.get("base_height", 0.0)), 12.0)), "roof field generates separate lower and upper exposed roof plateaus")
	var stacked_faces: Array[Dictionary] = Massing.boundary_faces(stacked_view)
	check(stacked_faces.any(func(face): return is_equal_approx(float(face.get("bottom", 0.0)), 6.0) and is_equal_approx(float(face.get("height", 0.0)), 12.0)), "upper-storey exterior wall begins at the supported floor below")

	var three_floor_sections: Array[Dictionary] = existing.duplicate(true)
	three_floor_sections.append(third_floor)
	var three_floor_view := base_view.duplicate(true)
	three_floor_view["massing_sections"] = three_floor_sections
	check(Massing.floor_count(three_floor_view) == 3 and Massing.section_top(third_floor) == 18.0, "stacking supports a third storey with the expected top height")

	var serialized_sections: Array = []
	for section in three_floor_sections:
		var offset: Vector3 = section["offset"]
		var size: Vector3 = section["size"]
		serialized_sections.append({"id": section["id"], "level": Massing.section_level(section), "offset": [offset.x, offset.y, offset.z], "size": [size.x, size.y, size.z]})
	var serialized_view := {"dimensions": Vector3(10, 6, 8), "roof_profile": "gentle_gable", "massing_sections": serialized_sections}
	var restored: Array[Dictionary] = Massing.sections_for(serialized_view)
	check(restored.size() == three_floor_sections.size(), "JSON-style section records resolve back into massing geometry")
	check(Massing.max_level(restored) == 2 and is_equal_approx((restored[-1]["offset"] as Vector3).y, 12.0), "serialized floor level restores vertical section offset")

	print("m2_house_massing_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
