extends SceneTree
# Post-bake gate: does a freshly baked mesh still match its authored source?
#
# A bake can emit on-grid vertices and still be a degenerate sliver, which is
# how a broken mesher hides from a vertex count.  This compares the baked
# footprint against the authored occupied bounds recorded in the asset receipt
# and exits non-zero when they disagree, so the bake can refuse the result.
#
# Usage: godot --headless --path . --script res://tools/magicavoxel/check_bake.gd -- \
#          res://assets/models/magicavoxel/<asset>.res [unit]

const UNIT_DEFAULT := 0.125
## The exposed-face mesher drops faces shared with a neighbour, so a correct
## mesh is inset by up to one cell per axis; two cells leaves room for the
## decorative grid's half-cell steps.
const MAX_INSET_CELLS := 2.0

var failures := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: check_bake.gd -- res://<asset>.res [unit]")
		quit(2)
	var mesh_path := args[0]
	var unit := float(args[1]) if args.size() > 1 else UNIT_DEFAULT
	var receipt_path := mesh_path.trim_suffix(".res") + ".asset.json"
	var mesh_res: Resource = ResourceLoader.load(mesh_path)
	if mesh_res == null:
		_fail("cannot load %s" % mesh_path)
		quit(1)
	var mesh: Mesh = mesh_res as Mesh
	if mesh == null:
		_fail("%s is not a Mesh" % mesh_path)
		quit(1)
	var box: AABB = mesh.get_aabb()
	for axis in ["x", "y", "z"]:
		var size: float = box.size[axis]
		if size <= 0.0001:
			_fail("mesh is flat on %s (aabb %s)" % [axis, box])
	if not FileAccess.file_exists(receipt_path):
		print(JSON.stringify({"ok": failures == 0, "mesh": mesh_path, "note": "no receipt, extent check skipped"}))
		quit(0 if failures == 0 else 1)
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(receipt_path)) != OK:
		_fail("receipt is not valid JSON: %s" % receipt_path)
		quit(1)
	var bounds: Dictionary = (json.data as Dictionary).get("occupied_bounds", {}) as Dictionary
	var lo: Array = bounds.get("min", []) as Array
	var hi: Array = bounds.get("max", []) as Array
	if lo.size() != 3 or hi.size() != 3:
		_fail("receipt has no occupied_bounds")
		quit(1)
	var want := Vector3(
		float(hi[0]) - float(lo[0]), float(hi[1]) - float(lo[1]), float(hi[2]) - float(lo[2])
	) * unit
	var limit := MAX_INSET_CELLS * unit
	var drift := (box.size - want).abs()
	for axis in ["x", "y", "z"]:
		if drift[axis] > limit:
			_fail("mesh %s %.3f vs authored %.3f (drift %.3f > %.3f)" % [
				axis, box.size[axis], want[axis], drift[axis], limit
			])
	print(JSON.stringify({
		"ok": failures == 0,
		"mesh": mesh_path,
		"aabb": [box.size.x, box.size.y, box.size.z],
		"authored": [want.x, want.y, want.z],
	}))
	quit(0 if failures == 0 else 1)

func _fail(message: String) -> void:
	failures += 1
	print("BAKE_GATE_FAIL: %s" % message)
