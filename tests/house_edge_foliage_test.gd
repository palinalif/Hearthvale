extends SceneTree

## Headless checks for the house-edge planting ring (scripts/house_edge_foliage.gd).
## No existing test is edited: the module is exercised through its pure plan/build
## API with a stub terrain, so the checks are deterministic and need no display.
const Foliage = preload("res://scripts/house_edge_foliage.gd")
const Rim = preload("res://scripts/house_dirt_rim.gd")
const Site = preload("res://scripts/house_landing_site.gd")
const Flora = preload("res://scripts/vegetation_mesh.gd")
const Generator = preload("res://scripts/m1_patch_generator.gd")

const DIMENSIONS := Vector3(18.0, 7.0, 14.0)
const GROUND := 8.0
const UNIT := 0.0625

var checks := 0
var failures := 0

## Flat 8 m ground over the whole 64 m patch, exactly like the starter valley
## outside its river band (top grass voxel index 63 -> surface 64 * 0.125).
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
	var plan := Foliage.plan(building, site_value)
	var half := Vector2(DIMENSIONS.x * 0.5, DIMENSIONS.z * 0.5)

	# --- placement: a ring appears, in the approved half-scale family ----------
	_check(not plan.is_empty(), "a committed house grows an edge tuft ring")
	_check(plan.size() <= Foliage.MAX_TUFTS, "tuft count stays inside the ring budget")
	var outside := true
	var on_ground := true
	var in_family := true
	for tuft: Dictionary in plan:
		if _inside_footprint(tuft["root"], building, half): outside = false
		var world: Vector3 = (building["transform"] as Transform3D) * (tuft["root"] as Vector3)
		if absf(world.y - GROUND) > 0.0001: on_ground = false
		if absf(float(tuft["cell"]) - Flora.PROP_UNIT) > 0.000001: in_family = false
		var heights: Array = tuft["heights"]
		if int(heights[0]) < 1 or int(heights[0]) > Foliage.TALL_COLUMN_CELLS: in_family = false
		if int(heights[1]) > Foliage.TALL_COLUMN_CELLS: in_family = false
	_check(outside, "every tuft sits outside the building footprint")
	_check(on_ground, "every tuft is rooted on the sampled ground surface")
	_check(in_family, "tufts use half-scale 0.0625 cells two-to-three cells high")

	var band_near := Foliage.RING_CLEARANCE_LOCAL
	var band_far := Foliage.RING_CLEARANCE_LOCAL + (float(Foliage.RIM_BAND_CELLS) + float(Foliage.SPAWN_JITTER_CELLS)) * UNIT
	var clear := true
	for tuft: Dictionary in plan:
		var root: Vector3 = tuft["root"]
		var reach := maxf(absf(root.x) - half.x, absf(root.z) - half.y)
		if reach < band_near or reach > band_far: clear = false
	_check(clear, "the ring hugs the footprint: outside the masonry band, inside the spawn band")

	# --- determinism ----------------------------------------------------------
	var repeat := Foliage.plan(building, site_value)
	_check(Foliage.digest(repeat) == Foliage.digest(plan), "same record twice derives an identical tuft ring")
	var regenerated := Foliage.plan(building, Site.site(StubBackend.new(), StubState.new()))
	_check(Foliage.digest(regenerated) == Foliage.digest(plan), "the ring is stable across terrain regeneration")
	var built := Foliage.build(building, site_value)
	var built_again := Foliage.build(building, site_value)
	_check(built["digest"] == built_again["digest"], "build digest matches on a second derivation")
	_check(_mesh_digest(built["mesh"]) == _mesh_digest(built_again["mesh"]), "the batched tuft mesh is byte-stable across derivations")
	_check(built["mesh"] != null and (built["mesh"] as ArrayMesh).get_surface_count() == 1, "the ring is one batched surface")

	# --- draw-call budget -----------------------------------------------------
	_check(int(built["draw_calls"]) == 1, "tuft ring costs exactly one draw call")
	var wide := _building("home-1", Vector3(20.0, GROUND, 20.0), 0.0, Vector3(26.0, 7.0, 15.0))
	var wide_built := Foliage.build(wide, site_value)
	_check(int(wide_built["draw_calls"]) == 1 and int(wide_built["tufts"]) == int(built["tufts"]), "draw calls do not grow with house size or tuft count")
	var expected_cells := 0
	for tuft: Dictionary in plan: expected_cells += int((tuft["heights"] as Array)[0]) + int((tuft["heights"] as Array)[1])
	_check(int(built["cells"]) == expected_cells, "batched cell count matches the derived columns")
	_check(int(built["vertices"]) == expected_cells * 24, "each decorative cell is one 24-vertex box")

	# --- per-house variation --------------------------------------------------
	var other := Foliage.plan(_building("home-2", Vector3(20.0, GROUND, 20.0)), site_value)
	_check(not other.is_empty() and Foliage.digest(other) != Foliage.digest(plan), "a different building id derives its own ring")

	# --- move: the ring follows the record ------------------------------------
	var moved := Foliage.plan(_building("home-1", Vector3(24.0, GROUND, 22.0)), site_value)
	_check(not moved.is_empty(), "a moved house keeps its ring")
	var followed := true
	var still_outside := true
	for tuft: Dictionary in moved:
		var world := Transform3D(Basis(), Vector3(24.0, GROUND, 22.0)) * (tuft["root"] as Vector3)
		if absf(world.y - GROUND) > 0.0001: followed = false
		if _inside_rect(world, Vector2(24.0, 22.0), half): still_outside = false
	_check(followed and still_outside, "the ring re-roots around the moved footprint")
	_check(Foliage.digest(moved) != Foliage.digest(plan), "the moved ring is re-derived, not reused")

	# --- rotate: the ring is the same record, rotated -------------------------
	var rotated := Foliage.plan(_building("home-1", Vector3(20.0, GROUND, 20.0), PI * 0.5), site_value)
	_check(rotated.size() == plan.size(), "rotating a house keeps the same number of tufts")
	var rotated_outside := true
	for tuft: Dictionary in rotated:
		var world := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(20.0, GROUND, 20.0)) * (tuft["root"] as Vector3)
		if _inside_rect(world, Vector2(20.0, 20.0), Vector2(half.y, half.x)): rotated_outside = false
	_check(rotated_outside, "the rotated ring hugs the rotated footprint")

	# --- resize: the ring reconciles to the new footprint ---------------------
	var resized := Foliage.plan(_building("home-1", Vector3(20.0, GROUND, 20.0), 0.0, Vector3(26.0, 7.0, 14.0)), site_value)
	var resized_half := Vector2(13.0, 7.0)
	var resized_outside := true
	for tuft: Dictionary in resized:
		var root: Vector3 = tuft["root"]
		if absf(root.x) <= resized_half.x and absf(root.z) <= resized_half.y: resized_outside = false
	_check(resized_outside and Foliage.digest(resized) != Foliage.digest(plan), "a resized house re-derives its ring for the new dimensions")

	# --- delete: nothing to derive -------------------------------------------
	var deleted := Foliage.plan({}, site_value)
	_check(deleted.is_empty() and Foliage.digest(deleted) == Foliage.digest([]), "a deleted house derives no ring")
	var empty_world := Foliage.build({}, site_value)
	_check(empty_world["mesh"] == null and int(empty_world["draw_calls"]) == 0, "a deleted house adds no mesh and no draw call")

	# --- path and water exclusion --------------------------------------------
	var first_world: Vector3 = (building["transform"] as Transform3D) * (plan[0]["root"] as Vector3)
	var painted: Array = [Vector2i(floori(first_world.x / 0.125), floori(first_world.z / 0.125))]
	_check(Foliage.digest(Foliage.plan(building, Site.site(StubBackend.new(), _state(painted)))) != Foliage.digest(plan), "a painted path cell removes the tuft over it")
	var all_cells: Array = []
	for cell_x in range(60, 260):
		for cell_z in range(60, 260): all_cells.append(Vector2i(cell_x, cell_z))
	_check(Foliage.plan(building, Site.site(StubBackend.new(), _state(all_cells))).is_empty(), "no tuft roots over painted ground")
	var river_building := _building("home-3", Vector3(Generator.river_center_x(20.0), GROUND, 20.0))
	var river_plan := Foliage.plan(river_building, site_value)
	var in_water := 0
	for tuft: Dictionary in river_plan:
		var world: Vector3 = (river_building["transform"] as Transform3D) * (tuft["root"] as Vector3)
		if Site.in_river(Vector2(world.x, world.z), 0.0): in_water += 1
	_check(in_water == 0, "no tuft roots inside the carved river band")
	_check(Foliage.digest(plan) == Foliage.digest(Foliage.plan(building, Site.site(StubBackend.new(), StubState.new()))), "an unrelated path document does not change the ring")

	# --- the rim keeps its own band ------------------------------------------
	var rim := Rim.plan(building, site_value)
	_check(not rim.is_empty(), "the dirt rim and the tuft ring coexist around the same house")
	var shared := 0
	for tuft: Dictionary in plan:
		var root: Vector3 = tuft["root"]
		for entry: Dictionary in rim:
			var centre: Vector3 = entry["centre"]
			if Vector2(root.x, root.z).distance_to(Vector2(centre.x, centre.z)) < UNIT * 0.5: shared += 1
	_check(shared == 0, "no tuft cell shares a cell centre with a dirt rim cell")

	_print_result()

func _inside_footprint(local: Vector3, building: Dictionary, half: Vector2) -> bool:
	return absf(local.x) <= half.x and absf(local.z) <= half.y

func _inside_rect(world: Vector3, centre: Vector2, half: Vector2) -> bool:
	return absf(world.x - centre.x) <= half.x and absf(world.z - centre.y) <= half.y

func _state(painted: Array) -> StubState:
	var state := StubState.new()
	state.painted = painted
	return state

func _building(id: String, origin: Vector3, yaw: float = 0.0, dimensions: Vector3 = DIMENSIONS) -> Dictionary:
	return {
		"id": id,
		"style_id": "riverside_cottage",
		"transform": Transform3D(Basis(Vector3.UP, yaw), origin),
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
