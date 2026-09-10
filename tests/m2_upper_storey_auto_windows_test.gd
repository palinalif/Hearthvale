extends SceneTree

const World = preload("res://scripts/m2_building_world.gd")
const Massing = preload("res://scripts/m2_house_massing.gd")
const Surfaces = preload("res://scripts/m2_massing_wall_surfaces.gd")

var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	var world := World.new()
	var building_id := "building-1"
	var index: int = world._building_index(building_id)
	var buildings: Array = world._document["buildings"]
	var building: Dictionary = buildings[index]
	var view: Dictionary = world.get_building(building_id)
	var dims: Vector3 = view["dimensions"]
	building["massing_sections"] = [
		{"id": "core", "level": 0, "offset": [0.0, 0.0, 0.0], "size": [dims.x, dims.y, dims.z]},
		{"id": "floor-2-core", "level": 1, "offset": [0.0, dims.y, 0.0], "size": [dims.x, dims.y, dims.z]},
	]
	building["massing_preset"] = "custom"
	check(Surfaces.sync_building(world, building), "full second floor generates bounded facade surfaces")
	world._reflow_automatic_windows(building)
	world._refresh_buckets(building)
	buildings[index] = building

	view = world.get_building(building_id)
	var automatic: Array[Dictionary] = _active_upper_windows(view)
	check(automatic.size() >= 4, "new upper storey is populated with automatic windows")
	var orientations: Dictionary = {}
	for detail in automatic:
		var surface_id: String = str((detail.get("anchor", {}) as Dictionary).get("surface_id", ""))
		var support: Dictionary = _surface(view, surface_id)
		orientations[str(support.get("orientation", ""))] = true
		check(str(detail.get("asset_id", "")) == "window_wood", "automatic upper windows inherit Riverside window family")
		check((detail.get("resolved_position", Vector3.ZERO) as Vector3).y > dims.y, "automatic upper window resolves above floor 1")
		check(not bool(detail.get("needs_placement", true)), "automatic upper window starts valid")
	check(orientations.size() >= 3, "automatic layout populates several exposed facade directions")

	if automatic.size() < 3:
		_finish()
		return
	var styled_id: String = str(automatic[0]["id"])
	var suppressed_id: String = str(automatic[1]["id"])
	var untouched_id: String = str(automatic[2]["id"])
	check(world.replace_detail(building_id, styled_id, "window_arch_casement"), "generated upstairs window can be restyled normally")
	check(world.suppress_detail(building_id, suppressed_id), "generated upstairs window can be suppressed normally")

	index = world._building_index(building_id)
	buildings = world._document["buildings"]
	building = buildings[index]
	world._reflow_automatic_windows(building)
	world._refresh_buckets(building)
	buildings[index] = building
	view = world.get_building(building_id)
	check(str(_detail(view, styled_id).get("asset_id", "")) == "window_arch_casement" and str(_detail(view, styled_id).get("state", "")) == "modified_locked", "reflow preserves a player-restyled automatic window")
	check(str(_detail(view, suppressed_id).get("state", "")) == "suppressed", "reflow does not resurrect a suppressed automatic window")
	check(str(_detail(view, untouched_id).get("state", "")) == "automatic", "untouched generated windows remain procedural")

	var serialized: String = world.serialize_document()
	var restored := World.new()
	check(restored.load_serialized_document(serialized), "automatic upper-window house reloads")
	var restored_view: Dictionary = restored.get_building(building_id)
	check(str(_detail(restored_view, styled_id).get("asset_id", "")) == "window_arch_casement", "restyled upper window survives reload")
	check(str(_detail(restored_view, suppressed_id).get("state", "")) == "suppressed", "suppressed upper window survives reload")
	check(_active_upper_windows(restored_view).size() >= 2, "ordinary generated upper windows survive reload")

	_check_inherited_edits(serialized, building_id, styled_id, suppressed_id)

	# If the storey disappears, untouched procedural windows become dormant,
	# while explicit player edits retain recovery semantics.
	index = world._building_index(building_id)
	buildings = world._document["buildings"]
	building = buildings[index]
	building["massing_sections"] = [{"id": "core", "level": 0, "offset": [0.0, 0.0, 0.0], "size": [dims.x, dims.y, dims.z]}]
	building["massing_preset"] = "custom"
	check(Surfaces.sync_building(world, building), "removing floor 2 retires its generated facade runs")
	world._reflow_automatic_windows(building)
	world._refresh_buckets(building)
	buildings[index] = building
	view = world.get_building(building_id)
	check(bool(_detail(view, styled_id).get("needs_placement", false)), "player-restyled window enters recovery when its floor disappears")
	check(str(_detail(view, suppressed_id).get("state", "")) == "suppressed", "suppressed player choice remains suppressed after floor removal")
	var untouched: Dictionary = _detail(view, untouched_id)
	check(not bool(untouched.get("layout_active", true)) and not bool(untouched.get("visible", true)) and not bool(untouched.get("needs_placement", true)), "untouched automatic window quietly goes dormant with its removed floor")

	_finish()

func _check_inherited_edits(serialized: String, building_id: String, styled_id: String, suppressed_id: String) -> void:
	# Use the actual M2 model, not the M1 resize model: upstairs support must add
	# to the existing edit API rather than accidentally replacing it.
	var world = World.new()
	var complete := true
	for method in ["move_building", "move_building_transform", "preview_handle_resize", "commit_handle_resize"]:
		var available: bool = world.has_method(method)
		check(available, "M2 retains inherited " + method)
		complete = complete and available
	if not complete: return
	check(world.load_serialized_document(serialized), "edited upper-floor move/resize fixture loads")
	var neighbor_id: String = world.duplicate_building(building_id, Vector3(8, 0, 8))
	check(not neighbor_id.is_empty(), "neighbor fixture has independent identity")
	var before: Dictionary = world.get_document()
	var original: Dictionary = world.get_building(building_id)
	var revision: int = world.get_revision()
	var target: Transform3D = original["transform"]
	target.basis = Basis(Vector3.UP, deg_to_rad(37.0)) * target.basis
	target.origin += Vector3(3.125, 0, 1.5)
	check(world.move_building_transform(building_id, target, revision), "M2 moves and rotates an edited two-floor house")
	check(world.get_revision() == revision + 1, "move/rotate is one revision")
	var moved: Dictionary = world.get_building(building_id)
	check((moved["transform"] as Transform3D).is_equal_approx(target), "M2 transform matches the requested position, yaw and miniature scale")
	check(moved["details"] == original["details"], "moving preserves resolved upper windows, overrides and suppressions")
	var after: Dictionary = world.get_document()
	var expected: Array = (before["buildings"] as Array).duplicate(true)
	var index: int = world._building_index(building_id)
	expected[index]["transform"] = after["buildings"][index]["transform"]
	check(after["buildings"] == expected and after["next_id"] == before["next_id"], "only the selected transform changes; neighbor, recipes and IDs are untouched")

	var stable: String = world.serialize_document()
	var current_revision: int = world.get_revision()
	check(not world.move_building_transform(building_id, target, current_revision), "identical transform is a no-op")
	check(not world.move_building_transform("missing-building", target, current_revision), "unknown building cannot move")
	check(not world.move_building_transform(building_id, original["transform"], revision), "stale transform cannot replace the current recipe")
	var invalid := target
	invalid.origin.x = INF
	check(not world.move_building_transform(building_id, invalid, current_revision), "nonfinite move is rejected")
	check(world.serialize_document() == stable, "rejected and no-op moves leave authority and revision unchanged")
	check(world.undo() and world.get_document()["buildings"] == before["buildings"], "one undo exactly restores the edited two-floor house and neighbor")
	check(world.redo() and world.get_document()["buildings"] == after["buildings"], "one redo restores the complete moved recipe")

	check(world.move_building(building_id, target.origin + Vector3(0.5, 0, 0), world.get_revision()), "legacy translation helper remains available on M2")
	var translated: Transform3D = world.get_building(building_id)["transform"]
	check(translated.origin.is_equal_approx(target.origin + Vector3(0.5, 0, 0)) and translated.basis.is_equal_approx(target.basis), "translation preserves yaw and scale")
	check(world.undo() and world.get_document()["buildings"] == after["buildings"], "translation is a separate undoable edit")
	var restored = World.new()
	check(restored.load_serialized_document(world.serialize_document()), "moved upper-floor recipe reloads through M2")
	var restored_view: Dictionary = restored.get_building(building_id)
	check((restored_view["transform"] as Transform3D).is_equal_approx(target) and restored_view["details"] == moved["details"], "reload preserves yaw, upper support, window edits and suppressions")

	# A preview is also cancellation: discarding it must not alter the document.
	var dimensions: Vector3 = moved["dimensions"]
	var requested := dimensions + Vector3(2, 0, 0)
	stable = world.serialize_document()
	revision = world.get_revision()
	var preview: Dictionary = world.preview_handle_resize(building_id, requested, Vector3.RIGHT, revision)
	check(not preview.is_empty(), "M2 retains one-sided resize previews on the same model")
	check(world.serialize_document() == stable, "discarding a resize preview leaves authority untouched")
	if preview.is_empty(): return
	var preview_view: Dictionary = preview["view"]
	check(str(_detail(preview_view, styled_id).get("asset_id", "")) == "window_arch_casement", "resize reflow retains the restyled upstairs window")
	check(str(_detail(preview_view, suppressed_id).get("state", "")) == "suppressed", "resize reflow does not resurrect the suppressed upstairs window")
	var upper: Array[Dictionary] = _active_upper_windows(preview_view)
	check(upper.size() >= 2, "resize uses the M2 upper-window resolver, not only the base-wall layout")
	for window in upper:
		check((window.get("resolved_position", Vector3.ZERO) as Vector3).y > dimensions.y, "inherited resize keeps upper-window resolution upstairs")
	check(world.commit_handle_resize(building_id, requested, Vector3.RIGHT, revision), "M2 commits the inherited one-sided resize")
	check(world.get_revision() == revision + 1 and world.get_building(building_id) == preview_view, "resize commits exactly its preview in one revision")
	check(not world.commit_handle_resize(building_id, dimensions, Vector3.RIGHT, revision), "stale resize cannot overwrite a committed edit")
	check(world.undo() and world.get_document()["buildings"] == after["buildings"], "one resize undo restores all recipes and upper-window records")
	check(world.redo() and world.get_building(building_id) == preview_view, "resize redo restores the approved preview")

func _active_upper_windows(view: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in view.get("details", []):
		var detail: Dictionary = value
		if not bool(detail.get("massing_auto", false)) or str(detail.get("kind", "")) != "window": continue
		if bool(detail.get("visible", false)) and not bool(detail.get("needs_placement", false)): result.append(detail)
	return result

func _detail(view: Dictionary, detail_id: String) -> Dictionary:
	for value in view.get("details", []):
		var detail: Dictionary = value
		if str(detail.get("id", "")) == detail_id: return detail
	return {}

func _surface(view: Dictionary, surface_id: String) -> Dictionary:
	for value in view.get("surfaces", []):
		var support: Dictionary = value
		if str(support.get("id", "")) == surface_id: return support
	return {}

func _finish() -> void:
	print("m2_upper_storey_auto_windows_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
