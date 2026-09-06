extends Node3D
class_name M1GardenVisual

## Small derived garden accents for the bounded M1 scene. All repeated pieces
## use a handful of MultiMesh draw calls; terrain remains authoritative.

const HIDDEN_POSITION := Vector3(0, -1000, 0)
const TREE_ANCHORS := [
	{"position": Vector3(12, 8, 10), "kind": "tree"},
	{"position": Vector3(35, 7, 17), "kind": "tree"},
	{"position": Vector3(9, 7.5, 30), "kind": "tree"},
	{"position": Vector3(31, 8, 7), "kind": "tree"},
	{"position": Vector3(36, 6, 35), "kind": "tree"},
]
const SAGE := Color("#638348")
const OLIVE := Color("#486d46")
const LIGHT_SAGE := Color("#87a657")
const OCHRE := Color("#b2ae65")
const TRUNK := Color("#765942")
const FLOWER := Color("#df9a8b")
const STONE := Color("#c7b897")

var _backend: Node
var _groups: Dictionary = {}
var _placements: Array[Dictionary] = []
var _anchors: Array[Dictionary] = []

func _ready() -> void:
	_build_geometry()

func attach_backend(backend: Node) -> void:
	_backend = backend
	refresh_terrain()

func refresh_terrain() -> void:
	if _backend == null or not _backend.has_method("sample_surface_plane"):
		return
	var surfaces: Dictionary = {}
	for index in _anchors.size():
		var anchor: Dictionary = _anchors[index]
		var sample: Dictionary = _backend.sample_surface_plane(anchor["position"], Vector3.UP, 7.0)
		var valid := bool(sample.get("valid", false)) and sample.get("point", null) is Vector3
		surfaces[index] = sample["point"] if valid else null
	for group_name in _groups.keys():
		var group: Dictionary = _groups[group_name]
		var multimesh: MultiMesh = group["multimesh"]
		var entries: Array = group["entries"]
		for index in entries.size():
			var entry: Dictionary = entries[index]
			var surface_point = surfaces.get(int(entry["anchor"]), null)
			var transform_value: Transform3D = entry["transform"]
			if surface_point is Vector3:
				transform_value.origin += surface_point
			else:
				transform_value.origin = HIDDEN_POSITION
			multimesh.set_instance_transform(index, transform_value)

func _build_geometry() -> void:
	_anchors.clear()
	for value in TREE_ANCHORS: _anchors.append(value)
	var trunk: Array[Dictionary] = []
	var sage: Array[Dictionary] = []
	var olive: Array[Dictionary] = []
	var light: Array[Dictionary] = []
	var ochre: Array[Dictionary] = []
	var flowers: Array[Dictionary] = []
	var stones: Array[Dictionary] = []
	var soil: Array[Dictionary] = []
	for index in TREE_ANCHORS.size():
		var scale_value: float = [2.0, 2.35, 1.8, 2.1, 1.7][index]
		trunk.append(_entry(index, Transform3D(Basis.IDENTITY.scaled(Vector3(1.9, 2.4 * scale_value, 1.9)), Vector3(0, 1.2 * scale_value, 0))))
		for branch in [-1.0, 1.0]:
			trunk.append(_entry(index, Transform3D(Basis(Vector3.FORWARD, branch * 0.6).scaled(Vector3(1.1, 1.4 * scale_value, 1.1)), Vector3(branch * 0.45, 2.0 * scale_value, 0))))
		_append_canopy(index, scale_value, sage, olive, light, ochre)
	# A small curving entrance walk: individual slabs follow the native surface.
	for step in 23:
		var t := float(step) / 22.0
		var position := Vector3(16.8 - t * 8.0, 8, 18 + sin(t * PI * 0.7) * 7.0)
		var index := _add_anchor(position)
		stones.append(_entry(index, Transform3D(Basis(Vector3.UP, -0.4 * t).scaled(Vector3(0.45, 0.08, 0.95)), Vector3(0, 0.06, 0))))
	# Deep beds wrap two sides without covering the open terrain editing area.
	for side in [-1.0, 1.0]:
		for step in 24:
			var position := Vector3(17.8 + step * 0.36, 8, 18 + side * 4.15)
			var index := _add_anchor(position)
			soil.append(_entry(index, Transform3D(Basis.IDENTITY.scaled(Vector3(0.37, 0.045, 0.95)), Vector3(0, 0.035, 0))))
			stones.append(_entry(index, Transform3D(Basis.IDENTITY.scaled(Vector3(0.32, 0.16, 0.18)), Vector3(0, 0.10, side * 0.55))))
			for tuft in 3:
				var offset := Vector3(sin(step * 1.7 + tuft) * 0.12, 0.19 + float(tuft % 2) * 0.09, (tuft - 1) * 0.25)
				olive.append(_entry(index, Transform3D(Basis.IDENTITY.scaled(Vector3(0.26, 0.32, 0.24)), offset)))
				if step % 4 != 0:
					flowers.append(_entry(index, Transform3D(Basis.IDENTITY.scaled(Vector3(0.13, 0.12, 0.13)), offset + Vector3(0, 0.20, 0))))
	# Loose clusters break the straight bank and pad boundaries, never a carpet
	# of randomly coloured voxels. Each rooted clump is resampled after sculpting.
	for step in 38:
		var position := Vector3(37.7 + sin(step * 0.7) * 0.5, 6, 10.5 + step * 0.82)
		var index := _add_anchor(position)
		stones.append(_entry(index, Transform3D(Basis.IDENTITY.scaled(Vector3(0.65, 0.20, 0.56)), Vector3(0, 0.10, 0))))
		for reed in 5:
			var height := 0.38 + float((step + reed) % 4) * 0.13
			var offset := Vector3(-0.45 + reed * 0.16, height * 0.5, sin(reed * 2.0) * 0.3)
			sage.append(_entry(index, Transform3D(Basis.IDENTITY.scaled(Vector3(0.075, height, 0.075)), offset)))
	for step in 32:
		var angle := float(step / 8) * 1.8 + float(step % 8) * 0.06
		var radius := 8.5 + sin(step * 1.9) * 1.2
		var position := Vector3(22 + cos(angle) * radius, 8, 18 + sin(angle) * radius * 0.85)
		var index := _add_anchor(position)
		for clump in 7:
			var offset := Vector3(sin(clump * 2.3) * 0.55, 0.22 + float(clump % 3) * 0.12, cos(clump * 1.7) * 0.45)
			sage.append(_entry(index, Transform3D(Basis.IDENTITY.scaled(Vector3(0.4, 0.36, 0.4)), offset)))
	_add_group("trunks", _cylinder_mesh(), TRUNK, trunk)
	_add_group("sage", _leaf_mesh(), SAGE, sage)
	_add_group("olive", _leaf_mesh(), OLIVE, olive)
	_add_group("light_sage", _leaf_mesh(), LIGHT_SAGE, light)
	_add_group("ochre", _leaf_mesh(), OCHRE, ochre)
	_add_group("flowers", _leaf_mesh(), FLOWER, flowers)
	_add_group("stones", _stone_mesh(), STONE, stones)
	_add_group("soil", _leaf_mesh(), Color("#79654b"), soil)
	refresh_terrain()

func _add_anchor(position: Vector3) -> int:
	_anchors.append({"position": position})
	return _anchors.size() - 1

func _entry(anchor_index: int, transform_value: Transform3D) -> Dictionary:
	return {"anchor": anchor_index, "transform": transform_value}

func _append_canopy(anchor_index: int, tree_scale: float, sage_entries: Array[Dictionary], olive_entries: Array[Dictionary], light_entries: Array[Dictionary], ochre_entries: Array[Dictionary]) -> void:
	var centers: Array[Vector3] = [Vector3(-0.62, 2.2, 0), Vector3(0.58, 2.45, 0.12), Vector3(-0.18, 3.35, -0.25), Vector3(0.45, 2.65, 0.65)]
	var spacing := 0.24
	var occupied: Dictionary = {}
	for unscaled_center in centers:
		var center := unscaled_center * tree_scale
		var radius := Vector3(0.95, 0.95, 0.82) * tree_scale
		var extent := Vector3i(ceil(radius / spacing))
		for ix in range(-extent.x, extent.x + 1):
			for iy in range(-extent.y, extent.y + 1):
				for iz in range(-extent.z, extent.z + 1):
					var cell := Vector3i(round((center + Vector3(ix, iy, iz) * spacing) / spacing))
					var local := Vector3(cell) * spacing
					if ((local - center) / radius).length_squared() > 1.0: continue
					occupied[cell] = local
	# Only the exposed shell is rendered. Contiguous stepped crowns with a few
	# broad shade regions read as foliage instead of disconnected confetti.
	for cell: Vector3i in occupied:
		var interior := true
		for neighbor in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
			if not occupied.has(cell + neighbor): interior = false; break
		if interior: continue
		var local: Vector3 = occupied[cell]
		var transform_value := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (spacing + 0.015)), local)
		if anchor_index == 3:
			ochre_entries.append(_entry(anchor_index, transform_value))
		elif local.y > tree_scale * 3.05:
			light_entries.append(_entry(anchor_index, transform_value))
		elif local.x < -tree_scale * 0.25:
			sage_entries.append(_entry(anchor_index, transform_value))
		else:
			olive_entries.append(_entry(anchor_index, transform_value))

func _add_group(group_name: String, mesh: Mesh, color: Color, entries: Array[Dictionary]) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = entries.size()
	var instance := MultiMeshInstance3D.new()
	instance.name = "Garden_%s" % group_name
	instance.multimesh = multi
	instance.material_override = _material(color)
	add_child(instance)
	_groups[group_name] = {"multimesh": multi, "entries": entries}

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material

func _leaf_mesh() -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	return mesh

func _stone_mesh() -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	return mesh

func _cylinder_mesh() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.07
	mesh.bottom_radius = 0.11
	mesh.height = 1.0
	mesh.radial_segments = 6
	return mesh
