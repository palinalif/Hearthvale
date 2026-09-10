extends "res://scripts/m2_scene_house_palette.gd"

## M2 house-detail expansion layered above palette handling. Extra window
## silhouettes reuse the existing authoritative detail records and style picker;
## only disposable joinery geometry is added here.

const DecorGrid = preload("res://scripts/visual_grid.gd")
const EXTRA_WINDOW_VARIATIONS := [
	["variant-window-cross", "Cottage cross-pane", "window_cottage_cross"],
	["variant-window-triple", "Cottage triple-mullion", "window_cottage_triple"],
	["variant-window-sunburst", "Round sunburst", "window_round_sunburst"],
]
const CUSTOM_WINDOW_ASSETS: Array[String] = [
	"window_cottage_cross",
	"window_cottage_triple",
	"window_round_sunburst",
]

var _window_overlay_signatures: Dictionary = {}

func _ready() -> void:
	super._ready()
	_install_extra_window_styles()
	_refresh_custom_window_overlays()

func _install_extra_window_styles() -> void:
	var box := _actions_box()
	if not box: return
	for spec_value in EXTRA_WINDOW_VARIATIONS:
		var spec: Array = spec_value
		var button_id := str(spec[0])
		if _style_buttons.has(button_id): continue
		var button := Button.new()
		button.name = button_id
		button.text = str(spec[1])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size = Vector2(0, 36)
		button.visible = false
		var asset_id := str(spec[2])
		button.focus_entered.connect(_preview_style_choice.bind("variation", asset_id))
		button.pressed.connect(_commit_style_choice.bind("variation", asset_id))
		box.add_child(button)
		_style_buttons[button_id] = button
		_style_button_specs[button_id] = {"mode": "variation", "kind": "window", "value": asset_id}

func _begin_style_picker(mode: String) -> void:
	super._begin_style_picker(mode)
	if _style_picker_mode != "variation" or str(_selected_detail_record().get("kind", "")) != "window" or not tools_panel: return
	tools_panel.size.y = minf(560.0, get_viewport().get_visible_rect().size.y - 48.0)
	for button_value in _style_candidates("variation"):
		(button_value as Button).custom_minimum_size.y = 36
	call_deferred("_dock_style_picker_away_from_target")

func _apply_style_preview() -> void:
	super._apply_style_preview()
	_refresh_custom_window_overlays()

func _update_presentation() -> void:
	super._update_presentation()
	_refresh_custom_window_overlays()

func _refresh_custom_window_overlays() -> void:
	var seen: Dictionary = {}
	for visual_value in cottage_visuals.values():
		if visual_value is Node3D and is_instance_valid(visual_value):
			var visual := visual_value as Node3D
			seen[visual.get_instance_id()] = true
			_refresh_custom_window_overlays_for_visual(visual)
	if cottage_visual is Node3D and is_instance_valid(cottage_visual) and not seen.has((cottage_visual as Node3D).get_instance_id()):
		_refresh_custom_window_overlays_for_visual(cottage_visual as Node3D)

func _refresh_custom_window_overlays_for_visual(visual: Node3D) -> void:
	var applied_value = visual.get("_applied_view")
	if not applied_value is Dictionary: return
	var view: Dictionary = applied_value
	if view.is_empty(): return
	var signature_parts: Array[String] = []
	var custom_details: Array[Dictionary] = []
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		var detail_id := str(detail.get("id", ""))
		var asset_id := str(detail.get("asset_id", ""))
		var uses_custom_joinery := asset_id in CUSTOM_WINDOW_ASSETS and bool(detail.get("visible", true)) and not bool(detail.get("needs_placement", false))
		var base_joinery := visual.get_node_or_null("Joinery_" + detail_id) as Node3D
		if base_joinery: base_joinery.visible = not uses_custom_joinery
		if not uses_custom_joinery: continue
		var local = detail.get("resolved_position", null)
		if not local is Vector3: continue
		custom_details.append(detail)
		signature_parts.append("%s|%s|%s|%s" % [detail_id, asset_id, str(local), str(detail.get("override", {}))])
	var signature := "%s|%s|%s" % [str(view.get("dimensions", Vector3.ZERO)), str(view.get("accent_material_id", "")), ";".join(signature_parts)]
	var visual_key := int(visual.get_instance_id())
	var has_overlay := false
	for child in visual.get_children():
		if str(child.name).begins_with("M2WindowDecor_"):
			has_overlay = true
			break
	if str(_window_overlay_signatures.get(visual_key, "")) == signature and (custom_details.is_empty() or has_overlay): return
	_window_overlay_signatures[visual_key] = signature
	for child in visual.get_children():
		if str(child.name).begins_with("M2WindowDecor_"):
			visual.remove_child(child)
			child.queue_free()
	var orientations: Dictionary = {}
	for surface_value in view.get("surfaces", []):
		var surface: Dictionary = surface_value
		orientations[str(surface.get("id", ""))] = str(surface.get("orientation", "front"))
	for detail in custom_details:
		_build_custom_window_overlay(visual, view, detail, orientations)

func _build_custom_window_overlay(visual: Node3D, view: Dictionary, detail: Dictionary, orientations: Dictionary) -> void:
	var detail_id := str(detail.get("id", ""))
	var base_joinery := visual.get_node_or_null("Joinery_" + detail_id) as Node3D
	if base_joinery: base_joinery.visible = false
	var local = detail.get("resolved_position", null)
	if not local is Vector3: return
	var orientation := str(orientations.get(str(detail.get("anchor", {}).get("surface_id", "")), "front"))
	var layout_value = visual.call("_window_layout", detail, local as Vector3, orientation)
	if not layout_value is Dictionary: return
	var layout: Dictionary = layout_value
	var basis: Basis = layout.get("basis", Basis.IDENTITY)
	var anchor: Vector3 = layout.get("anchor_center", Vector3.ZERO)
	var pane_center: Vector3 = layout.get("pane_center", Vector3.ZERO)
	var pane_size: Vector3 = layout.get("pane_size", Vector3(2.0, 2.8, 0.1))
	var detail_unit_value = visual.get("_detail_unit")
	var detail_unit: Vector3 = detail_unit_value if detail_unit_value is Vector3 else Vector3.ONE * 0.5
	var cell := (basis.inverse() * detail_unit).abs()
	var container := Node3D.new()
	container.name = "M2WindowDecor_" + detail_id
	container.transform = Transform3D(basis, anchor.snapped(detail_unit))
	visual.add_child(container)
	var colour := _custom_window_colour(view, detail)
	var asset_id := str(detail.get("asset_id", ""))
	if asset_id == "window_cottage_cross":
		_add_window_bar(container, "Vertical", pane_center, Vector3(cell.x, pane_size.y, cell.z), colour, cell)
		_add_window_bar(container, "Horizontal", pane_center, Vector3(pane_size.x, cell.y, cell.z), colour, cell)
	elif asset_id == "window_cottage_triple":
		for side in [-1.0, 1.0]:
			_add_window_bar(container, "Mullion%s" % side, pane_center + Vector3(side * pane_size.x / 3.0, 0, 0), Vector3(cell.x, pane_size.y, cell.z), colour, cell)
		_add_window_bar(container, "Transom", pane_center + Vector3(0, pane_size.y * 0.18, 0), Vector3(pane_size.x, cell.y, cell.z), colour, cell)
	else:
		_add_window_bar(container, "HubV", pane_center, Vector3(cell.x, pane_size.y * 0.78, cell.z), colour, cell)
		_add_window_bar(container, "HubH", pane_center, Vector3(pane_size.x * 0.78, cell.y, cell.z), colour, cell)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for step in 2:
					var offset := Vector3(sx * cell.x * (step + 1), sy * cell.y * (step + 1), 0)
					_add_window_bar(container, "Ray_%s_%s_%d" % [sx, sy, step], pane_center + offset, cell, colour, cell)

func _custom_window_colour(view: Dictionary, detail: Dictionary) -> Color:
	var colour_id := str((detail.get("override", {}) as Dictionary).get("color_id", "natural"))
	if colour_id != "natural": return DETAIL_COLOURS.get(colour_id, DETAIL_COLOURS["natural"])
	var accent_id := _accent_material_id(view)
	return ACCENT_COLOURS.get(accent_id, Color("#557a70"))

func _add_window_bar(parent: Node3D, node_name: String, center: Vector3, size: Vector3, colour: Color, unit: Vector3) -> void:
	var quantized: Dictionary = DecorGrid.quantized_box(center, size, unit)
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = quantized.get("size", size)
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	node.material_override = material
	node.position = quantized.get("center", center)
	parent.add_child(node)
