extends "res://scripts/m2_scene_house_editing.gd"

## Final presentation layer only: original roof authority, silhouette builders,
## editing and picking remain intact. Tags on generated nodes invalidate with
## their geometry, not with unrelated save revisions or camera movement.
const RoofCourses = preload("res://scripts/roof_course_layout.gd")
const RoofMassingVisual = preload("res://scripts/m2_house_massing_visual.gd")

func _ready() -> void:
	super._ready()
	_finish_all_roofs()

func _update_presentation() -> void:
	super._update_presentation()
	_finish_all_roofs()

func _apply_surface_material_preview() -> void:
	super._apply_surface_material_preview()
	_finish_all_roofs()

func _apply_roof_design_preview() -> void:
	super._apply_roof_design_preview()
	_finish_all_roofs()

func _refresh_massing_shell_for_visual(visual: Node3D, view: Dictionary) -> void:
	super._refresh_massing_shell_for_visual(visual, view)
	_finish_roof(visual, view)

func _finish_all_roofs() -> void:
	if not building_world or not RoofCourses.enabled: return
	var seen: Dictionary = {}
	var visuals: Array = cottage_visuals.values()
	visuals.append(cottage_visual)
	visuals.append(building_placement_ghost)
	for value in visuals:
		if not value is Node3D or not is_instance_valid(value): continue
		var visual := value as Node3D
		if seen.has(visual.get_instance_id()): continue
		seen[visual.get_instance_id()] = true
		var view: Variant = visual.get("_applied_view")
		if view is Dictionary and not (view as Dictionary).is_empty():
			_finish_roof(visual, _preview_massing_view(view))

func _finish_roof(visual: Node3D, view: Dictionary) -> void:
	var material_id := str(view.get("roof_material_id", "terracotta"))
	if not RoofCourses.enabled or not RoofCourses.supports(material_id): return
	var joined := visual.get_node_or_null("M2JoinedMassing") as Node3D
	if HouseMassing.sections_for(view).size() > 1:
		if joined: _finish_joined_roof(joined, view)
		return
	var custom := visual.get_node_or_null("M2RoofDesign") as Node3D
	# Custom profiles keep their original slabs. The first tessellated tint
	# study added thousands of boxes without enough visible improvement.
	if not custom: _finish_gable_roof(visual, view)
	# New geometry keeps StandardMaterial3D, including the existing metal/
	# shake finish contract and the player's live colour picker.
	_apply_extra_roof_material_to_visual(visual, material_id)
	var edge := visual.get_node_or_null("RoofEdgeLip") as GeometryInstance3D
	if edge:
		var fascia := edge.get_node_or_null("CourseFascia") as GeometryInstance3D
		if fascia: fascia.material_override = edge.material_override

func _finish_gable_roof(visual: Node3D, view: Dictionary) -> void:
	var first := visual.get_node_or_null("RoofTiles_0")
	if not first or first.has_meta("roof_courses"): return
	var unit: Vector3 = visual.get("_detail_unit")
	var dimensions: Vector3 = view["dimensions"]
	var ratio: float = visual.get("_roof_rise_ratio")
	var palette: Array = visual.get("_roof_tile_colors")
	var pieces := RoofCourses.gable(dimensions, unit, ratio, int(view.get("seed", 0)))
	_set_roof_scope_highlight(false)
	_roof_pick_key = ""
	for shade in 3:
		var old := visual.get_node_or_null("RoofTiles_%d" % shade) as GeometryInstance3D
		var was_visible := old.visible if old else true
		var overlay: Material = old.material_overlay if old else null
		if old:
			visual.remove_child(old)
			old.queue_free()
		var node: MultiMeshInstance3D = visual.call("_add_detail_boxes", "RoofTiles_%d" % shade, pieces[shade], palette[shade])
		node.set_meta("roof_courses", true)
		node.visible = was_visible
		node.material_overlay = overlay
		(node.material_override as StandardMaterial3D).roughness = 0.9
	var edge := visual.get_node_or_null("RoofEdgeLip") as Node3D
	if edge and not edge.has_node("CourseFascia"):
		var run := dimensions.z * 0.5 + 0.5
		var row := ceili(run / unit.z) - 1
		var z := (row + 0.5) * unit.z
		var height := snappedf(dimensions.y + dimensions.y * ratio * (1.0 - z / run), unit.y)
		var span := dimensions.x + 0.75
		var left := -snappedf(span * 0.5, unit.x)
		var width := ceili(span / (unit.x * 2.0)) * unit.x * 2.0
		var fascia: Array[Dictionary] = []
		for side in [-1.0, 1.0]:
			fascia.append(RoofCourses.piece(Vector3(left + width * 0.5, height - unit.y * 1.5, side * z), Vector3(width, unit.y, unit.z)))
		edge.add_child(RoofCourses.make_batch("CourseFascia", fascia, Color.WHITE))

func _finish_joined_roof(root: Node3D, view: Dictionary) -> void:
	var first := root.get_node_or_null("JoinedRoof_0")
	if not first or first.has_meta("roof_courses"): return
	# Preserve the existing joined-roof pitch and exact boxes. Only regroup
	# their quiet colours into stable courses, including across upper floors.
	_set_roof_scope_highlight(false)
	_roof_pick_key = ""
	var tiles: Array[Dictionary] = HouseMassing.roof_tiles(view)
	var by_cell: Dictionary = {}
	for tile in tiles: by_cell[tile["cell"]] = tile
	var buckets: Array = [[], [], []]
	var transform_value: Transform3D = view.get("transform", Transform3D.IDENTITY)
	var scale_value := transform_value.basis.get_scale().abs()
	var unit := Vector2(RoofGrid.COTTAGE_DETAIL_UNIT / scale_value.x, RoofGrid.COTTAGE_DETAIL_UNIT / scale_value.z)
	for tile in tiles:
		var centre: Vector3 = tile["center"]
		var slope: Vector2 = root.call("_roof_gradient", tile, by_cell)
		var column := floori(centre.x / unit.x)
		var row := floori(centre.z / unit.y)
		if absf(slope.x) > absf(slope.y):
			column = floori(centre.z / unit.y)
			row = floori(centre.x / unit.x)
		var shade := int(RoofCourses.address(column, row, int(view.get("seed", 0)))["shade"])
		var size := Vector3(HouseMassing.CELL * 1.14, RoofMassingVisual.ROOF_THICKNESS, HouseMassing.CELL * 1.14)
		var value: Transform3D = root.call("_roof_tile_transform", centre, size, slope)
		buckets[shade].append(value)
	var palette := _massing_roof_palette(str(view.get("roof_material_id", "terracotta")))
	for shade in 3:
		var old := root.get_node_or_null("JoinedRoof_%d" % shade)
		if old:
			root.remove_child(old)
			old.queue_free()
		root.call("_add_multimesh", "JoinedRoof_%d" % shade, buckets[shade], palette[shade], 0.9)
		var node := root.get_node_or_null("JoinedRoof_%d" % shade)
		if node: node.set_meta("roof_courses", true)
	root.call("_apply_highlight")
