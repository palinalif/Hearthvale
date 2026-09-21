extends SceneTree
const Bounds = preload("res://scripts/m2_world_bounds.gd")
const Generator = preload("res://scripts/m1_patch_generator.gd")
const Starter = preload("res://scripts/m2_starter_hamlet.gd")
const World = preload("res://scripts/m2_building_world.gd")
const Landscape = preload("res://scripts/landscape_state.gd")
const Region = preload("res://scripts/m2_painted_path_region.gd")
const Props = preload("res://scripts/m2_starter_props.gd")
const Visual = preload("res://scripts/m2_hamlet_visual.gd")
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
			print("STARTER_MIGRATION Native old solids, air and boundary preserved")
	else: check(false,"Native VoxelBuffer unavailable")
	print("STARTER_VALLEY_RESULT " + JSON.stringify({"ok":failures.is_empty(),"failures":failures.size(),"messages":failures}))
	quit(0 if failures.is_empty() else 1)

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
