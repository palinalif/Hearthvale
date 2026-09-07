extends RefCounted
## A bounded native occupancy snapshot, not a heightmap or terrain authority.
## Native remapping and byte searches skip air/solid runs without thousands of
## GDScript-to-native get_voxel calls. The source buffer is never modified.
var origin := Vector3i.ZERO
var size := Vector3i.ZERO
var axis := 1
var data_size := Vector3i.ZERO
var bytes_per_cell := 2
var bytes := PackedByteArray()
var copied_bytes := 0
static var _solid_map := PackedInt32Array()
static var _solid_map8 := PackedInt32Array()

func capture(source: Object, dimensions: Vector3i, center: Vector3, radius: float, facing_axis: int) -> bool:
	axis = facing_axis
	origin = Vector3i((center - Vector3.ONE * (radius + 3.0)).floor()).max(Vector3i.ZERO)
	var upper := Vector3i((center + Vector3.ONE * (radius + 3.0)).ceil()) + Vector3i.ONE
	upper = upper.min(dimensions)
	# The native seeder may walk to the end of a connected mass. Include the
	# complete queried axis, but only the brush + halo in the other two axes.
	origin[axis] = 0
	upper[axis] = dimensions[axis]
	size = upper - origin
	if size.x <= 0 or size.y <= 0 or size.z <= 0: return false
	var depth := int(source.get_channel_depth(0))
	if depth not in [0, 1]: return false
	bytes_per_cell = 1 << depth
	var snapshot: Object = ClassDB.instantiate("VoxelBuffer")
	snapshot.create(size.x, size.y, size.z)
	snapshot.set_channel_depth(0, depth)
	snapshot.copy_channel_from_area(source, origin, upper, Vector3i.ZERO, 0)
	if _solid_map.is_empty():
		_solid_map.resize(65536)
		_solid_map.fill(65535)
		_solid_map[0] = 0
	# 16-bit occupied cells become FF FF; 8-bit ones become FF. Both support
	# native byte searching for zero/nonzero with no material-ID assumptions.
	if depth == 0:
		if _solid_map8.is_empty():
			_solid_map8.resize(256)
			_solid_map8.fill(255)
			_solid_map8[0] = 0
		snapshot.remap_values(0, _solid_map8)
	else:
		snapshot.remap_values(0, _solid_map)
	# Native storage is ZXY with Y contiguous. Rotate X/Z rays onto +Y so all
	# six facing directions use the same bounded run search.
	if axis == 0: snapshot.rotate_90(Vector3.AXIS_Z, 1)
	elif axis == 2: snapshot.rotate_90(Vector3.AXIS_X, -1)
	data_size = snapshot.get_size()
	bytes = snapshot.get_channel_as_byte_array(0)
	copied_bytes = bytes.size()
	return copied_bytes == size.x * size.y * size.z * bytes_per_cell

func first(cell: Vector3i, direction: int, reach: int, occupied: bool) -> int:
	var local := cell - origin
	if local.x < 0 or local.y < 0 or local.z < 0 or local.x >= size.x or local.y >= size.y or local.z >= size.z or reach < 0: return -1
	var mapped := local
	if axis == 0: mapped = Vector3i(size.y - 1 - local.y, local.x, local.z)
	elif axis == 2: mapped = Vector3i(local.x, local.z, size.y - 1 - local.y)
	var last := clampi(mapped.y + direction * reach, 0, data_size.y - 1)
	var lower := mini(mapped.y, last)
	var upper := maxi(mapped.y, last)
	var offset := (mapped.z * data_size.x + mapped.x) * data_size.y
	# Bound the search itself, not merely its result. A global find on a huge
	# all-air array would otherwise scan subsequent columns before failing.
	var run := bytes.slice((offset + lower) * bytes_per_cell, (offset + upper + 1) * bytes_per_cell)
	var value := 255 if occupied else 0
	var found := run.find(value) if direction > 0 else run.rfind(value)
	return lower + found / bytes_per_cell + origin[axis] if found >= 0 else -1
