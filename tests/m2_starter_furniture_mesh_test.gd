extends SceneTree
# Asserts the starter-hamlet authored prop library is complete and usable.
#
# Two vocabularies exist and this test covers both:
#  - the asset modules' advertised styles, which the composition visuals load;
#  - the baked furniture meshes, which the hamlet props tint at runtime.
#
# For every entry it asserts the baked mesh is committed, loads as a Mesh, has
# geometry, keeps every vertex on the 0.0625 presentation grid, pivots at ground
# level, and carries a tintable material per surface.  Furniture is decorative
# presentation, so it lives on the fine 0.0625 grid; native terrain and
# authoritative structure stay on 0.125.  Asserting the finer grid still catches
# the scale defect, because a mesh baked at the wrong unit lands off both grids.

const UNIT := 0.0625
const MODULES := [
	"res://scripts/m2_planter_assets.gd",
	"res://scripts/m2_table_assets.gd",
	"res://scripts/m2_lantern_assets.gd",
]
const FURNITURE_STAGE := "res://assets/models/magicavoxel/"
const FURNITURE_MESHES := [
	"bench", "hay_cart", "lamp_post", "lantern", "maypole",
	"notice_board", "pumpkin_post", "signpost", "well",
]

var failures := 0
var checked := 0

func _init() -> void:
	for module_path: String in MODULES:
		var module: Object = load(module_path)
		if module == null:
			_check(false, "%s: asset module loads" % module_path)
			continue
		var paths: Dictionary = module.PATHS as Dictionary
		_check(paths.size() > 0, "%s: advertises at least one style" % module_path)
		for style_id: String in paths.keys():
			_check_style(str(style_id), str(paths[style_id]))
	for furniture: String in FURNITURE_MESHES:
		_check_style("furniture_" + furniture,
			FURNITURE_STAGE + "hearthvale_furniture_%s.res" % furniture)
	if failures == 0:
		print("M2 STARTER FURNITURE MESH PASS: %d authored styles verified" % checked)
		# quit() only schedules the exit for the end of the frame, so without this
		# return the failure branch below also runs and the suite exits 1 while
		# reporting zero failures.
		quit(0)
		return
	print("M2 STARTER FURNITURE MESH FAIL: %d failures" % failures)
	quit(1)

func _check_style(style_id: String, mesh_path: String) -> void:
	checked += 1
	_check(FileAccess.file_exists(mesh_path), "%s: baked mesh is committed" % style_id, mesh_path)
	var mesh := load(mesh_path) as Mesh
	_check(mesh != null, "%s: baked mesh loads as a Mesh" % style_id)
	if mesh == null:
		return
	var surfaces: int = mesh.get_surface_count()
	_check(surfaces > 0, "%s: mesh has geometry" % style_id)
	var vertices := 0
	var off_grid := 0
	var lowest := INF
	for surface in surfaces:
		var arrays: Array = mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		vertices += points.size()
		for point: Vector3 in points:
			if point.distance_to(point.snapped(Vector3.ONE * UNIT)) > 0.00002:
				off_grid += 1
			lowest = minf(lowest, point.y)
		_check(mesh.surface_get_material(surface) is StandardMaterial3D,
			"%s: surface %d keeps a tintable material" % [style_id, surface])
	_check(vertices > 0, "%s: mesh carries vertices" % style_id, "%d" % vertices)
	_check(off_grid == 0, "%s: every vertex sits on the 0.0625 presentation grid" % style_id,
		"%d off grid" % off_grid)
	_check(absf(lowest) < 0.0001, "%s: mesh pivots at ground level" % style_id,
		"lowest y %.4f" % lowest)

	# A mesh can carry on-grid vertices and still be a degenerate sliver, which is
	# exactly how a broken bake hides from a vertex count. The authored source
	# records its voxel dimensions; the baked footprint must be within the two-cell
	# inset the exposed-face mesher uses, and must occupy every axis.
	var box: AABB = mesh.get_aabb()
	_check(box.size.x > 0.0 and box.size.y > 0.0 and box.size.z > 0.0,
		"%s: mesh occupies all three axes" % style_id, "aabb %s" % box)
	var receipt_path := mesh_path.replace(".res", ".asset.json")
	if FileAccess.file_exists(receipt_path):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(receipt_path)) == OK:
			var dims: Array = (json.data as Dictionary).get("occupied_bounds", {}) as Dictionary
			var lo: Array = dims.get("min", []) as Array
			var hi: Array = dims.get("max", []) as Array
			if lo.size() == 3 and hi.size() == 3:
				var want := Vector3(
					float(hi[0]) - float(lo[0]), float(hi[1]) - float(lo[1]), float(hi[2]) - float(lo[2])
				) * UNIT
				var drift := (box.size - want).abs()
				_check(drift.x <= 2.0 * UNIT and drift.y <= 2.0 * UNIT and drift.z <= 2.0 * UNIT,
					"%s: baked footprint matches the authored dimensions" % style_id,
					"aabb %s vs authored %s" % [box.size, want])

func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		return
	failures += 1
	print("FAIL: %s%s" % [label, (" (" + detail + ")") if detail != "" else ""])
