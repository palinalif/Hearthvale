extends RefCounted
## Derived scenery outside the native foothills. Rasterise only the lowest
## mountain triangles onto the native 0.125 lattice, then expose their voxel
## tops/risers. No collision, terrain buffers, checkpoint records or per-frame
## work. The continuous face underneath hides the thin irregular outer seam.
const CELL := 0.125
# Two-cell risers retain the native lattice while allowing longer merged faces.
const MIN_COORD := -12.0
const GRID := 1472
const EMPTY := -1000.0

static func shade(height: float) -> Color:
	var value := lerpf(0.98, 0.52, smoothstep(22.0, 100.0, height))
	return Color(value, value, value)

static func build(rings: Array, material: Material) -> ArrayMesh:
	var heights := PackedFloat32Array()
	heights.resize(GRID * GRID)
	heights.fill(EMPTY)
	var segments: int = rings[0].size()
	for row in range(rings.size() - 1):
		for i in segments:
			var next := (i + 1) % segments
			_raster(heights, rings[row][i], rings[row+1][i], rings[row][next], Vector3(row,row+1,row)/float(rings.size()-1))
			_raster(heights, rings[row][next], rings[row+1][i], rings[row+1][next], Vector3(row,row+1,row+1)/float(rings.size()-1))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var buffers: Array = [vertices, normals, colors, indices]
	for z in GRID:
		var x := 0
		while x < GRID:
			var height := heights[z * GRID + x]
			if height == EMPTY:
				x += 1
				continue
			var end := x + 1
			while end < GRID and heights[z * GRID + end] == height:
				end += 1
			var x0 := MIN_COORD + x * CELL
			var x1 := MIN_COORD + end * CELL
			var z0 := MIN_COORD + z * CELL
			_quad(buffers, Vector3(x0,height,z0), Vector3(x1,height,z0), Vector3(x0,height,z0+CELL), Vector3(x1,height,z0+CELL), Vector3.UP)
			x = end
	# Merge coplanar risers along each axis as well as the top runs. Internal
	# faces are omitted; boundary skirts extend only 0.5 m into the underlay.
	for axis in 2:
		for direction in [-1, 1]:
			for row in GRID:
				var column := 0
				while column < GRID:
					var range_y := _edge(heights, axis, row, column, direction)
					if range_y.x <= range_y.y:
						column += 1
						continue
					var end := column + 1
					while end < GRID and _edge(heights, axis, row, end, direction) == range_y:
						end += 1
					var along0 := MIN_COORD + column * CELL
					var along1 := MIN_COORD + end * CELL
					var across := MIN_COORD + (row + (1 if direction > 0 else 0)) * CELL
					var a: Vector3
					var b: Vector3
					var normal: Vector3
					if axis == 0:
						a = Vector3(along0,range_y.x,across)
						b = Vector3(along1,range_y.x,across)
						normal = Vector3(0,0,direction)
					else:
						a = Vector3(across,range_y.x,along0)
						b = Vector3(across,range_y.x,along1)
						normal = Vector3(direction,0,0)
					var down := Vector3(0,range_y.y-range_y.x,0)
					_quad(buffers,a,b,a+down,b+down,normal)
					column = end
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = buffers[0]
	arrays[Mesh.ARRAY_NORMAL] = buffers[1]
	arrays[Mesh.ARRAY_COLOR] = buffers[2]
	arrays[Mesh.ARRAY_INDEX] = buffers[3]
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	result.surface_set_material(0, material)
	return result

static func _edge(heights: PackedFloat32Array, axis: int, row: int, column: int, direction: int) -> Vector2:
	var index := row * GRID + column if axis == 0 else column * GRID + row
	var high := heights[index]
	if high == EMPTY:
		return Vector2.ZERO
	var neighbor := row + direction
	var low := EMPTY
	if neighbor >= 0 and neighbor < GRID:
		low = heights[index + direction * (GRID if axis == 0 else 1)]
	if low == EMPTY:
		low = high - 0.5
	return Vector2(high, low)

static func _raster(heights: PackedFloat32Array, a: Vector3, b: Vector3, c: Vector3, progress: Vector3) -> void:
	var low := Vector2(minf(a.x,minf(b.x,c.x)),minf(a.z,minf(b.z,c.z)))
	var high := Vector2(maxf(a.x,maxf(b.x,c.x)),maxf(a.z,maxf(b.z,c.z)))
	var x0 := clampi(floori((low.x-MIN_COORD)/CELL),0,GRID-1)
	var x1 := clampi(ceili((high.x-MIN_COORD)/CELL),0,GRID-1)
	var z0 := clampi(floori((low.y-MIN_COORD)/CELL),0,GRID-1)
	var z1 := clampi(ceili((high.y-MIN_COORD)/CELL),0,GRID-1)
	var ab := Vector2(b.x-a.x,b.z-a.z)
	var ac := Vector2(c.x-a.x,c.z-a.z)
	var determinant := ab.cross(ac)
	if absf(determinant) < 0.000001:
		return
	for z in range(z0,z1+1):
		for x in range(x0,x1+1):
			var point := Vector2(MIN_COORD+(x+0.5)*CELL,MIN_COORD+(z+0.5)*CELL)
			var offset := point - Vector2(a.x,a.z)
			var u := offset.cross(ac)/determinant
			var v := ab.cross(offset)/determinant
			if u < 0.0 or v < 0.0 or u+v > 1.0:
				continue
			var height := a.y + u*(b.y-a.y) + v*(c.y-a.y)
			# Keep the complete river corridor untouched.
			if height <= 6.0:
				continue
			# A broken outer edge avoids a ruler-straight change of surface style.
			var distance := progress.x + u*(progress.y-progress.x) + v*(progress.z-progress.x)
			if distance > 0.78 + 0.18*sin(point.x*0.16+point.y*0.11):
				continue
			heights[z*GRID+x] = maxf(heights[z*GRID+x],ceilf(height/(CELL*2.0))*(CELL*2.0) + CELL*2.0)

static func _quad(buffers: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	var first: int = buffers[0].size()
	for point in [a,b,c,d]:
		buffers[0].append(point)
		buffers[1].append(normal)
		buffers[2].append(shade(point.y))
	# Godot front faces are clockwise when viewed from the outward normal.
	var order := [0,1,2,2,1,3] if (b-a).cross(c-a).dot(normal) < 0.0 else [0,2,1,2,3,1]
	for index in order:
		buffers[3].append(first+index)
