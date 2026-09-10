extends "res://scripts/m2_scene_roof_materials.gd"

## Terrain editing needs the hovered house to read clearly against the sculpt
## preview. Keep the established building/detail outline thickness untouched.
const BUILDING_OUTLINE_GROW_AMOUNT := 0.12
const TERRAIN_HOUSE_OUTLINE_GROW_AMOUNT := 0.24

func _set_world_mesh_highlight(building_id: String) -> void:
	# The terrain hover in the inherited layer uses CottageVisual's normal
	# building highlight material. Restore its established thickness before a
	# highlighted house is cleared or changed so Building mode always sees the
	# original 0.12 grow amount.
	if building_id != _world_mesh_highlight_id:
		_set_world_outline_grow(_world_mesh_highlight_id, BUILDING_OUTLINE_GROW_AMOUNT)
	super._set_world_mesh_highlight(building_id)
	if view_context == "terrain" and not building_id.is_empty():
		_set_world_outline_grow(building_id, TERRAIN_HOUSE_OUTLINE_GROW_AMOUNT)

func _set_world_outline_grow(building_id: String, grow_amount: float) -> void:
	if building_id.is_empty(): return
	var visual: Node3D = cottage_visuals.get(building_id, null) as Node3D
	if not is_instance_valid(visual): return
	for child in visual.get_children():
		if not child is GeometryInstance3D: continue
		var overlay: Material = (child as GeometryInstance3D).material_overlay
		if overlay is StandardMaterial3D:
			(overlay as StandardMaterial3D).grow_amount = grow_amount
