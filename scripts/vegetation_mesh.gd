extends RefCounted
class_name VegetationMesh

const Grid = preload("res://scripts/visual_grid.gd")
const U := Grid.UNIT
const COLORS := [Color("#638348"), Color("#486d46"), Color("#87a657"), Color("#765942"), Color("#c7b897"), Color("#df9a8b")]
const TREE_PATHS := [
	"res://assets/models/magicavoxel/hearthvale_tree_orchard.res",
	"res://assets/models/magicavoxel/hearthvale_tree_riverside.res",
	"res://assets/models/magicavoxel/hearthvale_tree_wind.res",
]
const FOLIAGE_PATHS := [
	"res://assets/models/magicavoxel/hearthvale_foliage_grass.res",
	"res://assets/models/magicavoxel/hearthvale_foliage_wildflowers.res",
	"res://assets/models/magicavoxel/hearthvale_foliage_leafy.res",
]
static var _cache: Dictionary = {}

static func meshes(kind: String, variant: int) -> Array:
	var key := "%s:%d" % [kind, posmod(variant, 3)]
	if _cache.has(key): return _cache[key]
	if kind in ["tree", "foliage"]:
		var paths: Array = TREE_PATHS if kind == "tree" else FOLIAGE_PATHS
		var mesh := load(paths[posmod(variant, 3)]) as Mesh
		assert(mesh != null, "Missing authored %s mesh variant %d" % [kind, posmod(variant, 3)])
		# Preserve the existing one-material-per-batch renderer while swapping in
		# the authored geometry. This keeps opaque/shadow draw ordering stable.
		var authored: Array = []
		for surface in mesh.get_surface_count():
			var part := ArrayMesh.new()
			part.add_surface_from_arrays(mesh.surface_get_primitive_type(surface), mesh.surface_get_arrays(surface))
			part.surface_set_material(0, mesh.surface_get_material(surface))
			authored.append(part)
		_cache[key] = authored
		return authored
	var groups: Array = []
	for i in COLORS.size(): groups.append([PackedVector3Array(), PackedVector3Array(), PackedInt32Array()])
	_rock(groups, posmod(variant, 3))
	var result: Array = []
	for shade in groups.size():
		if groups[shade][0].is_empty(): continue
		var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = groups[shade][0]; arrays[Mesh.ARRAY_NORMAL] = groups[shade][1]; arrays[Mesh.ARRAY_INDEX] = groups[shade][2]
		var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new(); material.albedo_color = COLORS[shade]; material.roughness = 1.0
		mesh.surface_set_material(0, material)
		result.append(mesh)
	_cache[key] = result
	return result

static func _tree(groups: Array, variant: int) -> void:
	var lobes: Array
	var trunk_height: float
	if variant == 0: # Broad, low orchard tree.
		lobes = [[Vector3(-0.85, 3.0, 0), Vector3(1.35, 1.15, 1.15)], [Vector3(0.75, 3.05, 0.15), Vector3(1.3, 1.2, 1.2)], [Vector3(0, 3.75, -0.2), Vector3(1.35, 1.0, 1.05)]]
		trunk_height = 2.75
	elif variant == 1: # Narrow, taller riverside silhouette.
		lobes = [[Vector3(-0.35, 3.0, 0), Vector3(0.9, 1.35, 0.85)], [Vector3(0.3, 4.05, 0.1), Vector3(0.85, 1.45, 0.8)], [Vector3(-0.15, 5.0, -0.1), Vector3(0.72, 1.05, 0.7)]]
		trunk_height = 3.5
	else: # Asymmetric wind-shaped crown.
		lobes = [[Vector3(-0.65, 2.8, 0.15), Vector3(1.05, 1.05, 1.0)], [Vector3(0.55, 3.35, 0), Vector3(1.3, 1.2, 1.05)], [Vector3(1.25, 4.1, -0.2), Vector3(1.05, 0.95, 0.9)]]
		trunk_height = 3.0
	# Merge crown intervals before meshing. Only exposed faces are emitted;
	# straight runs merge integer cells without changing the visible step size.
	var min_x := 10000.0; var max_x := -10000.0; var min_z := 10000.0; var max_z := -10000.0
	for lobe in lobes:
		var center: Vector3 = lobe[0]; var radius: Vector3 = lobe[1]
		min_x = minf(min_x, center.x - radius.x); max_x = maxf(max_x, center.x + radius.x)
		min_z = minf(min_z, center.z - radius.z); max_z = maxf(max_z, center.z + radius.z)
	var columns := {}
	for x in range(floori(min_x / U), ceili(max_x / U)):
		for z in range(floori(min_z / U), ceili(max_z / U)):
			var low := 10000; var high := -10000
			for lobe in lobes:
				var c: Vector3 = lobe[0]; var r: Vector3 = lobe[1]
				var q := pow(((x + 0.5) * U - c.x) / r.x, 2) + pow(((z + 0.5) * U - c.z) / r.z, 2)
				if q >= 1.0: continue
				var h := r.y * sqrt(1.0 - q)
				low = mini(low, floori((c.y - h) / U)); high = maxi(high, ceili((c.y + h) / U))
			if high > low: columns[Vector2i(x, z)] = Vector2i(low, high)
	for cell: Vector2i in columns:
		var extent: Vector2i = columns[cell]
		var shade := 2 if extent.y * U > 4.25 else (0 if cell.x < 2 else 1)
		var low := Vector3(cell.x, extent.x, cell.y) * U
		var high := Vector3(cell.x + 1, extent.y, cell.y + 1) * U
		_face(groups[shade], Vector3(low.x, high.y, low.z), Vector3(U, 0, 0), Vector3(0, 0, U), Vector3.UP)
		_face(groups[shade], low, Vector3(0, 0, U), Vector3(U, 0, 0), Vector3.DOWN)
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var adjacent: Vector2i = columns.get(cell + direction, Vector2i(extent.y, extent.y))
			for interval in [Vector2i(extent.x, mini(extent.y, adjacent.x)), Vector2i(maxi(extent.x, adjacent.y), extent.y)]:
				if interval.y <= interval.x: continue
				var y: float = interval.x * U; var height: float = (interval.y - interval.x) * U
				if direction.x < 0: _face(groups[shade], Vector3(low.x, y, low.z), Vector3(0, height, 0), Vector3(0, 0, U), Vector3.LEFT)
				elif direction.x > 0: _face(groups[shade], Vector3(high.x, y, low.z), Vector3(0, 0, U), Vector3(0, height, 0), Vector3.RIGHT)
				elif direction.y < 0: _face(groups[shade], Vector3(low.x, y, low.z), Vector3(U, 0, 0), Vector3(0, height, 0), Vector3.FORWARD)
				else: _face(groups[shade], Vector3(low.x, y, high.z), Vector3(0, height, 0), Vector3(U, 0, 0), Vector3.BACK)
	_box(groups[3], Vector3(-0.1875, 0, -0.1875), Vector3(0.375, snappedf(trunk_height, U), 0.375))
	for branch in [-1, 1]:
		for step in 6: _box(groups[3], Vector3(branch * step * U - U, trunk_height * 0.55 + step * U, 0), Vector3(U * 2, U * 2, U * 2))
	for side in [-1, 1]: _box(groups[3], Vector3(side * 0.25 - U, 0, -U), Vector3(U * 2, U * 2, U * 2))

static func _foliage(groups: Array, variant: int) -> void:
	for tuft in 9:
		var x := snappedf(sin(tuft * 2.4) * 0.32, U)
		var z := snappedf(cos(tuft * 1.8) * 0.28, U)
		var height := U * (2 + (tuft + variant) % 3)
		_box(groups[0 if tuft % 3 else 1], Vector3(x, 0, z), Vector3(U, height, U))
		_box(groups[0], Vector3(x - U, height * 0.5, z), Vector3(U * 3, U, U))
		if variant == 1 and tuft % 2 == 0: _box(groups[5], Vector3(x - U, height, z - U), Vector3(U * 2, U, U * 2))

static func _rock(groups: Array, variant: int) -> void:
	for x in range(-3 - variant, 4 + variant):
		for z in range(-3, 4):
			var q := pow(float(x) / (3 + variant), 2) + pow(float(z) / 3, 2)
			if q > 1.0: continue
			_box(groups[4], Vector3(x * U, 0, z * U), Vector3(U, U * maxi(1, roundi(sqrt(1.0 - q) * (2 + variant))), U))

static func _box(group: Array, low: Vector3, size: Vector3) -> void:
	var q := Grid.quantized_box(low + size * 0.5, size, Vector3.ONE * U)
	low = q["center"] - q["size"] * 0.5; size = q["size"]
	var x := Vector3(size.x, 0, 0); var y := Vector3(0, size.y, 0); var z := Vector3(0, 0, size.z)
	_face(group, low, x, y, Vector3.FORWARD); _face(group, low + z, y, x, Vector3.BACK)
	_face(group, low, y, z, Vector3.LEFT); _face(group, low + x, z, y, Vector3.RIGHT)
	_face(group, low, z, x, Vector3.DOWN); _face(group, low + y, x, z, Vector3.UP)

static func _face(group: Array, origin: Vector3, a: Vector3, b: Vector3, normal: Vector3) -> void:
	var vertices: PackedVector3Array = group[0]; var normals: PackedVector3Array = group[1]; var indices: PackedInt32Array = group[2]
	var base := vertices.size()
	for point in [origin, origin + a, origin + a + b, origin + b]: vertices.append(point); normals.append(normal)
	if a.cross(b).dot(normal) > 0: indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	else: indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	group[0] = vertices; group[1] = normals; group[2] = indices

