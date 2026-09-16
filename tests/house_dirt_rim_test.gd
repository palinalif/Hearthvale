extends SceneTree

## Headless checks for the packed-dirt foundation shoulder
## (scripts/house_dirt_rim.gd), including the no-z-fighting contract against the
## raised-foundation masonry band. Vertex positions are compared, never pixels.
const Rim = preload("res://scripts/house_dirt_rim.gd")
const Site = preload("res://scripts/house_landing_site.gd")
const Flora = preload("res://scripts/vegetation_mesh.gd")
const Generator = preload("res://scripts/m1_patch_generator.gd")

const DIMENSIONS := Vector3(18.0, 7.0, 14.0)
const GROUND := 8.0
const UNIT := 0.0625

var checks := 0
var failures := 0

class StubBackend extends RefCounted:
	var voxel_scale := 0.125
	var patch_size := Vector3i(512, 256, 512)
	var top := 63
	func voxel_at(cell: Vector3i) -> int:
		if cell.y < 0: return 0
		if cell.y == top: return 2
		return 1 if cell.y < top else 0

class StubState extends RefCounted:
	var painted: Array = []
	func path_cells(style_id: String) -> Array:
		return painted if style_id == "packed_earth" else []

func _initialize() -> void:
	var building := _building("home-1", Vector3(20.0, GROUND, 20.0))
	var site_value := Site.site(StubBackend.new(), StubState.new())
	var plan := Rim.plan(building, site_value)
	var half := Vector2(DIMENSIONS.x * 0.5, DIMENSIONS.z * 0.5)

	# --- placement ------------------------------------------------------------
	_check(not plan.is_empty(), "a committed house gains a dirt shoulder at the foundation edge")
	_check(plan.size() <= Rim.MAX_CELLS, "rim cell count stays inside the batch budget")
	var one_cell := true
	var seeded := true
	for entry: Dictionary in plan:
		var cell: Vector3 = entry["cell"]
		if absf(cell.x - UNIT) > 0.000001 or absf(cell.z - UNIT) > 0.000001: one_cell = false
		if float(entry["ground"]) != GROUND: seeded = false
	_check(one_cell, "rim cells are one fine 0.0625 cell wide")
	_check(seeded, "every rim cell is seated on the sampled ground height")

	# --- the rim hugs the outside edge of the footprint -----------------------
	var outside := true
	for entry: Dictionary in plan:
		var centre: Vector3 = entry["centre"]
		if absf(centre.x) <= half.x + 0.5 and absf(centre.z) <= half.y + 0.5: outside = false
	_check(outside, "no rim cell sits inside the footprint or the masonry band")

	# --- no shared face plane with the raised-foundation masonry --------------
	var rects := _masonry_rects(DIMENSIONS)
	_check(rects.size() > 0, "the raised-foundation masonry band is reproduced for the compare")
	var overlaps := 0
	var min_gap := INF
	for entry: Dictionary in plan:
		var centre: Vector3 = entry["centre"]
		var cell: Vector3 = entry["cell"]
		var rect := Rect2(centre.x - cell.x * 0.5, centre.z - cell.z * 0.5, cell.x, cell.z)
		for masonry: Rect2 in rects:
			if rect.intersects(masonry): overlaps += 1
			min_gap = minf(min_gap, _rect_gap(rect, masonry))
	_check(overlaps == 0, "no dirt rim cell intersects a raised-foundation brick (no z-fighting)")
	_check(min_gap >= Rim.MASONRY_CLEARANCE * 0.5, "the rim keeps a clear gap outside the masonry band (min gap %.5f)" % min_gap)

	# --- sunk into the terrain, never coplanar with the ground top -----------
	var sunk := true
	var at_ground := true
	for entry: Dictionary in plan:
		var centre: Vector3 = entry["centre"]
		var cell: Vector3 = entry["cell"]
		var ground_local := (GROUND - GROUND) / 1.0
		var top := centre.y + cell.y * 0.5
		var bottom := centre.y - cell.y * 0.5
		if top - ground_local >= cell.y or bottom >= ground_local: sunk = false
		if absf(centre.y - ground_local) > cell.y: at_ground = false
	_check(sunk, "the shoulder is sunk a quarter cell so it never shares the terrain top plane")
	_check(at_ground, "the shoulder stays within one cell of the ground, not up the wall")

	# --- ring shape -----------------------------------------------------------
	var keys := {}
	var duplicates := 0
	for entry: Dictionary in plan:
		var key: Vector2i = entry["key"]
		if keys.has(key): duplicates += 1
		keys[key] = true
	_check(duplicates == 0, "the perimeter ring emits no cell twice")
	var kx := 0
	var kz := 0
	for entry: Dictionary in plan:
		var key: Vector2i = entry["key"]
		kx = maxi(kx, absi(key.x))
		kz = maxi(kz, absi(key.y))
	var corners := 0
	for entry: Dictionary in plan:
		var key: Vector2i = entry["key"]
		if absi(key.x) == kx and absi(key.y) == kz: corners += 1
	_check(corners == 4, "the ring wraps the four corners as well as the edges")
	var rows := {}
	for entry: Dictionary in plan:
		var key: Vector2i = entry["key"]
		if absi(key.y) == kz:
			var row := "z:%d" % key.y
			if not rows.has(row): rows[row] = []
			rows[row].append(key.x)
		else:
			var row := "x:%d" % key.x
			if not rows.has(row): rows[row] = []
			rows[row].append(key.y)
	_check(rows.size() == 4, "the rim is four continuous rows (two per axis)")
	var contiguous := true
	for row: String in rows:
		var values: Array = rows[row]
		values.sort()
		for index in range(1, values.size()):
			if int(values[index]) - int(values[index - 1]) != 1: contiguous = false
	_check(contiguous, "rim cells are contiguous, one fine cell apart, with no gaps")

	# --- determinism ----------------------------------------------------------
	var repeat := Rim.plan(building, site_value)
	_check(Rim.digest(repeat) == Rim.digest(plan), "same record twice derives an identical dirt rim")
	var regenerated := Rim.plan(building, Site.site(StubBackend.new(), StubState.new()))
	_check(Rim.digest(regenerated) == Rim.digest(plan), "the rim is stable across terrain regeneration")
	var built := Rim.build(building, site_value)
	var built_again := Rim.build(building, site_value)
	_check(_mesh_digest(built["mesh"]) == _mesh_digest(built_again["mesh"]), "the batched rim mesh is byte-stable across derivations")
	_check(built["mesh"] != null and (built["mesh"] as ArrayMesh).get_surface_count() == 1, "the rim is one batched surface")
	_check(int(built["cells"]) == plan.size(), "batched cell count matches the derived ring")
	_check(int(built["vertices"]) == plan.size() * 24, "each dirt cell is one 24-vertex box")

	# --- draw-call budget -----------------------------------------------------
	_check(int(built["draw_calls"]) == 1, "dirt rim costs exactly one draw call")
	var biggest := Rim.build(_building("home-1", Vector3(20.0, GROUND, 20.0), Vector3(32.0, 18.0, 32.0)), site_value)
	_check(int(biggest["draw_calls"]) == 1 and int(biggest["cells"]) <= Rim.MAX_CELLS, "a maximum-size house still costs one draw call inside the cell budget")

	# --- move / resize / delete ----------------------------------------------
	var moved := Rim.plan(_building("home-1", Vector3(24.0, GROUND, 22.0)), site_value)
	_check(not moved.is_empty() and Rim.digest(moved) != Rim.digest(plan), "a moved house re-derives its shoulder on the new ground")
	var resized := Rim.plan(_building("home-1", Vector3(20.0, GROUND, 20.0), Vector3(26.0, 7.0, 14.0)), site_value)
	_check(Rim.digest(resized) != Rim.digest(plan) and resized.size() > plan.size(), "a resized house re-derives a longer shoulder")
	_check(Rim.plan({}, site_value).is_empty(), "a deleted house leaves no shoulder behind")
	_check(int(Rim.build({}, site_value)["draw_calls"]) == 0, "a deleted house adds no draw call")

	# --- raised house: the shoulder stays on the ground ----------------------
	var raised := Rim.plan(_building("home-1", Vector3(20.0, GROUND + 2.0, 20.0)), site_value)
	_check(not raised.is_empty(), "a raised house still gets its shoulder")
	var grounded := true
	var stayed_low := true
	for entry: Dictionary in raised:
		if absf(float(entry["ground"]) - GROUND) > 0.0001: grounded = false
		# The wall base is 2 units above the ground, so the shoulder must be
		# derived at ground level, ~2 units below the house origin.
		if absf(float((entry["centre"] as Vector3).y) + 2.0) > 2.0 * UNIT: stayed_low = false
	_check(grounded, "the raised-house shoulder still follows the open ground, not the wall base")
	_check(stayed_low, "the raised-house shoulder sits 2 units below the originating base plane")

	# --- path and water exclusion --------------------------------------------
	var first: Dictionary = plan[0]
	var first_centre: Vector3 = first["centre"]
	var painted: Array = [Vector2i(floori((first_centre.x + 20.0) / 0.125), floori((first_centre.z + 20.0) / 0.125))]
	_check(Rim.digest(Rim.plan(building, Site.site(StubBackend.new(), _state(painted)))) != Rim.digest(plan), "a painted path cell removes the dirt cell over it")
	var all_cells: Array = []
	for cell_x in range(60, 260):
		for cell_z in range(60, 260): all_cells.append(Vector2i(cell_x, cell_z))
	_check(Rim.plan(building, Site.site(StubBackend.new(), _state(all_cells))).is_empty(), "no dirt cell is laid over painted ground")
	var river_building := _building("home-3", Vector3(Generator.river_center_x(20.0), GROUND, 20.0))
	var river_plan := Rim.plan(river_building, site_value)
	var in_water := 0
	for entry: Dictionary in river_plan:
		var world := (river_building["transform"] as Transform3D) * (entry["centre"] as Vector3)
		if Site.in_river(Vector2(world.x, world.z), 0.0): in_water += 1
	_check(in_water == 0, "no dirt cell is laid in the carved river band")

	_print_result()

## The xz rects the raised-foundation masonry occupies, reproduced from
## scripts/m2_scene_raised_foundation.gd: brick depth 0.5 centred at
## (half extent + 0.25), courses 1.0 long, half-brick offset on odd rows.
func _masonry_rects(dimensions: Vector3) -> Array:
	var rects: Array = []
	for along_x: bool in [true, false]:
		var span := (dimensions.x if along_x else dimensions.z) + 0.5
		var edge := (dimensions.z * 0.5 if along_x else dimensions.x * 0.5) + 0.25
		for sign: float in [-1.0, 1.0]:
			for row in 2:
				var offset := 0.5 if row % 2 == 1 else 0.0
				var along := -span * 0.5 + 0.5 + offset
				while along <= span * 0.5 - 0.5 + 0.0001:
					if along_x: rects.append(Rect2(along - 0.5, sign * edge - 0.25, 1.0, 0.5))
					else: rects.append(Rect2(sign * edge - 0.25, along - 0.5, 0.5, 1.0))
					along += 1.0
	return rects

func _rect_gap(a: Rect2, b: Rect2) -> float:
	var gap_x := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
	var gap_y := maxf(maxf(a.position.y - b.end.y, b.position.y - a.end.y), 0.0)
	return Vector2(gap_x, gap_y).length()

func _state(painted: Array) -> StubState:
	var state := StubState.new()
	state.painted = painted
	return state

func _building(id: String, origin: Vector3, dimensions: Vector3 = DIMENSIONS) -> Dictionary:
	return {
		"id": id,
		"style_id": "riverside_cottage",
		"transform": Transform3D(Basis(), origin),
		"dimensions": dimensions,
	}

func _mesh_digest(mesh: Mesh) -> String:
	if mesh == null: return "empty"
	var payload: Array = []
	for surface in mesh.get_surface_count():
		payload.append(mesh.surface_get_arrays(surface))
	return var_to_bytes(payload).hex_encode().sha256_text()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _print_result() -> void:
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures}))
	quit(1 if failures else 0)
