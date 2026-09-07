extends RefCounted
## Pure CPU packing. Safe on the preview worker: no rendering resources,
## scene nodes, or per-instance RenderingServer calls are created here.
const STRIDE := 16 # row-major 3x4 transform, then RGBA

static func pack(plan: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var unit: float = plan.get("cell_size", 0.125)
	var normal: Vector3 = plan.get("normal", Vector3.UP)
	var face := Basis(Quaternion(Vector3.BACK, normal)).scaled(Vector3.ONE * unit)
	var cube := Basis.IDENTITY.scaled(Vector3.ONE * unit * 1.015)
	var counts := [plan.get("rim", []).size(), int(plan.get("remove_count", 0)), int(plan.get("add_count", 0))]
	var buffers: Array[PackedFloat32Array] = []
	for count in counts:
		var buffer := PackedFloat32Array()
		buffer.resize(int(count) * STRIDE)
		buffers.append(buffer)
	var cells: Array[Vector3i] = []
	cells.resize(plan.get("changes", []).size())
	var at := [0, 0, 0]
	var minimum := Vector3(INF, INF, INF)
	var maximum := -minimum
	for point: Vector3 in plan.get("rim", []):
		var position := point + normal * unit * 0.02
		_write(buffers[0], at[0], face, position, 1.0)
		at[0] += 1
		minimum = minimum.min(position); maximum = maximum.max(position)
	var i := 0
	for change: Dictionary in plan.get("changes", []):
		var cell: Vector3i = change["cell"]
		cells[i] = cell
		i += 1
		var position := (Vector3(cell) + Vector3.ONE * 0.5) * unit
		var layer := 1 if int(change["after"]) == 0 else 2
		if layer == 1: position += normal * unit * 0.515
		var alpha := lerpf(0.4, 1.0, sqrt(clampf(float(change["weight"]), 0.0, 1.0)))
		_write(buffers[layer], at[layer], face if layer == 1 else cube, position, alpha)
		at[layer] += 1
		minimum = minimum.min(position); maximum = maximum.max(position)
	var bounds := AABB()
	if minimum.is_finite(): bounds = AABB(minimum - Vector3.ONE * unit, maximum - minimum + Vector3.ONE * unit * 2.0)
	return {"buffers": buffers, "counts": counts, "cells": cells, "bounds": bounds, "pack_ms": (Time.get_ticks_usec() - started) / 1000.0}

static func _write(buffer: PackedFloat32Array, instance: int, basis: Basis, origin: Vector3, alpha: float) -> void:
	var i := instance * STRIDE
	buffer[i] = basis.x.x; buffer[i + 1] = basis.y.x; buffer[i + 2] = basis.z.x; buffer[i + 3] = origin.x
	buffer[i + 4] = basis.x.y; buffer[i + 5] = basis.y.y; buffer[i + 6] = basis.z.y; buffer[i + 7] = origin.y
	buffer[i + 8] = basis.x.z; buffer[i + 9] = basis.y.z; buffer[i + 10] = basis.z.z; buffer[i + 11] = origin.z
	buffer[i + 12] = 1.0; buffer[i + 13] = 1.0; buffer[i + 14] = 1.0; buffer[i + 15] = alpha
