extends RefCounted
## New-world composition only. This builds validated documents off to the side;
## loading an existing checkpoint never calls it and never adds missing props.
const Landscape = preload("res://scripts/landscape_state.gd")
const Generator = preload("res://scripts/m1_patch_generator.gd")
const Props = preload("res://scripts/m2_starter_props.gd")

static func documents(world: RefCounted) -> Dictionary:
	var candidate: RefCounted = world.get_script().new()
	if not candidate.load_document(world.get_document()): return {}
	for home in [
		["woodland_lodge", Vector3(16.0, 8.0, 30.0)],
		["village_gable", Vector3(28.0, 8.0, 35.0)],
	]:
		var target := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.25), home[1])
		if str(candidate.create_home_at(home[0], target)).is_empty(): return {}
	var landscape := Landscape.new()
	# Connected lanes leave the house footprints and the open green untouched.
	var routes: Array = [
		[[22, 16], [19, 15.5], [17.75, 17.5], [17.75, 22.5], [20, 25.5], [22, 26]],
		[[16, 28.5], [16, 26.25], [18, 25.25], [22, 26]],
		[[22, 26], [23.5, 25.75], [25.5, 26.5], [26, 28], [28, 31], [28, 32.75]],
		[[26, 28], [30, 28], [35, 29], [37.5, 29]],
		[[44.5, 29], [48, 31], [51, 35]],
	]
	for route: Array in routes:
		if landscape.add_path("packed_earth", 1.0, route) < 1: return {}
	if landscape.add_bridge("timber", 1.0, [[37.5, 29], [44.5, 29]]) < 1: return {}
	var props: Array = [
		["well", Vector2(23.5, 27.5), Vector2(2.5, 2.25), 0],
		["chopping_block", Vector2(12.0, 30.75), Vector2(1.0, 1.0), 1],
		["log_stack", Vector2(12.0, 32.25), Vector2(1.5, 1.0), 0],
		["bench", Vector2(21.0, 28.75), Vector2(1.5, 0.625), 2],
		["bench", Vector2(35.5, 31.0), Vector2(1.5, 0.625), 1],
		["lantern", Vector2(19.0, 24.25), Vector2(0.5, 0.5), 0],
		["lantern", Vector2(29.25, 32.75), Vector2(0.5, 0.5), 0],
		["signpost", Vector2(32.0, 29.0), Vector2(0.625, 0.625), 0],
		["barrel_planter", Vector2(23.75, 16.0), Vector2(0.75, 0.75), 0],
	]
	for prop: Array in props:
		if landscape.add_composition("furniture", prop[0], prop[1], prop[2], prop[3]) < 1: return {}
	for garden: Array in [
		["kitchen_rows", Vector2(16.0, 33.75), Vector2(3.0, 1.75)],
		["cottage_flowers", Vector2(30.25, 35.0), Vector2(1.0, 2.0)],
		["herb_garden", Vector2(20.25, 21.0), Vector2(1.5, 1.0)],
	]:
		if landscape.add_composition("garden", garden[0], garden[1], garden[2], 0) < 1: return {}
	for point: Vector2 in [Vector2(14.75, 35), Vector2(17.25, 35)]:
		if landscape.add_composition("fence", "rustic_fence", point, Vector2(2.0, 0.25), 0) < 1: return {}
	# Deliberate framing groves, with open foreground and expansion lawn.
	var trees: Array[Vector2] = [Vector2(7, 12), Vector2(9, 18), Vector2(7, 24), Vector2(8, 35), Vector2(11, 40), Vector2(18, 42), Vector2(27, 44), Vector2(33, 40), Vector2(33, 12), Vector2(30, 8), Vector2(18, 7), Vector2(12, 9), Vector2(49, 18), Vector2(53, 22), Vector2(54, 30), Vector2(52, 39), Vector2(47, 43), Vector2(48, 51), Vector2(55, 52), Vector2(20, 53)]
	for index in trees.size(): _plant(landscape, "tree", trees[index], index % 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1042
	for cluster: Vector2 in [Vector2(9, 21), Vector2(10, 37), Vector2(19, 41), Vector2(31, 39), Vector2(33, 10), Vector2(48, 19), Vector2(52, 39), Vector2(24, 50)]:
		for sample in 10:
			var angle := rng.randf_range(0.0, TAU)
			var radius := sqrt(rng.randf()) * 2.0
			_plant(landscape, "foliage", cluster + Vector2(cos(angle), sin(angle)) * radius, sample % 4)
	for point: Vector2 in [Vector2(36, 15), Vector2(36, 35), Vector2(45, 23), Vector2(46, 39), Vector2(53, 46), Vector2(10, 45)]: _plant(landscape, "rock", point, 1)
	# Reuse the painted cells and widen the root margin by the difference
	# between the 1.0 m path and the 1.5 m planting clearance.
	landscape.clear_records_in_path_cells(landscape.path_cells("packed_earth"), 4)
	var building_document: Dictionary = candidate.get_document()
	var landscape_document := landscape.document()
	if not Landscape.validate(landscape_document): return {}
	return {"buildings": building_document, "landscape": landscape_document}

static func _plant(landscape: RefCounted, kind: String, point: Vector2, seed_value: int) -> void:
	var height := floorf(Generator.terrain_height(point.x, point.y) / Generator.VOXEL_SCALE) * Generator.VOXEL_SCALE
	landscape.add(kind, Vector3(point.x, height, point.y), seed_value)
