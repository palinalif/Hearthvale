extends "res://scripts/m2_scene_roof_design.gd"

## Placeable roof accessories. Records live on the building recipe so save,
## undo/redo and whole-building duplication retain the authored composition.
const MAX_ROOF_ACCESSORIES := 10
const ROOF_ACCESSORY_SPECS: Array[Dictionary] = [
	{"id": "chimney_stone", "label": "Stone chimney", "kind": "chimney"},
	{"id": "chimney_brick", "label": "Brick chimney", "kind": "chimney"},
	{"id": "dormer_gable", "label": "Gabled dormer", "kind": "dormer"},
	{"id": "dormer_shed", "label": "Shed dormer", "kind": "dormer"},
	{"id": "weathervane_arrow", "label": "Arrow weathervane", "kind": "weathervane"},
	{"id": "weathervane_rooster", "label": "Rooster weathervane", "kind": "weathervane"},
]

var _roof_decor_button: Button
var _roof_decor_picker: PanelContainer
var _roof_decor_buttons: Array[Button] = []
var _roof_decor_remove_button: Button
var _roof_decor_picker_open := false
var roof_accessory_placement_active := false
var roof_accessory_asset_id := ""
var roof_accessory_u := 0.62
var roof_accessory_v := 0.38
var roof_accessory_yaw := 0.0

func _ready() -> void:
	super._ready()
	_install_roof_decor_action()
	_build_roof_decor_picker()
	_refresh_roof_accessories()

func _install_roof_decor_action() -> void:
	if not _building_panel: return
	var margin: MarginContainer = _building_panel.get_child(0) as MarginContainer
	var box: VBoxContainer = margin.get_child(0) as VBoxContainer
	_roof_decor_button = Button.new()
	_roof_decor_button.name = "RoofDecorAction"
	_roof_decor_button.text = "Roof decor"
	_roof_decor_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_roof_decor_button.focus_mode = Control.FOCUS_ALL
	_roof_decor_button.custom_minimum_size = Vector2(0, 31)
	_roof_decor_button.pressed.connect(_open_roof_decor_picker)
	box.add_child(_roof_decor_button)
	var roof_design: Button = null
	for button in _building_buttons:
		if button.text == "Roof design": roof_design = button; break
	if roof_design:
		box.move_child(_roof_decor_button, roof_design.get_index() + 1)
		var index: int = _building_buttons.find(roof_design)
		_building_buttons.insert(index + 1, _roof_decor_button)
	else:
		_building_buttons.append(_roof_decor_button)

func _build_roof_decor_picker() -> void:
	_roof_decor_picker = _make_catalogue_panel("RoofDecorPicker", Vector2(500, 440))
	var box: VBoxContainer = _catalogue_box(_roof_decor_picker)
	box.add_theme_constant_override("separation", 5)
	_add_catalogue_heading(box, "ROOF DECOR", "Choose an accessory, then position it on the roof")
	for spec in ROOF_ACCESSORY_SPECS:
		var button := Button.new()
		button.text = str(spec["label"])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(450, 40)
		button.focus_mode = Control.FOCUS_ALL
		button.set_meta("asset_id", str(spec["id"]))
		button.pressed.connect(_begin_roof_accessory_placement.bind(str(spec["id"])))
		box.add_child(button)
		_roof_decor_buttons.append(button)
	_roof_decor_remove_button = Button.new()
	_roof_decor_remove_button.text = "Remove last roof accessory"
	_roof_decor_remove_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_roof_decor_remove_button.custom_minimum_size = Vector2(450, 40)
	_roof_decor_remove_button.focus_mode = Control.FOCUS_ALL
	_roof_decor_remove_button.pressed.connect(_remove_last_roof_accessory)
	box.add_child(_roof_decor_remove_button)
	_roof_decor_buttons.append(_roof_decor_remove_button)

func _input(event: InputEvent) -> void:
	if roof_accessory_placement_active and not menu_open:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_cancel_roof_accessory_placement()
		elif event.is_action_pressed("m1_pause"):
			_cancel_roof_accessory_placement(); super._input(event)
		elif event.is_action_pressed("m1_accept"):
			_commit_roof_accessory_placement()
		elif event.is_action_pressed("m1_cycle_left"):
			roof_accessory_yaw -= PI * 0.5; _refresh_roof_accessory_preview()
		elif event.is_action_pressed("m1_cycle_right"):
			roof_accessory_yaw += PI * 0.5; _refresh_roof_accessory_preview()
		get_viewport().set_input_as_handled(); return
	if _roof_decor_picker_open and not menu_open:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_close_roof_decor_picker(true)
		elif event.is_action_pressed("m1_pause"):
			_close_roof_decor_picker(false); super._input(event)
		elif event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner(); if focus in _roof_decor_buttons: (focus as Button).pressed.emit()
		elif event.is_action_pressed("m1_height_up") or event.is_action_pressed("ui_up"):
			_move_focus(_roof_decor_buttons, -1)
		elif event.is_action_pressed("m1_height_down") or event.is_action_pressed("ui_down"):
			_move_focus(_roof_decor_buttons, 1)
		get_viewport().set_input_as_handled(); return
	super._input(event)

func _read_camera_and_cursor(delta: float) -> void:
	if not roof_accessory_placement_active:
		super._read_camera_and_cursor(delta); return
	var move := Vector2(Input.get_axis("m1_move_left", "m1_move_right"), Input.get_axis("m1_move_up", "m1_move_down"))
	if move.length() > 0.05:
		var speed: float = 0.16 if precision_mode else 0.42
		roof_accessory_u = clampf(roof_accessory_u + move.x * delta * speed, 0.05, 0.95)
		roof_accessory_v = clampf(roof_accessory_v - move.y * delta * speed, 0.05, 0.95)
		_refresh_roof_accessory_preview()
	var orbit_x: float = Input.get_axis("m1_orbit_left", "m1_orbit_right")
	var orbit_y: float = Input.get_axis("m1_orbit_up", "m1_orbit_down")
	camera_yaw += orbit_x * delta * 2.2
	camera_pitch = clampf(camera_pitch + orbit_y * delta * 1.5, 0.15, 1.25)
	var zoom: float = Input.get_axis("m1_zoom_out", "m1_zoom_in")
	camera_distance = clampf(camera_distance - zoom * delta * 18.0, 8.0, 52.0)

func _open_roof_decor_picker() -> void:
	_roof_decor_picker_open = true
	tools_open = true
	if _building_panel: _building_panel.visible = false
	_roof_decor_picker.visible = true
	_roof_decor_remove_button.disabled = _roof_accessories_for(selected_building_id).is_empty()
	if not _roof_decor_buttons.is_empty(): _roof_decor_buttons[0].grab_focus()
	_set_status("Roof decor • D-pad choose • A place • B back")
	_refresh_controller_hud()

func _close_roof_decor_picker(return_to_options: bool) -> void:
	_roof_decor_picker_open = false
	if _roof_decor_picker: _roof_decor_picker.visible = false
	if return_to_options:
		tools_open = true
		if _building_panel: _building_panel.visible = true
		if _roof_decor_button: _roof_decor_button.grab_focus()
		_set_status("Home options")
	else:
		tools_open = false
		get_viewport().gui_release_focus()
	_refresh_controller_hud()

func _begin_roof_accessory_placement(asset_id: String) -> void:
	var spec: Dictionary = _roof_accessory_spec(asset_id)
	if spec.is_empty(): return
	_close_roof_decor_picker(false)
	roof_accessory_placement_active = true
	roof_accessory_asset_id = asset_id
	roof_accessory_u = 0.62
	roof_accessory_v = 0.30 if asset_id.begins_with("dormer") else 0.42
	roof_accessory_yaw = 0.0
	_refresh_roof_accessory_preview()
	_set_status("Place %s • left stick move • D-pad left/right rotate • A place / B cancel" % _roof_accessory_label(asset_id))
	_refresh_controller_hud()

func _commit_roof_accessory_placement() -> bool:
	if not roof_accessory_placement_active: return false
	var accessory_id: String = _add_roof_accessory(selected_building_id, roof_accessory_asset_id, roof_accessory_u, roof_accessory_v, roof_accessory_yaw)
	var ok: bool = not accessory_id.is_empty()
	if ok: _record_history("building")
	_clear_roof_accessory_placement()
	_presentation_key = ""
	_update_presentation()
	_set_status("Roof accessory placed" if ok else "Roof accessory could not be placed")
	return ok

func _cancel_roof_accessory_placement() -> void:
	if not roof_accessory_placement_active: return
	_clear_roof_accessory_placement()
	_refresh_roof_accessories()
	_set_status("Roof accessory placement cancelled")
	_refresh_controller_hud()

func _clear_roof_accessory_placement() -> void:
	roof_accessory_placement_active = false
	roof_accessory_asset_id = ""
	roof_accessory_u = 0.62
	roof_accessory_v = 0.38
	roof_accessory_yaw = 0.0

func _add_roof_accessory(building_id: String, asset_id: String, u: float, v: float, yaw: float) -> String:
	var spec: Dictionary = _roof_accessory_spec(asset_id)
	if spec.is_empty(): return ""
	var index: int = building_world._building_index(building_id)
	if index < 0: return ""
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[index]
	var accessories: Array = building.get("roof_accessories", [])
	if accessories.size() >= MAX_ROOF_ACCESSORIES: return ""
	var before: Dictionary = building_world._copy(building_world._document)
	var accessory_id: String = building_world._allocate_id("roof-accessory")
	accessories.append({"id": accessory_id, "kind": str(spec["kind"]), "asset_id": asset_id, "u": clampf(u, 0.05, 0.95), "v": clampf(v, 0.05, 0.95), "yaw": yaw})
	building["roof_accessories"] = accessories
	buildings[index] = building
	if not building_world._record_change(before): return ""
	return accessory_id

func _remove_last_roof_accessory() -> bool:
	var index: int = building_world._building_index(selected_building_id)
	if index < 0: return false
	var buildings: Array = building_world._document["buildings"]
	var building: Dictionary = buildings[index]
	var accessories: Array = building.get("roof_accessories", [])
	if accessories.is_empty(): _set_status("No roof accessories to remove"); return false
	var before: Dictionary = building_world._copy(building_world._document)
	accessories.pop_back()
	building["roof_accessories"] = accessories
	buildings[index] = building
	var ok: bool = building_world._record_change(before)
	if ok: _record_history("building")
	_close_roof_decor_picker(true)
	_presentation_key = ""
	_update_presentation()
	_set_status("Removed last roof accessory" if ok else "No roof accessory removed")
	return ok

func _roof_accessory_spec(asset_id: String) -> Dictionary:
	for spec in ROOF_ACCESSORY_SPECS:
		if str(spec["id"]) == asset_id: return spec
	return {}

func _roof_accessory_label(asset_id: String) -> String:
	var spec: Dictionary = _roof_accessory_spec(asset_id)
	return str(spec.get("label", asset_id.replace("_", " ").capitalize()))

func _roof_accessories_for(building_id: String) -> Array:
	var view: Dictionary = building_world.get_building(building_id)
	var value = view.get("roof_accessories", [])
	return value if value is Array else []

func _update_presentation() -> void:
	super._update_presentation()
	_refresh_roof_accessories()

func _refresh_roof_accessory_preview() -> void:
	if not roof_accessory_placement_active: return
	var view: Dictionary = building_world.get_building(selected_building_id)
	var visual: Node3D = cottage_visuals.get(selected_building_id, null) as Node3D
	if view.is_empty() or not visual: return
	_refresh_roof_accessories_for_visual(visual, view, _preview_roof_accessory_record())

func _preview_roof_accessory_record() -> Dictionary:
	if not roof_accessory_placement_active: return {}
	var spec: Dictionary = _roof_accessory_spec(roof_accessory_asset_id)
	if spec.is_empty(): return {}
	return {"id": "preview-roof-accessory", "kind": str(spec["kind"]), "asset_id": roof_accessory_asset_id, "u": roof_accessory_u, "v": roof_accessory_v, "yaw": roof_accessory_yaw, "preview": true}

func _refresh_roof_accessories() -> void:
	if not building_world: return
	for building_id_value in cottage_visuals.keys():
		var building_id: String = str(building_id_value)
		var visual: Node3D = cottage_visuals.get(building_id, null) as Node3D
		var view: Dictionary = building_world.get_building(building_id)
		if not visual or view.is_empty(): continue
		var preview: Dictionary = _preview_roof_accessory_record() if roof_accessory_placement_active and building_id == selected_building_id else {}
		_refresh_roof_accessories_for_visual(visual, view, preview)

func _refresh_roof_accessories_for_visual(visual: Node3D, view: Dictionary, preview: Dictionary = {}) -> void:
	var records: Array = []
	var stored = view.get("roof_accessories", [])
	if stored is Array: records.append_array(stored)
	if not preview.is_empty(): records.append(preview)
	var signature: String = "%s|%s|%s|%s" % [str(view.get("dimensions", Vector3.ZERO)), str(view.get("roof_profile", "gentle_gable")), str(view.get("roof_material_id", "terracotta")), JSON.stringify(records)]
	var existing: Node3D = visual.get_node_or_null("M2RoofAccessories") as Node3D
	if existing and str(existing.get_meta("signature", "")) == signature: return
	if existing: visual.remove_child(existing); existing.queue_free()
	if records.is_empty(): return
	var root := Node3D.new()
	root.name = "M2RoofAccessories"
	root.set_meta("signature", signature)
	visual.add_child(root)
	for record_value in records:
		if record_value is Dictionary: _build_roof_accessory(root, view, record_value as Dictionary)

func _build_roof_accessory(root: Node3D, view: Dictionary, record: Dictionary) -> void:
	var dimensions: Vector3 = view.get("dimensions", Vector3(15, 6, 12))
	var u: float = clampf(float(record.get("u", 0.5)), 0.05, 0.95)
	var v: float = clampf(float(record.get("v", 0.5)), 0.05, 0.95)
	var x: float = lerpf(-dimensions.x * 0.36, dimensions.x * 0.36, u)
	var z: float = lerpf(-dimensions.z * 0.36, dimensions.z * 0.36, v)
	var profile: String = str(view.get("roof_profile", "gentle_gable"))
	var y: float = _roof_height_at(profile, dimensions, x, z)
	var holder := Node3D.new()
	holder.name = "Accessory_%s" % str(record.get("id", "roof"))
	holder.position = Vector3(x, y, z)
	holder.rotation.y = float(record.get("yaw", 0.0))
	root.add_child(holder)
	var asset_id: String = str(record.get("asset_id", ""))
	var wall_colour: Color = SURFACE_MATERIAL_COLOURS.get(str(view.get("wall_material_id", "stone_plaster")), Color("#e7cfab"))
	var roof_colour: Color = SURFACE_MATERIAL_COLOURS.get(str(view.get("roof_material_id", "terracotta")), Color("#b9654c"))
	var accent_colour: Color = ACCENT_COLOURS.get(_accent_material_id(view), Color("#557a70"))
	match asset_id:
		"chimney_stone": _build_chimney(holder, Color("#9a8776"), false)
		"chimney_brick": _build_chimney(holder, Color("#9c5d4a"), true)
		"dormer_gable": _build_dormer(holder, wall_colour, roof_colour, accent_colour, true, z > 0.0)
		"dormer_shed": _build_dormer(holder, wall_colour, roof_colour, accent_colour, false, z > 0.0)
		"weathervane_arrow": _build_weathervane(holder, accent_colour, false)
		"weathervane_rooster": _build_weathervane(holder, accent_colour, true)

func _roof_height_at(profile: String, dimensions: Vector3, x: float, z: float) -> float:
	var half_x: float = dimensions.x * 0.5 + 0.5
	var half_z: float = dimensions.z * 0.5 + 0.5
	if profile == "hip":
		var inset: float = minf(maxf(0.0, half_x - absf(x)), maxf(0.0, half_z - absf(z)))
		return dimensions.y + inset * 0.5
	if profile == "shed":
		var t: float = clampf((z + half_z) / (half_z * 2.0), 0.0, 1.0)
		return dimensions.y + t * maxf(2.0, dimensions.z * 0.24)
	if profile == "saltbox":
		var ridge_z: float = -dimensions.z * 0.16
		var rise: float = maxf(2.0, dimensions.y * 0.46)
		var run: float = ridge_z + half_z if z < ridge_z else half_z - ridge_z
		return dimensions.y + rise * (1.0 - clampf(absf(z - ridge_z) / maxf(run, 0.1), 0.0, 1.0))
	if profile == "gambrel":
		var rise: float = maxf(2.4, dimensions.y * 0.52)
		var t: float = clampf(absf(z) / half_z, 0.0, 1.0)
		var fraction: float = lerpf(1.0, 0.68, t / 0.45) if t <= 0.45 else lerpf(0.68, 0.0, (t - 0.45) / 0.55)
		return dimensions.y + rise * fraction
	var ratio: float = 0.30 if profile == "swept_gable" else 0.62 if profile == "steep_gable" else 0.42
	return dimensions.y + dimensions.y * ratio * (1.0 - clampf(absf(z) / half_z, 0.0, 1.0))

func _build_chimney(parent: Node3D, colour: Color, brick: bool) -> void:
	_add_accessory_box(parent, "Shaft", Vector3(0, 1.2, 0), Vector3(1.2, 2.4, 1.0), colour)
	_add_accessory_box(parent, "Cap", Vector3(0, 2.55, 0), Vector3(1.55, 0.3, 1.35), colour.lightened(0.08))
	if brick:
		for level in 4:
			var offset: float = 0.08 if level % 2 == 0 else -0.08
			_add_accessory_box(parent, "BrickCourse_%d" % level, Vector3(offset, 0.45 + level * 0.5, 0.53), Vector3(1.0, 0.14, 0.12), colour.lightened(float(level % 2) * 0.05))

func _build_weathervane(parent: Node3D, accent: Color, rooster: bool) -> void:
	var metal := Color("#4e5050")
	_add_accessory_box(parent, "Pole", Vector3(0, 1.5, 0), Vector3(0.18, 3.0, 0.18), metal)
	_add_accessory_box(parent, "Cross", Vector3(0, 2.65, 0), Vector3(2.0, 0.16, 0.16), metal)
	_add_accessory_box(parent, "Arrow", Vector3(1.05, 2.65, 0), Vector3(0.55, 0.3, 0.18), accent)
	_add_accessory_box(parent, "Tail", Vector3(-1.05, 2.65, 0), Vector3(0.45, 0.65, 0.18), accent.darkened(0.08))
	if rooster:
		_add_accessory_box(parent, "RoosterBody", Vector3(0.15, 3.05, 0), Vector3(0.65, 0.5, 0.18), accent)
		_add_accessory_box(parent, "RoosterHead", Vector3(0.55, 3.35, 0), Vector3(0.3, 0.3, 0.18), accent.lightened(0.08))
		for feather in 3:
			_add_accessory_box(parent, "TailFeather_%d" % feather, Vector3(-0.35 - feather * 0.18, 3.15 + feather * 0.12, 0), Vector3(0.18, 0.55, 0.18), accent.darkened(float(feather) * 0.05))

func _build_dormer(parent: Node3D, wall: Color, roof: Color, accent: Color, gabled: bool, back_side: bool) -> void:
	if back_side: parent.rotation.y += PI
	var width: float = 2.5 if gabled else 3.0
	_add_accessory_box(parent, "DormerBody", Vector3(0, 0.8, -0.15), Vector3(width, 1.6, 1.5), wall)
	_add_accessory_box(parent, "DormerWindow", Vector3(0, 0.8, -0.95), Vector3(width * 0.48, 0.8, 0.16), Color("#344e50"))
	_add_accessory_box(parent, "DormerMullion", Vector3(0, 0.8, -1.05), Vector3(0.16, 0.8, 0.16), accent)
	_add_accessory_box(parent, "DormerSill", Vector3(0, 0.32, -1.05), Vector3(width * 0.62, 0.16, 0.16), accent)
	if gabled:
		for side_value in [-1.0, 1.0]:
			var side: float = float(side_value)
			for step in 4:
				var x: float = side * (0.35 + step * 0.28)
				var y: float = 1.85 - step * 0.22
				_add_accessory_box(parent, "DormerGable_%s_%d" % [side, step], Vector3(x, y, -0.05), Vector3(0.55, 0.22, 1.85), roof)
		_add_accessory_box(parent, "DormerRidge", Vector3(0, 2.0, -0.05), Vector3(0.3, 0.22, 1.9), roof.lightened(0.06))
	else:
		for row in 4:
			_add_accessory_box(parent, "DormerShed_%d" % row, Vector3(0, 1.8 + row * 0.14, 0.55 - row * 0.38), Vector3(width + 0.35, 0.18, 0.55), roof.lightened(float(row % 2) * 0.03))

func _add_accessory_box(parent: Node3D, node_name: String, center: Vector3, size: Vector3, colour: Color) -> void:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new(); mesh.size = size; node.mesh = mesh
	var material := StandardMaterial3D.new(); material.albedo_color = colour; node.material_override = material
	node.position = center
	parent.add_child(node)

func _cancel_current_edit(reason: String) -> void:
	if roof_accessory_placement_active: _clear_roof_accessory_placement()
	if _roof_decor_picker_open:
		_roof_decor_picker_open = false
		if _roof_decor_picker: _roof_decor_picker.visible = false
	super._cancel_current_edit(reason)

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if _roof_decor_picker: _roof_decor_picker.visible = _roof_decor_picker_open and not menu_open
	if _roof_decor_picker_open:
		if _building_panel: _building_panel.visible = false
		if _tool_card: _tool_card.visible = false
		_tool_name.text = "Roof decor"
		_tool_meta.text = "Chimneys • dormers • weathervanes"
		_set_prompts([["UP/DOWN", "Choose"], ["A", "Place"], ["B", "Back"]])
	elif roof_accessory_placement_active:
		_tool_name.text = "Place roof decor"
		_tool_meta.text = _roof_accessory_label(roof_accessory_asset_id)
		_set_prompts([["LS", "Move"], ["◀▶", "Rotate"], ["A", "Place"], ["B", "Cancel"], ["RS", "Orbit"]])
