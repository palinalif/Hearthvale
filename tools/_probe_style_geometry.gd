extends SceneTree
## Probe: which furniture styles actually produce geometry?

const HamletVisual = preload("res://scripts/m2_hamlet_visual.gd")
const StreetFurniture = preload("res://scripts/m2_scene_street_furniture.gd")

func _initialize() -> void:
	var visual: Node = HamletVisual.new()
	root.add_child(visual)
	var records: Array = []
	var order: Array[String] = []
	var i := 0
	for style in StreetFurniture.FURNITURE_STYLE_ORDER:
		order.append(style)
		i += 1
		records.append({
			"kind": "furniture", "style_id": style, "id": i,
			"position": [0.0, 0.0], "yaw_quarters": 0, "colour_id": "",
		})
	visual.rebuild_furniture(records, null)
	var nodes: Array = visual.get_children().filter(func(n): return String(n.name).begins_with("Furniture_"))
	print("styles=%d furniture_nodes=%d" % [order.size(), nodes.size()])
	for node in nodes:
		var mesh: Mesh = node.mesh
		var tris := 0
		if mesh != null:
			for s in mesh.get_surface_count():
				var a: Array = mesh.surface_get_arrays(s)
				tris += int(a[Mesh.ARRAY_INDEX].size() / 3) if a[Mesh.ARRAY_INDEX].size() > 0 else 0
		var id := int(node.get_meta("composition_id"))
		print("id=%d style=%s mesh=%s tris=%d authored=%s" % [
			id, order[id - 1], "yes" if mesh != null else "NULL", tris,
			str(node.get_meta("authored_asset"))])
	quit(0)
