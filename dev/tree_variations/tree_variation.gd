extends RefCounted
class_name TreeVariation

## Disposable broadleaf tree generator for the bounded M1 variation trial.
## The returned Node3D is an authored asset instance; its scale stays identity.

const CELL_SIZE: float = 0.24
const SAGE := Color("#638348")
const OLIVE := Color("#486d46")
const LIGHT_SAGE := Color("#87a657")
const TRUNK := Color("#765942")

const VARIANT_SPECS: Dictionary = {
	"compact": {
		"label": "COMPACT / SPREADING",
		"trunk_top": 8,
		"branch_y": 6,
		"lobes": [
			{"center": Vector3i(-4, 7, 0), "radius": Vector3i(5, 4, 4)},
			{"center": Vector3i(4, 7, 1), "radius": Vector3i(5, 4, 4)},
			{"center": Vector3i(0, 11, -1), "radius": Vector3i(5, 4, 4)},
			{"center": Vector3i(0, 6, 2), "radius": Vector3i(4, 3, 4)}
		]
	},
	"tall": {
		"label": "TALL / UPRIGHT",
		"trunk_top": 11,
		"branch_y": 8,
		"lobes": [
			{"center": Vector3i(-2, 8, 0), "radius": Vector3i(4, 3, 3)},
			{"center": Vector3i(2, 12, 0), "radius": Vector3i(5, 4, 4)},
			{"center": Vector3i(-1, 16, -1), "radius": Vector3i(5, 4, 3)},
			{"center": Vector3i(1, 20, 0), "radius": Vector3i(3, 3, 3)}
		]
	},
	"asymmetric": {
		"label": "ASYMMETRIC / WIND-SWEPT",
		"trunk_top": 10,
		"branch_y": 7,
		"lobes": [
			{"center": Vector3i(-3, 8, 0), "radius": Vector3i(5, 4, 4)},
			{"center": Vector3i(2, 11, -1), "radius": Vector3i(5, 4, 4)},
			{"center": Vector3i(6, 15, -2), "radius": Vector3i(4, 3, 3)},
			{"center": Vector3i(9, 18, -2), "radius": Vector3i(3, 3, 3)}
		]
	}
}

static func build_variant(kind: String, seed: int = 1042) -> Node3D:
	var builder := new()
	return builder._build(kind, seed)

func _build(kind: String, seed: int) -> Node3D:
	var canonical := kind.to_lower()
	if not VARIANT_SPECS.has(canonical): canonical = "compact"
	var spec: Dictionary = VARIANT_SPECS[canonical]
	var root := Node3D.new()
	root.name = "TreeVariation_%s" % canonical
	var woody: Dictionary = {}
	_add_trunk_and_branches(woody, spec)
	var foliage: Dictionary = {}
	var lobe_index := 0
	for lobe_value in spec["lobes"]:
		var lobe: Dictionary = lobe_value
		var center: Vector3i = lobe["center"]
		# The seed provides a bounded deterministic authored nudge without
		# rotating or scaling the asset.
		if lobe_index == 2: center.z += (absi(seed) % 3) - 1
		_append_ellipsoid(foliage, center, lobe["radius"], lobe_index)
		lobe_index += 1
	# Wood owns a cell if a support line meets foliage. This keeps every
	# rendered cube unique while preserving connected woody support.
	for woody_cell in woody.keys(): foliage.erase(woody_cell)
	var foliage_cells: Array[Vector3i] = []
	for cell_value in foliage.keys(): foliage_cells.append(cell_value)
	foliage_cells.sort_custom(Callable(self, "_cell_sort"))
	# Keep only the exposed shell for rendering. Interior occupancy still
	# defines the mass, while this keeps the disposable review mesh light.
	var shell_cells: Array[Vector3i] = []
	for cell in foliage_cells:
		for offset in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
			if not foliage.has(cell + offset):
				shell_cells.append(cell)
				break
	foliage_cells = shell_cells
	foliage_cells.sort_custom(Callable(self, "_cell_sort"))
	var woody_cells: Array[Vector3i] = []
	for cell_value in woody.keys(): woody_cells.append(cell_value)
	woody_cells.sort_custom(Callable(self, "_cell_sort"))
	var palette_groups: Dictionary = {"sage": [], "olive": [], "light_sage": []}
	for cell in foliage_cells:
		# A lobe owns a coherent shade region. This keeps the stepped silhouette
		# readable at gameplay distance instead of making salt-and-pepper noise.
		var source_lobe: int = int(foliage[cell])
		var bucket := posmod(source_lobe * 2 + absi(seed), 6)
		if bucket < 2: palette_groups["light_sage"].append(cell)
		elif bucket < 4: palette_groups["sage"].append(cell)
		else: palette_groups["olive"].append(cell)
	_add_cells(root, "Foliage_Sage", palette_groups["sage"], SAGE)
	_add_cells(root, "Foliage_Olive", palette_groups["olive"], OLIVE)
	_add_cells(root, "Foliage_LightSage", palette_groups["light_sage"], LIGHT_SAGE)
	_add_cells(root, "Woody_Support", woody_cells, TRUNK)
	var all_cells: Array[Vector3i] = []
	all_cells.append_array(foliage_cells)
	all_cells.append_array(woody_cells)
	var bounds_min := Vector3i(0, 0, 0)
	var bounds_max := Vector3i(0, 0, 0)
	if not all_cells.is_empty():
		bounds_min = all_cells[0]
		bounds_max = all_cells[0]
		for cell in all_cells:
			bounds_min = Vector3i(mini(bounds_min.x, cell.x), mini(bounds_min.y, cell.y), mini(bounds_min.z, cell.z))
			bounds_max = Vector3i(maxi(bounds_max.x, cell.x), maxi(bounds_max.y, cell.y), maxi(bounds_max.z, cell.z))
	var stats := {
		"kind": canonical,
		"seed": seed,
		"cell_size": CELL_SIZE,
		"foliage_cells": foliage_cells.size(),
		"woody_cells": woody_cells.size(),
		"total_cells": all_cells.size(),
		"draw_groups": root.get_child_count(),
		"bounds_min_cell": bounds_min,
		"bounds_max_cell": bounds_max,
		"bounds_size_cells": bounds_max - bounds_min + Vector3i.ONE,
		"label": spec["label"]
	}
	root.set_meta("tree_stats", stats)
	root.set_meta("tree_foliage_cells", foliage_cells)
	root.set_meta("tree_woody_cells", woody_cells)
	root.set_meta("tree_cell_coordinates", all_cells)
	root.set_meta("tree_cell_size", CELL_SIZE)
	root.set_meta("tree_kind", canonical)
	root.set_meta("tree_seed", seed)
	return root

func _add_trunk_and_branches(woody: Dictionary, spec: Dictionary) -> void:
	var trunk_top: int = int(spec["trunk_top"])
	for y in range(0, trunk_top + 1):
		var radius := 1 if y < 3 else 0
		for x in range(-radius, radius + 1):
			for z in range(-radius, radius + 1): woody[Vector3i(x, y, z)] = true
	var branch_y: int = int(spec["branch_y"])
	for lobe_value in spec["lobes"]:
		var lobe: Dictionary = lobe_value
		_add_line(woody, Vector3i(0, branch_y, 0), lobe["center"])

func _add_line(occupied: Dictionary, start: Vector3i, finish: Vector3i) -> void:
	# A stepped path guarantees face-to-face support while interleaving axes so
	# leaning branches read as diagonals instead of right-angle pipes.
	var current := start
	occupied[current] = true
	var delta := finish - start
	var distance := maxi(absi(delta.x), maxi(absi(delta.y), absi(delta.z)))
	var step_index := 0
	while current != finish:
		var best_axis := -1
		var best_error := -INF
		for axis in 3:
			var target_component: int = [finish.x, finish.y, finish.z][axis]
			var current_component: int = [current.x, current.y, current.z][axis]
			if current_component == target_component: continue
			var delta_component: int = [delta.x, delta.y, delta.z][axis]
			var start_component: int = [start.x, start.y, start.z][axis]
			var progress := absi(current_component - start_component)
			var target_progress := float(step_index + 1) * float(absi(delta_component)) / float(maxi(1, distance))
			var error := target_progress - float(progress)
			if error > best_error:
				best_error = error
				best_axis = axis
		if best_axis == 0: current.x += 1 if finish.x > current.x else -1
		elif best_axis == 1: current.y += 1 if finish.y > current.y else -1
		else: current.z += 1 if finish.z > current.z else -1
		occupied[current] = true
		step_index += 1

func _append_ellipsoid(occupied: Dictionary, center: Vector3i, radius: Vector3i, lobe_index: int) -> void:
	for x in range(-radius.x, radius.x + 1):
		for y in range(-radius.y, radius.y + 1):
			for z in range(-radius.z, radius.z + 1):
				var normalized := Vector3(float(x) / float(maxi(1, radius.x)), float(y) / float(maxi(1, radius.y)), float(z) / float(maxi(1, radius.z)))
				if normalized.length_squared() <= 1.0: occupied[center + Vector3i(x, y, z)] = lobe_index

func _add_cells(root: Node3D, group_name: String, cells: Array, color: Color) -> void:
	# One ArrayMesh per shade keeps draw groups bounded while retaining explicit
	# cell geometry. Every cube is authored at exactly CELL_SIZE on each axis.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for cell_value in cells:
		var cell: Vector3i = cell_value
		_append_cube(vertices, normals, indices, Vector3(cell) * CELL_SIZE)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if not vertices.is_empty(): mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "Tree_%s" % group_name
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	instance.material_override = material
	root.add_child(instance)

func _append_cube(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, center: Vector3) -> void:
	var half := Vector3.ONE * CELL_SIZE * 0.5
	var corners: Array[Vector3] = [
		center + Vector3(-half.x, -half.y, -half.z), center + Vector3(half.x, -half.y, -half.z), center + Vector3(half.x, half.y, -half.z), center + Vector3(-half.x, half.y, -half.z),
		center + Vector3(-half.x, -half.y, half.z), center + Vector3(half.x, -half.y, half.z), center + Vector3(half.x, half.y, half.z), center + Vector3(-half.x, half.y, half.z)
	]
	var faces: Array = [
		[0, 3, 2, 1, Vector3(0, 0, -1)], [4, 5, 6, 7, Vector3(0, 0, 1)],
		[0, 1, 5, 4, Vector3.DOWN], [3, 7, 6, 2, Vector3.UP],
		[0, 4, 7, 3, Vector3.LEFT], [1, 2, 6, 5, Vector3.RIGHT]
	]
	for face_index in faces.size():
		var face: Array = faces[face_index]
		var base := vertices.size()
		var normal: Vector3 = face[4]
		for corner_index in 4:
			vertices.append(corners[int(face[corner_index])])
			normals.append(normal)
		indices.append(base); indices.append(base + 1); indices.append(base + 2)
		indices.append(base); indices.append(base + 2); indices.append(base + 3)

func _cell_sort(left: Vector3i, right: Vector3i) -> bool:
	if left.y != right.y: return left.y < right.y
	if left.x != right.x: return left.x < right.x
	return left.z < right.z
