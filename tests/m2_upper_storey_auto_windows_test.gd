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
