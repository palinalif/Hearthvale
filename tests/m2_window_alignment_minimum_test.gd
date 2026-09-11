extends SceneTree

const Builder = preload("res://scripts/m2_scene_window_alignment.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	var builder := Builder.new()
	# The real resize API permits 1x1 local units. At miniature scale there
	# are only four detail cells across it: two complete frames cannot fit.
	for scale_value in [0.25, 0.5, 1.0]:
		var cell := Vector3.ONE * 0.0625 / float(scale_value)
		for asset in ["window_wood", "window_awning"]:
			var group := Node3D.new()
			root.add_child(group)
			builder._build_open_window(group, asset, Vector3(0, 0, cell.z), Vector3(1, 1, cell.z * 2), cell, Color.WHITE)
			var leaf := group.get_node("AwningOpenLeaf" if asset == "window_awning" else "CasementOpenLeaf") as Node3D
			for child in leaf.get_children():
				var piece := child as MeshInstance3D
				var half := (piece.mesh as BoxMesh).size * 0.5
				var centre := piece.position + leaf.position
				check(centre.x - half.x >= -0.50001 and centre.x + half.x <= 0.50001, "minimum-width sash fits without stretching cells")
				check(centre.y - half.y >= -0.50001 and centre.y + half.y <= 0.50001, "minimum-height sash fits opening")
			if scale_value == 0.25:
				check(not group.has_node("CasementFixedGlass"), "narrowest window uses one nonoverlapping sash")
			group.free()
	builder.free()
	print("m2_window_alignment_minimum_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
