extends RefCounted
## Disposable brush-local surface statistics, never authoritative terrain.
## Missing/retired columns do not contribute. The caller supplies a halo so
## the brush boundary is not mistaken for the edge of the landscape.

static func means(columns: Array[Vector3i], surfaces: Dictionary, radius: int = 2) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	if columns.is_empty() or radius < 0: return result
	var lower := Vector2i(columns[0].x, columns[0].z)
	var upper := lower
	for column in columns:
		lower = lower.min(Vector2i(column.x, column.z))
		upper = upper.max(Vector2i(column.x, column.z))
	lower -= Vector2i.ONE * radius
	upper += Vector2i.ONE * radius
	var width := upper.x - lower.x + 1
	var height := upper.y - lower.y + 1
	var stride := width + 1
	var sums := PackedFloat64Array()
	var counts := PackedInt32Array()
	sums.resize(stride * (height + 1))
	counts.resize(sums.size())
	sums.fill(0.0)
	counts.fill(0)
	for z in height:
		var row_sum := 0.0
		var row_count := 0
		for x in width:
			var value := float(surfaces.get(Vector3i(lower.x + x, 0, lower.y + z), -1.0))
			if value >= 0.0:
				row_sum += value
				row_count += 1
			var index := (z + 1) * stride + x + 1
			sums[index] = sums[index - stride] + row_sum
			counts[index] = counts[index - stride] + row_count
	result.resize(columns.size())
	for i in columns.size():
		var column := columns[i]
		var x0 := column.x - lower.x - radius
		var z0 := column.z - lower.y - radius
		var x1 := x0 + radius * 2 + 1
		var z1 := z0 + radius * 2 + 1
		var a := z0 * stride + x0
		var b := z0 * stride + x1
		var c := z1 * stride + x0
		var d := z1 * stride + x1
		var count := counts[d] - counts[b] - counts[c] + counts[a]
		result[i] = (sums[d] - sums[b] - sums[c] + sums[a]) / float(count) if count > 0 else -1.0
	return result
