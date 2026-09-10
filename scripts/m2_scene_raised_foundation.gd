extends "res://scripts/m2_scene_building_feedback.gd"

## Terrain-aware presentation for the Riverside Cottage. Its ordinary foundation
## remains quiet on flat ground; when the terrain drops away beside the house,
## staggered masonry courses extend down the exposed side instead of leaving the
## miniature looking like it is floating. This is disposable presentation only.

const RAISED_FOUNDATION_STYLE := "riverside_cottage"
const RAISED_FOUNDATION_THRESHOLD := 0.18
const RAISED_FOUNDATION_MAX_DEPTH := 1.75
const RAISED_FOUNDATION_SAMPLE_MARGIN_LOCAL := 0.65
const FOUNDATION_BRICK_LENGTH_LOCAL := 1.0
const FOUNDATION_BRICK_HEIGHT_LOCAL := 0.5
const FOUNDATION_BRICK_DEPTH_LOCAL := 0.5
const FOUNDATION_BRICK_COLOUR := Color("#a48770")

var _raised_foundation_roots: Dictionary = {}
var _raised_foundation_signature := ""

func _update_presentation() -> void:
	super._update_presentation()
	_refresh_raised_foundation_masonry()

func _refresh_raised_foundation_masonry(force: bool = false) -> void:
	if not building_world or not backend or not backend.has_method("voxel_at"):
		return
	var signature_parts: Array[String] = [str(_terrain_revision())]
	for building: Dictionary in building_world.get_buildings():
		signature_parts.append("%s|%s|%s|%s" % [building.get("id", ""), building.get("style_id", ""), building.get("transform", Transform3D.IDENTITY), building.get("dimensions", Vector3.ZERO)])
	var signature := "||".join(signature_parts)
	if not force and signature == _raised_foundation_signature:
		return
	_raised_foundation_signature = signature

	var seen := {}
	for building: Dictionary in building_world.get_buildings():
		var building_id := str(building.get("id", ""))
		if building_id.is_empty(): continue
		seen[building_id] = true
		if str(building.get("style_id", "")) != RAISED_FOUNDATION_STYLE:
			_remove_raised_foundation(building_id)
			continue
		var exposure := _foundation_side_exposure(building)
		if _max_foundation_exposure(exposure) < RAISED_FOUNDATION_THRESHOLD:
			_remove_raised_foundation(building_id)
			continue
		_rebuild_raised_foundation(building_id, building, exposure)

	for building_id in _raised_foundation_roots.keys():
		if not seen.has(building_id): _remove_raised_foundation(str(building_id))

func _foundation_side_exposure(building: Dictionary) -> Dictionary:
	var transform_value = building.get("transform", Transform3D.IDENTITY)
	if not transform_value is Transform3D: return {}
	var building_transform := transform_value as Transform3D
	var dimensions: Vector3 = building.get("dimensions", Vector3.ZERO)
	if not dimensions.is_finite() or dimensions.x <= 0.0 or dimensions.z <= 0.0: return {}
	var sample_margin := RAISED_FOUNDATION_SAMPLE_MARGIN_LOCAL
	var samples := {
		"front": [Vector3(-dimensions.x * 0.32, 0, -dimensions.z * 0.5 - sample_margin), Vector3(0, 0, -dimensions.z * 0.5 - sample_margin), Vector3(dimensions.x * 0.32, 0, -dimensions.z * 0.5 - sample_margin)],
		"back": [Vector3(-dimensions.x * 0.32, 0, dimensions.z * 0.5 + sample_margin), Vector3(0, 0, dimensions.z * 0.5 + sample_margin), Vector3(dimensions.x * 0.32, 0, dimensions.z * 0.5 + sample_margin)],
		"left": [Vector3(-dimensions.x * 0.5 - sample_margin, 0, -dimensions.z * 0.32), Vector3(-dimensions.x * 0.5 - sample_margin, 0, 0), Vector3(-dimensions.x * 0.5 - sample_margin, 0, dimensions.z * 0.32)],
		"right": [Vector3(dimensions.x * 0.5 + sample_margin, 0, -dimensions.z * 0.32), Vector3(dimensions.x * 0.5 + sample_margin, 0, 0), Vector3(dimensions.x * 0.5 + sample_margin, 0, dimensions.z * 0.32)],
	}
	var result := {}
	for side in samples:
		var heights: Array[float] = []
		for local_point: Vector3 in samples[side]:
			var world_point := building_transform * local_point
			var height := _foundation_surface_height(Vector2(world_point.x, world_point.z))
			if is_finite(height): heights.append(height)
		if heights.is_empty():
			result[side] = 0.0
			continue
		heights.sort()
		var ground_height := heights[heights.size() / 2]
		result[side] = clampf(building_transform.origin.y - ground_height, 0.0, RAISED_FOUNDATION_MAX_DEPTH)
	return result

func _foundation_surface_height(point: Vector2) -> float:
	var scale_value := maxf(0.001, float(backend.get("voxel_scale")))
	var patch: Vector3i = backend.get("patch_size")
	var x := clampi(floori(point.x / scale_value), 0, patch.x - 1)
	var z := clampi(floori(point.y / scale_value), 0, patch.z - 1)
	for y in range(patch.y - 2, -1, -1):
		if int(backend.voxel_at(Vector3i(x, y, z))) != 0 and int(backend.voxel_at(Vector3i(x, y + 1, z))) == 0:
			return float(y + 1) * scale_value
	return NAN

func _max_foundation_exposure(exposure: Dictionary) -> float:
	var result := 0.0
	for value in exposure.values(): result = maxf(result, float(value))
	return result

func _rebuild_raised_foundation(building_id: String, building: Dictionary, exposure: Dictionary) -> void:
	_remove_raised_foundation(building_id)
	var transform_value = building.get("transform", Transform3D.IDENTITY)
	if not transform_value is Transform3D: return
	var building_transform := transform_value as Transform3D
	var world_scale := building_transform.basis.get_scale().abs()
	if world_scale.y <= 0.0001: return
	var dimensions: Vector3 = building.get("dimensions", Vector3.ZERO)
	var x_transforms: Array[Transform3D] = []
	var z_transforms: Array[Transform3D] = []

	_append_side_bricks(x_transforms, z_transforms, "front", float(exposure.get("front", 0.0)) / world_scale.y, dimensions)
	_append_side_bricks(x_transforms, z_transforms, "back", float(exposure.get("back", 0.0)) / world_scale.y, dimensions)
	_append_side_bricks(x_transforms, z_transforms, "left", float(exposure.get("left", 0.0)) / world_scale.y, dimensions)
	_append_side_bricks(x_transforms, z_transforms, "right", float(exposure.get("right", 0.0)) / world_scale.y, dimensions)
	if x_transforms.is_empty() and z_transforms.is_empty(): return

	var root := Node3D.new()
	root.name = "RaisedFoundationMasonry_%s" % building_id
	root.transform = building_transform
	add_child(root)
	if not x_transforms.is_empty(): root.add_child(_foundation_multimesh("CoursesX", Vector3(FOUNDATION_BRICK_LENGTH_LOCAL, FOUNDATION_BRICK_HEIGHT_LOCAL, FOUNDATION_BRICK_DEPTH_LOCAL), x_transforms))
	if not z_transforms.is_empty(): root.add_child(_foundation_multimesh("CoursesZ", Vector3(FOUNDATION_BRICK_DEPTH_LOCAL, FOUNDATION_BRICK_HEIGHT_LOCAL, FOUNDATION_BRICK_LENGTH_LOCAL), z_transforms))
	_raised_foundation_roots[building_id] = root

func _append_side_bricks(x_transforms: Array[Transform3D], z_transforms: Array[Transform3D], side: String, local_depth: float, dimensions: Vector3) -> void:
	if local_depth * 0.25 < RAISED_FOUNDATION_THRESHOLD and local_depth < FOUNDATION_BRICK_HEIGHT_LOCAL:
		return
	var rows := clampi(ceili(local_depth / FOUNDATION_BRICK_HEIGHT_LOCAL), 1, 14)
	var along_x := side in ["front", "back"]
	var span := dimensions.x + 0.5 if along_x else dimensions.z + 0.5
	var edge := (dimensions.z * 0.5 + 0.25) if along_x else (dimensions.x * 0.5 + 0.25)
	var sign := -1.0 if side in ["front", "left"] else 1.0
	for row in rows:
		var offset := FOUNDATION_BRICK_LENGTH_LOCAL * 0.5 if row % 2 == 1 else 0.0
		var along := -span * 0.5 + FOUNDATION_BRICK_LENGTH_LOCAL * 0.5 + offset
		while along <= span * 0.5 - FOUNDATION_BRICK_LENGTH_LOCAL * 0.5 + 0.0001:
			var y := -(float(row) + 0.5) * FOUNDATION_BRICK_HEIGHT_LOCAL
			var position := Vector3(along, y, sign * edge) if along_x else Vector3(sign * edge, y, along)
			if along_x: x_transforms.append(Transform3D(Basis.IDENTITY, position))
			else: z_transforms.append(Transform3D(Basis.IDENTITY, position))
			along += FOUNDATION_BRICK_LENGTH_LOCAL

func _foundation_multimesh(node_name: String, brick_size: Vector3, transforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = brick_size
	var material := StandardMaterial3D.new()
	material.albedo_color = FOUNDATION_BRICK_COLOUR
	material.roughness = 0.96
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size(): multimesh.set_instance_transform(index, transforms[index])
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multimesh
	return node

func _remove_raised_foundation(building_id: String) -> void:
	if not _raised_foundation_roots.has(building_id): return
	var root: Node = _raised_foundation_roots[building_id]
	if is_instance_valid(root): root.queue_free()
	_raised_foundation_roots.erase(building_id)
