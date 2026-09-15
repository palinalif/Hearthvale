extends SceneTree

## Step-4 composition probe (read-only, writes nothing to the repo).
##
## Boots the REAL scene, builds the same three-home hamlet fixture the
## composition render test uses, then answers: where can the existing planting
## system put something, and what is already there?
##
##   godot --headless --path . --script tools/bob_ground_map.gd
##
## Output: a 48x48 world map at 1u cells plus per-area plantable counts.
##   digit = probe/walkable terrain is plantable, number = surface height (u)
##   x     = no plantable surface (water, off-map, below the 5.05u floor)
##   B     = inside a home footprint   P = on a lane   C = composition footprint
##   T/f/r = existing tree / foliage / rock record within 0.6u

const World = preload("res://scripts/building_world.gd")
const State = preload("res://scripts/landscape_state.gd")

var scene: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(320, 180)
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://bob-ground-map-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline: int = Time.get_ticks_msec() + 65000
	while (not scene._player_restored or scene.backend == null or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not scene._player_restored or not scene.backend.is_ready():
		print("GROUND_MAP_SCENE_UNAVAILABLE")
		quit(2)
		return
	scene.set_process(false)

	var lodge_basis: Basis = Basis(Vector3.UP, deg_to_rad(-10.0)).scaled(Vector3.ONE * World.MINIATURE_SCALE)
	scene.building_world.create_home_at("woodland_lodge", Transform3D(lodge_basis, Vector3(12.0, 8.0, 32.0)), scene.building_world.get_revision())
	var gable_basis: Basis = Basis(Vector3.UP, deg_to_rad(12.0)).scaled(Vector3.ONE * World.MINIATURE_SCALE)
	scene.building_world.create_home_at("village_gable", Transform3D(gable_basis, Vector3(31.0, 8.0, 31.0)), scene.building_world.get_revision())
	if scene.has_method("_sync_cottage_visuals"): scene._sync_cottage_visuals()

	scene.landscape_state.add_path("packed_earth", 1.0, [[8.0, 25.0], [14.0, 24.0], [21.0, 25.0], [29.0, 27.0], [35.0, 25.5], [38.5, 24.5]])
	scene.landscape_state.add_path("stepping_stones", 0.75, [[21.0, 25.0], [21.5, 22.5], [22.0, 20.5]])
	scene.landscape_state.add_path("packed_earth", 0.75, [[14.0, 24.0], [13.0, 27.0], [12.0, 29.5]])
	scene.landscape_state.add_path("cobblestone", 0.875, [[29.0, 27.0], [30.0, 28.5]])
	scene.landscape_state.add_bridge("timber", 1.0, [[38.5, 24.5], [43.5, 24.5]])
	scene.landscape_state.add_composition("garden", "cottage_flowers", Vector2(17.0, 17.0), Vector2(3.0, 2.0), 1)
	scene.landscape_state.add_composition("garden", "kitchen_rows", Vector2(12.0, 36.0), Vector2(3.5, 2.5), 0)
	scene.landscape_state.add_composition("garden", "herb_garden", Vector2(35.0, 31.0), Vector2(2.25, 2.25), 1)
	scene.landscape_state.add_composition("fence", "rustic_fence", Vector2(17.0, 15.75), Vector2(3.0, 0.25), 0)
	scene.landscape_state.add_composition("fence", "rustic_fence", Vector2(15.5, 17.0), Vector2(3.0, 0.25), 1)
	scene.landscape_state.add_composition("fence", "rustic_gate", Vector2(18.5, 17.0), Vector2(1.5, 0.375), 1)
	scene.landscape_state.add_composition("fence", "rustic_fence", Vector2(12.0, 37.375), Vector2(3.0, 0.25), 0)
	scene.landscape_state.add_composition("furniture", "bench", Vector2(23.5, 26.25), Vector2(1.5, 0.625), 0)
	scene.landscape_state.add_composition("furniture", "barrel_planter", Vector2(19.0, 25.75), Vector2(0.75, 0.75), 0)
	scene.landscape_state.add_composition("furniture", "signpost", Vector2(28.0, 26.0), Vector2(0.625, 0.625), 1)
	scene.landscape_state.add_composition("furniture", "lantern", Vector2(36.5, 25.5), Vector2(0.5, 0.5), 0)

	var records: Array = scene.landscape_state.records
	print("EXISTING_RECORDS %d (trees %d foliage %d rock %d)" % [records.size(), _count(records, "tree"), _count(records, "foliage"), _count(records, "rock")])
	for record_value in records:
		var record: Dictionary = record_value
		print("  %s %d @ %.2f %.2f y=%.3f" % [record.kind, int(record.seed), float(record.position[0]), float(record.position[2]), float(record.position[1])])

	var plantable := 0
	var rows: Array[String] = []
	var fixture: Array[String] = []
	for z in 48:
		var line := ""
		var marks := ""
		var z_value := float(z) + 0.5
		for x in 48:
			var x_value := float(x) + 0.5
			var glyph := "x"
			var ground: Dictionary = scene._plant_ground(Vector3(x_value, 8.0, z_value), true)
			if not ground.is_empty():
				var height := snappedf(float(ground["point"].y), 0.125)
				glyph = str(clampi(int(height), 0, 9)) if height < 10.0 else "+"
				plantable += 1
			var mark := "."
			if _in_home(Vector3(x_value, 8.0, z_value)): mark = "B"
			elif _on_path(Vector2(x_value, z_value)): mark = "P"
			elif _on_composition(Vector2(x_value, z_value)): mark = "C"
			var existing := _record_at(records, x_value, z_value)
			if not existing.is_empty(): mark = existing
			line += glyph
			marks += mark
		rows.append("  z=%02d %s" % [z, line])
		fixture.append("  z=%02d %s" % [z, marks])
	print("MAP 1/2 — PLANTABLE GROUND (digit = surface height u, x = no plantable surface)")
	for row in rows: print(row)
	print("MAP 2/2 — FIXTURE OVERLAY (B home, P lane, C composition footprint, T/f/r existing record)")
	for row in fixture: print(row)
	print("PLANTABLE_CELLS %d / 2304" % plantable)
	print("GROUND_MAP_DONE")
	scene._shutting_down = true
	scene.queue_free()
	await process_frame
	quit(0)

func _count(records: Array, kind: String) -> int:
	var total := 0
	for record_value in records:
		if str((record_value as Dictionary).kind) == kind: total += 1
	return total

func _in_home(point: Vector3) -> bool:
	for building_value in scene.building_world.get_buildings():
		var building: Dictionary = building_value
		var local: Vector3 = (building["transform"] as Transform3D).affine_inverse() * point
		var dims: Vector3 = building["dimensions"]
		if absf(local.x) < dims.x * 0.5 and absf(local.z) < dims.z * 0.5: return true
	return false

func _on_path(point: Vector2) -> bool:
	for path_value in scene.landscape_state.paths:
		var path: Dictionary = path_value
		var points: Array = path.points
		for index in range(1, points.size()):
			var a := Vector2(float(points[index - 1][0]), float(points[index - 1][1]))
			var b := Vector2(float(points[index][0]), float(points[index][1]))
			var segment := b - a
			var amount := clampf((point - a).dot(segment) / maxf(segment.length_squared(), 0.000001), 0.0, 1.0)
			if point.distance_to(a.lerp(b, amount)) <= float(path.width) * 0.5 + 0.25: return true
	return false

func _on_composition(point: Vector2) -> bool:
	for object_value in scene.landscape_state.composition:
		var object: Dictionary = object_value
		var size := Vector2(float(object.size[0]), float(object.size[1]))
		if int(object.yaw_quarters) % 2 == 1: size = Vector2(size.y, size.x)
		var center := Vector2(float(object.position[0]), float(object.position[1]))
		if absf(point.x - center.x) <= size.x * 0.5 and absf(point.y - center.y) <= size.y * 0.5: return true
	return false

func _record_at(records: Array, x: float, z: float) -> String:
	for record_value in records:
		var record: Dictionary = record_value
		if Vector2(x, z).distance_to(Vector2(float(record.position[0]), float(record.position[2]))) <= 0.6:
			return {"tree": "T", "foliage": "f", "rock": "r"}[str(record.kind)]
	return ""
