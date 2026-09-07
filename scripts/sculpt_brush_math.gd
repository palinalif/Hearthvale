extends RefCounted
## Pure brush math. Surface samples are temporary edit-query data; the native
## 3D voxel buffer remains authoritative, including caves and overhangs.

static func influence(distance: float, radius: float, falloff: float) -> float:
	if not is_finite(distance) or not is_finite(radius) or not is_finite(falloff) or radius <= 0.0:
		return 0.0
	var t := clampf(distance / radius, 0.0, 1.0)
	if t >= 1.0:
		return 0.0
	# Falloff is the width of the soft rim, not an exponent that sharpens
	# every brush into a cone. Zero is a flat brush; one is a rounded dome.
	var rim := clampf(falloff, 0.0, 1.0)
	if rim <= 0.000001:
		return 1.0
	var edge := clampf((t - (1.0 - rim)) / rim, 0.0, 1.0)
	return 1.0 - edge * edge * (3.0 - 2.0 * edge)

static func surface_prefix(heights: PackedFloat64Array, width: int, depth: int) -> Dictionary:
	if width <= 0 or depth <= 0 or heights.size() != width * depth:
		return {}
	var stride := width + 1
	var sums := PackedFloat64Array()
	var counts := PackedInt32Array()
	sums.resize(stride * (depth + 1))
	counts.resize(sums.size())
	# A zero border makes inclusive/exclusive rectangle queries branch-free.
	for z in depth:
		var row_sum := 0.0
		var row_count := 0
		for x in width:
			var height := heights[x + z * width]
			if height >= 0.0 and is_finite(height):
				row_sum += height
				row_count += 1
			var index := x + 1 + (z + 1) * stride
			sums[index] = sums[index - stride] + row_sum
			counts[index] = counts[index - stride] + row_count
	return {"sums": sums, "counts": counts, "stride": stride, "width": width, "depth": depth}

static func surface_average(prefix: Dictionary, x0: int, z0: int, x1: int, z1: int) -> float:
	if prefix.is_empty():
		return -1.0
	var width: int = prefix["width"]
	var depth: int = prefix["depth"]
	x0 = clampi(x0, 0, width)
	x1 = clampi(x1, 0, width)
	z0 = clampi(z0, 0, depth)
	z1 = clampi(z1, 0, depth)
	if x1 <= x0 or z1 <= z0:
		return -1.0
	var stride: int = prefix["stride"]
	var sums: PackedFloat64Array = prefix["sums"]
	var counts: PackedInt32Array = prefix["counts"]
	var a := x0 + z0 * stride
	var b := x1 + z0 * stride
	var c := x0 + z1 * stride
	var d := x1 + z1 * stride
	var count := counts[d] - counts[b] - counts[c] + counts[a]
	if count == 0:
		return -1.0
	return (sums[d] - sums[b] - sums[c] + sums[a]) / float(count)
