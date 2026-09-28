extends SceneTree
## Repro: v85 "placing a stream/lake at the map edge can commit without
## digging".
##
## Where the player digs the generated mountain ring down to the excavation
## floor (one 0.125 m voxel), a water region reaching the outermost world
## cell (x/z 159.875 m) has every bed/bank target at or above that floor, so
## the excavation plan is zero changes - yet _commit_water recorded the
## water region anyway: a "water + dig as ONE transaction" commit that dug
## nothing (a floating sheet with no bed carrying it).
##
## The live lake commit converts Vector2 outline vertices to [x, y] arrays;
## a raised-terrain lake below checks that this path does excavate.
##
## Fix: _commit_water rejects a commit whose plan changes zero voxels AND
## whose footprint touches the outermost world cell (the reported case), and
## records nothing. Interior zero-dig placements (e.g. a 1.5 m stream on flat
## 1.0 m ground, covered by water_tool_responsiveness_test) still commit.
## tests/water_edge_probe_test.gd documents the fresh-world counter-evidence.
const Buildings = preload("res://scripts/building_world.gd")

class ToolScene:
	extends "res://scripts/m2_scene_water.gd"
	var status := ""
	func _set_status(message: String) -> void: status = message
	func _refresh_controller_hud() -> void: pass

# The map-edge 6 m x 6 m corner (x/z 154.0 .. 159.875 m), dug down to the
# excavation floor: every column is a single 0.125 m voxel. The patch is
# declared full-world sized like the real VoxelBackend so the excavation
# sampler does not clip world-edge cells; outside the 6 m box it is air.
class EdgeBackend:
	extends Node
	var voxel_scale := 0.125
	var patch_size := Vector3i(1280, 256, 1280)
	var buf: Object
	var rev := 0
	func _init() -> void:
		buf = ClassDB.instantiate("VoxelBuffer")
		buf.create(48, 32, 48)
		for x in 48:
			for z in 48:
				buf.set_voxel(1, x, 0, z, 0)
	func voxel_at(p: Vector3i) -> int:
		if p.y >= 32: return 0
		if p.x < 1232 or p.x >= 1280 or p.z < 1232 or p.z >= 1280: return 0
		return buf.get_voxel(p.x - 1232, p.y, p.z - 1232, 0)
	func apply_voxel_changes(changes: Array) -> bool:
		for change in changes:
			var pos: Vector3i = change["position"]
			buf.set_voxel(int(change["after"]), pos.x - 1232, pos.y, pos.z - 1232, 0)
		rev += 1
		return true
	func stats() -> Dictionary: return {"revision": rev}

class EdgeVisual:
	extends Node3D
	var updates := 0
	func set_regions_incremental(_regions: Array, _cells: Array = []) -> void:
		updates += 1

var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: " + label)

func _initialize() -> void:
	var checks := 0
	var scene := ToolScene.new()
	var backend := EdgeBackend.new()
	var visual := EdgeVisual.new()
	scene.backend = backend
	scene.water_visual = visual
	scene.building_world = Buildings.new()
	scene.water_placement_active = true
	scene._reset_water_baseline()

	# --- Stream at the edge: start on the floor, draw 4.75 m along the edge. ---
	scene.water_kind = "stream"
	scene._terrain_target_valid = true
	scene._terrain_target_point = Vector3(159.875, 0.125, 159.875)
	checks += 1
	check(scene._start_water_stream(), "stream starts on the dug-to-floor edge")
	scene._terrain_target_point = Vector3(155.125, 0.125, 159.875)
	checks += 1
	check(scene._sample_water_stream(), "stream samples along the edge")
	var before_stream := scene.landscape_state.document()
	var rev_before := backend.rev
	checks += 1
	check(not scene._commit_water_stream(), "floor-level stream commit is rejected (nothing to dig)")
	checks += 1
	check(scene.landscape_state.document() == before_stream, "rejected stream records no water region")
	checks += 1
	check(backend.rev == rev_before, "rejected stream leaves terrain untouched")
	checks += 1
	check(scene.status.contains("dig"), "rejected stream explains the dig")
	checks += 1
	check(not scene.water_stroking and scene.water_stream_points.is_empty(), "rejected stream releases the stroke")

	# --- Lake at the edge: 2 x 2 m outline; its sampled level is 0.125 m,
	# whose bed sits below the 0.125 m floor: zero changes. ---
	scene.water_kind = "lake"
	scene.water_placement_active = true
	scene.water_lake_points = [
		Vector2(159.875, 159.875), Vector2(157.875, 159.875),
		Vector2(157.875, 157.875), Vector2(159.875, 157.875)
	]
	var before_lake := scene.landscape_state.document()
	rev_before = backend.rev
	checks += 1
	check(not scene._commit_water_lake(), "floor-level lake commit is rejected (nothing to dig)")
	checks += 1
	check(scene.landscape_state.document() == before_lake, "rejected lake records no water region")
	checks += 1
	check(backend.rev == rev_before, "rejected lake leaves terrain untouched")
	checks += 1
	check(scene.water_lake_points.is_empty(), "rejected lake clears the outline")

	# --- Control: the same stream on 1.0 m terrain (a normal dig) must still
	# commit through the real scene method. ---
	for x in 48:
		for z in 48:
			for y in range(1, 8):
				backend.buf.set_voxel(1, x, y, z, 0)
	backend.rev += 1
	scene._reset_water_baseline()
	scene.water_placement_active = true
	scene.water_kind = "stream"
	scene._terrain_target_point = Vector3(159.875, 1.0, 159.875)
	checks += 1
	check(scene._start_water_stream(), "stream starts on 1.0 m edge terrain")
	scene._terrain_target_point = Vector3(155.125, 1.0, 159.875)
	checks += 1
	check(scene._sample_water_stream(), "stream samples along the 1.0 m edge")
	var before_good := scene.landscape_state.document()
	checks += 1
	check(scene._commit_water_stream(), "digging stream on 1.0 m terrain still commits")
	checks += 1
	check(scene.landscape_state.water.size() == before_good.get("water", []).size() + 1, "digging stream records its region")

	# The live lake outline is Vector2, converted to [x, y] by _lake_region.
	# On raised terrain it must excavate, not just record a water sheet.
	scene._reset_water_baseline()
	scene.water_kind = "lake"
	scene.water_placement_active = true
	scene.water_lake_points = [
		Vector2(159.875, 159.875), Vector2(157.875, 159.875),
		Vector2(157.875, 157.875), Vector2(159.875, 157.875)
	]
	var before_good_lake := scene.landscape_state.document()
	rev_before = backend.rev
	checks += 1
	check(scene._commit_water_lake(), "lake on 1.0 m edge terrain commits")
	checks += 1
	check(backend.rev > rev_before, "lake commit excavates native terrain")
	checks += 1
	check(scene.landscape_state.water.size() == before_good_lake.get("water", []).size() + 1, "lake commit records its region")

	visual.free()
	backend.free()
	scene.free()
	print("water_edge_commit_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
