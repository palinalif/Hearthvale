extends SceneTree
const World = preload("res://scripts/cottage_resize_world.gd")
const Visual = preload("res://scripts/cottage_visual.gd")
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)

func detail(view: Dictionary, id: String) -> Dictionary:
	for entry in view["details"]:
		if str(entry["id"]) == id: return entry
	return {}

func world_position(view: Dictionary, id: String) -> Vector3:
	return (view["transform"] as Transform3D) * (detail(view, id)["resolved_position"] as Vector3)

func _run() -> void:
	for rotation in [0.0, 0.65]:
		var world := World.new()
		var document := world.get_document()
		document["buildings"][0]["transform"]["rotation"] = [0.0, rotation, 0.0]
		check(world.load_document(document), "same save schema accepts rotated fixture")
		var id := "building-1"
		check(world.move_detail(id, "window-front-0", "wall-front", Vector3(-4, 3.5, -7.02)), "manually positioned window fixture")
		check(world.replace_detail(id, "window-back-0", "window_round"), "variation fixture")
		check(world.move_detail(id, "window-front-1", "wall-front", Vector3(0, 3.5, -7.02)), "manual suppression anchor fixture")
		check(world.suppress_detail(id, "window-front-1"), "suppression fixture")
		var box_id := world.add_detail(id, "flower_box", "wall-front", Vector3(6, 0.75, -7.02), "flower_box")
		check(not box_id.is_empty(), "edge attachment fixture")
		var copy_id := world.duplicate_building(id, Vector3(8, 0, 8))
		var other_before := world.get_building(copy_id)
		var before := world.get_building(id)
		var serialized := world.serialize_document()
		var origin: Transform3D = before["transform"]
		var old_position := world_position(before, "window-front-0")
		var old_suppression := world_position(before, "window-front-1")
		var dimensions: Vector3 = before["dimensions"]
		var preview := world.preview_handle_resize(id, dimensions + Vector3(4, 0, 0), Vector3.RIGHT, world.get_revision())
		check(not preview.is_empty() and world.serialize_document() == serialized, "preview never changes document/history")
		var view: Dictionary = preview["view"]
		var transformed: Transform3D = view["transform"]
		check((transformed * Vector3(-(dimensions.x + 4) * 0.5, 0, 0)).is_equal_approx(origin * Vector3(-dimensions.x * 0.5, 0, 0)), "opposite edge stays fixed after rotation and miniature scaling")
		check(world_position(view, "window-front-0").is_equal_approx(old_position), "manual window world tangent and height do not drift")
		check(world_position(view, "window-front-1").is_equal_approx(old_suppression), "moved/suppressed exclusion stays fixed")
		check(not bool(detail(view, "window-front-1")["visible"]), "suppressed window never resurrects")
		check(str(detail(view, "window-back-0")["asset_id"]) == "window_round", "variation survives resize")
		var visual := Visual.new()
		root.add_child(visual)
		visual.request_revision(world.get_revision())
		visual.apply_building(before, world.get_revision())
		var window := visual.get_node("Detail_window-front-0") as MeshInstance3D
		var original_rendered := window.global_position
		var original_size := (window.mesh as BoxMesh).size
		visual.apply_building(view, world.get_revision())
		window = visual.get_node("Detail_window-front-0") as MeshInstance3D
		check(window.global_position.is_equal_approx(original_rendered), "rendered window stays fixed, not only its record")
		check((window.mesh as BoxMesh).size.is_equal_approx(original_size), "rendered pane does not stretch")
		var revision := world.get_revision()
		check(world.commit_handle_resize(id, dimensions + Vector3(4, 0, 0), Vector3.RIGHT, revision), "one-sided resize commits")
		check(world.get_revision() == revision + 1 and world.get_building(id) == view, "preview matches committed full view exactly")
		check(world.get_building(copy_id) == other_before, "other cottage unchanged")
		check(world.undo() and world.get_building(id) == before, "one undo restores original bounds, anchors and exclusions")
		check(world.redo() and world.get_building(id) == view, "one redo restores full resized recipe")
		check(not world.commit_handle_resize(id, dimensions, Vector3.RIGHT, revision), "stale commit rejected")
		check(world.undo(), "return to original fixture")
		var shrink := world.preview_handle_resize(id, Vector3(8, dimensions.y, dimensions.z), Vector3.RIGHT, world.get_revision())
		check(shrink["needs_placement"].has(box_id), "shrinking past manual attachment retains it for recovery")
		check(world.commit_handle_resize(id, Vector3(8, dimensions.y, dimensions.z), Vector3.RIGHT, world.get_revision()), "shrink commits")
		check(not detail(world.get_building(id), box_id).is_empty(), "unsupported identity survives shrink")
		check(world.commit_handle_resize(id, dimensions, Vector3.RIGHT, world.get_revision()), "grow back")
		check(world_position(world.get_building(id), "window-front-0").is_equal_approx(old_position), "shrink/grow cycle has no manual drift")
		check(not bool(detail(world.get_building(id), box_id)["needs_placement"]), "growing back restores original supported attachment")
		var reloaded := World.new()
		check(reloaded.load_serialized_document(world.serialize_document()), "resized recipe saves and loads through existing schema")
		check(world_position(reloaded.get_building(id), "window-front-0").is_equal_approx(old_position), "manual position survives reload")
		var corner := world.preview_handle_resize(id, dimensions + Vector3(2, 0, 2), Vector3(-1, 0, -1), world.get_revision())
		var corner_view: Dictionary = corner["view"]
		var corner_transform: Transform3D = corner_view["transform"]
		check((corner_transform * Vector3((dimensions.x + 2) * 0.5, 0, (dimensions.z + 2) * 0.5)).is_equal_approx(origin * Vector3(dimensions.x * 0.5, 0, dimensions.z * 0.5)), "corner drag holds the opposite corner fixed")
		var top := world.preview_handle_resize(id, dimensions + Vector3(0, 2, 0), Vector3.UP, world.get_revision())
		check((top["view"]["transform"] as Transform3D).is_equal_approx(origin), "height handle keeps foundation fixed")
		check(world_position(top["view"], "window-front-0").is_equal_approx(old_position), "manual window height is not proportional to new wall height")
		check(world.preview_handle_resize(id, dimensions + Vector3(0, 1, 0), Vector3.RIGHT, world.get_revision()).is_empty(), "side cannot secretly change height")
		var snap := World.handle_dimensions(dimensions, dimensions + Vector3(0.7, 0, 0), Vector3.ONE * 0.25, Vector3.RIGHT, true)
		check(is_equal_approx(snap.x, dimensions.x + 1.0), "precision snap preserves visual grid phase")
		var limit := World.handle_dimensions(dimensions, Vector3(100, -100, 100), Vector3.ONE * 0.25, Vector3(1, 0, 1), true)
		check(limit.x <= World.MAX_DIMENSIONS.x and limit.z <= World.MAX_DIMENSIONS.z and limit.y == dimensions.y, "bounds and inactive axis respected")
		visual.queue_free()
		await process_frame
	print("cottage_handle_resize_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
