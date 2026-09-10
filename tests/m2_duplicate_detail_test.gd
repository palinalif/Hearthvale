extends SceneTree

var checks := 0
var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-duplicate-detail-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene._player_restored, "duplicate-detail scene ready")
	if not scene._player_restored:
		_finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	var view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	var source: Dictionary = {}
	for value in view.get("details", []):
		var detail: Dictionary = value
		if str(detail.get("kind", "")) in ["window", "door", "shutter", "flower_box"] and bool(detail.get("visible", false)) and not bool(detail.get("needs_placement", false)):
			source = detail
			break
	_check(not source.is_empty(), "fixture has a duplicable visible detail")
	if source.is_empty():
		_finish()
		return
	var source_id := str(source["id"])
	var source_asset := str(source.get("asset_id", ""))
	var source_override: Dictionary = source.get("override", {})
	var before_count: int = view.get("details", []).size()
	var history_before: int = scene._history_tags.size()
	scene.selected_detail_id = source_id
	scene.selected_surface_id = str((source.get("anchor", {}) as Dictionary).get("surface_id", ""))
	scene.hovered_detail_id = source_id
	scene.hovered_detail_kind = str(source.get("kind", ""))
	scene._context_actions_open = true
	scene.tools_open = true
	scene._begin_duplicate_selected_detail()
	_check(scene.detail_move_active and not scene._duplicate_source_detail.is_empty(), "Duplicate enters wall placement preview")
	_check(scene.placement_asset_id == source_asset, "Duplicate preview preserves the selected variation")
	var ok: bool = scene._commit_detail_move()
	_check(ok, "Duplicate commits from the placement preview")
	var after: Dictionary = scene.building_world.get_building(scene.selected_building_id)
	_check(after.get("details", []).size() == before_count + 1, "Duplicate adds exactly one detail")
	_check(scene._history_tags.size() == history_before + 1, "Duplicate records one building history entry")
	var copy: Dictionary = {}
	for value in after.get("details", []):
		var detail: Dictionary = value
		if str(detail.get("id", "")) == scene.selected_detail_id:
			copy = detail
			break
	_check(not copy.is_empty() and str(copy.get("id", "")) != source_id, "Duplicate receives an independent detail ID")
	_check(str(copy.get("kind", "")) == str(source.get("kind", "")) and str(copy.get("asset_id", "")) == source_asset, "Duplicate preserves kind and variation")
	_check(str(copy.get("state", "")) == "manual" and not bool(copy.get("generated", true)), "Duplicate is an independent manual detail")
	var copy_override: Dictionary = copy.get("override", {})
	_check(str(copy_override.get("color_id", "natural")) == str(source_override.get("color_id", "natural")), "Duplicate preserves colour")
	_check(copy_override.get("size", null) == source_override.get("size", null), "Duplicate preserves authored size override")
	_finish()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _finish() -> void:
	if scene and is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures}))
	quit(1 if failures else 0)
