extends SceneTree

const Placement = preload("res://scripts/wall_attachment_placement.gd")
var failures := 0
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _init() -> void:
	var view := {"dimensions": Vector3(18, 7, 14), "surfaces": [
		{"id":"wall-front","kind":"wall","orientation":"front","deleted":false},
		{"id":"wall-back","kind":"wall","orientation":"back","deleted":false},
		{"id":"wall-left","kind":"wall","orientation":"left","deleted":false},
		{"id":"wall-right","kind":"wall","orientation":"right","deleted":false},
		{"id":"roof-left","kind":"roof","orientation":"left","deleted":false},
		{"id":"wall-deleted","kind":"wall","orientation":"front","deleted":true}
	]}
	check(Placement.wall_ids(view) == ["wall-front","wall-back","wall-left","wall-right"], "only live walls are placement supports")
	var box_footprint := Placement.footprint("flower_box")
	var front := Placement.clamp_to_wall(view, "wall-front", Vector3(99, 99, 99), box_footprint)
	var back := Placement.clamp_to_wall(view, "wall-back", Vector3.ZERO, box_footprint)
	var left := Placement.clamp_to_wall(view, "wall-left", Vector3.ZERO, box_footprint)
	var right := Placement.clamp_to_wall(view, "wall-right", Vector3.ZERO, box_footprint)
	check(not front.is_empty() and (front["position"] as Vector3).z < -7.0, "front attachment is outside front face")
	check(not back.is_empty() and (back["position"] as Vector3).z > 7.0, "back attachment is outside back face")
	check(not left.is_empty() and (left["position"] as Vector3).x < -9.0, "left attachment is outside left face")
	check(not right.is_empty() and (right["position"] as Vector3).x > 9.0, "right attachment is outside right face")
	check(is_equal_approx((front["position"] as Vector3).x, 8.2), "tangent clamps to wall footprint")
	check(is_equal_approx((front["position"] as Vector3).y, 6.8), "vertical movement clamps to wall footprint")
	check(Placement.clamp_to_wall(view, "wall-deleted", Vector3.ZERO, box_footprint).is_empty(), "deleted wall is rejected")
	check(Placement.clamp_to_wall(view, "roof-left", Vector3.ZERO, box_footprint).is_empty(), "roof is rejected for furniture")
	var quarter := Placement.clamp_to_wall(view, "wall-front", Vector3(4.1, 3.0, 0), box_footprint)
	var remapped := Placement.remap_between_walls(view, "wall-front", "wall-left", quarter["position"], box_footprint)
	var expected_ratio := 4.1 / 8.2
	var expected_z := expected_ratio * (7.0 - 0.8)
	check(not remapped.is_empty() and is_equal_approx((remapped["position"] as Vector3).z, expected_z), "wall cycling preserves relative horizontal placement")
	check(is_equal_approx((remapped["position"] as Vector3).y, 3.0), "wall cycling preserves height")
	print("wall_attachment_placement_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
