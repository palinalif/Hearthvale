extends SceneTree

## Data-only M1 regression. It never creates an engine mesh or touches a save
## directory; every check runs against the authoritative building document.

var failures := 0

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
	_check(world.resize(copy_id, Vector3(20, 10, 14)), "edit duplicate")
	_check(world.get_building(building_id)["dimensions"] == Vector3(4.5, 10, 14), "source independent from duplicate")

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

	_print_result()
	quit(1 if failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: %s" % label)

func _print_result() -> void:
	print(JSON.stringify({"ok": failures == 0, "failures": failures, "buildings": "authoritative", "undo_redo": failures == 0, "serialization": failures == 0, "duplication": failures == 0, "revision_guard": failures == 0}))
