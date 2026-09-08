extends SceneTree
## Same-view caching must not hide real previews or weaken stale-revision guards.
const World = preload("res://scripts/building_world.gd")
const Grid = preload("res://scripts/visual_grid.gd")
var checks := 0
var failures := 0

class InspectedVisual:
	extends "res://scripts/cottage_visual.gd"
	var corner_boxes: Array = []

	func _add_instanced_boxes(node_name: String, boxes: Array, colour: Color) -> MultiMeshInstance3D:
		# Record the actual generated inputs, while still running the unmodified
		# upload path. The separate Mobile pixel gate verifies real rendering.
		if node_name == "CornerQuoins": corner_boxes = boxes.duplicate(true)
		return super._add_instanced_boxes(node_name, boxes, colour)

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)

func _run() -> void:
	var world := World.new()
	var visual := InspectedVisual.new()
	root.add_child(visual)
	var view: Dictionary = world.get_building("building-1")
	var revision: int = world.get_revision()
	visual.request_revision(revision)
	check(visual.apply_building(view, revision), "initial recipe renders")
	var first_id := visual.get_child(0).get_instance_id()
	check(visual.apply_building(view.duplicate(true), revision), "equal private recipe accepted")
	check(visual.get_child(0).get_instance_id() == first_id, "unchanged geometry instances retained")
	var original: Dictionary = view.duplicate(true)
	view["material_id"] = "rose_lime"
	check(visual.apply_building(view, revision), "changed same-revision preview accepted")
	check(visual.get_child(0).get_instance_id() != first_id, "mutating caller recipe cannot mutate cache")
	check(visual.apply_building(original, revision), "cancel restores authored recipe")
	var restored_id := visual.get_child(0).get_instance_id()
	check(visual.apply_building(original, revision) and visual.get_child(0).get_instance_id() == restored_id, "repeated cancel presentation is stable")
	check(world.get_building("building-1") == original, "render previews never mutate authoritative world")
	visual.request_revision(revision + 1)
	check(not visual.apply_building(original, revision), "cache never accepts stale revision")
	check(visual.apply_building(original, revision + 1), "new requested revision accepted")
	var dims: Vector3 = original["dimensions"]
	check(visual.corner_boxes.size() == 12, "all corner stone courses retained")
	for i in visual.corner_boxes.size():
		var piece: Dictionary = visual.corner_boxes[i]
		var quantized: Dictionary = Grid.quantized_box(piece["center"], piece["size"], visual._unit)
		var centre: Vector3 = quantized["center"]
		var half: Vector3 = quantized["size"] * 0.5
		check(absf(centre.x) + half.x > dims.x * 0.5 + 0.001, "corner X face does not coincide with wall: %d" % i)
		check(absf(centre.z) + half.z > dims.z * 0.5 + 0.001, "corner Z face does not coincide with wall: %d" % i)
	visual.queue_free()
	await process_frame
	print("cottage_render_stability_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
