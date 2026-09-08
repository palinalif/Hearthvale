extends SceneTree

## Data-only M1 regression. It never creates an engine mesh or touches a save
## directory; every check runs against the authoritative building document.

var failures := 0
const CottageVisualScript = preload("res://scripts/cottage_visual.gd")

func _initialize() -> void:
	_test_window_reflow()
	var world := BuildingWorld.new()
	var building_id := "building-1"
	var initial: Dictionary = world.get_building(building_id)
	_check(initial.get("schema_version") == BuildingWorld.SCHEMA_VERSION, "schema version")
	_check(initial.get("generator_version") == BuildingWorld.GENERATOR_VERSION, "generator version")
	_check(initial.get("dimensions") == Vector3(18, 7, 14), "default dimensions")
	_check((initial["transform"] as Transform3D).basis.get_scale().is_equal_approx(Vector3.ONE * BuildingWorld.MINIATURE_SCALE), "default cottage is quarter-scale miniature")
	_check((initial.get("details", []) as Array).size() == 6, "six automatic windows")
	_check((initial.get("surfaces", []) as Array).size() >= 6, "stable cottage surfaces")
	for detail_value in initial["details"]:
		var detail: Dictionary = detail_value
		_check(str(detail.get("kind", "")) == "window" and bool(detail.get("visible", false)) and not bool(detail.get("needs_placement", true)) and detail.get("resolved_position") is Vector3, "default window remains valid")

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

	# A pre-miniature save loads at its authored scale until the player invokes
	# the explicit conversion.  Conversion is one whole-record transaction and
	# must leave edited details, dimensions, origin and rotation intact.
	var old_source := BuildingWorld.new()
	var old_window_id := str((old_source.get_building(building_id)["details"] as Array)[0]["id"])
	_check(old_source.move_detail(building_id, old_window_id, "wall-front", Vector3(-5.0, 4.0, -7.02)), "old save edited window")
	_check(old_source.replace_detail(building_id, str((old_source.get_building(building_id)["details"] as Array)[1]["id"]), "window_round"), "old save replaced window")
	_check(old_source.suppress_detail(building_id, str((old_source.get_building(building_id)["details"] as Array)[2]["id"])), "old save suppressed window")
	var old_document: Dictionary = old_source.get_document()
	old_document["buildings"][0]["transform"]["scale"] = [1.0, 1.0, 1.0]
	old_document["buildings"][0]["transform"]["rotation"] = [0.0, 0.4, 0.0]
	var old_loaded := BuildingWorld.new()
	_check(old_loaded.load_document(old_document), "load pre-miniature save")
	var old_before: Dictionary = old_loaded.get_building(building_id)
	var old_before_transform: Transform3D = old_before["transform"]
	var old_before_details: Array = old_before["details"]
	var old_before_dimensions: Vector3 = old_before["dimensions"]
	_check(old_before_transform.basis.get_scale().is_equal_approx(Vector3.ONE), "old save keeps original scale")
	_check(old_loaded.set_miniature_scale(building_id), "explicit miniature conversion")
	var converted: Dictionary = old_loaded.get_building(building_id)
	var converted_transform: Transform3D = converted["transform"]
	_check(converted_transform.basis.get_scale().is_equal_approx(Vector3.ONE * BuildingWorld.MINIATURE_SCALE), "conversion sets current uniform miniature scale")
	_check(converted_transform.origin == old_before_transform.origin and converted_transform.basis.get_euler().is_equal_approx(old_before_transform.basis.get_euler()), "conversion preserves origin and rotation")
	_check(converted["dimensions"] == old_before_dimensions and converted["details"] == old_before_details, "conversion preserves dimensions and edited details")
	_check(not old_loaded.set_miniature_scale(building_id), "repeated miniature conversion is a no-op")
	_check(old_loaded.undo(), "undo miniature conversion")
	_check((old_loaded.get_building(building_id)["transform"] as Transform3D).basis.get_scale().is_equal_approx(Vector3.ONE), "undo restores old scale")
	_check(old_loaded.redo(), "redo miniature conversion")
	_check((old_loaded.get_building(building_id)["transform"] as Transform3D).basis.get_scale().is_equal_approx(Vector3.ONE * BuildingWorld.MINIATURE_SCALE), "redo restores miniature scale")
	var converted_serialized := old_loaded.serialize_document()
	var converted_reload := BuildingWorld.new()
	_check(converted_reload.load_serialized_document(converted_serialized), "save converted miniature")
	_check((converted_reload.get_building(building_id)["transform"] as Transform3D).basis.get_scale().is_equal_approx(Vector3.ONE * BuildingWorld.MINIATURE_SCALE), "reload preserves miniature scale")
	var converted_copy_id := converted_reload.duplicate_building(building_id)
	_check(not converted_copy_id.is_empty(), "duplicate converted miniature")
	_check((converted_reload.get_building(converted_copy_id)["transform"] as Transform3D).basis.get_scale().is_equal_approx(Vector3.ONE * BuildingWorld.MINIATURE_SCALE), "duplicate preserves miniature scale")
	_check((converted_reload.get_building(converted_copy_id)["details"] as Array).size() == 6, "converted duplicate keeps all six windows")

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
		if node.name == "Detail_%s" % visual_second:
			has_round = node.mesh is BoxMesh and is_equal_approx((node.mesh as BoxMesh).size.x, 1.5) and visual.get_node_or_null("Reveal_%s" % visual_second) != null
		if node.name == "Detail_%s" % visual_third: has_suppressed = true
	_check(has_round and not has_suppressed, "replacement and suppression render")
	var front_wall: Node = visual.get_node_or_null("WallFront")
	_check(front_wall != null and (front_wall as MeshInstance3D).material_override.albedo_color == Color("#d5a982"), "material reaches shell")
	_check(visual.transform.basis.get_scale().is_equal_approx(Vector3.ONE * BuildingWorld.MINIATURE_SCALE), "renderer applies authored miniature transform")
	_check(visual.get_node_or_null("Door") != null and visual.get_node_or_null("Detail_%s" % visual_second) != null, "renderer transforms door and edited detail")
	var door_mesh := (visual.get_node("Door") as MeshInstance3D).mesh as BoxMesh
	_check(door_mesh != null and door_mesh.size.y < 5.0 and door_mesh.size.z < 2.2, "door proportions stay small at miniature scale")
	var roof_tile_batches := 0
	var roof_tile_vertices := 0
	for child_value in visual.get_children():
		var child: Node = child_value
		if not child.name.begins_with("RoofTiles_"): continue
		roof_tile_batches += 1
		if child is MultiMeshInstance3D:
			var tile_instances: MultiMesh = child.multimesh
			_check(tile_instances.mesh is BoxMesh, "roof instances use native outward cube faces")
			_check(child.has_meta("cottage_detail_grid"), "visible roof tiles declare cottage half-cell tier")
			roof_tile_vertices += tile_instances.instance_count * 24

	_check(roof_tile_batches > 0 and roof_tile_batches <= 6 and roof_tile_vertices > 10000 and roof_tile_vertices < 100000, "roof tiles use bounded batched geometry on cottage detail grid")
	_check(visual.get_child_count() < 140, "cottage detail node budget remains bounded")
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

func _test_window_reflow() -> void:
	var world := BuildingWorld.new()
	var id := "building-1"
	var initial := world.get_building(id)
	var initial_ids: Array = []
	for detail in initial["details"]: initial_ids.append(detail["id"])
	_check(_visible_window_count(initial) == 6, "layout starts with six windows")
	var before := world.get_document()
	var preview := world.preview_resize(id, Vector3(30, 7, 14))
	_check(world.get_document() == before and _visible_window_count(preview) == 10, "preview reflows without mutating recipe")
	_check(world.resize(id, Vector3(30, 7, 14)), "layout grows")
	var grown: Dictionary = world.get_document()["buildings"][0]
	_check(_visible_window_count(world.get_building(id)) == 10, "long cottage adds automatic windows")
	_check(world.undo() and world.get_document()["buildings"][0] == before["buildings"][0], "reflow undo restores exact original recipe")
	_check(world.redo() and world.get_document()["buildings"][0] == grown, "reflow redo restores exact generated identities")
	var grown_ids: Array = []
	for detail in grown["details"]: grown_ids.append(detail["id"])
	for length in [5.0, 6.0, 9.0, 12.0, 18.0, 25.0, 32.0]:
		_check(world.resize(id, Vector3(length, 7, 14)), "resize length %s" % length)
		_check_window_clearance(world.get_building(id))
	_check(world.resize(id, Vector3(6, 7, 14)), "layout shrink")
	_check(_visible_window_count(world.get_building(id)) == 2, "small cottage removes surplus automatic windows")
	for detail_id in grown_ids: _check(not _detail_by_id(world.get_building(id), str(detail_id)).is_empty(), "dormant generated ID retained")
	_check(world.resize(id, Vector3(30, 7, 14)), "layout regrow")
	for detail_id in grown_ids: _check(not _detail_by_id(world.get_building(id), str(detail_id)).is_empty(), "regrow reuses stable ID")
	var moved_id := str(initial_ids[0])
	var replaced_id := str(initial_ids[1])
	var suppressed_id := str(initial_ids[2])
	_check(world.move_detail(id, moved_id, "wall-front", Vector3(-7, 4, -7.02)), "layout fixture moved window")
	_check(world.replace_detail(id, replaced_id, "window_round"), "layout fixture replacement")
	_check(world.suppress_detail(id, suppressed_id), "layout fixture suppression")
	var shutter_id := world.add_detail(id, "shutter", "wall-back", Vector3(0, 3.4, 7.02), "shutter_wood")
	_check(not shutter_id.is_empty(), "manual shutter is an editable attachment")
	var protected: Dictionary = {}
	for detail_id in [moved_id, replaced_id, suppressed_id, shutter_id]:
		var detail := _detail_by_id(world.get_building(id), detail_id)
		protected[detail_id] = {"anchor": detail["anchor"].duplicate(true), "asset_id": detail["asset_id"], "state": detail["state"]}
	_check(world.resize(id, Vector3(6, 7, 14)), "shrink edited cottage")
	_check(bool(_detail_by_id(world.get_building(id), moved_id)["needs_placement"]), "moved window becomes recoverable on shrink")
	_check(world.resize(id, Vector3(30, 7, 14)), "regrow edited cottage")
	var edited := world.get_building(id)
	_check(not bool(_detail_by_id(edited, moved_id)["needs_placement"]), "regrow recovers moved window")
	for detail_id in protected:
		var detail := _detail_by_id(edited, str(detail_id))
		for field in ["anchor", "asset_id", "state"]: _check(detail[field] == protected[detail_id][field], "reflow preserves authored %s" % field)
	_check(not bool(_detail_by_id(edited, suppressed_id)["visible"]), "suppressed slot never regenerated")
	_check_window_clearance(edited)
	var reload := BuildingWorld.new()
	_check(reload.load_serialized_document(world.serialize_document()), "layout save reload")
	var reloaded_details: Array = reload.get_building(id)["details"]
	_check(reloaded_details.size() == (edited["details"] as Array).size(), "reload preserves dormant and protected record count")
	for detail in edited["details"]:
		var reloaded_detail := _detail_by_id(reload.get_building(id), str(detail["id"]))
		for field in ["state", "asset_id", "visible", "needs_placement", "layout_slot", "layout_active", "show_shutters"]:
			_check(reloaded_detail.get(field) == detail.get(field), "reload preserves window %s" % field)
		if detail.get("resolved_position") is Vector3:
			_check(reloaded_detail.get("resolved_position") is Vector3 and (reloaded_detail["resolved_position"] as Vector3).is_equal_approx(detail["resolved_position"]), "reload preserves resolved attachment position")
	var copy_id := reload.duplicate_building(id)
	_check(not copy_id.is_empty(), "layout duplicate")
	var copy := reload.get_building(copy_id)
	_check(_visible_window_count(copy) == _visible_window_count(edited), "duplicate preserves generated layout")
	var source_recipe: Dictionary = reload.get_document()["buildings"][0].duplicate(true)
	_check(reload.resize(copy_id, Vector3(12, 7, 14)), "duplicate layout resize")
	_check(reload.get_document()["buildings"][0] == source_recipe, "duplicate reflow is independent")
	# Unknown optional landscape data is part of the same authoritative document
	# and must survive building operations without being rewritten by this model.
	var landscape_document := world.get_document()
	landscape_document["landscape"] = {"version": 1, "decorations": [{"id": "tree-1", "position": [2, 3, 4]}]}
	_check(reload.load_document(landscape_document), "optional landscape loads")
	_check(reload.resize(id, Vector3(18, 7, 14)) and reload.undo() and reload.redo(), "landscape fixture building history")
	_check(reload.get_document()["landscape"] == landscape_document["landscape"], "building history preserves landscape")
	_check(world.resize(id, Vector3(4, 4, 14)), "minimum size layout")
	_check(_visible_window_count(world.get_building(id)) == 0, "minimum cottage does not protrude automatic windows")

func _visible_window_count(building: Dictionary) -> int:
	var count := 0
	for detail in building["details"]:
		if str(detail.get("kind", "")) == "window" and bool(detail.get("visible", false)) and not bool(detail.get("needs_placement", false)): count += 1
	return count

func _detail_by_id(building: Dictionary, id: String) -> Dictionary:
	for detail in building["details"]:
		if str(detail["id"]) == id: return detail
	return {}

func _check_window_clearance(building: Dictionary) -> void:
	var dimensions: Vector3 = building["dimensions"]
	var placed: Array[Dictionary] = []
	for detail in building["details"]:
		if str(detail.get("kind", "")) != "window" or not bool(detail.get("visible", false)) or bool(detail.get("needs_placement", false)): continue
		var position: Vector3 = detail["resolved_position"]
		var half := 1.91 if bool(detail.get("show_shutters", false)) else 0.8 if str(detail.get("asset_id", "")).contains("round") else 1.375
		_check(absf(position.x) + half <= dimensions.x * 0.5, "window including optional shutters stays within wall")
		for other in placed:
			if str(other["anchor"]["surface_id"]) != str(detail["anchor"]["surface_id"]): continue
			var other_half := 1.91 if bool(other.get("show_shutters", false)) else 0.8 if str(other.get("asset_id", "")).contains("round") else 1.375
			_check(absf(position.x - (other["resolved_position"] as Vector3).x) >= half + other_half + 0.5, "visible windows have a clear gap")
		placed.append(detail)

func _print_result() -> void:
	print(JSON.stringify({"ok": failures == 0, "failures": failures, "buildings": "authoritative", "undo_redo": failures == 0, "serialization": failures == 0, "duplication": failures == 0, "revision_guard": failures == 0}))
