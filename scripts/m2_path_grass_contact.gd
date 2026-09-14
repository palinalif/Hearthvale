extends RefCounted

## Render-only edge contact; no planting records, terrain writes or frame work.
## Reuses the existing path box batcher and vegetation's cubic detail tier/palette.
const Flora = preload("res://scripts/vegetation_mesh.gd")
const UNIT := Flora.PROP_UNIT
const MAX_TUFTS := 128
const MAX_PER_PATH := 16
const MAX_CELLS_PER_TUFT := 4
const MAX_HEIGHT := UNIT * 3.0
const STONE_VERTICES := 50
const CLEARANCE := UNIT * 0.707107 + 0.003
static var _material: StandardMaterial3D

static func record_primary(builder: Dictionary, path_id: int, cluster: int, surface: int) -> void:
	if not builder.has("contact_primaries"): builder["contact_primaries"] = []
	var vertices: Array = builder["surfaces"][surface]["vertices"]
	builder["contact_primaries"].append({"path_id": path_id, "cluster": cluster, "surface": surface, "offset": vertices.size() - STONE_VERTICES})

static func empty_result() -> Dictionary:
	return {"mesh": null, "tufts": 0, "cells": 0, "roots": [], "primary_ids": [], "primary_count": 0, "draw_calls": 0, "vertices": 0, "triangles": 0}

static func _seed(path_id: int, cluster: int, salt: int = 0) -> int:
	# Integer identity only: no RNG, frame time, terrain revision or input order.
	var value := posmod(path_id, 1000003) * 92821 + cluster * 68917 + salt * 2833
	value = posmod(value, 104729)
	return posmod(value * value * 31 + value * 17, 104729)

static func selected_primaries(candidates: Array) -> Array:
	var counts := {}
	var ranked: Array = candidates.duplicate(true)
	for item: Dictionary in ranked:
		var path_id := int(item["path_id"])
		counts[path_id] = int(counts.get(path_id, 0)) + 1
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["path_id"]) != int(b["path_id"]): return int(a["path_id"]) < int(b["path_id"])
		var rank_a := _seed(int(a["path_id"]), int(a["cluster"]))
		var rank_b := _seed(int(b["path_id"]), int(b["cluster"]))
		return rank_a < rank_b if rank_a != rank_b else int(a["cluster"]) < int(b["cluster"]))
	var result: Array = []
	var used := {}
	var accepted := {}
	for item: Dictionary in ranked:
		if result.size() >= MAX_TUFTS: break
		var path_id := int(item["path_id"])
		var cluster := int(item["cluster"])
		var budget := mini(MAX_PER_PATH, floori(float(counts[path_id]) * 0.35))
		if int(used.get(path_id, 0)) >= budget: continue
		# Never decorate consecutive stepping targets. Hash ranking makes the
		# empty runs uneven rather than placing grass at every Nth stone.
		if accepted.has(Vector2i(path_id, cluster - 1)) or accepted.has(Vector2i(path_id, cluster + 1)): continue
		accepted[Vector2i(path_id, cluster)] = true
		used[path_id] = int(used.get(path_id, 0)) + 1
		result.append(item)
	return result

static func footprint(vertices: Array, offset: int) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for index in 8:
		var point: Vector3 = vertices[offset + 2 + index * 2]
		ring.append(Vector2(point.x, point.z))
	return ring

static func footprint_bins(builder: Dictionary) -> Dictionary:
	var bins := {}
	for surface: Dictionary in builder["surfaces"]:
		var vertices: Array = surface["vertices"]
		for offset in range(0, vertices.size(), STONE_VERTICES):
			var centre: Vector3 = vertices[offset]
			var key := Vector2i(floori(centre.x), floori(centre.z))
			if not bins.has(key): bins[key] = []
			bins[key].append(footprint(vertices, offset))
	return bins

static func clears_stones(point: Vector2, bins: Dictionary) -> bool:
	var key := Vector2i(floori(point.x), floori(point.y))
	# All locked stones have footprint radius < 1 m. Only neighbouring bins
	# can intersect a detail cell; this does not scan every stone per tuft.
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for ring: PackedVector2Array in bins.get(key + Vector2i(dx, dz), []):
				if Geometry2D.is_point_in_polygon(point, ring): return false
				for edge in 8:
					var nearest := Geometry2D.get_closest_point_to_segment(point, ring[edge], ring[(edge + 1) % 8])
					if point.distance_to(nearest) < CLEARANCE: return false
	return true

static func build(renderer: Node, stones: Dictionary) -> Dictionary:
	var result := empty_result()
	var candidates: Array = stones.get("contact_primaries", [])
	result["primary_count"] = candidates.size()
	if candidates.is_empty(): return result
	var bins := footprint_bins(stones)
	var selected := selected_primaries(candidates)
	var grass: Dictionary = renderer._new_builder()
	var colors := PackedColorArray()
	var occupied := {}
	for item: Dictionary in selected:
		var source: Array = stones["surfaces"][int(item["surface"])]["vertices"]
		var ring := footprint(source, int(item["offset"]))
		# Small primaries, all companions and third stones remain undecorated.
		if ring[0].distance_to(ring[5]) < 0.28 or ring[2].distance_to(ring[7]) < 0.34: continue
		var path_id := int(item["path_id"])
		var cluster := int(item["cluster"])
		var seed_value := _seed(path_id, cluster, 5)
		var edge := seed_value % 8
		var tangent := (ring[(edge + 1) % 8] - ring[edge]).normalized()
		var outward := Vector2(-tangent.y, tangent.x)
		var alpha := 0.27 + float(_seed(path_id, cluster, 7) % 37) / 100.0
		var point := ring[edge].lerp(ring[(edge + 1) % 8], alpha) + outward * (UNIT * 1.15)
		var cell := Vector2i(floori(point.x / UNIT), floori(point.y / UNIT))
		var step := Vector2i(1 if tangent.x > 0.0 else -1, 0) if absf(tangent.x) > absf(tangent.y) else Vector2i(0, 1 if tangent.y > 0.0 else -1)
		if seed_value % 2 == 0: step = -step
		var roots: Array[Vector3] = []
		var valid := true
		for root_cell: Vector2i in [cell, cell + step]:
			var xz := (Vector2(root_cell) + Vector2.ONE * 0.5) * UNIT
			if not clears_stones(xz, bins) or occupied.has(root_cell):
				valid = false
				break
			if renderer.backend == null:
				valid = false
				break
			var patch: Vector3i = renderer.backend.get("patch_size")
			var scale_value := float(renderer.backend.get("voxel_scale"))
			if xz.x < UNIT or xz.y < UNIT or xz.x >= float(patch.x) * scale_value - UNIT or xz.y >= float(patch.z) * scale_value - UNIT:
				valid = false
				break
			var height: float = renderer._surface_height(xz)
			# A cell never straddles a terrace or hangs off it. Its own footprint
			# must agree with the native height, not with the stone top.
			for corner: Vector2 in [Vector2(-0.49, -0.49), Vector2(0.49, -0.49), Vector2(0.49, 0.49), Vector2(-0.49, 0.49)]:
				if not is_equal_approx(float(renderer._surface_height(xz + corner * UNIT)), height): valid = false
			roots.append(Vector3(xz.x, height, xz.y))
		if not valid or roots.size() != 2: continue
		if absf(roots[0].y - roots[1].y) > UNIT * 2.0: continue
		for column in 2:
			var height_cells := (3 if seed_value % 5 == 0 else 2) if column == 0 else 1
			for level in height_cells:
				var center := roots[column] + Vector3.UP * (float(level) + 0.5) * UNIT
				renderer._append_box(grass, center, Vector3.ONE * UNIT, Basis.IDENTITY, 0)
				var shade: Color = Flora.COLORS[0].lerp(Flora.COLORS[2], 0.20 if (seed_value + column) % 3 == 0 else 0.0)
				for vertex in 24: colors.append(shade)
			occupied[cell if column == 0 else cell + step] = true
		result["roots"].append_array(roots)
		result["primary_ids"].append(Vector2i(path_id, cluster))
		result["tufts"] = int(result["tufts"]) + 1
	result["cells"] = int(grass["cells"])
	if int(result["cells"]) == 0: return result
	var surface: Dictionary = grass["surfaces"][0]
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(surface["vertices"])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(surface["normals"])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(surface["indices"])
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		# Vegetation palette values are authored in sRGB, like albedo colours.
		_material.vertex_color_is_srgb = true
		_material.roughness = 1.0
		_material.metallic_specular = 0.0
	mesh.surface_set_material(0, _material)
	result["mesh"] = mesh
	result["draw_calls"] = 1
	result["vertices"] = (surface["vertices"] as Array).size()
	result["triangles"] = (surface["indices"] as Array).size() / 3
	return result
