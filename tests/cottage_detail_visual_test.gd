extends SceneTree
## Inspect quantized upload inputs headlessly; visual_grid_test separately
## verifies the actual native MultiMesh output under the Mobile renderer.
const World = preload("res://scripts/building_world.gd")
const Grid = preload("res://scripts/visual_grid.gd")
var checks := 0
var failures := 0

class InspectedVisual:
	extends "res://scripts/cottage_visual.gd"
	var uploads: Dictionary = {}
	func _make_instanced_boxes(node_name: String, boxes: Array, color: Color, unit: Vector3) -> MultiMeshInstance3D:
		var quantized: Array = []
		for piece in boxes:
			quantized.append(Grid.quantized_box(piece["center"], piece["size"], unit))
		var node := super._make_instanced_boxes(node_name, boxes, color, unit)
		uploads[str(node.name)] = {"boxes": quantized, "color": color, "unit": unit}
		return node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := World.new()
	world.add_detail("building-1", "flower_box", "wall-front", Vector3(0, 1.5, -7.02), "flower_box_wood")
	world.add_detail("building-1", "shutter", "wall-back", Vector3(0, 3.4, 7.02), "shutter_wood")
	var original: Dictionary = world.get_document()
	var view: Dictionary = world.get_building("building-1")
	var visual := InspectedVisual.new()
	root.add_child(visual)
	_check(visual.apply_building(view, 0), "initial fixture builds")
	var upload_snapshot: Dictionary = visual.uploads.duplicate(true)
	var recipe_snapshot: Dictionary = view.duplicate(true)
	visual.request_revision(1)
	_check(visual.apply_building(view, 1), "rebuild same recipe")
	_check(visual.uploads == upload_snapshot, "regeneration retains exact geometry and palette")
	_check(view == recipe_snapshot and world.get_document() == original, "render leaves recipe and authority untouched")
	var roof_snapshot: Dictionary = {}
	for key in visual.uploads:
		if str(key).begins_with("RoofTiles_"): roof_snapshot[key] = visual.uploads[key].duplicate(true)
	view["seed"] = int(view["seed"]) + 1
	visual.apply_building(view, 1)
	_check(visual.uploads != upload_snapshot, "seed changes derived craft")
	for key in roof_snapshot:
		_check(visual.uploads[key] == roof_snapshot[key], "seed leaves authoritative roof profile presentation unchanged: " + key)
	var round_layout: Dictionary = visual._window_layout({"asset_id": "window_round"}, Vector3(0, 3.4, -7.02), "front")
	var round_world_size := Vector2((round_layout["pane_size"] as Vector3).x * 0.25, (round_layout["pane_size"] as Vector3).y * 0.25)
	_check(round_world_size.is_equal_approx(Vector2(0.375, 0.375)), "round pane retains enlarged miniature size")
	# Fixed world detail units survive miniature/legacy scales and cardinal
	# attachment orientation. Nonuniform transforms are tested for detail only;
	# this test does not relax or redesign existing structural geometry.
	for scale_value in [Vector3.ONE * 0.25, Vector3.ONE * 0.5, Vector3.ONE, Vector3(0.25, 0.5, 1.0)]:
		view["transform"] = Transform3D(Basis.IDENTITY.scaled(scale_value), Vector3(3, 8, 4))
		visual.apply_building(view, 1)
		for child in visual.get_children():
			if not child.has_meta("cottage_detail_grid"): continue
			var upload: Dictionary = visual.uploads[str(child.name)]
			var cell: Vector3 = upload["unit"]
			var world_cell: Vector3 = (visual.transform.basis * child.transform.basis * cell).abs()
			_check(world_cell.is_equal_approx(Vector3.ONE * Grid.COTTAGE_DETAIL_UNIT), str(child.name) + " cubic world detail cell")
			var grid_ok := true
			for box in upload["boxes"]:
				for sign_x in [-1.0, 1.0]:
					for sign_y in [-1.0, 1.0]:
						for sign_z in [-1.0, 1.0]:
							var corner: Vector3 = box["center"] + box["size"] * Vector3(sign_x, sign_y, sign_z) * 0.5
							var point: Vector3 = visual.transform * child.transform * corner - visual.position
							grid_ok = grid_ok and point.is_equal_approx(point.snapped(Vector3.ONE * Grid.COTTAGE_DETAIL_UNIT))
			_check(grid_ok, str(child.name) + " full-transform phase")
	# All three choices are geometric and deterministic, not stochastic noise.
	var cell := Vector3.ONE * 0.25
	var shutter_signatures: Array = []
	for variant in 3:
		shutter_signatures.append(visual._shutter_pieces(0, 0.75, 3.0, cell, variant))
	_check(shutter_signatures[0] != shutter_signatures[1] and shutter_signatures[1] != shutter_signatures[2], "three distinct shutter craft choices")
	var variants: Dictionary = {}
	for index in 24:
		variants[visual._craft_variant({"id": "detail-%d" % index, "asset_id": "window_wood"})] = true
	_check(variants.size() == 3, "stable detail identities reach all craft choices")
	visual.free()
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "detail_unit": Grid.COTTAGE_DETAIL_UNIT}))
	quit(1 if failures else 0)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 30: print("FAIL: " + label)
