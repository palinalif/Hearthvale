extends SceneTree
const Bounds = preload("res://scripts/m2_world_bounds.gd")
const Generator = preload("res://scripts/m1_patch_generator.gd")
const Starter = preload("res://scripts/m2_starter_hamlet.gd")
const World = preload("res://scripts/m2_building_world.gd")
const Landscape = preload("res://scripts/landscape_state.gd")
const Region = preload("res://scripts/m2_painted_path_region.gd")
const Props = preload("res://scripts/m2_starter_props.gd")
const Visual = preload("res://scripts/m2_hamlet_visual.gd")
const Ponds = preload("res://scripts/premade_ponds.gd")
const CarvePlan = preload("res://scripts/water_carve_plan.gd")
const RegionGeometry = preload("res://scripts/water_region_geometry.gd")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func _initialize() -> void:
	check(Generator.PATCH_SIZE == Vector3i(640,256,640), "Expanded native dimensions")
	check(is_equal_approx(Generator.VOXEL_SCALE,0.125), "Native cell scale preserved")
	check(is_equal_approx(Landscape.EDITABLE_WORLD_SIZE,80.0), "Landscape reaches new edge")
	check(is_equal_approx(Region.DEFAULT_WORLD_SIZE,80.0), "Paths reach new edge")
	var world := World.new()
	var before := JSON.stringify(world.get_document())
	var documents := Starter.documents(world)
	check(not documents.is_empty(), "Starter composition validates")
	check(before == JSON.stringify(world.get_document()), "Building starter does not mutate live authority")
	if not documents.is_empty():
		check(documents["buildings"]["buildings"].size() == 3, "Three independent starter homes")
		check(Landscape.validate(documents["landscape"]), "Saved landscape validates")
		check(documents["landscape"]["composition"].size() == 14, "Starter gardens, fences and furniture")
		check(documents["landscape"]["bridges"].size() == 1, "Riverside crossing")
		check(JSON.stringify(documents) == JSON.stringify(Starter.documents(world)), "Deterministic starter")
		var restored := Landscape.new()
		check(restored.restore(JSON.parse_string(JSON.stringify(documents["landscape"]))), "Landscape JSON round trip")
		check(restored.path_cells("packed_earth").any(func(cell): return int(cell[0]) >= 384), "Paths remain editable beyond the old edge")
		print("STARTER_DOCUMENT " + JSON.stringify({"homes":3,"planting":restored.records.size(),"composition":restored.composition.size(),"path_cells":restored.path_cells("packed_earth").size(),"bytes":JSON.stringify(documents).to_utf8_buffer().size()}))
	if not documents.is_empty(): _check_layout(documents)
	var visual := Visual.new()
	for style in Props.ORDER:
		var builder: Dictionary = visual._new_builder(4)
		Props.append(visual,builder,Vector3.ZERO,Basis.IDENTITY,style)
		check(int(builder["cells"]) > 0, style + " has geometry")
		for surface in builder["surfaces"]:
			for vertex: Vector3 in surface["vertices"]:
				check(vertex.is_equal_approx(vertex.snapped(Vector3.ONE * Props.CELL)), style + " obeys decorative grid")
		print("STARTER_PROP " + JSON.stringify({"style":style,"boxes":builder["cells"]}))
	visual.free()
	if ClassDB.class_exists("VoxelBuffer"):
		var old: Object = ClassDB.instantiate("VoxelBuffer")
		old.create(512,256,512)
		old.set_voxel(1,10,10,10,0)
		old.set_voxel(2,511,63,511,0)
		var expanded: Object = Generator.expand_previous(old)
		check(expanded != null, "Native region migration succeeds")
		if expanded != null:
			check(expanded.get_voxel(10,10,10,0) == 1, "Saved solid retained")
			check(expanded.get_voxel(511,63,511,0) == 2, "Last old column retained")
			check(expanded.get_voxel(20,20,20,0) == 0, "Saved excavation remains air")
			check(expanded.get_voxel(560,10,560,0) == 1, "New meadow generated outside old volume")
			_check_ground_materials(expanded)
			_check_ponds()
			print("STARTER_MIGRATION Native old solids, air and boundary preserved")
	else: check(false,"Native VoxelBuffer unavailable")
	print("STARTER_VALLEY_RESULT " + JSON.stringify({"ok":failures.is_empty(),"failures":failures.size(),"messages":failures}))
	quit(0 if failures.is_empty() else 1)

func _check_ground_materials(expanded: Object) -> void:
	var ring_ids := [6, 7, 9]
	var top := -1
	for y in range(255, -1, -1):
		if int(expanded.get_voxel(560, y, 560, 0)) != 0:
			top = y
			break
	check(top > 0, "New ring column has a surface")
	if top > 0:
		check(int(expanded.get_voxel(560, top, 560, 0)) in ring_ids, "New ring land paints a ring material (got %d)" % int(expanded.get_voxel(560, top, 560, 0)))
		check(int(expanded.get_voxel(560, top - 1, 560, 0)) in ring_ids, "Second ring voxel paints a ring material")
		check(int(expanded.get_voxel(560, top - 2, 560, 0)) == 1, "Subsurface below the paint stays stone (1)")
	check(_paint_digest(Generator.generate()) == _paint_digest(Generator.generate()), "Ground paint is deterministic across runs")
	check(Generator.surface_material(20.0, 18.0, 8.0) == 2, "Hamlet highland stays grass (2)")
	check(Generator.surface_material(Generator.river_center_x(40.0), 40.0, 4.375) == 4, "River bed is sand (4)")
	check(Generator.surface_material(24.0, 27.5, 8.0) == 3, "Lane at the well is packed dirt (3)")
	var library: Object = Generator.build_library()
	check(library.get_models().size() == 10, "Generator library carries the full ground set (10 models)")

func _check_ponds() -> void:
	var ponds: Array = Ponds.regions()
	check(ponds.size() == 2, "Two premade ponds defined")
	check(JSON.stringify(ponds) == JSON.stringify(Ponds.regions()), "Premade ponds are deterministic")
	var green := Generator.VILLAGE_GREEN
	var river_clear := true
	var hamlet_clear := true
	var carved := {}
	for pond: Dictionary in ponds:
		for point: Array in pond["points"]:
			var p := Vector2(float(point[0]), float(point[1]))
			check(green.has_point(p), "Pond outline stays on the village green")
			check(absf(p.x - Generator.river_center_x(p.y)) > Generator.river_half_width(p.y) + 0.5, "Pond outline clears the river")
			check(p.y >= 26.0, "Pond stays off the flat hamlet plateau")
			if p.x >= 12.0 and p.x <= 32.0 and p.y >= 10.0 and p.y <= 26.0: hamlet_clear = false
			if absf(p.x - 21.5) < 10.0 and absf(p.y - 29.0) < 1.0: river_clear = false
		var landscape := Landscape.new()
		check(landscape.add_water("lake", pond["level"], pond["points"]) > 0 and Landscape.validate(landscape.document()), "Pond is a valid lake water region")
		var cells: Array = RegionGeometry.footprint_cells(pond, Landscape.EDITABLE_WORLD_SIZE)
		# The water tool's excavation profile against the analytical valley
		# terrain: every footprint cell on the flat green takes the 6.75 m
		# lake bed and the ring of green cells around the outline a 7.5 m
		# bank shelf, so the water (7.5) sits below its surroundings.
		var plan: Dictionary = CarvePlan.plan(pond, _pond_sampler(carved), Landscape.EDITABLE_WORLD_SIZE)
		var bed: Array = plan.get("bed", [])
		check(bed.size() == cells.size(), "Pond bed excavation covers the whole footprint (%d/%d cells)" % [bed.size(), cells.size()])
		var bank: Array = plan.get("banks", [])
		check(bank.size() >= 8, "Pond bank ring plans (%d cells)" % bank.size())
		var profile_ok := true
		for entry: Array in bed:
			if not is_equal_approx(float(entry[1]), float(pond["level"]) - Ponds.BED_DEPTH): profile_ok = false
		check(profile_ok, "Pond bed depth matches the lake tool profile")
		check(not Ponds.already_carved(_pond_sampler({}), pond), "Fresh valley floor is not reported as carved")
		for cell: Vector2i in bank:
			carved[cell] = float(pond["level"])
		for entry: Array in bed:
			carved[Vector2i(entry[0])] = float(entry[1])
		# Idempotency: once the bed is at the lake bed, the scene's guard
		# recognises the pond and skips excavation, so a loaded save's shore
		# ring never ratchets outward on each start.
		check(Ponds.already_carved(_pond_sampler(carved), pond), "Carved pond bed is recognised (excavation idempotent)")
	check(river_clear, "Ponds leave the premade river clear")
	check(hamlet_clear, "Ponds stay out of the flat hamlet zone")


func _pond_sampler(carved: Dictionary) -> Callable:
	return func(c: Vector2) -> float:
		var cell := Vector2i(roundi(c.x / 0.125), roundi(c.y / 0.125))
		if carved.has(cell):
			return carved[cell]
		return Generator.terrain_height(c.x, c.y)


func _paint_digest(voxels: Object) -> String:
	var digest := 0
	for x in range(0, 640, 24):
		for z in range(0, 640, 24):
			var top := -1
			for y in range(255, -1, -1):
				if int(voxels.get_voxel(x, y, z, 0)) != 0:
					top = y
					break
				if top > 0:
					break
			if top > 0:
				digest = (digest * 31 + int(voxels.get_voxel(x, top, z, 0)) * 131 + int(voxels.get_voxel(x, top - 1, z, 0))) % 999999937
	return str(digest)

func _check_layout(documents: Dictionary) -> void:
	var placed := World.new()
	check(placed.load_document(documents["buildings"]), "Starter building document reloads")
	var state := Landscape.new()
	state.restore(documents["landscape"])
	for cell: Vector2i in state.path_cells("packed_earth"):
		var point := (Vector2(float(cell[0]),float(cell[1])) + Vector2.ONE * 0.5) * 0.125
		check(point.distance_to(Vector2(23.5,27.5)) >= 0.75, "Lane routes around the well, not through it")
	for object: Dictionary in state.composition:
		if object["kind"] != "garden": continue
		var position := Vector2(float(object["position"][0]),float(object["position"][1]))
		var size := Vector2(float(object["size"][0]),float(object["size"][1]))
		var plot := Rect2(position-size*0.5,size)
		for home: Dictionary in documents["buildings"]["buildings"]:
			var view: Dictionary = placed.get_building(str(home["id"]))
			var dimensions: Vector3 = view["dimensions"]
			var transform_value: Transform3D = view["transform"]
			var first := true
			var footprint := Rect2()
			for sign_x in [-1,1]:
				for sign_z in [-1,1]:
					var corner := transform_value * Vector3(float(sign_x)*dimensions.x*0.5,0,float(sign_z)*dimensions.z*0.5)
					var ground := Vector2(corner.x,corner.z)
					footprint = Rect2(ground,Vector2.ZERO) if first else footprint.expand(ground)
					first = false
			check(not plot.intersects(footprint), "Garden stays outside the cottage footprint")
