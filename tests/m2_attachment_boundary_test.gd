extends SceneTree

const World = preload("res://scripts/m2_building_world.gd")
const Placement = preload("res://scripts/wall_attachment_placement.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	var world := World.new()
	var buildings: Array = world.get_document().get("buildings", [])
	check(not buildings.is_empty(), "boundary fixture has a starter building")
	if buildings.is_empty():
		_finish()
		return
	var base: Dictionary = buildings[0]
	var view: Dictionary = world.get_building(str(base.get("id", "")))
	var view_ready: bool = not view.is_empty() and view.get("dimensions") is Vector3 and view.get("surfaces", []) is Array
	check(view_ready, "boundary fixture resolves starter building geometry")
	if not view_ready:
		_finish()
		return
	var dimensions: Vector3 = view["dimensions"]
	var cases: Array[Dictionary] = [
		{"kind": "shutter", "asset_id": "shutter_wood"},
		{"kind": "flower_box", "asset_id": "flower_box_wood"},
		{"kind": "window", "asset_id": "window_wood"},
		{"kind": "window", "asset_id": "window_round"},
		{"kind": "door", "asset_id": "door_timber"},
	]
	for upper in [false, true]:
		for source in view["surfaces"]:
			if str(source.get("kind", "")) != "wall" or bool(source.get("deleted", false)): continue
			var support: Dictionary = source.duplicate(true)
			var geometry := Placement.wall_geometry(view, support)
			var geometry_ready: bool = not geometry.is_empty() and geometry.has("bottom") and geometry.has("top") and support.has("id") and support.has("orientation")
			check(geometry_ready, "wall boundary fixture resolves geometry")
			if not geometry_ready: continue
			if upper:
				support.merge(geometry, true)
				support["massing_wall"] = true
				support["massing_level"] = 1
				support["bottom"] = dimensions.y
				support["top"] = dimensions.y * 2.0
			var fixture: Dictionary = base.duplicate(true)
			fixture["surfaces"] = [support]
			var placement_view := {"dimensions": dimensions, "surfaces": [support], "details": []}
			geometry = Placement.wall_geometry(placement_view, support)
			if geometry.is_empty() or not geometry.has("bottom") or not geometry.has("top"):
				check(false, "placement wall fixture resolves geometry")
				continue
			var axis := 0 if str(support["orientation"]) in ["front", "back"] else 2
			for spec in cases:
				var half := Placement.footprint_for_detail(spec)
				var middle := Vector3.ZERO
				middle.y = (float(geometry["bottom"]) + float(geometry["top"])) * 0.5
				for edge in ["top", "bottom", "left", "right"]:
					var direction := Vector3.ZERO
					if edge in ["top", "bottom"]: direction.y = 1.0 if edge == "top" else -1.0
					else: direction[axis] = 1.0 if edge == "right" else -1.0
					var candidate := Placement.clamp_to_wall(placement_view, str(support["id"]), middle + direction * 100.0, half)
					var label := "%s/%s/%s/upper=%s" % [spec["kind"], support["orientation"], edge, upper]
					check(not candidate.is_empty() and candidate.get("position") is Vector3, label + ": clamp supplies a placement")
					if candidate.is_empty() or not candidate.get("position") is Vector3: continue
					var position: Vector3 = candidate["position"]
					var detail: Dictionary = spec.duplicate(true)
					detail.merge({"id": "boundary-test", "state": "manual", "generated": false, "anchor": {"surface_id": support["id"], "policy": "surface_local", "local_position": [position.x, position.y, position.z]}}, true)
					fixture["details"] = [detail]
					var before := JSON.stringify(fixture)
					check(Placement.position_available(placement_view, "boundary-test", str(support["id"]), position, half), label + ": preview accepts the edge")
					var resolved_values: Array = world._resolved_details(fixture)
					check(not resolved_values.is_empty() and resolved_values[0] is Dictionary, label + ": authority resolves the attachment")
					if resolved_values.is_empty() or not resolved_values[0] is Dictionary: continue
					var resolved: Dictionary = resolved_values[0]
					check(not bool(resolved.get("needs_placement", true)), label + ": authority agrees at the exact clamped edge")
					check(resolved.get("resolved_position") is Vector3 and (resolved["resolved_position"] as Vector3).is_equal_approx(position), label + ": authority does not nudge the attachment")
					check(JSON.stringify(fixture) == before, label + ": resolving is read-only")
					# Much smaller than a 0.125 cell, but well beyond float rounding.
					var outside := position + direction * 0.001
					detail["anchor"]["local_position"] = [outside.x, outside.y, outside.z]
					check(not Placement.position_available(placement_view, "boundary-test", str(support["id"]), outside, half), label + ": preview rejects a real overhang")
					var outside_resolved: Array = world._resolved_details(fixture)
					check(not outside_resolved.is_empty() and outside_resolved[0] is Dictionary and bool((outside_resolved[0] as Dictionary).get("needs_placement", false)), label + ": authority still rejects a real overhang")
	_finish()

func _finish() -> void:
	print("m2_attachment_boundary_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
