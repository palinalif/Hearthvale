extends RefCounted
## Disposable worker-owned occupancy, never authoritative terrain. Native
## remapping/rotation and bounded byte searches replace long per-cell scans.
var origin := Vector3i.ZERO
var size := Vector3i.ZERO
var rotated_size := Vector3i.ZERO
var axis := 1
var bytes_per_cell := 2
var data := PackedByteArray()
var uniform := -1

func build(buffer: Object, minimum: Vector3i, facing_axis: int) -> bool:
	var depth := int(buffer.get_channel_depth(0))
	if depth not in [0, 1]: return false
	origin = minimum
	size = buffer.get_size()
	axis = facing_axis
	bytes_per_cell = 1 << depth
	var local: Object = ClassDB.instantiate("VoxelBuffer")
	local.set_channel_depth(0, depth)
	local.create(size.x, size.y, size.z)
	local.copy_channel_from_area(buffer, Vector3i.ZERO, size, Vector3i.ZERO, 0)
	var map := PackedInt32Array()
	map.resize(256 if depth == 0 else 65536)
	map.fill(255 if depth == 0 else 65535)
	map[0] = 0
	local.remap_values(0, map)
	uniform = -1
	var raw: PackedByteArray = local.get_channel_as_byte_array(0)
	if raw.find(255) < 0: uniform = 0
	elif raw.find(0) < 0: uniform = 1
	# Uniform columns need neither rotation nor a byte search. This also
	# avoids uniform-buffer rotation size quirks in the bundled extension.
	if uniform >= 0:
		data = raw
		rotated_size = size
		return raw.size() == size.x * size.y * size.z * bytes_per_cell
	# Native OrthoBasis uses CLOCKWISE turns, unlike Basis rotations.
	# Map the queried positive axis onto positive Y (native contiguous axis).
	if axis == 0: local.rotate_90(Vector3.AXIS_Z, -1)
	elif axis == 2: local.rotate_90(Vector3.AXIS_X, 1)
	rotated_size = local.get_size()
	data = local.get_channel_as_byte_array(0)
	return data.size() == size.x * size.y * size.z * bytes_per_cell

func first(cell: Vector3i, direction: int, reach: int, occupied: bool) -> int:
	var p := cell - origin
	if reach < 0 or p.x < 0 or p.y < 0 or p.z < 0 or p.x >= size.x or p.y >= size.y or p.z >= size.z: return -1
	if uniform >= 0: return cell[axis] if bool(uniform) == occupied else -1
	var mapped := p
	if axis == 0: mapped = Vector3i(size.y - 1 - p.y, p.x, p.z)
	elif axis == 2: mapped = Vector3i(p.x, p.z, size.y - 1 - p.y)
	var last := clampi(mapped.y + direction * reach, 0, rotated_size.y - 1)
	var low := mini(mapped.y, last)
	var high := maxi(mapped.y, last)
	var offset := (mapped.z * rotated_size.x + mapped.x) * rotated_size.y
	var run := data.slice((offset + low) * bytes_per_cell, (offset + high + 1) * bytes_per_cell)
	var value := 255 if occupied else 0
	var found := run.find(value) if direction > 0 else run.rfind(value)
	return low + found / bytes_per_cell + origin[axis] if found >= 0 else -1
