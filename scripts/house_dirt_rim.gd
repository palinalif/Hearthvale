extends RefCounted

## Render-only packed-dirt shoulder around a placed home's foundation: a one
## fine-cell rim lying on the open ground just outside the wall, so a committed
## house does not read as floating over grass.
##
## This is a sibling of scripts/m2_scene_raised_foundation.gd, not a rewrite of
## it. The raised-foundation masonry band spans |half extent| .. +0.5 in building
## local units (offset 0.25 plus half a 0.5-deep brick), and the rim starts half a
## fine cell clear of that, so the two systems never share a face plane and cannot
## z-fight; the rim also sinks a quarter cell into the terrain, so it never shares
## the ground plane with the terrain top face.
##
## Presentation only: derived from the building record, no landscape record, no
## terrain write, no new save data, no per-frame work, one draw call per house.
## A spot that is water (the carved river band) or a painted path is skipped.
const Site = preload("res://scripts/house_landing_site.gd")
const Flora = preload("res://scripts/vegetation_mesh.gd")

const UNIT := Flora.PROP_UNIT
const MASONRY_OUTER_LOCAL := 0.5
const MASONRY_CLEARANCE := UNIT * 0.5
const MAX_CELLS := 4096
const SOIL_SINK_FRACTION := 0.25
## Mirrors the packed-earth soil palette in scripts/m2_packed_earth.gd. That file
## belongs to the path branch, so the literals are copied rather than edited in.
const SOIL_BASE := Color("#916b52")
const SOIL_EDGE := Color("#866149")
const SOIL_WEAR := Color("#ad8567")

static var _material: StandardMaterial3D

## Deterministic description of the rim: no mesh, no scene, fully testable.
static func plan(building: Dictionary, site_value: Dictionary) -> Array:
	var result: Array = []
	var dimensions: Vector3 = building.get("dimensions", Vector3.ZERO)
	var transform_value = building.get("transform", Transform3D.IDENTITY)
	if not dimensions.is_finite() or not transform_value is Transform3D: return result
	if dimensions.x <= 0.0 or dimensions.z <= 0.0: return result
	var building_transform := transform_value as Transform3D
	var world_scale := building_transform.basis.get_scale().abs()
	if world_scale.x <= 0.0001 or world_scale.y <= 0.0001 or world_scale.z <= 0.0001: return result
	var unit := Vector3(UNIT / world_scale.x, UNIT / world_scale.y, UNIT / world_scale.z)
	var half := Vector2(dimensions.x * 0.5, dimensions.z * 0.5)
	var band := MASONRY_OUTER_LOCAL + MASONRY_CLEARANCE
	var factor := 1.0
	var offsets := ring_offsets(half, band, unit.x, unit.z)
	if offsets.size() > MAX_CELLS:
		factor = 2.0
		offsets = ring_offsets(half, band, unit.x * factor, unit.z * factor)
	if offsets.size() > MAX_CELLS: return result
	var cell := Vector3(unit.x * factor, unit.y, unit.z * factor)
	var seed_value := Site.identity(str(building.get("id", "")), 29, building_transform.origin)
	for offset: Vector2 in offsets:
		var world := world_point(building_transform, offset)
		var ground := Site.ground_height(site_value, world)
		if is_nan(ground): continue
		var local_y := (ground - building_transform.origin.y) / world_scale.y
		var key := Vector2i(roundi(offset.x / cell.x), roundi(offset.y / cell.z))
		result.append({
			"key": key,
			"centre": Vector3(offset.x, local_y + cell.y * (0.5 - SOIL_SINK_FRACTION), offset.y),
			"colour": soil_colour(seed_value, key),
			"cell": cell,
			"ground": ground,
		})
	return result

## Ring cell centres in building-local space: the two long rows carry the full
## span (corners included) and the two short rows stop one cell short of them, so
## no cell is emitted twice.
static func ring_offsets(half: Vector2, band: float, cell_x: float, cell_z: float) -> Array:
	var result: Array = []
	var kx := floori((half.x + band) / cell_x) + 1
	var kz := floori((half.y + band) / cell_z) + 1
	var centre_x := float(kx) * cell_x
	var centre_z := float(kz) * cell_z
	for ix in range(-kx, kx + 1):
		var x := float(ix) * cell_x
		result.append(Vector2(x, centre_z))
		result.append(Vector2(x, -centre_z))
	for iz in range(-(kz - 1), kz):
		var z := float(iz) * cell_z
		result.append(Vector2(centre_x, z))
		result.append(Vector2(-centre_x, z))
	return result

## Quiet soil tone: small deterministic drift, rare worn patches. Same integer
## identity discipline as the planting ring (no RNG, stable across reloads).
static func soil_colour(seed_value: int, key: Vector2i) -> Color:
	var tone := float(Site.cell_hash(seed_value, key.x, key.y, 17) % 100) / 100.0
	var colour := SOIL_BASE.lerp(SOIL_EDGE, tone * 0.35)
	if Site.cell_hash(seed_value, key.x, key.y, 19) % 7 == 0:
		colour = colour.lerp(SOIL_WEAR, 0.18)
	return colour

static func world_point(building_transform: Transform3D, offset: Vector2) -> Vector2:
	var world := building_transform * Vector3(offset.x, 0.0, offset.y)
	return Vector2(world.x, world.z)

## Batched rim mesh. One draw call for the whole house.
static func build(building: Dictionary, site_value: Dictionary) -> Dictionary:
	var cells := plan(building, site_value)
	var result := {"mesh": null, "plan": cells, "cells": cells.size(), "draw_calls": 0, "vertices": 0, "triangles": 0, "digest": digest(cells)}
	if cells.is_empty(): return result
	var target := Site.geometry()
	for entry: Dictionary in cells:
		Site.emit_box(target, entry["centre"], entry["cell"], entry["colour"])
	if _material == null: _material = Site.prop_material()
	var mesh := Site.mesh_from(target, _material)
	if mesh == null: return result
	result["mesh"] = mesh
	result["draw_calls"] = 1
	result["vertices"] = (target["vertices"] as Array).size()
	result["triangles"] = (target["indices"] as Array).size() / 3
	return result

## Determinism digest over the derived rim only (no GPU state).
static func digest(plan_value: Array) -> String:
	var payload: Array = []
	for entry: Dictionary in plan_value:
		payload.append([entry["key"], entry["centre"], entry["colour"]])
	return var_to_bytes(payload).hex_encode().sha256_text()
