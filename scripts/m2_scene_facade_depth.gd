extends "res://scripts/m2_scene_joined_roof_courses.gd"

## Presentation-only architectural relief. It follows current saved wall/detail
## records but never adds authoritative surfaces, openings, anchors or history.
const FacadeDepth = preload("res://scripts/facade_depth_layout.gd")
const BRICK_STYLE := "riverside_cottage"
const BRICK_START_LOCAL := 0.9
const BRICK_SPACING_LOCAL := 1.5
const BRICK_TOP_MARGIN_LOCAL := 0.75

var _facade_signatures: Dictionary = {}

func _ready() -> void:
	super._ready()
	_refresh_facade_depth(true)

func _update_presentation() -> void:
	super._update_presentation()
	_refresh_facade_depth()

func _apply_surface_material_preview() -> void:
	super._apply_surface_material_preview()
	_refresh_facade_depth(true)

func _refresh_massing_shell_for_visual(visual: Node3D, view: Dictionary) -> void:
	super._refresh_massing_shell_for_visual(visual, view)
	_finish_facade_for_visual(visual, view, true)

func _refresh_facade_depth(force: bool = false) -> void:
	var seen: Dictionary = {}
	var visuals: Array = cottage_visuals.values()
	visuals.append(cottage_visual)
	visuals.append(building_placement_ghost)
	for value in visuals:
		if not value is Node3D or not is_instance_valid(value): continue
		var visual := value as Node3D
		if seen.has(visual.get_instance_id()): continue
		seen[visual.get_instance_id()] = true
		var applied = visual.get("_applied_view")
		if not applied is Dictionary or (applied as Dictionary).is_empty(): continue
		_finish_facade_for_visual(visual, _preview_massing_view(applied as Dictionary), force)

func _finish_facade_for_visual(visual: Node3D, view: Dictionary, force: bool = false) -> void:
	var visual_key := int(visual.get_instance_id())
	var signature := str([FacadeDepth.enabled, view.get("id", ""), view.get("dimensions", Vector3.ZERO), view.get("style_id", ""), view.get("wall_material_id", ""), view.get("surfaces", []), view.get("details", [])])
	if not force and str(_facade_signatures.get(visual_key, "")) == signature and visual.get_node_or_null("M2FacadeDepthMarker"):
		return
	_remove_facade_nodes(visual)
	_facade_signatures[visual_key] = signature
	if not FacadeDepth.enabled:
		_set_legacy_quoin_visibility(visual, true)
		return
	_set_legacy_quoin_visibility(visual, false)
	var detail_value = visual.get("_detail_unit")
	if not detail_value is Vector3: return
	var detail_unit: Vector3 = detail_value
	var runs := FacadeDepth.wall_runs(view)
	if runs.is_empty(): return
	var shell := FacadeDepth.shell_pieces(view, runs, detail_unit)
	var palette := _facade_palette(view)
	_add_facade_batch(visual, "M2FacadePlinth", shell["plinth"], palette["stone"])
	_add_facade_batch(visual, "M2FacadeEaveReveal", shell["eave"], palette["shadow"])
	var sills: Array[Dictionary] = []
	var lintels: Array[Dictionary] = []
	var thresholds: Array[Dictionary] = []
	_append_opening_relief(visual, view, detail_unit, sills, lintels, thresholds)
	_add_facade_batch(visual, "M2FacadeWindowSills", sills, palette["trim"])
	_add_facade_batch(visual, "M2FacadeWindowLintels", lintels, palette["trim"])
	_add_facade_batch(visual, "M2FacadeDoorThresholds", thresholds, palette["stone"])
	_add_facade_batch(visual, "M2FacadeBrickQuoins", _brick_corner_pieces(view, runs, detail_unit), palette["brick"])
	var marker := Node3D.new()
	marker.name = "M2FacadeDepthMarker"
	marker.set_meta("facade_depth", true)
	visual.add_child(marker)

func _append_opening_relief(visual: Node3D, view: Dictionary, detail_unit: Vector3, sills: Array[Dictionary], lintels: Array[Dictionary], thresholds: Array[Dictionary]) -> void:
	var orientations: Dictionary = {}
	for value in view.get("surfaces", []):
		if not value is Dictionary: continue
		var surface: Dictionary = value
		orientations[str(surface.get("id", ""))] = str(surface.get("orientation", "front"))
	for value in view.get("details", []):
		if not value is Dictionary: continue
		var detail: Dictionary = value
		if not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)): continue
		var kind := str(detail.get("kind", ""))
		if kind not in ["window", "door"]: continue
		var local = detail.get("resolved_position", null)
		if not local is Vector3: continue
		var surface_id := str((detail.get("anchor", {}) as Dictionary).get("surface_id", ""))
		var orientation := str(orientations.get(surface_id, "front"))
		if kind == "window":
			var layout_value = visual.call("_window_layout", detail, local as Vector3, orientation)
			if not layout_value is Dictionary: continue
			var layout: Dictionary = layout_value
			var asset_id := str(detail.get("asset_id", ""))
			if asset_id == "window_bay": continue
			var basis: Basis = layout.get("basis", Basis.IDENTITY)
			var anchor: Vector3 = layout.get("anchor_center", Vector3.ZERO)
			var pane_center: Vector3 = layout.get("pane_center", Vector3.ZERO)
			var pane_size: Vector3 = layout.get("pane_size", Vector3(2, 2.8, detail_unit.z))
			var cell := (basis.inverse() * detail_unit).abs()
			var half := Vector2(pane_size.x, pane_size.y) * 0.5
			# The base joinery already owns the visible sill/frame height. Extend
			# only its outer depth, so this pass reads as relief rather than a
			# second chunky outline around every opening.
			_append_oriented_piece(sills, basis, anchor, pane_center + Vector3(0, -half.y - cell.y * 0.5, cell.z * 2.5), Vector3(pane_size.x + cell.x * 2.0, cell.y, cell.z * 2.0))
			if not asset_id.contains("round"):
				_append_oriented_piece(lintels, basis, anchor, pane_center + Vector3(0, half.y + cell.y * 0.5, cell.z * 2.0), Vector3(pane_size.x + cell.x * 2.0, cell.y, cell.z))
		else:
			var layout_value = visual.call("_door_layout", detail, local as Vector3, orientation)
			if not layout_value is Dictionary: continue
			var layout: Dictionary = layout_value
			var basis: Basis = layout.get("basis", Basis.IDENTITY)
			var anchor: Vector3 = layout.get("anchor_center", Vector3.ZERO)
			var leaf_center: Vector3 = layout.get("leaf_center", Vector3.ZERO)
			var leaf_size: Vector3 = layout.get("leaf_size", Vector3(1.75, 3.7, detail_unit.z))
			var cell := (basis.inverse() * detail_unit).abs()
			_append_oriented_piece(thresholds, basis, anchor, leaf_center + Vector3(0, -leaf_size.y * 0.5 - cell.y * 0.5, cell.z * 2.0), Vector3(leaf_size.x + cell.x * 2.0, cell.y, cell.z * 3.0))

func _brick_corner_pieces(view: Dictionary, runs: Array[Dictionary], detail_unit: Vector3) -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	if str(view.get("style_id", "")) != BRICK_STYLE: return pieces
	if not detail_unit.is_finite() or detail_unit.x <= 0.0 or detail_unit.y <= 0.0 or detail_unit.z <= 0.0: return pieces
	var spans := _brick_corner_spans(runs)
	for span in spans:
		var point: Vector2 = span["point"]
		var bottom := float(span["bottom"])
		var top := float(span["top"])
		var y := snappedf(bottom + BRICK_START_LOCAL, detail_unit.y)
		var level := 0
		while y <= top - BRICK_TOP_MARGIN_LOCAL + 0.001:
			var long_x := posmod(level + roundi(point.x / detail_unit.x) + roundi(point.y / detail_unit.z), 2) == 0
			var size := Vector3(detail_unit.x * (3.0 if long_x else 2.0), detail_unit.y * 2.0, detail_unit.z * (2.0 if long_x else 3.0))
			pieces.append({"center": Vector3(point.x, y, point.y), "size": size, "basis": Basis.IDENTITY})
			y += BRICK_SPACING_LOCAL
			level += 1
	return pieces

func _brick_corner_spans(runs: Array[Dictionary]) -> Array[Dictionary]:
	var points: Dictionary = {}
	for run in runs:
		var orientation := str(run.get("orientation", ""))
		if orientation not in ["front", "back", "left", "right"]: continue
		var axis := "x" if orientation in ["front", "back"] else "z"
		var normal := float(run.get("normal", 0.0))
		var bottom := float(run.get("bottom", 0.0))
		var top := float(run.get("top", 0.0))
		for tangent_value in [float(run.get("tangent_min", 0.0)), float(run.get("tangent_max", 0.0))]:
			var point := Vector2(tangent_value, normal) if axis == "x" else Vector2(normal, tangent_value)
			var key := "%.4f|%.4f" % [point.x, point.y]
			if not points.has(key): points[key] = {"point": point, "x": [], "z": []}
			(points[key][axis] as Array).append(Vector2(bottom, top))
	var result: Array[Dictionary] = []
	for key_value in points.keys():
		var record: Dictionary = points[key_value]
		var overlaps: Array[Vector2] = []
		for x_value in record["x"]:
			var x_span: Vector2 = x_value
			for z_value in record["z"]:
				var z_span: Vector2 = z_value
				var low := maxf(x_span.x, z_span.x)
				var high := minf(x_span.y, z_span.y)
				if high > low + 0.001: overlaps.append(Vector2(low, high))
		if overlaps.is_empty(): continue
		overlaps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var merged: Array[Vector2] = []
		for overlap in overlaps:
			if merged.is_empty() or overlap.x > merged[-1].y + 0.001:
				merged.append(overlap)
			else:
				var tail := merged[-1]
				tail.y = maxf(tail.y, overlap.y)
				merged[-1] = tail
		for span in merged:
			result.append({"point": record["point"], "bottom": span.x, "top": span.y})
	return result

func _set_legacy_quoin_visibility(visual: Node3D, visible: bool) -> void:
	var legacy := visual.get_node_or_null("CornerQuoins") as Node3D
	if legacy: legacy.visible = visible

func _append_oriented_piece(target: Array[Dictionary], basis: Basis, anchor: Vector3, center: Vector3, size: Vector3) -> void:
	var transformed_center := anchor + basis * center
	var transformed_size := (basis * size).abs()
	target.append({"center": transformed_center, "size": transformed_size, "basis": Basis.IDENTITY})

func _facade_palette(view: Dictionary) -> Dictionary:
	var material_id := str(view.get("wall_material_id", view.get("material_id", "stone_plaster")))
	var trim := Color("#d2bd9e")
	var stone := Color("#957d69")
	match material_id:
		"warm_plaster": trim = Color("#dfc4a3"); stone = Color("#9d7f68")
		"timber": trim = Color("#78584a"); stone = Color("#87786a")
		"pale_stone": trim = Color("#d4c4ad"); stone = Color("#887f75")
		"chalk_white": trim = Color("#ded2bc"); stone = Color("#8e8478")
		"moss_stone": trim = Color("#c0c6ad"); stone = Color("#788273")
		"rose_lime": trim = Color("#e2c0ad"); stone = Color("#97786e")
	var style := str(view.get("style_id", "riverside_cottage"))
	if style == "woodland_lodge": trim = Color("#78584a")
	elif style == "village_gable": trim = trim.lightened(0.05)
	return {"trim": trim, "stone": stone, "brick": Color("#b38f70"), "shadow": trim.darkened(0.34)}

func _add_facade_batch(visual: Node3D, node_name: String, boxes: Array, colour: Color) -> void:
	if boxes.is_empty(): return
	var node_value = visual.call("_add_detail_boxes", node_name, boxes, colour)
	if not node_value is GeometryInstance3D: return
	var node := node_value as GeometryInstance3D
	node.set_meta("facade_depth", true)
	if node.material_override is StandardMaterial3D:
		(node.material_override as StandardMaterial3D).roughness = 0.94

func _remove_facade_nodes(visual: Node3D) -> void:
	for child in visual.get_children():
		if str(child.name).begins_with("M2Facade"):
			visual.remove_child(child)
			child.queue_free()
