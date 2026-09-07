extends RefCounted
## Immutable, brush-local input for a preview worker. Capture ONLY on the
## gameplay thread. No live Node or live VoxelBuffer crosses the boundary.
const COPIED_STATE := ["_stroke_tool", "_stroke_settings", "_stroke_reference", "_stroke_normal", "_stroke_front_axis", "_stroke_front_sign", "_stroke_fronts", "_stroke_front_cache_center", "_stroke_front_columns", "_stroke_front_influence", "_smooth_targets", "_smooth_targets_dirty"]

class ReadView extends RefCounted:
	var buffer: Object
	var origin: Vector3i
	var size: Vector3i
	var out_of_bounds_reads := 0
	func get_voxel(x: int, y: int, z: int, channel: int) -> int:
		var p := Vector3i(x, y, z) - origin
		if p.x < 0 or p.y < 0 or p.z < 0 or p.x >= size.x or p.y >= size.y or p.z >= size.z:
			out_of_bounds_reads += 1
			return 0
		return int(buffer.get_voxel(p.x, p.y, p.z, channel))

var patch_size := Vector3i.ZERO
var voxel_scale := 1.0
var voxels: ReadView
var state: Dictionary = {}
var plane_reference: Dictionary = {}
var copied_bytes := 0
var capture_ms := 0.0
var copied_fronts := 0

func is_ready() -> bool:
	return voxels != null

func _get(property: StringName) -> Variant:
	return state.get(property)

static func capture(source: Node, tool: String, world_center: Vector3, settings: Dictionary, plane: Dictionary = {}) -> RefCounted:
	if source == null or not source.is_ready() or not world_center.is_finite(): return null
	var started := Time.get_ticks_usec()
	var snapshot: RefCounted = load("res://scripts/sculpt_preview_snapshot.gd").new()
	snapshot.patch_size = source.patch_size
	snapshot.voxel_scale = source.voxel_scale
	var active := bool(source.get("_stroke_active"))
	var effective_tool := String(source.get("_stroke_tool")) if active else String(source._normalize_sculpt_tool(tool))
	if effective_tool.is_empty() or not source._world_center_valid(world_center): return null
	var radius := float(source.get("_stroke_settings")["radius"]) if active else clampf(float(settings.get("radius", 2.0)), 0.25, 8.0) / float(source.voxel_scale)
	var axis := int(source.get("_stroke_front_axis")) if active else int(source._dominant_axis(source._settings_normal(settings)))
	if effective_tool in ["level", "slope", "smooth"]: axis = 1
	var center: Vector3 = world_center / float(source.voxel_scale)
	var lower := Vector3i((center - Vector3.ONE * (radius + 4.0)).floor()).max(Vector3i.ZERO)
	var upper := (Vector3i((center + Vector3.ONE * (radius + 4.0)).ceil()) + Vector3i.ONE).min(source.patch_size)
	# Seeding can follow a contiguous solid all the way to its exposed end;
	# only that axis is complete. The two other axes stay brush + halo local.
	lower[axis] = 0
	upper[axis] = source.patch_size[axis]
	var size := upper - lower
	if size.x <= 0 or size.y <= 0 or size.z <= 0: return null
	var buffer: Object = ClassDB.instantiate("VoxelBuffer")
	buffer.set_channel_depth(0, source.voxels.get_channel_depth(0))
	buffer.create(size.x, size.y, size.z)
	buffer.copy_channel_from_area(source.voxels, lower, upper, Vector3i.ZERO, 0)
	snapshot.voxels = ReadView.new()
	snapshot.voxels.buffer = buffer
	snapshot.voxels.origin = lower
	snapshot.voxels.size = size
	snapshot.copied_bytes = size.x * size.y * size.z * (1 << int(buffer.get_channel_depth(0)))
	snapshot.state = {"_stroke_active": active, "_revision": source.get("_revision")}
	if active:
		for property in COPIED_STATE:
			var value: Variant = source.get(property)
			if property == "_stroke_fronts":
				value = _local_fronts(value, lower, upper, axis)
				snapshot.copied_fronts = value.size()
			elif value is Dictionary or value is Array or value is PackedFloat64Array: value = value.duplicate()
			snapshot.state[property] = value
	snapshot.plane_reference = plane.duplicate(true)
	if not active and effective_tool in ["level", "slope"] and snapshot.plane_reference.is_empty():
		# Same bounded reference probe as begin_stroke, on the owning thread.
		snapshot.plane_reference = source.sample_surface_plane(world_center, source._settings_normal(settings), float(settings.get("radius", 2.0)) + 1.0)
	snapshot.capture_ms = (Time.get_ticks_usec() - started) / 1000.0
	return snapshot

static func _local_fronts(fronts: Dictionary, lower: Vector3i, upper: Vector3i, axis: int) -> Dictionary:
	var axes := [0, 2] if axis == 1 else ([1, 2] if axis == 0 else [0, 1])
	var u := int(axes[0])
	var v := int(axes[1])
	var capacity := (upper[u] - lower[u]) * (upper[v] - lower[v])
	# Short strokes copy cheaply. Long stroke history never makes a small
	# brush copy the entire world's frontier dictionary on the gameplay thread.
	if fronts.size() <= capacity: return fronts.duplicate()
	var result: Dictionary = {}
	for a in range(lower[u], upper[u]):
		for b in range(lower[v], upper[v]):
			var column := Vector3i.ZERO
			column[u] = a
			column[v] = b
			if fronts.has(column): result[column] = fronts[column]
	return result
