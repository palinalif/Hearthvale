extends RefCounted

## Render-only house-edge planting: a deterministic ring of small grass tufts
## around every placed home, so a committed building reads as grown into the
## landscape instead of dropped onto it. Presentation only - no planting records,
## no terrain writes, no new save data, no per-frame work.
##
## The ring is a sibling of the raised-foundation presentation
## (scripts/m2_scene_raised_foundation.gd): it owns its own roots and leaves that
## masonry, the structural grid, collision and save data untouched.
##
## Reconciliation comes from the records, not from stored planting: the ring is
## re-derived from the building record (id + transform + dimensions) on every
## presentation pass, so a moved, resized, duplicated, undone or reloaded house
## gets exactly the ring its record describes - and no new save format is
## introduced (zero save-compat risk).
##
## Tufts are decorative fine cells (0.0625 m, the approved half-scale foliage
## family), batched into one mesh = one draw call per house.
const Site = preload("res://scripts/house_landing_site.gd")
const Flora = preload("res://scripts/vegetation_mesh.gd")

const UNIT := Flora.PROP_UNIT
## Ring sits outside the raised-foundation masonry band (0.5 local) and outside
## the dirt rim band, so no two systems share a face plane.
const RING_CLEARANCE_LOCAL := 0.5
const RIM_BAND_CELLS := 2
const CORNER_TUFTS := 4
const EDGE_TUFTS := 2
const MAX_TUFTS := 16
const MAX_COLUMNS := 2
const TALL_COLUMN_CELLS := 3
const SHORT_COLUMN_CELLS := 2
const SPAWN_JITTER_CELLS := 2
const TALL_SAMPLE_CHANCE := 5
const EDGE_TUFTS_ON_LONG_EDGES_ONLY := true

static var _material: StandardMaterial3D

## Deterministic description of the ring: no mesh, no scene, fully testable.
static func plan(building: Dictionary, site_value: Dictionary) -> Array:
	var result: Array = []
	var dimensions: Vector3 = building.get("dimensions", Vector3.ZERO)
	var transform_value = building.get("transform", Transform3D.IDENTITY)
	if not dimensions.is_finite() or not transform_value is Transform3D: return result
	if dimensions.x <= 0.0 or dimensions.z <= 0.0: return result
	var building_transform := transform_value as Transform3D
	var world_scale := building_transform.basis.get_scale().abs()
	if world_scale.x <= 0.0001 or world_scale.y <= 0.0001 or world_scale.z <= 0.0001: return result
	var cell := UNIT / world_scale.x
	var cell_y := UNIT / world_scale.y
	var half := Vector2(dimensions.x * 0.5, dimensions.z * 0.5)
	var band := RING_CLEARANCE_LOCAL + float(RIM_BAND_CELLS) * cell
	var seed_value := Site.identity(str(building.get("id", "")), 11, building_transform.origin)
	var slots := _slots(half, band, cell, seed_value)
	var occupied := {}
	for slot: Dictionary in slots:
		if result.size() >= MAX_TUFTS: break
		var base: Vector2 = slot["point"]
		var outward: Vector2 = slot["outward"]
		var jitter := float(Site.cell_hash(seed_value, int(slot["index"]), 1) % 100) / 100.0
		var point := base + outward * (jitter * float(SPAWN_JITTER_CELLS) * cell)
		# The decorative cell must be open ground, flat over its own footprint,
		# and not shared with another tuft.
		var world := _world_point(building_transform, point)
		var ground := Site.ground_height(site_value, world)
		if is_nan(ground): continue
		if not Site.flat_at(site_value, world, UNIT, ground): continue
		var world_cell := Vector2i(floori(world.x / UNIT), floori(world.y / UNIT))
		if occupied.has(world_cell): continue
		# Companion cell: a second fine column one cell along the wall.
		var step := Vector2(outward.y, -outward.x)
		if Site.cell_hash(seed_value, int(slot["index"]), 3) % 2 == 0: step = -step
		var companion := point + step * cell
		var companion_world := _world_point(building_transform, companion)
		var companion_ground := Site.ground_height(site_value, companion_world)
		if is_nan(companion_ground): continue
		if not Site.flat_at(site_value, companion_world, UNIT, companion_ground): continue
		var companion_cell := Vector2i(floori(companion_world.x / UNIT), floori(companion_world.y / UNIT))
		if occupied.has(companion_cell): continue
		var tall := Site.cell_hash(seed_value, int(slot["index"]), 5) % TALL_SAMPLE_CHANCE == 0
		var heights: Array[int] = [TALL_COLUMN_CELLS if tall else SHORT_COLUMN_CELLS, 1]
		var root_y := (ground - building_transform.origin.y) / world_scale.y
		var companion_y := (companion_ground - building_transform.origin.y) / world_scale.y
		if absf(root_y - companion_y) > cell_y * 2.0: continue
		occupied[world_cell] = true
		occupied[companion_cell] = true
		result.append({
			"key": world_cell,
			"root": Vector3(point.x, root_y, point.y),
			"companion": Vector3(companion.x, companion_y, companion.y),
			"heights": heights,
			"seed": Site.cell_hash(seed_value, int(slot["index"]), 7),
			"cell": cell,
			"cell_y": cell_y,
		})
	return result

## Corners plus a couple of tufts per edge, deterministic in the building id.
static func _slots(half: Vector2, band: float, cell: float, seed_value: int) -> Array:
	var slots: Array = []
	var outer := half + Vector2.ONE * band
	var indices := [-1, 1]
	var corner_index := 0
	for sign_x: int in indices:
		for sign_z: int in indices:
			slots.append({
				"point": Vector2(float(sign_x) * outer.x, float(sign_z) * outer.y),
				"outward": Vector2(float(sign_x), float(sign_z)).normalized(),
				"index": corner_index,
			})
			corner_index += 1
	var long_axis_is_x := half.x >= half.y
	for side in 4:
		if EDGE_TUFTS_ON_LONG_EDGES_ONLY and ((side % 2 == 0) != long_axis_is_x): continue
		var along_x := side % 2 == 0
		var sign := -1.0 if side < 2 else 1.0
		var length := half.x if along_x else half.y
		for k in EDGE_TUFTS:
			var t := (float(k) + 1.0) / (float(EDGE_TUFTS) + 1.0)
			var jitter := float(Site.cell_hash(seed_value, side + 4, k, 13) % 21) / 100.0 - 0.10
			var along := (t + jitter) * length * 2.0 - length
			var point := Vector2(along, sign * outer.y) if along_x else Vector2(sign * outer.x, along)
			var outward := Vector2(0.0, sign) if along_x else Vector2(sign, 0.0)
			slots.append({"point": point, "outward": outward, "index": 4 + side * EDGE_TUFTS + k})
	return slots

static func _world_point(building_transform: Transform3D, point: Vector2) -> Vector2:
	var world := building_transform * Vector3(point.x, 0.0, point.y)
	return Vector2(world.x, world.z)

## Batched ring mesh. One draw call for the whole house.
static func build(building: Dictionary, site_value: Dictionary) -> Dictionary:
	var tufts := plan(building, site_value)
	var result := {"mesh": null, "plan": tufts, "tufts": tufts.size(), "cells": 0, "draw_calls": 0, "vertices": 0, "triangles": 0, "digest": digest(tufts)}
	if tufts.is_empty(): return result
	var target := Site.geometry()
	var cells := 0
	for tuft: Dictionary in tufts:
		var shade: Color = Flora.COLORS[0].lerp(Flora.COLORS[2], 0.20 if int(tuft["seed"]) % 3 == 0 else 0.0)
		var size := Vector3(float(tuft["cell"]), float(tuft["cell_y"]), float(tuft["cell"]))
		var columns := [
			[tuft["root"], int((tuft["heights"] as Array)[0])],
			[tuft["companion"], int((tuft["heights"] as Array)[1])],
		]
		for column: Array in columns:
			var root: Vector3 = column[0]
			for level in int(column[1]):
				var centre := root + Vector3.UP * (float(level) + 0.5) * float(tuft["cell_y"])
				Site.emit_box(target, centre, size, shade)
				cells += 1
	if cells == 0: return result
	if _material == null: _material = Site.prop_material()
	var mesh := Site.mesh_from(target, _material)
	if mesh == null: return result
	result["mesh"] = mesh
	result["cells"] = cells
	result["draw_calls"] = 1
	result["vertices"] = (target["vertices"] as Array).size()
	result["triangles"] = (target["indices"] as Array).size() / 3
	return result

## Determinism digest over the derived plan only (no GPU state).
static func digest(plan_value: Array) -> String:
	var payload: Array = []
	for tuft: Dictionary in plan_value:
		payload.append([tuft["key"], tuft["root"], tuft["companion"], tuft["heights"], tuft["seed"]])
	return var_to_bytes(payload).hex_encode().sha256_text()
