extends "res://scripts/m2_scene_multi_floor_layout.gd"

## Town-building default: every newly generated upper-storey facade gets a
## sensible automatic window layout immediately. The M2 BuildingWorld owns the
## stable generated detail records; this layer simply runs that reflow after
## massing wall surfaces have been synchronized inside the same transaction.
func _sync_surface_record(building: Dictionary) -> bool:
	if not super._sync_surface_record(building): return false
	building_world._reflow_automatic_windows(building)
	return true
