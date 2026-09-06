extends SceneTree

## Calls the real scene placement helper without adding that scene to the
## tree: no native valley, rendering, checkpoint I/O or controller setup.
const SceneScript := preload("res://scripts/m1_scene.gd")

class FakeBackend extends Node:
	var voxel_scale := 0.125
	var patch_size := Vector3i(128, 128, 128)
	var columns: Dictionary = {}
	var sampled_columns: Dictionary = {}
	var available := true

	func is_ready() -> bool:
		return available

	func voxel_at(cell: Vector3i) -> int:
		var column := Vector2i(cell.x, cell.z)
		sampled_columns[column] = true
		for interval: Vector2i in columns.get(column, []):
			if cell.y >= interval.x and cell.y < interval.y: return 2
		return 0

class FakeBuildingWorld extends RefCounted:
	var buildings: Array[Dictionary] = []

	func get_buildings() -> Array[Dictionary]:
		return buildings

var checks := 0
var failures := 0

func _initialize() -> void:
	var scene := SceneScript.new()
	var backend := FakeBackend.new()
	var buildings := FakeBuildingWorld.new()
	scene.backend = backend
	scene.building_world = buildings

	# The unsnapped point lies in column 80 on both axes. Snapping the root to
	# 10.125 moves it into column 81, whose ground is 1.5 world units lower.
	backend.columns[Vector2i(80, 80)] = [Vector2i(0, 64)]
	backend.columns[Vector2i(81, 81)] = [Vector2i(0, 52)]
	var edge: Dictionary = scene._plant_ground(Vector3(10.10, 7.5, 10.10))
	_check(edge.get("point") == Vector3(10.125, 6.5, 10.125), "snapped root uses the ground in its actual column")
	_check(backend.sampled_columns.has(Vector2i(81, 81)) and not backend.sampled_columns.has(Vector2i(80, 80)), "both horizontal axes are snapped before sampling")

	# Two exposed surfaces share X/Z. Both fall within the placement search
	# radius, so this exercises nearest-surface selection, not only its cutoff.
	backend.columns[Vector2i(96, 96)] = [Vector2i(0, 48), Vector2i(56, 60)]
	var floor_target: Dictionary = scene._plant_ground(Vector3(12, 6, 12))
	_check(floor_target.get("point") == Vector3(12, 6, 12), "cave-floor target plants below the overhang")
	var roof_target: Dictionary = scene._plant_ground(Vector3(12, 7.4, 12))
	_check(roof_target.get("point") == Vector3(12, 7.5, 12), "roof target chooses the nearer upper surface")
	var seeded: Dictionary = scene._plant_ground(Vector3(12, 6, 12), true)
	_check(seeded.get("point") == Vector3(12, 7.5, 12), "explicit seeded scatter still chooses topmost ground")
	_check(scene._plant_ground(Vector3(12, 12, 12)).is_empty(), "interactive planting does not jump to distant ground")

	backend.columns[Vector2i(88, 88)] = [Vector2i(0, 40)]
	_check(scene._plant_ground(Vector3(11, 5, 11)).is_empty(), "underwater ground remains excluded")
	buildings.buildings = [{"transform": Transform3D(Basis.IDENTITY, Vector3(12, 0, 12)), "dimensions": Vector3(4, 7, 4)}]
	_check(scene._plant_ground(Vector3(12, 6, 12)).is_empty(), "nearby ground inside cottage footprint remains excluded")
	backend.available = false
	_check(scene._plant_ground(Vector3(10.10, 7.5, 10.10)).is_empty(), "unready terrain rejects planting")

	scene.free()
	backend.free()
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "native_scene_started": false}))
	quit(1 if failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: %s" % label)
