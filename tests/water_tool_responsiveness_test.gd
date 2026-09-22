extends SceneTree
const Geometry = preload("res://scripts/water_region_geometry.gd")
const Buildings = preload("res://scripts/building_world.gd")
var checks := 0
var failures := 0

class ToolScene:
	extends "res://scripts/m2_scene_water.gd"
	func _set_status(_message: String) -> void: pass
	func _refresh_controller_hud() -> void: pass

class MockBackend:
	extends Node
	var voxel_scale := 0.125
	var patch_size := Vector3i(80, 32, 80)
	var calls := 0
	var rev := 0
	func stats() -> Dictionary: return {"revision": rev}
	func voxel_at(p: Vector3i) -> int:
		calls += 1
		return 1 if p.y < 8 else 0
	func apply_voxel_changes(_changes: Array) -> bool:
		rev += 1
		return true

class MockVisual:
	extends Node3D
	var updates := 0
	func set_regions_incremental(_regions: Array, _cells: Array = []) -> void:
		updates += 1

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)

func _initialize() -> void:
	var scene := ToolScene.new()
	var backend := MockBackend.new()
	var visual := MockVisual.new()
	scene.backend = backend
	scene.water_visual = visual
	scene.building_world = Buildings.new()
	scene.water_placement_active = true
	scene.water_kind = "lake"
	scene.water_lake_points = [Vector2(2, 2), Vector2(4, 2), Vector2(4, 4), Vector2(2, 4)]
	scene._update_water_preview()
	check(backend.calls > 0, "changed lake outline samples its level")
	backend.calls = 0
	var updates := visual.updates
	for frame in range(120): scene._update_water_preview()
	check(backend.calls == 0 and visual.updates == updates, "stationary lake preview never rescans terrain")
	scene.water_lake_points.clear()
	scene.water_kind = "stream"
	scene._stroke_width = 2.0
	scene.water_stream_level = 1.5
	scene.water_stream_points = PackedVector2Array([Vector2(2, 2), Vector2(4, 2)])
	scene._stroke_add_segment(Vector2(2, 2), Vector2(4, 2))
	var region := scene._stream_region()
	var expected := Geometry.footprint_cells(region, scene.WaterState.EDITABLE_WORLD_SIZE)
	check(scene._stroke_cell_list.size() == expected.size(), "preview and committed stream have identical width")
	var matches := true
	for cell: Vector2i in expected:
		if not scene._stroke_cells.has(cell): matches = false
	check(matches, "preview and committed stream cover the same cells")
	# Sub-threshold movement accumulates from the last accepted sample.
	scene._reset_water_baseline()
	scene.water_stroking = true
	scene._terrain_target_valid = true
	scene._water_last_sample = Vector2(4, 2)
	scene._terrain_target_point = Vector3(4.125, 1, 2)
	check(scene._sample_water_stream(), "fine cursor movement adds a stream sample")
	scene.water_stroking = false
	var before := scene.landscape_state.document()
	check(scene._commit_water(scene._stream_region()), "water commits through the real scene method")
	check(scene._landscape_history.size() == 1 and scene._history_tags.size() == 1, "water is one history transaction")
	var entry: Dictionary = scene._landscape_history.back()
	check(entry["before"].get("water", []) == before.get("water", []), "water undo snapshot predates region creation")
	check(entry["after"].get("water", []).size() == before.get("water", []).size() + 1, "redo snapshot contains committed water")
	visual.free()
	backend.free()
	scene.free()
	print("water_tool_responsiveness_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
