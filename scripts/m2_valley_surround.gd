extends Node3D
## Disposable stepped scenery outside the editable native volume. There are no
## collision shapes or saved records here. The player's terrain is never filled
## or overwritten to disguise an edge. Border samples follow saved/sculpted land.
const Generator = preload("res://scripts/m1_patch_generator.gd")
const WIDTH := 16.0
const STEP := 0.5
const HEIGHT_STEP := 0.0625
var backend: Node
var _land: MeshInstance3D
var _water: MeshInstance3D
var _columns := 0
var _faces := 0
var _extent := Vector3.ZERO
var _edge_heights: Dictionary = {}

func rebuild(terrain_backend: Node) -> void:
	backend = terrain_backend
	if backend == null or not backend.is_ready(): return
	_extent = backend.world_size()
	_edge_heights.clear()
	var start := -roundi(WIDTH / STEP)
	var finish_x := ceili((_extent.x + WIDTH) / STEP)
	var finish_z := ceili((_extent.z + WIDTH) / STEP)
	var heights := {}
	for z in range(start, finish_z):
		for x in range(start, finish_x):
			var point := Vector2(float(x) + 0.5, float(z) + 0.5) * STEP
			if _inside(point): continue
			heights[Vector2i(x,z)] = _height(point)
	_columns = heights.size()
	var top := {"v": [], "n": [], "i": []}
	var sides := {"v": [], "n": [], "i": []}
	_faces = 0
	for key: Vector2i in heights:
		var x := float(key.x) * STEP
		var z := float(key.y) * STEP
		var y := float(heights[key])
		_quad(top, [Vector3(x,y,z),Vector3(x+STEP,y,z),Vector3(x+STEP,y,z+STEP),Vector3(x,y,z+STEP)], Vector3.UP)
		for direction: Vector2i in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.DOWN,Vector2i.UP]:
			var neighbour := key + direction
			var point := (Vector2(neighbour) + Vector2.ONE * 0.5) * STEP
			var low := float(heights.get(neighbour, -0.5))
			# At the playable boundary, use the native top rather than a guessed
			# generated height. The skirt covers only outside-facing gaps.
			if _inside(point): low = _border_height(point)
			if low >= y - 0.00001: continue
			match direction:
				Vector2i.RIGHT: _quad(sides,[Vector3(x+STEP,low,z),Vector3(x+STEP,low,z+STEP),Vector3(x+STEP,y,z+STEP),Vector3(x+STEP,y,z)],Vector3.RIGHT)
				Vector2i.LEFT: _quad(sides,[Vector3(x,low,z+STEP),Vector3(x,low,z),Vector3(x,y,z),Vector3(x,y,z+STEP)],Vector3.LEFT)
				Vector2i.DOWN: _quad(sides,[Vector3(x+STEP,low,z+STEP),Vector3(x,low,z+STEP),Vector3(x,y,z+STEP),Vector3(x+STEP,y,z+STEP)],Vector3.BACK)
				Vector2i.UP: _quad(sides,[Vector3(x,low,z),Vector3(x+STEP,low,z),Vector3(x+STEP,y,z),Vector3(x,y,z)],Vector3.FORWARD)
	var mesh := ArrayMesh.new()
	_add_surface(mesh,top,Color("#7d9957"))
	_add_surface(mesh,sides,Color("#ac9677"))
	if _land == null:
		_land = MeshInstance3D.new()
		_land.name = "ScenicTerracesOutsideEditableMap"
		add_child(_land)
	_land.mesh = mesh
	_rebuild_water()

func affected_by(edit: AABB) -> bool:
	if edit.size == Vector3.ZERO: return true
	return edit.position.x < STEP or edit.position.z < STEP or edit.end.x > _extent.x - STEP or edit.end.z > _extent.z - STEP

func stats() -> Dictionary:
	return {"columns":_columns,"faces":_faces,"editable":false,"width":WIDTH}

func _inside(point: Vector2) -> bool:
	return point.x >= 0.0 and point.y >= 0.0 and point.x < _extent.x and point.y < _extent.z

func _height(point: Vector2) -> float:
	var nearest := point.clamp(Vector2.ZERO,Vector2(_extent.x,_extent.z))
	var distance := point.distance_to(nearest)
	var edge := _border_height(nearest)
	# A broad shoulder rolls down through shallow steps into the distance.
	var blend := smoothstep(1.0, WIDTH, distance)
	var low := 1.0 + sin(point.x * 0.075 + 0.4) * 0.375 + sin(point.y * 0.09) * 0.375
	var channel_distance := absf(point.x - Generator.river_center_x(point.y))
	if point.y < 0.0 or point.y >= _extent.z:
		low = lerpf(5.5, low, smoothstep(4.0, 14.0, channel_distance))
	var height := lerpf(edge,low,blend)
	# Let the river leave the map naturally rather than stop against a wall.
	if point.y < 0.0 or point.y >= _extent.z:
		var river_distance := absf(point.x - Generator.river_center_x(point.y))
		if river_distance < Generator.river_half_width(point.y) + 0.5:
			height = minf(height,4.375)
	return snappedf(height,HEIGHT_STEP)

func _border_height(point: Vector2) -> float:
	var scale_value := float(backend.voxel_scale)
	var x := clampi(floori(point.x / scale_value),0,int(backend.patch_size.x)-1)
	var z := clampi(floori(point.y / scale_value),0,int(backend.patch_size.z)-1)
	var key := Vector2i(x,z)
	if _edge_heights.has(key): return float(_edge_heights[key])
	var height := 0.0
	for y in range(int(backend.patch_size.y)-1,-1,-1):
		if backend.voxel_at(Vector3i(x,y,z)) != 0:
			height = float(y+1) * scale_value
			break
	_edge_heights[key] = height
	return height

func _quad(data: Dictionary, corners: Array, normal: Vector3) -> void:
	var vertices: Array = data["v"]
	var normals: Array = data["n"]
	var indices: Array = data["i"]
	var base := vertices.size()
	for corner: Vector3 in corners:
		vertices.append(corner)
		normals.append(normal)
	indices.append_array(PackedInt32Array([base,base+1,base+2,base,base+2,base+3]))
	data["v"] = vertices
	data["n"] = normals
	data["i"] = indices
	_faces += 1

func _add_surface(mesh: ArrayMesh, data: Dictionary, colour: Color) -> void:
	if (data["v"] as Array).is_empty(): return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(data["v"])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(data["n"])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(data["i"])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	mesh.surface_set_material(mesh.get_surface_count()-1,material)

func _rebuild_water() -> void:
	var data := {"v":[],"n":[],"i":[]}
	for z in range(-roundi(WIDTH / STEP),ceili((_extent.z + WIDTH)/STEP)):
		var z0 := float(z) * STEP
		if z0 >= 0.0 and z0 < _extent.z: continue
		var z1 := z0 + STEP
		var a := Generator.river_center_x(z0)
		var b := Generator.river_center_x(z1)
		var wa := Generator.river_half_width(z0)
		var wb := Generator.river_half_width(z1)
		_quad(data,[Vector3(a-wa,5,z0),Vector3(a+wa,5,z0),Vector3(b+wb,5,z1),Vector3(b-wb,5,z1)],Vector3.UP)
	var mesh := ArrayMesh.new()
	_add_surface(mesh,data,Color(0.30,0.57,0.56,0.86))
	if mesh.get_surface_count() > 0:
		var material := mesh.surface_get_material(0) as StandardMaterial3D
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 0.42
	if _water == null:
		_water = MeshInstance3D.new()
		_water.name = "ScenicRiverBeyondMap"
		add_child(_water)
	_water.mesh = mesh
