extends SceneTree

const Grid = preload("res://scripts/visual_grid.gd")
var scene: Node
var checks := 0
var failures := 0
var captures := 0
var rendered := false
const OUTPUT := ".tools/cottage-repair/window-alignment"

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	rendered = "--require-rendering" in OS.get_cmdline_user_args()
	if rendered:
		check(DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "mobile", "actual Mobile rendering required")
		if failures:
			await _finish()
			return
		root.size = Vector2i(1280, 720)
		DirAccess.make_dir_recursive_absolute(OUTPUT)
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://window-alignment-%s" % Time.get_ticks_usec()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 65000
	while not scene._player_restored and Time.get_ticks_msec() < deadline: await process_frame
	check(scene._player_restored, "native scene ready")
	if not scene._player_restored:
		await _finish()
		return
	scene.set_process(false)
	scene._set_view_context("building", "test")
	_check_geometry_matrix()
	await _check_gameplay()
	await _finish()

func _check_geometry_matrix() -> void:
	var before: String = scene.building_world.serialize_document()
	for scale_value in [0.25, 0.5, 1.0]:
		var cell: Vector3 = Vector3.ONE * Grid.COTTAGE_DETAIL_UNIT / float(scale_value)
		for size in [Vector3(2, 3, cell.z * 2), Vector3(3.5, 4, cell.z * 2)]:
			for orientation in ["front", "back", "left", "right"]:
				var house := Node3D.new()
				house.transform = Transform3D(Basis(Vector3.UP, 0.37).scaled(Vector3.ONE * scale_value), Vector3(5, 8, 3))
				root.add_child(house)
				var wall := Node3D.new()
				wall.transform = Transform3D(scene.cottage_visual._surface_basis(orientation), Vector3(1, 10.5, -7))
				house.add_child(wall)
				for asset_id in ["window_wood", "window_awning"]:
					var group := Node3D.new()
					wall.add_child(group)
					scene._build_open_window(group, asset_id, Vector3(0, 0, cell.z), size, cell, Color.WHITE)
					_check_hinge(group, asset_id, size, cell)
					group.free()
				for style in ["boarded", "louvered", "braced"]:
					for state in ["closed", "half_open"]:
						var group := Node3D.new()
						wall.add_child(group)
						scene._build_window_shutters(group, Vector3(0, 0, cell.z), size, cell, Color.WHITE, {"shutter_style": style, "shutter_state": state}, "window_wood")
						for child in group.get_children():
							var holder := child as Node3D
							if not str(holder.name).ends_with("_closed"): continue
							var panel := holder.get_node("Panel") as MeshInstance3D
							var back := holder.position.z + panel.position.z - (panel.mesh as BoxMesh).size.z * 0.5
							check(is_equal_approx(back, cell.z), "closed shutter back touches reveal, including half-open, rotated and upstairs")
							check(holder.basis.is_equal_approx(Basis.IDENTITY), "closed shutter stays flat")
						group.free()
				# Opening a sash must not clip through the exterior closed shutter.
				for asset_id in ["window_wood", "window_awning"]:
					var group := Node3D.new()
					wall.add_child(group)
					scene._build_adventure_shape(group, asset_id, Vector3(0, 0, cell.z), size, cell, Color.WHITE, {"window_state": "open", "shutter_state": "closed", "shutter_style": "boarded"})
					var leaf := group.get_node("AwningOpenLeaf" if asset_id == "window_awning" else "CasementOpenLeaf") as Node3D
					check(leaf.basis.is_equal_approx(Basis.IDENTITY), "blocked open sash rests behind closed shutter without changing saved preference")
					group.free()
				house.free()
	check(scene.building_world.serialize_document() == before, "geometry generation never edits window anchors or saves")

func _check_hinge(group: Node3D, asset_id: String, size: Vector3, cell: Vector3) -> void:
	var awning := asset_id == "window_awning"
	var leaf := group.get_node("AwningOpenLeaf" if awning else "CasementOpenLeaf") as Node3D
	var frame := leaf.get_node("AwningFrameHTop" if awning else "OpenFrameVRight") as MeshInstance3D
	var half := (frame.mesh as BoxMesh).size * 0.5
	var expected := Vector3(0, size.y * 0.5, cell.z) if awning else Vector3(size.x * 0.5, 0, cell.z)
	for along in [-1.0, 0.0, 1.0]:
		var point := Vector3(along * half.x, half.y, half.z) if awning else Vector3(half.x, along * half.y, half.z)
		var edge := frame.transform * point
		var closed_edge := edge + leaf.position
		var opened_edge := leaf.transform * edge
		check(opened_edge.is_equal_approx(closed_edge), "entire hinge edge is stationary, not the panel centre")
		check(is_equal_approx(opened_edge.z, expected.z) and is_equal_approx(opened_edge.y if awning else opened_edge.x, expected.y if awning else expected.x), "hinge edge remains on the fixed reveal")
		check(frame.to_global(point).is_equal_approx(group.to_global(closed_edge)), "hinge stays attached under parent rotation, scale and floor height")
	var glass := leaf.get_node("AwningGlass" if awning else "OpenGlass") as MeshInstance3D
	var glass_half := (glass.mesh as BoxMesh).size * 0.5
	var free_corner := Vector3(0, -glass_half.y, glass_half.z) if awning else Vector3(-glass_half.x, 0, glass_half.z)
	check((leaf.transform * (glass.transform * free_corner)).z > cell.z, "free panel edge swings outward rather than through the wall")
	check(leaf.basis.get_scale().is_equal_approx(Vector3.ONE), "sash is rotated, never stretched")
	for child in leaf.get_children():
		var piece := child as MeshInstance3D
		var closed_centre := piece.position + leaf.position
		var piece_half := (piece.mesh as BoxMesh).size * 0.5
		for corner in [closed_centre - piece_half, closed_centre + piece_half]:
			check(corner.is_equal_approx(corner.snapped(cell)), "sash preserves cubic detail-grid dimensions before rotation")
	if not awning:
		var fixed := group.get_node("CasementFixedFrameVRight") as MeshInstance3D
		var moving := leaf.get_node("OpenFrameVLeft") as MeshInstance3D
		var fixed_end := fixed.position.x + (fixed.mesh as BoxMesh).size.x * 0.5
		var moving_start := moving.position.x + leaf.position.x - (moving.mesh as BoxMesh).size.x * 0.5
		check(is_equal_approx(fixed_end, moving_start), "fixed and moving sash frames meet without overlapping")

func _refresh() -> void:
	scene._presentation_key = ""
	scene._update_presentation()
	await process_frame

func _check_gameplay() -> void:
	scene._begin_next_storey()
	check(scene.portion_valid and scene._commit_portion_placement(), "add a supported upper floor through normal edit API")
	await _refresh()
	var id := ""
	for detail in scene.building_world.get_building(scene.selected_building_id).get("details", []):
		if str(detail.get("kind", "")) != "window" or not bool(detail.get("visible", false)) or bool(detail.get("needs_placement", true)): continue
		var view: Dictionary = scene.building_world.get_building(scene.selected_building_id)
		var support: Dictionary = scene.WallPlacement.surface(view, str(detail.get("anchor", {}).get("surface_id", "")))
		if int(support.get("massing_level", 0)) == 1 and str(support.get("orientation", "")) == "front":
			id = str(detail["id"])
			break
	check(not id.is_empty(), "select actual upstairs window")
	if id.is_empty(): return
	scene.selected_detail_id = id
	var before: String = scene.building_world.serialize_document()
	scene._open_window_extras()
	scene._window_extras_preview["window_state"] = "open"
	scene._window_extras_preview["shutter_style"] = "braced"
	scene._window_extras_preview["shutter_state"] = "half_open"
	scene._refresh_window_customization()
	await process_frame
	var visual := scene.cottage_visuals[scene.selected_building_id] as Node3D
	var joinery := visual.get_node_or_null("Joinery_" + id) as Node3D
	check(joinery != null and not joinery.visible, "opening hides obsolete closed-pane bars")
	check(scene.building_world.serialize_document() == before, "window/shutter preview is read-only")
	scene._cancel_window_extras()
	await _refresh()
	joinery = visual.get_node_or_null("Joinery_" + id) as Node3D
	check(joinery != null and joinery.visible, "cancel restores original closed joinery")
	check(scene.building_world.serialize_document() == before, "cancel restores exact document")
	scene._open_window_extras()
	scene._window_extras_preview["window_state"] = "open"
	scene._window_extras_preview["shutter_style"] = "braced"
	scene._window_extras_preview["shutter_state"] = "half_open"
	var revision: int = scene.building_world.get_revision()
	check(scene._commit_window_extras(), "commit open sash and half-open shutters")
	check(scene.building_world.get_revision() == revision + 1, "one window edit is one undo transaction")
	await _refresh()
	var signature := _geometry_signature(visual.get_node("M2WindowAdventure_" + id))
	check(scene.building_world.undo(), "window extras undo succeeds")
	await _refresh()
	check(scene.building_world.redo(), "window extras redo succeeds")
	await _refresh()
	check(_geometry_signature(visual.get_node("M2WindowAdventure_" + id)) == signature, "redo regenerates identical hinged window and shutters")
	var saved: String = scene.building_world.serialize_document()
	check(scene.building_world.load_serialized_document(saved), "window/shutter save reloads")
	await _refresh()
	visual = scene.cottage_visuals[scene.selected_building_id]
	check(_geometry_signature(visual.get_node("M2WindowAdventure_" + id)) == signature, "reload regenerates identical corrected geometry")
	if rendered:
		scene.hud.visible = false
		await _capture_window(visual, id, "casement-half-open")
		for spec in [["window_awning", "open", "awning-open"], ["window_wood", "closed", "shutters-closed"]]:
			check(scene.building_world.replace_detail(scene.selected_building_id, id, spec[0]), "change fixture variant")
			await _refresh()
			scene._open_window_extras()
			scene._window_extras_preview["shutter_state"] = spec[1]
			scene._window_extras_preview["shutter_style"] = "louvered"
			check(scene._commit_window_extras(), "save gallery shutter state")
			await _refresh()
			scene.hud.visible = false
			await _capture_window(scene.cottage_visuals[scene.selected_building_id], id, spec[2])

func _geometry_signature(node: Node3D) -> String:
	var parts: Array[String] = []
	for child in node.get_children():
		if not child is Node3D: continue
		parts.append("%s|%s|%s" % [child.name, child.transform, child.visible])
		if child is MeshInstance3D: parts.append(str((child.mesh as BoxMesh).size))
		parts.append(_geometry_signature(child))
	return "\n".join(parts)

func _capture_window(visual: Node3D, id: String, label: String) -> void:
	var window := visual.get_node("M2WindowAdventure_" + id) as Node3D
	var target := window.global_position
	var normal := window.global_basis.z.normalized()
	var tangent := window.global_basis.x.normalized()
	for side in [0.0, 1.0]:
		scene.camera.look_at_from_position(target + normal * 2.4 + tangent * side * 2.0 + Vector3.UP * 0.5, target)
		for frame in 5: await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		check(not image.is_empty(), "actual Mobile window capture exists")
		check(image.save_png("%s/%s-%s.png" % [OUTPUT, label, "front" if side == 0 else "side"]) == OK, "window capture saved")
		captures += 1

func _finish() -> void:
	if is_instance_valid(scene):
		scene._shutting_down = true
		scene.queue_free()
		await process_frame
		await process_frame
	if rendered: check(captures == 6, "all six actual Mobile review views captured")
	print("WINDOW_ALIGNMENT_RESULT " + JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "captures": captures}))
	quit(1 if failures else 0)
