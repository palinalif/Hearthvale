extends SceneTree

const World = preload("res://scripts/building_world.gd")
const Visual = preload("res://scripts/cottage_visual.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	var world := World.new()
	var visual := Visual.new()
	var view: Dictionary = world.get_building("building-1")
	visual.request_revision(world.get_revision())
	visual.apply_building(view, world.get_revision())
	var detail: Dictionary = view["details"][0]
	var local: Vector3 = detail["resolved_position"]
	_check(not _wall_hit(visual.get_node("WallFront"), local), "actual wall opening behind editable window")
	_check(_wall_hit(visual.get_node("WallFront"), Vector3(0, 0.8, -7.02)), "solid wall below windows")
	_check(_clockwise_faces(visual), "outward normals and clockwise rendered triangles agree")
	world.move_detail("building-1", str(detail["id"]), "wall-front", Vector3(-2.6, 4.8, -7.02))
	world.resize("building-1", Vector3(23, 8, 12))
	visual.request_revision(world.get_revision())
	visual.apply_building(world.get_building("building-1"), world.get_revision())
	var moved: Dictionary = world.get_building("building-1")["details"][0]
	_check(not _wall_hit(visual.get_node("WallFront"), moved["resolved_position"]), "opening follows moved detail after resizing")
	world.suppress_detail("building-1", str(detail["id"]))
	visual.request_revision(world.get_revision())
	visual.apply_building(world.get_building("building-1"), world.get_revision())
	_check(visual.get_node_or_null("Detail_%s" % detail["id"]) == null, "suppression removes entire window presentation")
	_check(_wall_hit(visual.get_node("WallFront"), moved["resolved_position"]), "suppression closes the wall opening")
	visual.free()
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "visual_geometry": true}))
	quit(1 if failures else 0)

func _wall_hit(wall: MeshInstance3D, position: Vector3) -> bool:
	var arrays := wall.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in range(0, indices.size(), 3):
		var a: Vector3 = wall.transform * vertices[indices[i]]
		var b: Vector3 = wall.transform * vertices[indices[i+1]]
		var c: Vector3 = wall.transform * vertices[indices[i+2]]
		if Geometry3D.ray_intersects_triangle(position + Vector3(0, 0, -3), Vector3.BACK, a, b, c) != null: return true
	return false

func _clockwise_faces(visual: Node3D) -> bool:
	for child in visual.get_children():
		if not child is MeshInstance3D or not child.mesh is ArrayMesh: continue
		if child.mesh.get_surface_count() == 0: continue
		var arrays: Array = child.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0, indices.size(), 3):
			var a := vertices[indices[i]]
			var b := vertices[indices[i+1]]
			var c := vertices[indices[i+2]]
			if (b-a).cross(c-a).dot(normals[indices[i]]) >= 0: return false
	return true

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: " + label)

