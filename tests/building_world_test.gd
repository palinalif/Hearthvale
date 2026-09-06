extends SceneTree

## Data-only M1 regression. It never creates an engine mesh or touches a save
## directory; every check runs against the authoritative building document.

var failures := 0
const CottageVisualScript = preload("res://scripts/cottage_visual.gd")

func _initialize() -> void:
	var world := BuildingWorld.new()
	var building_id := "building-1"
	var initial: Dictionary = world.get_building(building_id)
	_check(initial.get("schema_version") == BuildingWorld.SCHEMA_VERSION, "schema version")
	_check(initial.get("generator_version") == BuildingWorld.GENERATOR_VERSION, "generator version")
	_check(initial.get("dimensions") == Vector3(18, 10, 14), "default dimensions")
	_check((initial.get("details", []) as Array).size() == 6, "six automatic windows")
	_check((initial.get("surfaces", []) as Array).size() >= 6, "stable cottage surfaces")

	var details: Array = initial["details"]
	var first_id := str(details[0]["id"])
	var second_id := str(details[1]["id"])
	var third_id := str(details[2]["id"])
	var source_surface := str(details[0]["anchor"]["surface_id"])
	_check(world.move_detail(building_id, first_id, source_surface, Vector3(-7.0, 4.0, -7.02)), "move window")
	_check(world.get_building(building_id)["details"][0]["state"] == "modified_locked", "moved window is locked")
	_check(world.replace_detail(building_id, second_id, "window_round"), "replace window")
	_check(world.suppress_detail(building_id, third_id), "suppress window")
	var flower_id := world.add_detail(building_id, "flower_box", source_surface, Vector3(3.0, 2.2, -7.02), "flower_box_wood")
	_check(not flower_id.is_empty(), "add flower box")
	var edited: Dictionary = world.get_building(building_id)
	_check(edited["details"][2]["state"] == "suppressed" and edited["details"][2]["visible"] == false, "suppression persists")
	_check(not world.suppress_detail(building_id, third_id), "repeated suppression is a no-op")
	_check(not world.move_detail(building_id, third_id, source_surface, Vector3(0, 3, -7)), "suppressed detail cannot move")
	_check((edited["automatic_defaults"] as Array).size() == 6, "generated defaults remain complete")
	_check((edited["manual_attachments"] as Array).size() == 1, "manual attachment record")
	_check((edited["modified_locked"] as Array).size() == 2, "modified records")
	_check((edited["overrides"] as Dictionary).size() == 3, "separate overrides")
	_check(world.move_detail(building_id, flower_id, source_surface, Vector3(2.0, 2.4, -7.02)), "move manual attachment")
	_check(world.replace_detail(building_id, flower_id, "flower_box_painted"), "replace manual attachment")
	_check(world.suppress_detail(building_id, flower_id) and world.suppress_detail(building_id, flower_id, false), "suppress and restore manual attachment")
	_check(world.get_building(building_id)["details"][6]["state"] == "manual", "manual state survives edits")

	var before_resize := world.get_document()
	var resize_preview: Dictionary = world.preview_resize(building_id, Vector3(30, 10, 14))
	_check(world.get_document() == before_resize, "resize preview is read only")
	_check(resize_preview["dimensions"] == Vector3(30, 10, 14), "widen preview")
	_check(world.resize(building_id, Vector3(30, 10, 14)), "widen cottage")
	_check(is_equal_approx(float((world.get_building(building_id)["details"][0]["resolved_position"] as Vector3).z), -7.02), "moved anchor follows wall depth")
	_check(world.resize(building_id, Vector3(30, 10, 20)), "deepen cottage")
	_check(is_equal_approx(float((world.get_building(building_id)["details"][0]["resolved_position"] as Vector3).z), -10.02), "surface-local anchor follows depth resize")
	_check(world.resize(building_id, Vector3(4.5, 10, 14)), "shorten cottage")
	var shortened: Dictionary = world.get_building(building_id)
	var needs_count := 0
	for detail in shortened["details"]:
		if bool((detail as Dictionary).get("needs_placement", false)): needs_count += 1
	_check(needs_count > 0, "orphaned detail remains recoverable")
	_check(world.set_material(building_id, "warm_plaster"), "set material")

	var after_edits := world.get_document()
	_check(world.undo(), "undo material")
	_check(world.undo(), "undo resize")
	_check(world.redo(), "redo resize")
	_check(world.redo(), "redo material")
	_check(world.get_document()["buildings"][0]["material_id"] == after_edits["buildings"][0]["material_id"], "undo redo restores recipe")

	var serialized := world.serialize_document()
	_check(serialized.length() < BuildingWorld.HISTORY_BYTES_LIMIT, "bounded serialized document")
	var reloaded := BuildingWorld.new()
	var loaded_ok := reloaded.load_serialized_document(serialized)
	_check(loaded_ok, "serialize reload")
	var reloaded_details: Array = reloaded.get_building(building_id)["details"]
	var current_details: Array = world.get_building(building_id)["details"]
	var same_details := reloaded_details.size() == current_details.size()
	for detail_index in reloaded_details.size():
		var left: Dictionary = reloaded_details[detail_index]
		var right: Dictionary = current_details[detail_index]
		same_details = same_details and left.get("id") == right.get("id") and left.get("state") == right.get("state") and left.get("asset_id") == right.get("asset_id") and left.get("needs_placement") == right.get("needs_placement") and left.get("resolved_position") == right.get("resolved_position")
	_check(same_details, "reload preserves details")
	_check(not reloaded.load_document({"schema_version": 999}), "reject invalid document")
	var invalid_reference: Dictionary = world.get_document()
	invalid_reference["buildings"][0]["details"][0]["anchor"]["surface_id"] = "missing-surface"
	_check(not BuildingWorld.validate_document(invalid_reference), "reject dangling anchor reference")
	var invalid_transform: Dictionary = world.get_document()
	invalid_transform["buildings"][0]["transform"]["scale"] = [0.0, 1.0, 1.0]
	_check(not BuildingWorld.validate_document(invalid_transform), "reject invalid transform")

	var copy_id := world.duplicate_building(building_id)
	_check(not copy_id.is_empty() and copy_id != building_id, "duplicate allocates building id")
	var copy := world.get_building(copy_id)
	_check((copy["automatic_defaults"] as Array)[0]["id"] != world.get_building(building_id)["automatic_defaults"][0]["id"], "duplicate remaps generated defaults")
	_check(copy["details"][0]["id"] != world.get_building(building_id)["details"][0]["id"], "duplicate remaps detail ids")
	_check(copy["surfaces"][0]["id"] != world.get_building(building_id)["surfaces"][0]["id"], "duplicate remaps surface ids")
	_check(copy["details"][0]["default"]["id"] != world.get_building(building_id)["details"][0]["default"]["id"], "duplicate remaps default detail ids")
	_check(copy["details"][0]["default"]["anchor"]["surface_id"] == copy["details"][0]["anchor"]["surface_id"], "duplicate remaps default anchor")
	_check(world.resize(copy_id, Vector3(20, 10, 14)), "edit duplicate")
	_check(world.get_building(building_id)["dimensions"] == Vector3(4.5, 10, 14), "source independent from duplicate")

	# Duplicating a design must respect the global detail budget, including the
	# automatic records already present on every building.
	var budget_world := BuildingWorld.new()
	var added_details := 0
	for _i in 250:
		if not budget_world.add_detail("building-1", "flower_box", "wall-front", Vector3(0, 2, -7.02), "flower_box_wood").is_empty(): added_details += 1
	_check(added_details == 250, "detail budget fixture fills one cottage")
	_check(budget_world.duplicate_building("building-1").is_empty(), "duplicate rejects global detail overflow")

	var stale_revision := world.get_revision()
	_check(world.set_material(building_id, "stone_plaster"), "new revision edit")
	_check(not world.is_revision_current(stale_revision), "stale revision rejected")
	_check(not world.accept_mesh_result(stale_revision) and world.accept_mesh_result(world.get_revision()), "mesh revision guard")
	_check(world.delete_surface(building_id, source_surface), "delete supporting surface")
	var deleted_surface_view := world.get_building(building_id)
	var deleted_needs := 0
	for detail in deleted_surface_view["details"]:
		if bool((detail as Dictionary).get("needs_placement", false)): deleted_needs += 1
	_check(deleted_needs > 0, "deleted surface keeps needs placement records")
	_check(not world.reattach_detail(building_id, first_id, source_surface, Vector3(-1, 3, -7)), "reject reattach to deleted surface")

	# The presentation consumes resolved records and honors replacement,
	# suppression, material and deleted support metadata.
	var visual_world := BuildingWorld.new()
	var visual_view: Dictionary = visual_world.get_building(building_id)
	var visual_details: Array = visual_view["details"]
	var visual_second := str(visual_details[1]["id"])
	var visual_third := str(visual_details[2]["id"])
	_check(visual_world.replace_detail(building_id, visual_second, "window_round"), "visual replacement source")
	_check(visual_world.suppress_detail(building_id, visual_third), "visual suppression source")
	_check(visual_world.set_material(building_id, "warm_plaster"), "visual material source")
	var visual := CottageVisualScript.new()
	visual.request_revision(visual_world.get_revision())
	_check(visual.apply_building(visual_world.get_building(building_id), visual_world.get_revision()), "apply cottage presentation")
	var has_round := false
	var has_suppressed := false
	for child in visual.get_children():
		var node: Node = child
		if node.name == "Detail_%s" % visual_second: has_round = node.mesh is CylinderMesh
		if node.name == "Detail_%s" % visual_third: has_suppressed = true
	_check(has_round and not has_suppressed, "replacement and suppression render")
	var front_wall: Node = visual.get_node_or_null("WallFront")
	_check(front_wall != null and (front_wall as MeshInstance3D).material_override.albedo_color == Color("#d5a982"), "material reaches shell")
	_check(visual_world.delete_surface(building_id, "wall-front"), "visual delete support source")
	visual.request_revision(visual_world.get_revision())
	_check(visual.apply_building(visual_world.get_building(building_id), visual_world.get_revision()), "apply deleted support")
	_check(visual.get_node_or_null("WallFront") == null, "deleted support is hidden")
	var visual_copy_id: String = visual_world.duplicate_building(building_id, Vector3(22, 0, 0))
	var visual_copy := CottageVisualScript.new()
	visual_copy.request_revision(visual_world.get_revision())
	_check(visual_copy.apply_building(visual_world.get_building(visual_copy_id), visual_world.get_revision()), "apply duplicated cottage")
	_check(visual_copy.get_node_or_null("WallBack") != null, "duplicate orientation resolves by metadata")
	visual.free()
	visual_copy.free()
	await process_frame

	_print_result()
	quit(1 if failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: %s" % label)

func _print_result() -> void:
	print(JSON.stringify({"ok": failures == 0, "failures": failures, "buildings": "authoritative", "undo_redo": failures == 0, "serialization": failures == 0, "duplication": failures == 0, "revision_guard": failures == 0}))
