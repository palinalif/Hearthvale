extends SceneTree
# Asserts the starter-hamlet furniture the runtime actually loads is genuinely
# authored: every style an asset module advertises has a baked mesh that loads,
# geometry on the 0.0625 presentation grid, a ground-level pivot, and a tintable
# material per surface.
#
# The style list is read from the asset modules themselves, so the contract
# tracks the catalogue instead of a hand-maintained copy of it.  Furniture is
# decorative presentation, so it lives on the fine 0.0625 grid; native terrain
# and authoritative structure stay on 0.125.  Asserting the finer grid still
# catches the scale defect, because a mesh baked at the wrong unit lands off
# both grids.

const UNIT := 0.0625
const SOURCE_DIR := "res://assets/source/magicavoxel/"
const MODULES := [
	"res://scripts/m2_planter_assets.gd",
	"res://scripts/m2_table_assets.gd",
	"res://scripts/m2_lantern_assets.gd",
]

# Every furniture style the runtime tints must be authored; a style that is
# tintable but has no baked mesh is a silent procedural fallback.
const FURNITURE_STYLES := [
	"table", "chair", "cabinet", "lantern", "crate", "barrel", "bed", "fence", "planter",
	"bench", "signpost", "lamp_post", "maypole", "notice_board", "pump", "hay_bale",
]

var failures := 0
var checked := 0

func _init() -> void:
	var advertised: Dictionary = {}
	for module_path: String in MODULES:
		var module: Object = load(module_path)
		if module == null:
			_check(false, "%s: asset module loads" % module_path)
			continue
		var paths: Dictionary = module.PATHS as Dictionary
		_check(paths.size() > 0, "%s: advertises at least one style" % module_path)
		advertised.merge(paths, true, true)
	for style in FURNITURE_STYLES:
		_check(M2HamletVisual.FURNITURE_COLOURS.has(style), "%s: registered as tintable furniture" % style)
		_check(advertised.has(style), "%s: advertised by an asset module" % style)
		if advertised.has(style):
			_check_style(str(style), str(advertised[style]))
	if failures == 0:
		print("M2 STARTER FURNITURE MESH PASS: %d authored styles verified" % checked)
		quit(0)
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

func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		return
	failures += 1
	print("FAIL: %s%s" % [label, (" (" + detail + ")") if detail != "" else ""])
