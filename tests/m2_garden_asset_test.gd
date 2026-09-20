extends SceneTree
## Authored 0.0625-grid garden plot meshes: grid accuracy, declared footprint,
## grounded pivot, matte materials, bounded triangles, canonical cache, preview
## invariants, placement transforms and save-authority neutrality. Headless.
const Visual = preload("res://scripts/m2_composition_visual.gd")
const State = preload("res://scripts/landscape_state.gd")
const CELL := 0.0625
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _declared_units(path: String) -> Vector2i:
	var parts := path.split("x")
	if parts.size() != 2: return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))

func _run() -> void:
	for path_value in Visual.GARDEN_MESHES.values():
		var path := str(path_value)
		var mesh: ArrayMesh = load(path)
		_check(mesh != null, "Baked plot mesh loads: " + path)
		if mesh == null: continue
		var units := _declared_units(path.get_file().replace("hearthvale_garden_", "").replace(".res", ""))
		_check(units.x > 0 and units.y > 0, "Declared footprint units parse: " + path)
		var bounds := mesh.get_aabb()
		_check(is_equal_approx(bounds.size.x, units.x * CELL) and is_equal_approx(bounds.size.z, units.y * CELL), "Exact placement footprint: " + path)
		_check(bounds.position.y > -0.001 and bounds.position.y < 0.001, "Grounded base pivot: " + path)
		_check(bounds.size.y > 0.0 and bounds.size.y <= 0.7, "Miniature plot height: " + path)
		var triangles := 0
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			triangles += indices.size() / 3
			for point in points:
				_check(point.distance_to(point.snapped(Vector3.ONE * CELL)) < 0.00002, "Cubic 0.0625 grid: " + path)
			for i in range(0, indices.size(), 3):
				var cross := (points[indices[i + 1]] - points[indices[i]]).cross(points[indices[i + 2]] - points[indices[i]])
				_check(cross.length_squared() > 0.00000001 and cross.dot(normals[indices[i]]) < 0.0, "Outward nondegenerate winding: " + path)
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			_check(material != null and is_zero_approx(material.metallic) and is_equal_approx(material.roughness, 1.0), "Matte canonical material: " + path)
		_check(triangles >= 150 and triangles <= 3000, "Bounded plot triangle cost: " + path + " (" + str(triangles) + ")")
	# Placement: the three starter-hamlet plots through the saved-composition path.
	var state := State.new()
	var flower_id := state.add_composition("garden", "cottage_flowers", Vector2(30.25, 35.0), Vector2(1.0, 2.0), 0)
	var kitchen_id := state.add_composition("garden", "kitchen_rows", Vector2(16.0, 33.75), Vector2(3.0, 1.75), 1)
	var herb_id := state.add_composition("garden", "herb_garden", Vector2(20.25, 21.0), Vector2(1.5, 1.0), 3)
	_check(flower_id > 0 and kitchen_id > 0 and herb_id > 0, "Starter-hamlet plots accepted by saved composition")
	var before := state.document()
	var visual := Visual.new()
	root.add_child(visual)
	visual.rebuild_gardens(state.composition)
	_check(visual._garden_nodes.size() == 3, "All three plots rebuild")
	var expected_meshes := [
		"res://assets/models/magicavoxel/hearthvale_garden_flowers_16x32.res",
		"res://assets/models/magicavoxel/hearthvale_garden_kitchen_48x28.res",
		"res://assets/models/magicavoxel/hearthvale_garden_herbs_24x16.res",
	]
	var expected_ids := [flower_id, kitchen_id, herb_id]
	var expected_yaws := [0, 1, 3]
	for index in 3:
		var node: MeshInstance3D = visual._garden_nodes[index]
		var authored: ArrayMesh = load(expected_meshes[index])
		_check(int(node.get_meta("composition_id")) == expected_ids[index], "Stable identity kept: " + str(expected_ids[index]))
		_check(node.mesh == authored, "Authored 0.0625 mesh in use: " + expected_meshes[index])
		var aabb := authored.get_aabb()
		_check(absf(node.position.y - (8.0 + aabb.size.y * 0.5 - (aabb.end.y - aabb.size.y))) < 0.001, "Grounded placement height: " + expected_meshes[index])
		_check(node.basis.is_equal_approx(Basis(Vector3.UP, float(expected_yaws[index]) * PI * 0.5)), "Saved quarter-turn preserved: " + expected_meshes[index])
	# Preview invariants: a translucent, unshaded ghost that never mutates the
	# canonical cached resource.
	visual.show_garden_preview("kitchen_rows", Vector2(16.0, 33.75), Vector2(3.0, 1.75), 1, true)
	_check(visual._garden_preview_node != null, "Garden preview node shown")
	if visual._garden_preview_node != null:
		var canonical: ArrayMesh = load(expected_meshes[1])
		var ghost_mesh := visual._garden_preview_node.mesh as ArrayMesh
		_check(ghost_mesh != null and ghost_mesh != canonical and ghost_mesh.get_aabb().is_equal_approx(canonical.get_aabb()), "Preview ghost shares canonical bounds")
		var ghost_material := ghost_mesh.surface_get_material(0) as StandardMaterial3D
		var canonical_material := canonical.surface_get_material(0) as StandardMaterial3D
		_check(ghost_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and is_equal_approx(ghost_material.albedo_color.a, 0.56), "Ghost preview is translucent")
		_check(canonical_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and is_equal_approx(canonical_material.albedo_color.a, 1.0), "Canonical mesh stays opaque after preview")
	visual.hide_garden_preview()
	_check(state.document() == before, "All presentation work is save-authority neutral")
	visual.queue_free()
	await process_frame
	print("GARDEN_ASSET_CHECK " + JSON.stringify({"ok": failures.is_empty(), "checks": checks, "failures": failures.size(), "messages": failures}))
	quit(0 if failures.is_empty() else 1)
