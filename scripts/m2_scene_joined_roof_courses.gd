extends "res://scripts/m2_scene_roof_courses.gd"

const JoinedCourses = preload("res://scripts/joined_roof_course_layout.gd")

func _finish_joined_roof(root: Node3D, view: Dictionary) -> void:
	if not JoinedCourses.enabled:
		super._finish_joined_roof(root, view)
		return
	var first := root.get_node_or_null("JoinedRoof_0")
	if not first or first.has_meta("joined_course_skin"): return
	var transform_value: Transform3D = view.get("transform", Transform3D.IDENTITY)
	var scale_value := transform_value.basis.get_scale().abs()
	if scale_value.x <= 0 or not scale_value.is_equal_approx(Vector3.ONE * scale_value.x):
		super._finish_joined_roof(root, view)
		return
	var unit := Vector3.ONE * RoofGrid.COTTAGE_DETAIL_UNIT / scale_value.x
	var tiles := HouseMassing.roof_tiles(view)
	var by_cell: Dictionary = {}
	for tile in tiles: by_cell[tile["cell"]] = tile
	var slopes: Dictionary = {}
	for tile in tiles: slopes[tile["cell"]] = root.call("_roof_gradient", tile, by_cell)
	var cells := JoinedCourses.columns(tiles, slopes, unit, int(view.get("seed", 0)))
	if cells.is_empty():
		super._finish_joined_roof(root, view)
		return
	var faces := JoinedCourses.quads(cells)
	var boxes := JoinedCourses.pick_boxes(cells, unit)
	var palette := _massing_roof_palette(str(view.get("roof_material_id", "terracotta")))
	_set_roof_scope_highlight(false)
	_roof_pick_key = ""
	for shade in 3:
		var old := root.get_node_or_null("JoinedRoof_%d" % shade) as GeometryInstance3D
		var was_visible := old.visible if old else true
		if old:
			root.remove_child(old)
			old.queue_free()
		var node := MeshInstance3D.new()
		node.name = "JoinedRoof_%d" % shade
		node.mesh = JoinedCourses.make_mesh(faces, unit, shade)
		var material := StandardMaterial3D.new()
		material.albedo_color = palette[shade]
		material.roughness = 0.92 if str(view.get("roof_material_id", "")) == "wood_shake" else 0.9
		node.material_override = material
		node.visible = was_visible
		node.set_meta("joined_course_skin", true)
		node.set_meta("cottage_detail_grid", RoofGrid.COTTAGE_DETAIL_UNIT)
		# All three draws receive highlighting, but the solid pick runs are
		# cached only once. Never target the single combined mesh AABB.
		node.set_meta("joined_course_pick_boxes", boxes if shade == 0 else [])
		root.add_child(node)
	root.call("_apply_highlight")

func _cache_roof_boxes(node: Node3D, visual: Node3D, inside_roof: bool) -> void:
	if not node.visible: return
	if not node.has_meta("joined_course_skin"):
		super._cache_roof_boxes(node, visual, inside_roof)
		return
	_roof_pick_nodes.append(node as GeometryInstance3D)
	var relative := visual.global_transform.affine_inverse() * node.global_transform
	var buckets: Dictionary = {}
	for box: AABB in node.get_meta("joined_course_pick_boxes", []):
		_bucket_roof_box(buckets, relative * box)
	for bucket in buckets.values(): _roof_pick_groups.append(bucket)
