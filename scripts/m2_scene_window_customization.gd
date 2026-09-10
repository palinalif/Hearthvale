extends "res://scripts/m2_scene_terrain_house_outline.gd"

## Combinatorial window customization layered above the existing window styles.
## Shape remains the normal variation asset; shutters, flower box, open state
## and Juliet rail are saved as independent per-window overrides.
const WindowGrid = preload("res://scripts/visual_grid.gd")

const ADVENTURE_WINDOW_VARIATIONS: Array[Array] = [
	["variant-window-arch", "Arched cottage casement", "window_arch_casement"],
	["variant-window-awning", "Awning window", "window_awning"],
	["variant-window-slider", "Horizontal slider", "window_slider"],
	["variant-window-bay", "Tiny bay window", "window_bay"],
]
const ADVENTURE_WINDOW_ASSETS: Array[String] = [
	"window_arch_casement",
	"window_awning",
	"window_slider",
	"window_bay",
]
const WINDOW_EXTRA_ORDER: Array[String] = [
	"shutter_style",
	"shutter_state",
	"flower_box",
	"window_state",
	"balcony",
]
const WINDOW_EXTRA_OPTIONS := {
	"shutter_style": ["original", "none", "boarded", "louvered", "braced"],
	"shutter_state": ["open", "closed", "half_open"],
	"flower_box": ["none", "timber", "bracketed", "woven"],
	"window_state": ["closed", "open"],
	"balcony": ["none", "juliet"],
}
const WINDOW_EXTRA_LABELS := {
	"shutter_style": "Shutters",
	"shutter_state": "Shutter state",
	"flower_box": "Flower box",
	"window_state": "Window",
	"balcony": "Tiny balcony",
}
const ADVENTURE_GLASS := Color("#739295")
const ADVENTURE_TRIM := Color("#dcc9a6")
const ADVENTURE_FOLIAGE := Color("#58754b")
const ADVENTURE_FLOWERS: Array[Color] = [Color("#d56d65"), Color("#c88ba0"), Color("#d6ad68")]

var _window_extras_action: Button
var _window_extras_panel: PanelContainer
var _window_extras_buttons: Array[Button] = []
var _window_extra_buttons_by_key: Dictionary = {}
var _window_extras_open := false
var _window_extras_detail_id := ""
var _window_extras_original: Dictionary = {}
var _window_extras_preview: Dictionary = {}
var _window_adventure_signatures: Dictionary = {}

func _ready() -> void:
	super._ready()
	_install_adventure_window_styles()
	_install_window_extras_action()
	_build_window_extras_panel()
	_refresh_window_customization()

func _install_adventure_window_styles() -> void:
	var box := _actions_box()
	if not box: return
	for spec_value in ADVENTURE_WINDOW_VARIATIONS:
		var spec: Array = spec_value
		var button_id: String = str(spec[0])
		if _style_buttons.has(button_id): continue
		var button := Button.new()
		button.name = button_id
		button.text = str(spec[1])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size = Vector2(0, 36)
		button.visible = false
		var asset_id: String = str(spec[2])
		button.focus_entered.connect(_preview_style_choice.bind("variation", asset_id))
		button.pressed.connect(_commit_style_choice.bind("variation", asset_id))
		box.add_child(button)
		_style_buttons[button_id] = button
		_style_button_specs[button_id] = {"mode": "variation", "kind": "window", "value": asset_id}

func _install_window_extras_action() -> void:
	var box := _actions_box()
	if not box: return
	_window_extras_action = Button.new()
	_window_extras_action.name = "WindowExtrasAction"
	_window_extras_action.text = "Window extras"
	_window_extras_action.focus_mode = Control.FOCUS_ALL
	_window_extras_action.custom_minimum_size = Vector2(0, 42)
	_window_extras_action.pressed.connect(_open_window_extras)
	box.add_child(_window_extras_action)
	_tool_buttons["Window extras"] = _window_extras_action

func _build_window_extras_panel() -> void:
	_window_extras_panel = _make_catalogue_panel("WindowExtrasPicker", Vector2(520, 430))
	var box := _catalogue_box(_window_extras_panel)
	box.add_theme_constant_override("separation", 5)
	_add_catalogue_heading(box, "WINDOW EXTRAS", "Mix details freely • browse to preview • Apply saves all")
	for key in WINDOW_EXTRA_ORDER:
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size = Vector2(470, 38)
		button.set_meta("window_extra_key", key)
		button.pressed.connect(_cycle_window_extra.bind(key, 1))
		box.add_child(button)
		_window_extras_buttons.append(button)
		_window_extra_buttons_by_key[key] = button
	var apply_button := Button.new()
	apply_button.name = "WindowExtrasApply"
	apply_button.text = "Apply"
	apply_button.focus_mode = Control.FOCUS_ALL
	apply_button.custom_minimum_size = Vector2(470, 40)
	apply_button.pressed.connect(_commit_window_extras)
	box.add_child(apply_button)
	_window_extras_buttons.append(apply_button)
	var cancel_button := Button.new()
	cancel_button.name = "WindowExtrasCancel"
	cancel_button.text = "Cancel"
	cancel_button.focus_mode = Control.FOCUS_ALL
	cancel_button.custom_minimum_size = Vector2(470, 40)
	cancel_button.pressed.connect(_cancel_window_extras)
	box.add_child(cancel_button)
	_window_extras_buttons.append(cancel_button)

func _update_action_buttons() -> void:
	super._update_action_buttons()
	if not _window_extras_action: return
	var show: bool = _context_actions_open and _style_picker_mode.is_empty() and str(_selected_detail_record().get("kind", "")) == "window"
	_window_extras_action.visible = show
	_window_extras_action.disabled = not show

func _input(event: InputEvent) -> void:
	if _window_extras_open and not menu_open:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_cancel_window_extras()
		elif event.is_action_pressed("m1_pause"):
			_close_window_extras(false)
			super._input(event)
		elif event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner()
			if focus in _window_extras_buttons: (focus as Button).pressed.emit()
		elif event.is_action_pressed("m1_height_up") or event.is_action_pressed("ui_up"):
			_move_focus(_window_extras_buttons, -1)
		elif event.is_action_pressed("m1_height_down") or event.is_action_pressed("ui_down"):
			_move_focus(_window_extras_buttons, 1)
		elif event.is_action_pressed("m1_cycle_left"):
			_cycle_focused_window_extra(-1)
		elif event.is_action_pressed("m1_cycle_right"):
			_cycle_focused_window_extra(1)
		get_viewport().set_input_as_handled()
		return
	super._input(event)

func _open_window_extras() -> void:
	var detail: Dictionary = _selected_detail_record()
	if str(detail.get("kind", "")) != "window" or not _window_extras_panel: return
	_window_extras_detail_id = str(detail.get("id", ""))
	_window_extras_original = _saved_window_extras(detail)
	_window_extras_preview = _window_extras_original.duplicate(true)
	_window_extras_open = true
	_context_actions_open = false
	tools_open = true
	detail_open = false
	if tools_panel: tools_panel.visible = false
	_window_extras_panel.visible = true
	_refresh_window_extra_buttons()
	if not _window_extras_buttons.is_empty(): _window_extras_buttons[0].grab_focus()
	_refresh_window_customization()
	_set_status("Window extras • D-pad up/down choose • left/right change • A cycles • Apply saves • B back")
	_refresh_controller_hud()

func _close_window_extras(return_to_actions: bool) -> void:
	_window_extras_open = false
	if _window_extras_panel: _window_extras_panel.visible = false
	_window_extras_detail_id = ""
	_window_extras_original.clear()
	_window_extras_preview.clear()
	if return_to_actions:
		_context_actions_open = true
		tools_open = true
		if tools_panel: tools_panel.visible = true
		_update_action_buttons()
		if _window_extras_action: _window_extras_action.grab_focus()
		_set_status("Window options")
	else:
		_context_actions_open = false
		tools_open = false
		if tools_panel: tools_panel.visible = false
		get_viewport().gui_release_focus()
	_refresh_controller_hud()

func _cancel_window_extras() -> void:
	if not _window_extras_open: return
	_close_window_extras(true)
	_refresh_window_customization()

func _cycle_focused_window_extra(direction: int) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if not focus is Button: return
	var key: String = str((focus as Button).get_meta("window_extra_key", ""))
	if not key.is_empty(): _cycle_window_extra(key, direction)

func _cycle_window_extra(key: String, direction: int) -> void:
	if not _window_extras_open or not WINDOW_EXTRA_OPTIONS.has(key): return
	var options: Array = WINDOW_EXTRA_OPTIONS[key]
	var current: String = str(_window_extras_preview.get(key, options[0]))
	var index: int = options.find(current)
	if index < 0: index = 0
	_window_extras_preview[key] = str(options[posmod(index + direction, options.size())])
	_refresh_window_extra_buttons()
	_refresh_window_customization()

func _refresh_window_extra_buttons() -> void:
	for key in WINDOW_EXTRA_ORDER:
		var button: Button = _window_extra_buttons_by_key.get(key, null) as Button
		if not button: continue
		var value: String = str(_window_extras_preview.get(key, ""))
		button.text = "%s: %s" % [str(WINDOW_EXTRA_LABELS[key]), _window_extra_value_label(key, value)]

func _window_extra_value_label(key: String, value: String) -> String:
	if key == "shutter_style" and value == "original": return "Original house shutters"
	if key == "balcony" and value == "juliet": return "Juliet balcony"
	if key == "window_state": return value.capitalize()
	return value.replace("_", " ").capitalize()

func _commit_window_extras() -> bool:
	if not _window_extras_open or _window_extras_detail_id.is_empty(): return false
	var building_index: int = building_world._building_index(selected_building_id)
	if building_index < 0: return false
	var before: Dictionary = building_world.get_document()
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[building_index]
	var detail_index: int = building_world._detail_index(building, _window_extras_detail_id)
	if detail_index < 0: return false
	var details: Array = building["details"]
	var detail: Dictionary = details[detail_index]
	if _window_extras_preview == _window_extras_original:
		_close_window_extras(false)
		_refresh_window_customization()
		_set_status("No window extras changed")
		return false
	var overrides: Dictionary = detail.get("override", {})
	overrides["window_extras"] = _window_extras_preview.duplicate(true)
	detail["override"] = overrides
	# Cosmetic extras stay attached to automatic windows without freezing their
	# proportional layout, so resizing a house can still reflow them naturally.
	details[detail_index] = detail
	building["details"] = details
	building_world._refresh_buckets(building)
	buildings[building_index] = building
	var ok: bool = building_world._record_change(before)
	if ok: _record_history("building")
	_close_window_extras(false)
	_presentation_key = ""
	_update_presentation()
	_set_status("Window extras saved" if ok else "No window extras changed")
	return ok

func _window_extra_defaults(detail: Dictionary) -> Dictionary:
	return {
		"shutter_style": "original",
		"shutter_state": "open",
		"flower_box": "none",
		"window_state": "open" if str(detail.get("asset_id", "")) == "window_awning" else "closed",
		"balcony": "none",
	}

func _saved_window_extras(detail: Dictionary) -> Dictionary:
	var result: Dictionary = _window_extra_defaults(detail)
	var overrides: Dictionary = detail.get("override", {})
	var stored = overrides.get("window_extras", {})
	if stored is Dictionary:
		for key in WINDOW_EXTRA_ORDER:
			if (stored as Dictionary).has(key) and str((stored as Dictionary)[key]) in WINDOW_EXTRA_OPTIONS[key]:
				result[key] = str((stored as Dictionary)[key])
	return result

func _effective_window_extras(detail: Dictionary) -> Dictionary:
	if _window_extras_open and str(detail.get("id", "")) == _window_extras_detail_id:
		return _window_extras_preview
	return _saved_window_extras(detail)

func _has_custom_window_extras(detail: Dictionary, extras: Dictionary) -> bool:
	var defaults: Dictionary = _window_extra_defaults(detail)
	for key in WINDOW_EXTRA_ORDER:
		if str(extras.get(key, defaults[key])) != str(defaults[key]): return true
	return false

func _apply_style_preview() -> void:
	super._apply_style_preview()
	_refresh_window_customization()

func _update_presentation() -> void:
	super._update_presentation()
	_refresh_window_customization()

func _refresh_window_customization() -> void:
	var seen: Dictionary = {}
	for visual_value in cottage_visuals.values():
		if visual_value is Node3D and is_instance_valid(visual_value):
			var visual := visual_value as Node3D
			seen[visual.get_instance_id()] = true
			_refresh_window_customization_for_visual(visual)
	if cottage_visual is Node3D and is_instance_valid(cottage_visual) and not seen.has((cottage_visual as Node3D).get_instance_id()):
		_refresh_window_customization_for_visual(cottage_visual as Node3D)

func _refresh_window_customization_for_visual(visual: Node3D) -> void:
	var applied_value = visual.get("_applied_view")
	if not applied_value is Dictionary: return
	var view: Dictionary = applied_value
	if view.is_empty(): return
	var custom_details: Array[Dictionary] = []
	var signature_parts: Array[String] = []
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("kind", "")) != "window": continue
		var id: String = str(detail.get("id", ""))
		var asset_id: String = str(detail.get("asset_id", ""))
		var extras: Dictionary = _effective_window_extras(detail)
		var renderable: bool = bool(detail.get("visible", true)) and not bool(detail.get("needs_placement", false))
		_set_base_window_visibility(visual, id, asset_id, extras, renderable)
		var owns_shape: bool = asset_id in ADVENTURE_WINDOW_ASSETS
		var owns_extras: bool = _has_custom_window_extras(detail, extras)
		if renderable and (owns_shape or owns_extras):
			custom_details.append({"detail": detail, "extras": extras})
			signature_parts.append("%s|%s|%s|%s|%s" % [id, asset_id, str(detail.get("resolved_position", Vector3.ZERO)), str(detail.get("override", {})), str(extras)])
	var signature: String = "%s|%s|%s" % [str(view.get("dimensions", Vector3.ZERO)), str(view.get("accent_material_id", "")), ";".join(signature_parts)]
	var visual_key: int = int(visual.get_instance_id())
	var has_overlay := false
	for child in visual.get_children():
		if str(child.name).begins_with("M2WindowAdventure_"):
			has_overlay = true
			break
	if str(_window_adventure_signatures.get(visual_key, "")) == signature and (custom_details.is_empty() or has_overlay): return
	_window_adventure_signatures[visual_key] = signature
	for child in visual.get_children():
		if str(child.name).begins_with("M2WindowAdventure_"):
			visual.remove_child(child)
			child.queue_free()
	var orientations: Dictionary = {}
	for surface_value in view.get("surfaces", []):
		var surface: Dictionary = surface_value
		orientations[str(surface.get("id", ""))] = str(surface.get("orientation", "front"))
	for record_value in custom_details:
		var record: Dictionary = record_value
		_build_window_customization_overlay(visual, view, record["detail"] as Dictionary, record["extras"] as Dictionary, orientations)

func _set_base_window_visibility(visual: Node3D, id: String, asset_id: String, extras: Dictionary, renderable: bool) -> void:
	var joinery := visual.get_node_or_null("Joinery_" + id) as Node3D
	if joinery:
		joinery.visible = renderable and asset_id not in CUSTOM_WINDOW_ASSETS and asset_id not in ADVENTURE_WINDOW_ASSETS
	var shutters := visual.get_node_or_null("Shutters_" + id) as Node3D
	if shutters:
		var custom_shutters: bool = str(extras.get("shutter_style", "original")) != "original" or str(extras.get("shutter_state", "open")) != "open"
		var shape_suppresses: bool = asset_id in ["window_awning", "window_slider", "window_bay"]
		shutters.visible = renderable and not custom_shutters and not shape_suppresses
	var pane := visual.get_node_or_null("Detail_" + id) as Node3D
	if pane:
		var custom_pane: bool = asset_id == "window_bay" or str(extras.get("window_state", "closed")) == "open"
		pane.visible = renderable and not custom_pane
	var legacy_overlay := visual.get_node_or_null("M2WindowDecor_" + id) as Node3D
	if legacy_overlay:
		legacy_overlay.visible = renderable and asset_id in CUSTOM_WINDOW_ASSETS and str(extras.get("window_state", "closed")) != "open"

func _build_window_customization_overlay(visual: Node3D, view: Dictionary, detail: Dictionary, extras: Dictionary, orientations: Dictionary) -> void:
	var id: String = str(detail.get("id", ""))
	var local = detail.get("resolved_position", null)
	if not local is Vector3: return
	var orientation: String = str(orientations.get(str(detail.get("anchor", {}).get("surface_id", "")), "front"))
	var layout_value = visual.call("_window_layout", detail, local as Vector3, orientation)
	if not layout_value is Dictionary: return
	var layout: Dictionary = layout_value
	var basis: Basis = layout.get("basis", Basis.IDENTITY)
	var anchor: Vector3 = layout.get("anchor_center", Vector3.ZERO)
	var pane_center: Vector3 = layout.get("pane_center", Vector3.ZERO)
	var pane_size: Vector3 = layout.get("pane_size", Vector3(2.0, 2.8, 0.1))
	var detail_unit_value = visual.get("_detail_unit")
	var detail_unit: Vector3 = detail_unit_value if detail_unit_value is Vector3 else Vector3.ONE * 0.0625
	var cell: Vector3 = (basis.inverse() * detail_unit).abs()
	var container := Node3D.new()
	container.name = "M2WindowAdventure_" + id
	container.transform = Transform3D(basis, anchor.snapped(detail_unit))
	visual.add_child(container)
	var accent: Color = _custom_window_colour(view, detail)
	var asset_id: String = str(detail.get("asset_id", ""))
	_build_adventure_shape(container, asset_id, pane_center, pane_size, cell, accent, extras)
	_build_window_shutters(container, pane_center, pane_size, cell, accent, extras, asset_id)
	_build_window_flower_box(container, pane_center, pane_size, cell, accent, str(extras.get("flower_box", "none")))
	if str(extras.get("balcony", "none")) == "juliet":
		_build_juliet_balcony(container, pane_center, pane_size, cell, accent)

func _build_adventure_shape(parent: Node3D, asset_id: String, pane_center: Vector3, pane_size: Vector3, cell: Vector3, accent: Color, extras: Dictionary) -> void:
	var half := Vector2(pane_size.x, pane_size.y) * 0.5
	var state: String = str(extras.get("window_state", "closed"))
	if asset_id == "window_arch_casement":
		_add_adventure_box(parent, "ArchCenter", pane_center, Vector3(cell.x, pane_size.y * 0.74, cell.z), accent, cell)
		_add_adventure_box(parent, "ArchTransom", pane_center + Vector3(0, -pane_size.y * 0.12, 0), Vector3(pane_size.x, cell.y, cell.z), accent, cell)
		for side in [-1.0, 1.0]:
			for step in 3:
				var x: float = side * (half.x * 0.22 + float(step) * cell.x)
				var y: float = half.y - (float(step) + 0.75) * cell.y
				_add_adventure_box(parent, "Arch_%s_%d" % [side, step], pane_center + Vector3(x, y, cell.z), cell * Vector3(2, 1, 1), accent, cell)
	elif asset_id == "window_slider":
		for x in [-pane_size.x * 0.18, pane_size.x * 0.18]:
			_add_adventure_box(parent, "SliderMullion", pane_center + Vector3(x, 0, cell.z), Vector3(cell.x, pane_size.y, cell.z), accent, cell)
		_add_adventure_box(parent, "SliderRail", pane_center + Vector3(0, -half.y * 0.48, cell.z), Vector3(pane_size.x, cell.y, cell.z), accent, cell)
	elif asset_id == "window_awning" and state == "closed":
		_add_adventure_box(parent, "AwningHinge", pane_center + Vector3(0, half.y * 0.25, cell.z), Vector3(pane_size.x, cell.y, cell.z), accent, cell)
	elif asset_id == "window_bay":
		_build_bay_window(parent, pane_center, pane_size, cell, accent)
	if state == "open" and asset_id != "window_bay":
		_build_open_window(parent, asset_id, pane_center, pane_size, cell, accent)

func _build_open_window(parent: Node3D, asset_id: String, pane_center: Vector3, pane_size: Vector3, cell: Vector3, accent: Color) -> void:
	var half := Vector2(pane_size.x, pane_size.y) * 0.5
	if asset_id == "window_awning":
		var leaf := Node3D.new()
		leaf.name = "AwningOpenLeaf"
		leaf.position = pane_center + Vector3(0, half.y * 0.18, cell.z * 3.0)
		leaf.rotation.x = -0.48
		parent.add_child(leaf)
		_add_framed_glass(leaf, "Awning", Vector3.ZERO, Vector2(pane_size.x, pane_size.y * 0.82), cell, accent)
	elif asset_id == "window_slider":
		_add_framed_glass(parent, "SliderFixed", pane_center + Vector3(-half.x * 0.24, 0, 0), Vector2(pane_size.x * 0.52, pane_size.y), cell, accent)
		_add_framed_glass(parent, "SliderOpen", pane_center + Vector3(half.x * 0.08, 0, cell.z * 3.0), Vector2(pane_size.x * 0.52, pane_size.y), cell, accent)
	else:
		_add_framed_glass(parent, "CasementFixed", pane_center + Vector3(-half.x * 0.26, 0, 0), Vector2(pane_size.x * 0.48, pane_size.y), cell, accent)
		var leaf := Node3D.new()
		leaf.name = "CasementOpenLeaf"
		leaf.position = pane_center + Vector3(half.x * 0.28, 0, cell.z * 2.5)
		leaf.rotation.y = -0.62
		parent.add_child(leaf)
		_add_framed_glass(leaf, "Open", Vector3.ZERO, Vector2(pane_size.x * 0.48, pane_size.y), cell, accent)

func _build_bay_window(parent: Node3D, pane_center: Vector3, pane_size: Vector3, cell: Vector3, accent: Color) -> void:
	var half := Vector2(pane_size.x, pane_size.y) * 0.5
	_add_framed_glass(parent, "BayCenter", pane_center + Vector3(0, 0, cell.z * 4.0), Vector2(pane_size.x * 0.58, pane_size.y), cell, accent)
	for side in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.name = "BayWingLeft" if side < 0.0 else "BayWingRight"
		wing.position = pane_center + Vector3(side * half.x * 0.40, 0, cell.z * 2.2)
		wing.rotation.y = -side * 0.48
		parent.add_child(wing)
		_add_framed_glass(wing, "Glass", Vector3.ZERO, Vector2(pane_size.x * 0.34, pane_size.y), cell, accent)
	_add_adventure_box(parent, "BaySill", pane_center + Vector3(0, -half.y - cell.y, cell.z * 3.0), Vector3(pane_size.x + cell.x * 4.0, cell.y * 2.0, cell.z * 6.0), ADVENTURE_TRIM, cell)
	_add_adventure_box(parent, "BayCanopy", pane_center + Vector3(0, half.y + cell.y, cell.z * 3.0), Vector3(pane_size.x + cell.x * 4.0, cell.y, cell.z * 6.0), ADVENTURE_TRIM, cell)

func _add_framed_glass(parent: Node3D, prefix: String, center: Vector3, size: Vector2, cell: Vector3, accent: Color) -> void:
	_add_adventure_box(parent, prefix + "Glass", center, Vector3(size.x, size.y, cell.z), ADVENTURE_GLASS, cell)
	var half := size * 0.5
	for side in [-1.0, 1.0]:
		var horizontal_name: String = "Left" if side < 0.0 else "Right"
		var vertical_name: String = "Bottom" if side < 0.0 else "Top"
		_add_adventure_box(parent, prefix + "FrameV" + horizontal_name, center + Vector3(side * (half.x + cell.x * 0.5), 0, cell.z), Vector3(cell.x, size.y + cell.y * 2.0, cell.z), accent, cell)
		_add_adventure_box(parent, prefix + "FrameH" + vertical_name, center + Vector3(0, side * (half.y + cell.y * 0.5), cell.z), Vector3(size.x + cell.x * 2.0, cell.y, cell.z), accent, cell)

func _build_window_shutters(parent: Node3D, pane_center: Vector3, pane_size: Vector3, cell: Vector3, accent: Color, extras: Dictionary, asset_id: String) -> void:
	var style: String = str(extras.get("shutter_style", "original"))
	var state: String = str(extras.get("shutter_state", "open"))
	if style == "none": return
	if style == "original" and state == "open" and asset_id not in ["window_awning", "window_slider", "window_bay"]: return
	if style == "original": style = "boarded"
	var states: Array[String] = ["closed", "open"]
	if state == "closed": states = ["closed", "closed"]
	elif state == "open": states = ["open", "open"]
	else: states = ["closed", "open"]
	for index in 2:
		var side: float = -1.0 if index == 0 else 1.0
		_build_window_shutter_leaf(parent, "CustomShutter%d" % index, side, states[index], style, pane_center, pane_size, cell, accent)

func _build_window_shutter_leaf(parent: Node3D, node_name: String, side: float, state: String, style: String, pane_center: Vector3, pane_size: Vector3, cell: Vector3, accent: Color) -> void:
	var half := Vector2(pane_size.x, pane_size.y) * 0.5
	var leaf_width: float = maxf(cell.x * 3.0, pane_size.x * 0.46)
	var holder := Node3D.new()
	holder.name = node_name + "_" + state
	if state == "closed":
		holder.position = pane_center + Vector3(side * pane_size.x * 0.24, 0, cell.z * 4.0)
	else:
		holder.position = pane_center + Vector3(side * (half.x + leaf_width * 0.55 + cell.x), 0, cell.z * 2.5)
		holder.rotation.y = -side * 0.38
	parent.add_child(holder)
	_add_adventure_box(holder, "Panel", Vector3.ZERO, Vector3(leaf_width, pane_size.y, cell.z * 2.0), accent, cell)
	if style == "louvered":
		for row in 5:
			var y: float = -half.y * 0.72 + float(row) * pane_size.y * 0.18
			_add_adventure_box(holder, "Louver%d" % row, Vector3(0, y, cell.z * 1.5), Vector3(leaf_width - cell.x, cell.y, cell.z), accent.lightened(0.08), cell)
	elif style == "braced":
		for y in [-half.y * 0.30, half.y * 0.30]:
			_add_adventure_box(holder, "BraceHBottom" if y < 0.0 else "BraceHTop", Vector3(0, y, cell.z * 1.5), Vector3(leaf_width - cell.x, cell.y, cell.z), accent.darkened(0.08), cell)
		for step in 6:
			var x: float = -leaf_width * 0.32 + float(step) * leaf_width * 0.13
			var y: float = -pane_size.y * 0.30 + float(step) * pane_size.y * 0.12
			_add_adventure_box(holder, "BraceD%d" % step, Vector3(x, y, cell.z * 1.5), cell * Vector3(2, 2, 1), accent.darkened(0.08), cell)
	else:
		for y in [-half.y * 0.30, half.y * 0.30]:
			_add_adventure_box(holder, "BoardStrapBottom" if y < 0.0 else "BoardStrapTop", Vector3(0, y, cell.z * 1.5), Vector3(leaf_width - cell.x, cell.y, cell.z), accent.darkened(0.08), cell)
		_add_adventure_box(holder, "BoardSeam", Vector3(0, 0, cell.z * 1.5), Vector3(cell.x, pane_size.y - cell.y, cell.z), accent.darkened(0.06), cell)

func _build_window_flower_box(parent: Node3D, pane_center: Vector3, pane_size: Vector3, cell: Vector3, accent: Color, style: String) -> void:
	if style == "none": return
	var half := Vector2(pane_size.x, pane_size.y) * 0.5
	var width: float = pane_size.x + cell.x * 2.0
	var y: float = pane_center.y - half.y - cell.y * 2.2
	var z: float = pane_center.z + cell.z * 4.0
	_add_adventure_box(parent, "WindowFlowerBox", Vector3(pane_center.x, y, z), Vector3(width, cell.y * 2.0, cell.z * 5.0), accent, cell)
	_add_adventure_box(parent, "WindowFlowerLip", Vector3(pane_center.x, y + cell.y * 1.5, z + cell.z), Vector3(width + cell.x, cell.y, cell.z * 2.0), accent.lightened(0.05), cell)
	if style == "bracketed":
		for side in [-1.0, 1.0]:
			_add_adventure_box(parent, "FlowerBracketLeft" if side < 0.0 else "FlowerBracketRight", Vector3(pane_center.x + side * width * 0.28, y - cell.y * 1.5, z - cell.z), cell * Vector3(2, 3, 2), accent.darkened(0.10), cell)
	elif style == "woven":
		for i in 5:
			_add_adventure_box(parent, "FlowerWeave%d" % i, Vector3(pane_center.x - width * 0.36 + float(i) * width * 0.18, y, z + cell.z * 2.8), cell, accent.lightened(0.10 if i % 2 == 0 else 0.02), cell)
	for i in 7:
		var x: float = pane_center.x - width * 0.38 + float(i) * width * 0.125
		var plant_y: float = y + cell.y * (2.5 + float(i % 2))
		_add_adventure_box(parent, "FlowerLeaf%d" % i, Vector3(x, plant_y, z + cell.z), cell, ADVENTURE_FOLIAGE, cell)
		if i % 2 == 0:
			_add_adventure_box(parent, "FlowerBloom%d" % i, Vector3(x, plant_y + cell.y, z + cell.z * 1.5), cell, ADVENTURE_FLOWERS[i % ADVENTURE_FLOWERS.size()], cell)

func _build_juliet_balcony(parent: Node3D, pane_center: Vector3, pane_size: Vector3, cell: Vector3, accent: Color) -> void:
	var half := Vector2(pane_size.x, pane_size.y) * 0.5
	var width: float = pane_size.x + cell.x * 5.0
	var bottom_y: float = pane_center.y - half.y * 0.78
	var front_z: float = pane_center.z + cell.z * 7.0
	_add_adventure_box(parent, "JulietSill", Vector3(pane_center.x, pane_center.y - half.y - cell.y, pane_center.z + cell.z * 3.5), Vector3(width, cell.y, cell.z * 7.0), ADVENTURE_TRIM, cell)
	_add_adventure_box(parent, "JulietTopRail", Vector3(pane_center.x, bottom_y + pane_size.y * 0.38, front_z), Vector3(width, cell.y * 2.0, cell.z), accent, cell)
	_add_adventure_box(parent, "JulietBottomRail", Vector3(pane_center.x, bottom_y, front_z), Vector3(width, cell.y, cell.z), accent, cell)
	for i in 7:
		var x: float = pane_center.x - width * 0.42 + float(i) * width * 0.14
		_add_adventure_box(parent, "JulietBaluster%d" % i, Vector3(x, bottom_y + pane_size.y * 0.19, front_z), Vector3(cell.x, pane_size.y * 0.38, cell.z), accent, cell)

func _add_adventure_box(parent: Node3D, node_name: String, center: Vector3, size: Vector3, colour: Color, unit: Vector3) -> MeshInstance3D:
	var quantized: Dictionary = WindowGrid.quantized_box(center, size, unit)
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = quantized.get("size", size)
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.82
	node.material_override = material
	node.position = quantized.get("center", center)
	parent.add_child(node)
	return node
