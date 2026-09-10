extends "res://scripts/m2_scene_attachment_repair.gd"

## Window motion is presentation-only. Quantize each sash in its closed
## facade coordinates, then move its origin to the actual frame edge.
func _build_open_window(parent: Node3D, asset_id: String, pane_center: Vector3, pane_size: Vector3, cell: Vector3, accent: Color) -> void:
	if asset_id == "window_slider":
		super._build_open_window(parent, asset_id, pane_center, pane_size, cell, accent)
		return
	var half := Vector2(pane_size.x, pane_size.y) * 0.5
	# The fixed reveal occupies z=0..cell.z. The source pane_center.z is
	# quantization padding, not the surface of that reveal or a hinge offset.
	var glass_center := Vector3(pane_center.x, pane_center.y, -cell.z * 0.5)
	if asset_id == "window_awning":
		var glass_size := Vector2(maxf(cell.x, pane_size.x - cell.x * 2.0), maxf(cell.y, pane_size.y - cell.y * 2.0))
		var hinge := Vector3(pane_center.x, pane_center.y + half.y, cell.z)
		_add_edge_hinged_glass(parent, "AwningOpenLeaf", "Awning", glass_center, glass_size, hinge, Vector3.RIGHT, -0.48, cell, accent)
	elif pane_size.x < cell.x * 6.0:
		# At the smallest legal width, two complete framed panes cannot fit.
		# Use one right-hinged sash rather than overlap frames or shrink cells.
		var glass_size := Vector2(maxf(cell.x, pane_size.x - cell.x * 2.0), maxf(cell.y, pane_size.y - cell.y * 2.0))
		var hinge := Vector3(pane_center.x + half.x, pane_center.y, cell.z)
		_add_edge_hinged_glass(parent, "CasementOpenLeaf", "Open", glass_center, glass_size, hinge, Vector3.UP, 0.62, cell, accent)
	else:
		# Two disjoint sashes occupy the left and right halves of the opening.
		# Frame thickness is included, not added outside overlapping glass.
		var glass_size := Vector2(maxf(cell.x, half.x - cell.x * 2.0), maxf(cell.y, pane_size.y - cell.y * 2.0))
		_add_framed_glass(parent, "CasementFixed", glass_center - Vector3(half.x * 0.5, 0, 0), glass_size, cell, accent)
		var hinge := Vector3(pane_center.x + half.x, pane_center.y, cell.z)
		_add_edge_hinged_glass(parent, "CasementOpenLeaf", "Open", glass_center + Vector3(half.x * 0.5, 0, 0), glass_size, hinge, Vector3.UP, 0.62, cell, accent)

func _add_edge_hinged_glass(parent: Node3D, node_name: String, prefix: String, center: Vector3, size: Vector2, hinge: Vector3, axis: Vector3, angle: float, cell: Vector3, accent: Color) -> void:
	var leaf := Node3D.new()
	leaf.name = node_name
	parent.add_child(leaf)
	_add_framed_glass(leaf, prefix, center, size, cell, accent)
	# Rebase AFTER snapping, so moving a pivot cannot change the sash's
	# dimensions, introduce a half-cell gap, or stretch the decorative cells.
	for child in leaf.get_children():
		if child is Node3D: (child as Node3D).position -= hinge
	leaf.transform = Transform3D(Basis(axis, angle), hinge)

func _build_window_shutter_leaf(parent: Node3D, node_name: String, side: float, state: String, style: String, pane_center: Vector3, pane_size: Vector3, cell: Vector3, accent: Color) -> void:
	super._build_window_shutter_leaf(parent, node_name, side, state, style, pane_center, pane_size, cell, accent)
	if state != "closed": return
	var holder := parent.get_node(node_name + "_closed") as Node3D
	var panel := holder.get_node("Panel") as MeshInstance3D
	var back: float = panel.position.z - (panel.mesh as BoxMesh).size.z * 0.5
	# Rest the actual panel back on the fixed reveal's outer face. This also
	# fixes the closed leaf of half-open shutters, at every presentation scale.
	holder.position.z = cell.z - back

func _set_base_window_visibility(visual: Node3D, id: String, asset_id: String, extras: Dictionary, renderable: bool) -> void:
	super._set_base_window_visibility(visual, id, asset_id, extras, renderable)
	if str(extras.get("window_state", "closed")) != "open": return
	var joinery := visual.get_node_or_null("Joinery_" + id) as Node3D
	if joinery: joinery.hide()

func _build_adventure_shape(parent: Node3D, asset_id: String, pane_center: Vector3, pane_size: Vector3, cell: Vector3, accent: Color, extras: Dictionary) -> void:
	super._build_adventure_shape(parent, asset_id, pane_center, pane_size, cell, accent, extras)
	if str(extras.get("window_state", "closed")) != "open": return
	# Do not leave closed-pane bars suspended across an opened arched sash.
	for node_name in ["ArchCenter", "ArchTransom"]:
		var bar := parent.get_node_or_null(node_name) as Node3D
		if bar: bar.hide()
	# A closed exterior shutter physically blocks an outward-opening sash.
	# Park it against its frame until that shutter opens; retain BOTH saved
	# settings, and never silently rewrite an automatic window's overrides.
	if str(extras.get("shutter_style", "original")) == "none": return
	var shutter_state := str(extras.get("shutter_state", "open"))
	var full_width_sash := asset_id == "window_awning" or pane_size.x < cell.x * 6.0
	var blocked := shutter_state == "closed" or (full_width_sash and shutter_state == "half_open")
	if not blocked: return
	var leaf := parent.get_node_or_null("AwningOpenLeaf" if asset_id == "window_awning" else "CasementOpenLeaf") as Node3D
	if leaf: leaf.basis = Basis.IDENTITY
