extends SceneTree
# Asserts the starter-hamlet furniture is genuinely authored: every style has a
# MagicaVoxel source, a baked mesh that loads, and a mesh that respects the
# 0.125 structural grid, sits on a ground pivot, and keeps one material per
# surface so runtime tinting can reach it.

const UNIT := 0.125
const MESH_DIR := "res://assets/models/magicavoxel/"
const SOURCE_DIR := "res://assets/source/magicavoxel/"
const STYLES := ["bench", "stone_bench", "signpost", "lamp_post", "maypole", "notice_board", "water_pump", "hay_cart", "market_cross"]

var failures := 0

func _init() -> void:
	for style: String in STYLES:
		var source := "%shearthvale_%s.vox" % [SOURCE_DIR, style]
		_check(FileAccess.file_exists(source), "%s: authored .vox source exists" % style)
		var mesh_path := "%shearthvale_prop_%s.res" % [MESH_DIR, style]
		_check(FileAccess.file_exists(mesh_path), "%s: baked mesh is committed" % style)
		var mesh := load(mesh_path) as Mesh
		_check(mesh != null, "%s: baked mesh loads as a Mesh" % style)
		if mesh == null:
			continue
		var surfaces: int = mesh.get_surface_count()
		_check(surfaces > 0, "%s: mesh has geometry" % style)
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
			_check(mesh.surface_get_material(surface) is StandardMaterial3D, "%s: surface %d keeps a tintable material" % [style, surface])
		_check(vertices > 0, "%s: mesh carries vertices" % style, "%d" % vertices)
		_check(off_grid == 0, "%s: every vertex sits on the 0.125 structural grid" % style, "%d off grid" % off_grid)
		_check(absf(lowest) < 0.0001, "%s: mesh pivots at ground level" % style, "lowest y %.4f" % lowest)
	if failures == 0:
		print("M2 STARTER FURNITURE MESH PASS: %d authored styles verified" % STYLES.size())
		quit(0)
	print("M2 STARTER FURNITURE MESH FAIL: %d failures" % failures)
	quit(1)

func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		return
	failures += 1
	print("FAIL: %s%s" % [label, (" (" + detail + ")") if detail != "" else ""])
