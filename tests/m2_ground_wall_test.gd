extends SceneTree

const World = preload("res://scripts/m2_building_world.gd")
const Massing = preload("res://scripts/m2_house_massing.gd")
const Surfaces = preload("res://scripts/m2_massing_wall_surfaces.gd")
const Placement = preload("res://scripts/wall_attachment_placement.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + label)

func _initialize() -> void:
	for shape in ["rectangle", "l_shape", "t_shape", "u_shape"]:
		var world := World.new()
		var before: Dictionary = world.get_document()
		var building: Dictionary = world._document["buildings"][0]
		var id := str(building["id"])
		var legacy_ids: Array[String] = []
		for support in building["surfaces"]: legacy_ids.append(str(support["id"]))
		if shape != "rectangle": building["massing_sections"] = _serial(Massing.preset_sections(world.get_building(id), shape))
		check(Surfaces.sync_building(world, building), shape + ": sync exposes ground-floor facade runs")
		world._refresh_buckets(building)
		if shape != "rectangle": check(world._record_change(before), shape + ": setup is one change")
		var view := world.get_building(id)
		for old_id in legacy_ids: check(not Placement.surface(view, old_id).is_empty(), shape + ": original anchors keep their IDs")
		var visible_walls := Placement.wall_ids(view)
		check(visible_walls.size() >= 4, shape + ": available wall cycle exists")
		if shape == "u_shape": check(visible_walls.size() >= 8, "U courtyard and arm ends have selectable supports")
		var generated_count := 0
		var added: Array[String] = []
		for support in view["surfaces"]:
			if not bool(support.get("massing_wall", false)) or bool(support.get("deleted", false)) or int(support.get("massing_level", -1)) != 0: continue
			generated_count += 1
			var half := Placement.footprint("window", "window_wood")
			var placed := Placement.clamp_to_wall(view, str(support["id"]), Vector3(0, 3.5, 0), half)
			if placed.is_empty(): continue
			var position: Vector3 = placed["position"]
			var detail_id := world.add_detail(id, "window", str(support["id"]), position, "window_wood")
			check(not detail_id.is_empty(), shape + ": courtyard/wing window can be placed")
			added.append(detail_id)
			var updated := world.get_building(id)
			for detail in updated["details"]:
				if str(detail["id"]) == detail_id: check(bool(detail["visible"]) and not bool(detail["needs_placement"]), shape + ": real manual detail resolves on generated ground wall")
			view = updated
		if shape != "rectangle": check(generated_count > 0, shape + ": missing supports were generated")
		if shape == "u_shape":
			var first_front := ""
			for support in view["surfaces"]:
				if str(support.get("orientation", "")) == "front" and not bool(support.get("massing_wall", false)): first_front = str(support["id"])
			var half := Placement.footprint("window")
			var concealed := Vector3(-7, 3.5, -7.02)
			check(not Placement.position_available(view, "", first_front, concealed, half), "legacy rectangle cannot accept windows inside a U arm")
		var serialized := world.serialize_document()
		var restored := World.new()
		check(restored.load_serialized_document(serialized), shape + ": new ground surfaces remain save-compatible")
		check(JSON.parse_string(JSON.stringify(restored.get_building(id)["details"])) == JSON.parse_string(JSON.stringify(world.get_building(id)["details"])), shape + ": window records resolve identically after reload")
		if not added.is_empty():
			check(world.undo() and world.redo(), shape + ": window placement undo/redo remains available")
			var expected: Dictionary = JSON.parse_string(serialized)
			var redone: Dictionary = JSON.parse_string(world.serialize_document())
			check(int(redone["revision"]) == int(expected["revision"]) + 2, shape + ": undo/redo advances the revision guard")
			redone["revision"] = expected["revision"]
			check(redone == expected, shape + ": redo retains every saved field except its advancing revision")
	print("m2_ground_wall_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _serial(sections: Array[Dictionary]) -> Array:
	var result: Array = []
	for item in sections:
		var p: Vector3 = item["offset"]
		var s: Vector3 = item["size"]
		result.append({"id": item["id"], "level": item["level"], "offset": [p.x,p.y,p.z], "size": [s.x,s.y,s.z]})
	return result
