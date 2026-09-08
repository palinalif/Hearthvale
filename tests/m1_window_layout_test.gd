extends SceneTree

const BuildingWorldScript = preload("res://scripts/building_world.gd")
const CottageVisualScript = preload("res://scripts/cottage_visual.gd")

var failures := 0
var world: RefCounted
var visual: Node3D

func _initialize() -> void:
	world = BuildingWorldScript.new()
	visual = CottageVisualScript.new()
	root.add_child(visual)
	_check_layout("initial")

	# A wider/taller resize must redistribute automatic windows without
	# stretching the pane, reveal, or opening geometry.
	_check(world.resize("building-1", Vector3(23.0, 8.0, 12.0)), "wide resize accepted")
	_check_layout("wide")

	# A narrow resize reduces the active slot count. Any surviving windows must
	# still use the same authored proportions rather than being scaled to fit.
	_check(world.resize("building-1", Vector3(10.0, 6.0, 10.0)), "narrow resize accepted")
	_check_layout("narrow")

	# Manually moved windows keep their authored geometry after another resize.
	var moved_view: Dictionary = world.get_building("building-1")
	var moved_detail: Dictionary = _first_visible_window(moved_view)
	if moved_detail.is_empty():
		_fail("visible window exists for manual move")
	else:
		var anchor: Dictionary = moved_detail.get("anchor", {})
		var position: Vector3 = moved_detail.get("resolved_position", Vector3.ZERO)
		position.x += 0.5
		_check(world.move_detail("building-1", str(moved_detail["id"]), str(anchor.get("surface_id", "")), position), "manual window move accepted")
		_check(world.resize("building-1", Vector3(18.0, 7.0, 14.0)), "restore resize accepted")
		_check_layout("manual-after-resize")

	_finish()

func _check_layout(label: String) -> void:
	var view: Dictionary = world.get_building("building-1")
	visual.request_revision(world.get_revision())
	_check(visual.apply_building(view, world.get_revision()), "%s visual applies" % label)
	var orientations := {}
	for surface_value in view.get("surfaces", []):
		var surface: Dictionary = surface_value
		orientations[str(surface.get("id", ""))] = str(surface.get("orientation", "front"))
	var visible_count := 0
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("kind", "")) != "window" or not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)):
			continue
		var local = detail.get("resolved_position", null)
		if not local is Vector3:
			continue
		visible_count += 1
		var orientation := str(orientations.get(str(detail.get("anchor", {}).get("surface_id", "")), "front"))
		var layout: Dictionary = visual._window_layout(detail, local, orientation)
		var pane_size: Vector3 = layout["pane_size"]
		var opening_half: Vector2 = layout["opening_half"]
		_check(is_equal_approx(opening_half.x * 2.0, pane_size.x) and is_equal_approx(opening_half.y * 2.0, pane_size.y), "%s opening matches pane %s" % [label, detail["id"]])
		var expected_size := Vector3(1.0, 1.0, 0.5) if str(detail.get("asset_id", "")).contains("round") else Vector3(2.0, 3.0, 0.5)
		_check(pane_size.is_equal_approx(expected_size), "%s window proportions stay fixed %s" % [label, detail["id"]])
		var pane_node := visual.get_node_or_null("Detail_%s" % detail["id"])
		var reveal_node := visual.get_node_or_null("Reveal_%s" % detail["id"])
		_check(pane_node is MeshInstance3D and reveal_node is MultiMeshInstance3D, "%s generated window pieces exist %s" % [label, detail["id"]])
		if pane_node is MeshInstance3D and reveal_node is MultiMeshInstance3D:
			_check((pane_node.mesh as BoxMesh).size.is_equal_approx(pane_size), "%s rendered pane uses shared size %s" % [label, detail["id"]])
			var basis: Basis = layout["basis"]
			var surface_center: Vector2 = layout["surface_center"]
			# The final renderer snaps MultiMesh depth to the visual grid. Compare
			# tangent + height, which define the wall opening and must stay exact.
			var reveal_surface: Vector3 = basis.inverse() * reveal_node.transform.origin
			_check(Vector2(reveal_surface.x, reveal_surface.y).is_equal_approx(surface_center), "%s reveal uses shared wall-plane centre %s" % [label, detail["id"]])
			var pane_surface: Vector3 = basis.inverse() * pane_node.transform.origin
			_check(Vector2(pane_surface.x, pane_surface.y).is_equal_approx(surface_center), "%s pane uses shared wall-plane centre %s" % [label, detail["id"]])
	_check(visible_count > 0, "%s has visible windows" % label)

func _first_visible_window(view: Dictionary) -> Dictionary:
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("kind", "")) == "window" and bool(detail.get("visible", true)) and not bool(detail.get("needs_placement", false)) and detail.get("resolved_position", null) is Vector3:
			return detail
	return {}

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: %s" % label)

func _fail(label: String) -> void:
	failures += 1
	print("FAIL: %s" % label)

func _finish() -> void:
	if visual and is_instance_valid(visual):
		visual.queue_free()
		await process_frame
	print(JSON.stringify({"ok": failures == 0, "failures": failures, "window_layout": failures == 0}))
	quit(1 if failures > 0 else 0)
