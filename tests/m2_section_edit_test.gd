extends SceneTree
const World = preload("res://scripts/m2_section_edit_world.gd")
const Edit = preload("res://scripts/m2_section_edit.gd")
const Massing = preload("res://scripts/m2_house_massing.gd")
const Surfaces = preload("res://scripts/m2_massing_wall_surfaces.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + label)
func _initialize() -> void:
	for shape in ["rectangle", "u_shape"]:
		for edge in Edit.EDGES:
			var world := World.new()
			var id := "building-1"
			var recipe: Dictionary = world._document["buildings"][0]
			var fixture_before := world.get_document()
			var sections := Massing.preset_sections(world.get_building(id), shape)
			sections.append({"id": "upper", "level": 1, "size": Vector3(6,7,6), "offset": Vector3(0,7,0)})
			recipe["massing_sections"] = _serial(sections)
			check(Surfaces.sync_building(world, recipe), "fixture wall supports generated")
			world._reflow_automatic_windows(recipe)
			world._refresh_buckets(recipe)
			# In-place fixture setup must go through the mutation funnel so the
			# revision-keyed resolved-building cache sees the new document.
			world._record_change(fixture_before)
			var before := world.serialize_document()
			var revision := world.get_revision()
			var original := Edit.section(world.get_building(id), "upper")
			var candidate := Edit.resize_edge(original, edge, 2)
			var original_rect := Massing.section_rect(original)
			var new_rect := Massing.section_rect(candidate)
			if edge == "left": check(new_rect.end.x == original_rect.end.x, "left resize fixes right edge")
			elif edge == "right": check(new_rect.position.x == original_rect.position.x, "right resize fixes left edge")
			elif edge == "front": check(new_rect.end.y == original_rect.end.y, "front resize fixes back edge")
			else: check(new_rect.position.y == original_rect.position.y, "back resize fixes front edge")
			var preview := world.preview_section_resize(id, "upper", candidate, revision)
			check(preview.has("view"), shape + ": existing upper floor can expand")
			check(world.serialize_document() == before and world.get_revision() == revision, "preview is read-only including ID allocation")
			check(world.commit_section_resize(id, "upper", candidate, revision), "section applies")
			check(world.get_revision() == revision + 1, "section resize is one revision")
			check(Edit.section(world.get_building(id), "upper") == candidate, "same section ID has desired dimensions and offset")
			for item in sections:
				if str(item["id"]) != "upper": check(Edit.section(world.get_building(id), str(item["id"])) == item, "other sections are unchanged")
			var saved := world.serialize_document()
			check(world.undo() and world.redo(), "section history works")
			var expected: Dictionary = JSON.parse_string(saved)
			var redone: Dictionary = JSON.parse_string(world.serialize_document())
			check(int(redone["revision"]) == int(expected["revision"]) + 2, "history advances the revision guard")
			redone["revision"] = expected["revision"]
			check(redone == expected, "redo regenerates every saved field except its advancing revision")
			check(not world.commit_section_resize(id, "upper", original, revision), "stale section change is rejected")
			var restored := World.new()
			check(restored.load_serialized_document(saved), "section save loads")
			check(JSON.parse_string(JSON.stringify(restored.get_building(id)["details"])) == JSON.parse_string(JSON.stringify(world.get_building(id)["details"])), "windows survive section reload")
			var bad := candidate.duplicate(true)
			bad["offset"] = Vector3(50,7,50)
			check(not world.preview_section_resize(id,"upper",bad,world.get_revision()).has("view"), "unsupported upper floor is rejected")
	# Main-section edge resize rebases the building without moving a wing.
	var world := World.new()
	var recipe: Dictionary = world._document["buildings"][0]
	var base_view := world.get_building("building-1")
	var fixture_before := world.get_document()
	var sections := Massing.preset_sections(base_view, "l_shape")
	recipe["massing_sections"] = _serial(sections)
	Surfaces.sync_building(world,recipe)
	world._refresh_buckets(recipe)
	world._record_change(fixture_before)
	var original := Edit.section(world.get_building("building-1"),"core")
	var candidate := Edit.resize_edge(original,"left",2)
	var before := world.serialize_document()
	var preview := world.preview_section_resize("building-1","core",candidate,world.get_revision())
	check(preview.has("view"), "main section uses the same edge workflow")
	if preview.has("view"):
		var after: Dictionary = preview["view"]
		var old_wing: Vector3 = (base_view["transform"] as Transform3D) * (sections[1]["offset"] as Vector3)
		var new_wing: Vector3 = (after["transform"] as Transform3D) * (Edit.section(after,"l-wing")["offset"] as Vector3)
		check(old_wing.is_equal_approx(new_wing), "main edge edit does not translate the other section")
	check(world.serialize_document() == before, "main resize preview remains read-only")
	check(not world.commit_section_resize("building-1","core",original,world.get_revision()), "confirm without resize creates no history")
	# Pointer drag amount: the aim ray hits the camera-facing plane through
	# the dragged face. `offset` is the section centre in x/z, so for this
	# 4x3x4 section the faces sit at x = -2/+2 and z = -2/+2 (independent
	# expectation from `Massing.section_rect`, not from the drag formula).
	var identity_view := {"transform": Transform3D.IDENTITY}
	var flat := {"offset": Vector3(0, 0, 0), "size": Vector3(4, 3, 4)}
	var cam := Vector3(-3.9, 2.6, -8.2)
	var left_face := Vector3(-2, 1.5, 0)
	check(absf(Edit.drag_amount(identity_view, flat, "left", cam, (left_face - cam).normalized())) < 0.01, "pointer exactly on the left face reports no change")
	check(absf(Edit.drag_amount(identity_view, flat, "left", cam, (Vector3(-4, 1.5, 0) - cam).normalized()) - 2.0) < 0.05, "pointer 2 units past the left face grows by 2")
	var centre_amount := Edit.drag_amount(identity_view, flat, "left", cam, (Vector3(0, 1.5, 0) - cam).normalized())
	check(centre_amount < -1.6 and centre_amount > -2.1, "pointer at the centre proposes a shrink towards the left face")
	var past_right := Edit.drag_amount(identity_view, flat, "left", cam, (Vector3(2, 1.5, 0) - cam).normalized())
	check(past_right < -3.0 and past_right > -3.8, "pointer past the right face proposes close to the full size shrink")
	check(absf(Edit.drag_amount(identity_view, flat, "front", cam, (Vector3(0, 1.5, -2) - cam).normalized())) < 0.01, "pointer exactly on the front face reports no change")
	check(absf(Edit.drag_amount(identity_view, flat, "right", cam, (Vector3(2, 1.5, 0) - cam).normalized())) < 0.01, "pointer exactly on the right face reports no change")
	check(is_inf(Edit.drag_amount(identity_view, flat, "left", cam, Vector3(8.2, 0, -1.9).normalized())), "ray parallel to the face-facing plane leaves the last candidate")
	check(is_inf(Edit.drag_amount(identity_view, flat, "left", cam, (cam - left_face).normalized())), "ray pointing away from the face leaves the last candidate")
	print("m2_section_edit_test checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
func _serial(sections: Array[Dictionary]) -> Array:
	var result: Array = []
	for item in sections:
		var p: Vector3 = item["offset"]
		var s: Vector3 = item["size"]
		result.append({"id":item["id"],"level":item["level"],"offset":[p.x,p.y,p.z],"size":[s.x,s.y,s.z]})
	return result
