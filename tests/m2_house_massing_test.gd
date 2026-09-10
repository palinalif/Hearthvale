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
	var core := Massing.sections_for(base_view)
	check(core.size() == 1, "legacy rectangular house resolves to one core section")

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
	var edge_candidate := {"id": "edge", "offset": Vector3(7, 0, 0), "size": Vector3(4, 6, 4)}
	var detached_candidate := {"id": "far", "offset": Vector3(14, 0, 0), "size": Vector3(4, 6, 4)}
	var corner_candidate := {"id": "corner", "offset": Vector3(7, 0, 6), "size": Vector3(4, 6, 4)}
	check(Massing.can_add_portion(existing, edge_candidate), "portion sharing a real wall is accepted")
	check(not Massing.can_add_portion(existing, detached_candidate), "detached portion is rejected")
	check(not Massing.can_add_portion(existing, corner_candidate), "corner-only contact is not considered a joined house")

	var serialized_sections: Array = []
	for section in l_sections:
		var offset: Vector3 = section["offset"]
		var size: Vector3 = section["size"]
		serialized_sections.append({"id": section["id"], "offset": [offset.x, offset.y, offset.z], "size": [size.x, size.y, size.z]})
	var serialized_view := {"dimensions": Vector3(10, 6, 8), "roof_profile": "gentle_gable", "massing_sections": serialized_sections}
	check(Massing.sections_for(serialized_view).size() == 2, "JSON-style section records resolve back into massing geometry")

	print("m2_house_massing_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
