extends "res://scripts/m2_scene_window_alignment.gd"

## Direct surface controls and one-sided edits of existing named sections.
## All previews are disposable; the world API owns the single commit.
const PartPick = preload("res://scripts/m2_house_part_pick.gd")
const SectionMath = preload("res://scripts/m2_section_edit.gd")
const SectionWorld = preload("res://scripts/m2_section_edit_world.gd")
const SectionOverlay = preload("res://scripts/ui/m2_section_overlay.gd")
var _house_ux_ready := false
var _part_hover: Dictionary = {}
var _part_target: Dictionary = {}
var _part_menu: ColourPopover
var _part_buttons: Array[Button] = []
var _part_menu_open := false
var _part_revision := -1
var _part_building := ""
var _part_hint: Label
var _part_lines: SectionOverlay
var _roof_pick_key := ""
var _roof_pick_groups: Array = []
var _roof_pick_nodes: Array[GeometryInstance3D] = []
var _roof_scope_highlight: StandardMaterial3D
var _roof_overlay_backup: Dictionary = {}
var _part_wall_runs: Array[Dictionary] = []
var _section_edit_active := false
var _section_edit_id := ""
var _section_original: Dictionary = {}
var _section_candidate: Dictionary = {}
var _section_result: Dictionary = {}
var _section_reason := ""
var _section_edge := 0
var _section_amount := 0.0
var _section_step := 0.0
var _addition_raw := Vector3.ZERO
var _addition_was_active := false

func _build_world() -> void:
	super._build_world()
	# World construction occurs before save restoration or signal listeners.
	building_world = SectionWorld.new()

func _ready() -> void:
	super._ready()
	_part_menu = ColourPopover.new()
	_part_menu.name = "HousePartActions"
	hud.add_child(_part_menu)
	for spec in [["shape", "Shape"], ["material", "Material"], ["resize", "Resize"], ["window", "Window"], ["door", "Door"], ["section", "+ Section"], ["floor", "+ Floor"], ["house", "House"]]:
		var button := Button.new()
		button.text = spec[1]
		button.accessibility_name = spec[1]
		button.custom_minimum_size = Vector2(86, 48)
		button.set_meta("part_action", spec[0])
		button.pressed.connect(_choose_part_action.bind(str(spec[0])))
		_part_menu.row.add_child(button)
		_part_buttons.append(button)
	_part_hint = Label.new()
	_part_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_part_hint.add_theme_font_size_override("font_size", 18)
	hud.add_child(_part_hint)
	_part_lines = SectionOverlay.new()
	hud.add_child(_part_lines)
	_compact_roof_choices()
	_house_ux_ready = true

func _compact_roof_choices() -> void:
	var previous := _roof_design_picker
	_roof_design_picker = ColourPopover.new()
	_roof_design_picker.name = "RoofShapePopover"
	hud.add_child(_roof_design_picker)
	for button in _roof_design_buttons:
		var profile := str(button.get_meta("roof_profile"))
		(_roof_design_picker as ColourPopover).add_choice(button, Color("#bf7755"), _roof_label(profile))
		button.icon = _roof_shape_icon(profile)
	previous.queue_free()

func _roof_shape_icon(profile: String) -> Texture2D:
	var points := "4,30 24,9 44,30"
	match profile:
		"swept_gable": points = "4,30 24,21 44,30"
		"steep_gable": points = "4,32 24,3 44,32"
		"hip": points = "4,31 15,13 33,13 44,31 4,31"
		"shed": points = "4,31 4,10 44,27 44,31"
		"saltbox": points = "4,31 16,9 44,31"
		"gambrel": points = "4,32 12,15 24,7 36,15 44,32"
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="48" height="40"><polyline points="%s" fill="none" stroke="#fff2d4" stroke-width="4" stroke-linejoin="round"/></svg>' % points)
	return ImageTexture.create_from_image(image)

func _part_idle() -> bool:
	return _house_ux_ready and _idle_building() and not portion_placement_active and not _resize_selecting and not _section_edit_active and not _blocked_until_accept_release

func _process(delta: float) -> void:
	if _house_ux_ready and tools_open and not menu_open and (_part_menu_open or _section_edit_active or _roof_design_picker_open or _surface_material_picker_open):
		_read_part_orbit(delta)
		if _section_edit_active:
			var amount := -Input.get_axis("m1_move_up", "m1_move_down")
			if absf(amount) > 0.05: _change_section_size(amount * delta * (1.5 if precision_mode else 4.0))
		if not _part_building.is_empty() and (selected_building_id != _part_building or building_world.get_revision() != _part_revision):
			_cancel_current_edit("House changed; edit cancelled")
	super._process(delta)
	if not _house_ux_ready: return
	if _part_idle(): _part_hover = _pick_house_part(edit_pointer)
	else: _part_hover = {}
	_refresh_part_feedback()

func _read_part_orbit(delta: float) -> void:
	camera_yaw += Input.get_axis("m1_orbit_left", "m1_orbit_right") * delta * 2.2
	camera_pitch = clampf(camera_pitch + Input.get_axis("m1_orbit_up", "m1_orbit_down") * delta * 1.5, 0.08, 1.40)
	camera_distance = clampf(camera_distance - Input.get_axis("m1_zoom_out", "m1_zoom_in") * delta * 18, BUILDING_CAMERA_MIN_DISTANCE, BUILDING_CAMERA_MAX_DISTANCE)

func _input(event: InputEvent) -> void:
	if not _house_ux_ready or _shutting_down or _blocked_until_accept_release:
		super._input(event)
		return
	if _section_edit_active and not menu_open:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"): _cancel_section_edit()
		elif event.is_action_pressed("m1_pause"): _cancel_section_edit(); super._input(event)
		elif event.is_action_pressed("m1_accept"): _commit_section_edit()
		elif event.is_action_pressed("m1_cycle_left"): _select_section_edge(-1)
		elif event.is_action_pressed("m1_cycle_right"): _select_section_edge(1)
		elif event.is_action_pressed("m1_height_up"): _change_section_size(1.0)
		elif event.is_action_pressed("m1_height_down"): _change_section_size(-1.0)
		elif event.is_action_pressed("m1_precision"): precision_mode = not precision_mode
		get_viewport().set_input_as_handled()
		return
	if _part_menu_open and not menu_open:
		if event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"): _close_part_menu()
		elif event.is_action_pressed("m1_pause"): _close_part_menu(); super._input(event)
		elif event.is_action_pressed("m1_accept"):
			var focused := get_viewport().gui_get_focus_owner()
			if focused in _part_buttons: (focused as Button).pressed.emit()
		elif event.is_action_pressed("m1_cycle_left") or event.is_action_pressed("m1_height_up"): _move_focus(_part_candidates(), -1)
		elif event.is_action_pressed("m1_cycle_right") or event.is_action_pressed("m1_height_down"): _move_focus(_part_candidates(), 1)
		get_viewport().set_input_as_handled()
		return
	if _roof_design_picker_open and not menu_open:
		if event.is_action_pressed("m1_cycle_left") or event.is_action_pressed("m1_cycle_right"):
			_move_focus(_roof_design_buttons, -1 if event.is_action_pressed("m1_cycle_left") else 1)
			get_viewport().set_input_as_handled()
			return
	if _part_idle() and event.is_action_pressed("m1_accept"):
		_update_detail_hover()
		var hit := _pick_house_part(edit_pointer)
		if hovered_detail_id.is_empty() and not hit.is_empty():
			_open_part_menu(hit)
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _pick_house_part(point: Vector2) -> Dictionary:
	if not camera or not building_world: return {}
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty(): return {}
	var inverse: Transform3D = (view["transform"] as Transform3D).affine_inverse()
	var origin := inverse * camera.project_ray_origin(point)
	var direction := inverse.basis * camera.project_ray_normal(point)
	var key := "%s|%d|%s" % [selected_building_id, building_world.get_revision(), view.get("roof_profile", "")]
	if key != _roof_pick_key:
		_set_roof_scope_highlight(false)
		_roof_pick_key = key
		_part_wall_runs = PartPick.walls(view)
		_roof_pick_groups.clear()
		_roof_pick_nodes.clear()
		var visual := cottage_visuals.get(selected_building_id) as Node3D
		if visual: _cache_roof_boxes(visual, visual, false)
	var hit := PartPick.pick_wall(_part_wall_runs, origin, direction)
	var nearest: float = float(hit.get("distance", INF))
	for group in _roof_pick_groups:
		var broad: float = _ray_box_distance(origin, direction, group["bounds"])
		if broad < 0 or broad > nearest: continue
		for box in group["boxes"]:
			var distance: float = _ray_box_distance(origin, direction, box)
			if distance < 0 or distance >= nearest: continue
			nearest = distance
			hit = {"kind": "roof", "position": origin + direction * distance, "distance": distance}
	if hit.is_empty(): return {}
	hit["section_id"] = PartPick.section_at(view, hit["position"], hit["kind"] == "roof")
	var owners: Array = (hit.get("run", {}) as Dictionary).get("edge_owners", [])
	if owners.size() == 1: hit["section_id"] = str(owners[0])
	hit["building_id"] = selected_building_id
	return hit

func _cache_roof_boxes(node: Node3D, visual: Node3D, inside_roof: bool) -> void:
	if not node.visible: return
	var name_value := str(node.name)
	var roof := inside_roof or name_value == "M2RoofDesign" or name_value.begins_with("RoofTiles_") or name_value.begins_with("JoinedRoof") or name_value == "RidgeCourses"
	# Do not target wall infill beneath custom roofs.
	if name_value.contains("Fill"): roof = false
	if roof and node is GeometryInstance3D:
		_roof_pick_nodes.append(node as GeometryInstance3D)
		var relative := visual.global_transform.affine_inverse() * node.global_transform
		var buckets: Dictionary = {}
		if node is MultiMeshInstance3D and DisplayServer.get_name() != "headless":
			var multi: MultiMesh = (node as MultiMeshInstance3D).multimesh
			if multi and multi.mesh:
				for i in multi.instance_count:
					var box: AABB = (relative * multi.get_instance_transform(i)) * multi.mesh.get_aabb()
					_bucket_roof_box(buckets, box)
		elif node is MeshInstance3D and (node as MeshInstance3D).mesh:
			_bucket_roof_box(buckets, relative * (node as MeshInstance3D).mesh.get_aabb())
		for bucket in buckets.values(): _roof_pick_groups.append(bucket)
	for child in node.get_children():
		if child is Node3D: _cache_roof_boxes(child, visual, roof)

func _bucket_roof_box(buckets: Dictionary, box: AABB) -> void:
	var point := box.get_center()
	var key := Vector2i(floori(point.x / 2.0), floori(point.z / 2.0))
	if not buckets.has(key): buckets[key] = {"bounds": box, "boxes": []}
	buckets[key]["bounds"] = (buckets[key]["bounds"] as AABB).merge(box)
	buckets[key]["boxes"].append(box)

func _open_part_menu(hit: Dictionary) -> void:
	if hit.is_empty(): return
	_part_target = hit.duplicate(true)
	_part_building = selected_building_id
	_part_revision = building_world.get_revision()
	_part_menu_open = true
	tools_open = true
	_building_actions_open = false
	_context_actions_open = false
	_clear_hover()
	for button in _part_buttons:
		var action := str(button.get_meta("part_action"))
		button.visible = action not in ["shape", "window", "door"] or (action == "shape" and hit["kind"] == "roof") or (action in ["window", "door"] and hit["kind"] == "wall")
		button.disabled = action in ["resize", "section", "floor"] and str(hit.get("section_id", "")).is_empty()
	_part_menu.show()
	var candidates := _part_candidates()
	if not candidates.is_empty(): candidates[0].grab_focus()
	_refresh_controller_hud()
	_refresh_part_feedback.call_deferred()

func _part_candidates() -> Array[Button]:
	var result: Array[Button] = []
	for button in _part_buttons:
		if button.visible and not button.disabled: result.append(button)
	return result

func _close_part_menu() -> void:
	_part_menu_open = false
	if _part_menu: _part_menu.hide()
	tools_open = false
	get_viewport().gui_release_focus()
	_refresh_controller_hud()

func _choose_part_action(action: String) -> void:
	if not _part_menu_open: return
	var target := _part_target.duplicate(true)
	_close_part_menu()
	match action:
		"material": _open_surface_material_picker("roof" if target["kind"] == "roof" else "wall")
		"shape": _open_roof_design_picker()
		"house": _open_house_actions()
		"resize": _begin_section_edit(str(target.get("section_id", "")))
		"window", "door":
			selected_surface_id = str(target.get("surface_id", ""))
			selected_detail_id = ""
			_begin_new_attachment(action)
			if detail_move_active:
				var view: Dictionary = building_world.get_building(selected_building_id)
				var placed := WallPlacement.nearest_available(view, "", selected_surface_id, target["position"], _attachment_preview_half(_attachment_preview_detail()))
				if not placed.is_empty():
					detail_move_position = placed["position"]
					_detail_free_position = detail_move_position
					_update_presentation()
		"section", "floor": _add_from_section(str(target.get("section_id", "")), action == "floor")

func _add_from_section(id: String, above: bool) -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	var item := SectionMath.section(view, id)
	if item.is_empty(): return
	var level := HouseMassing.section_level(item) + (1 if above else 0)
	if level >= HouseMassing.MAX_FLOORS: _set_status("Maximum floor count reached"); return
	if level == 0: _begin_portion_placement()
	else: _begin_portion_on_level(level)
	if not portion_placement_active: return
	var size: Vector3 = item["size"]
	portion_size = Vector3(minf(6, size.x), size.y, minf(6, size.z))
	portion_offset = item["offset"]
	if not above:
		var orientation := str((_part_target.get("run", {}) as Dictionary).get("orientation", "right"))
		var axis := 0 if orientation in ["left", "right"] else 2
		portion_offset[axis] += (-1 if orientation in ["left", "front"] else 1) * (size[axis] + portion_size[axis]) * 0.5
	portion_offset.y = level * size.y
	_addition_raw = portion_offset
	_addition_was_active = true
	_update_portion_preview()

func _clear_portion_placement() -> void:
	_addition_was_active = false
	super._clear_portion_placement()

func _read_camera_and_cursor(delta: float) -> void:
	if not portion_placement_active: _addition_was_active = false; super._read_camera_and_cursor(delta); return
	# Accumulate sub-cell motion instead of rounding each frame back to zero.
	if not _addition_was_active: _addition_raw = portion_offset; _addition_was_active = true
	var move := Vector2(Input.get_axis("m1_move_left", "m1_move_right"), Input.get_axis("m1_move_up", "m1_move_down"))
	if move.length() > 0.05:
		var view: Dictionary = building_world.get_building(selected_building_id)
		var forward := Vector3(sin(camera_yaw), 0, cos(camera_yaw))
		var right := Vector3(forward.z, 0, -forward.x)
		_addition_raw += (view["transform"] as Transform3D).basis.inverse() * (right * move.x + forward * move.y) * delta * (2.2 if precision_mode else 4.5)
		portion_offset.x = snappedf(_addition_raw.x, HouseMassing.CELL)
		portion_offset.z = snappedf(_addition_raw.z, HouseMassing.CELL)
		_update_portion_preview()
	_read_part_orbit(delta)

func _begin_section_edit(id: String) -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	var item := SectionMath.section(view, id)
	if item.is_empty(): return
	_part_building = selected_building_id
	_part_revision = building_world.get_revision()
	_section_edit_id = id
	_section_original = item
	_section_candidate = item.duplicate(true)
	_section_edge = 0
	_section_amount = 0
	_section_step = 0
	_section_edit_active = true
	tools_open = true
	_building_actions_open = false
	_update_section_preview()

func _select_section_edge(direction: int) -> void:
	_section_edge = posmod(_section_edge + direction, SectionMath.EDGES.size())
	_section_original = _section_candidate.duplicate(true)
	_section_amount = 0
	_section_step = 0
	_refresh_part_feedback()

func _change_section_size(amount: float) -> void:
	if not _section_edit_active: return
	_section_amount += amount
	var step := snappedf(_section_amount, 1.0)
	if step == _section_step: return
	_section_step = step
	_section_candidate = SectionMath.resize_edge(_section_original, SectionMath.EDGES[_section_edge], step)
	_update_section_preview()

func _update_section_preview() -> void:
	_section_result = building_world.preview_section_resize(_part_building, _section_edit_id, _section_candidate, _part_revision)
	_section_reason = str(_section_result.get("reason", "House changed; cancel and retry"))
	if _section_result.has("view"):
		var preview: Dictionary = _section_result["view"]
		_section_reason = _portion_world_reason(preview, HouseMassing.sections_for(preview))
	_presentation_key = ""
	_update_presentation()
	_refresh_controller_hud()
	_refresh_part_feedback()

func _commit_section_edit() -> bool:
	if not _section_edit_active: return false
	_update_section_preview()
	if not _section_reason.is_empty(): _set_status(_section_reason); return false
	var ok: bool = building_world.commit_section_resize(_part_building, _section_edit_id, _section_candidate, _part_revision)
	_cancel_section_edit()
	if ok: _record_history("building"); _set_status("Section resized")
	return ok

func _cancel_section_edit() -> void:
	_section_edit_active = false
	_section_result = {}
	_section_reason = ""
	tools_open = false
	_presentation_key = ""
	_roof_pick_key = ""
	_update_presentation()
	_refresh_controller_hud()
	_refresh_part_feedback()

func _preview_massing_view(view: Dictionary) -> Dictionary:
	if _section_edit_active and str(view.get("id", "")) == _part_building and _section_result.has("view"):
		return (_section_result["view"] as Dictionary).duplicate(true)
	var result: Dictionary = super._preview_massing_view(view)
	if str(view.get("id", "")) == selected_building_id and (_roof_design_picker_open or _surface_material_picker_open):
		result = result.duplicate(true)
		if _roof_design_picker_open: result["roof_profile"] = _roof_design_preview
		if _surface_material_picker_open and _surface_material_picker_kind in ["roof", "wall"]: result[_surface_material_picker_kind + "_material_id"] = _surface_material_picker_preview
	return result

func _update_presentation() -> void:
	super._update_presentation()
	if _section_edit_active and _section_result.has("view"):
		var preview: Dictionary = _section_result["view"]
		var visual := cottage_visuals.get(_part_building) as Node3D
		if visual:
			visual.apply_building(preview, building_world.get_revision())
			_refresh_massing_shell_for_visual(visual, preview)
			_apply_accent_to_visual(visual, preview, _accent_material_id(preview))

func _open_roof_design_picker() -> void:
	_part_building = selected_building_id
	_part_revision = building_world.get_revision()
	super._open_roof_design_picker()

func _open_surface_material_picker(kind: String) -> void:
	_part_building = selected_building_id
	_part_revision = building_world.get_revision()
	super._open_surface_material_picker(kind)

func _commit_roof_design(profile: String) -> void:
	if _part_revision != building_world.get_revision() or _part_building != selected_building_id:
		_cancel_roof_design_picker()
		_set_status("House changed; roof edit cancelled")
		return
	super._commit_roof_design(profile)
	_roof_pick_key = ""

func _commit_surface_material(material_id: String) -> void:
	if _part_revision != building_world.get_revision() or _part_building != selected_building_id:
		_cancel_surface_material_picker()
		_set_status("House changed; material edit cancelled")
		return
	super._commit_surface_material(material_id)

func _apply_roof_design_preview() -> void:
	super._apply_roof_design_preview()
	if _roof_design_picker_open: _refresh_massing_shells()

func _apply_surface_material_preview() -> void:
	super._apply_surface_material_preview()
	if _surface_material_picker_open: _refresh_massing_shells()

func _cancel_current_edit(reason: String) -> void:
	if _part_menu_open: _close_part_menu()
	if _section_edit_active: _cancel_section_edit()
	if _roof_design_picker_open: _cancel_roof_design_picker()
	super._cancel_current_edit(reason)
	_part_building = ""

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if not _house_ux_ready or menu_open: return
	if _part_menu_open or _section_edit_active or _roof_design_picker_open:
		for control in [tools_panel, _building_panel, _tool_card, _world_prompt, _hover_prompt, _resize_hint]:
			if control: control.hide()
		if _section_edit_active: _set_prompts([["LEFT/RIGHT", "Edge"], ["UP/DOWN", "Resize"], ["A", "Apply"], ["B", "Cancel"], ["RS", "Orbit"]])
		else: _set_prompts([["LEFT/RIGHT", "Choose"], ["A", "Apply" if _roof_design_picker_open else "Choose"], ["B", "Back"], ["RS", "Orbit"]])

func _refresh_part_feedback() -> void:
	if not _house_ux_ready: return
	_set_roof_scope_highlight(false)
	_part_hint.hide()
	_part_lines.hide()
	if menu_open or view_context != "building": return
	if _section_edit_active:
		_draw_selected_section()
		return
	var target := _part_target if _part_menu_open or _roof_design_picker_open or _surface_material_picker_open else _part_hover
	if target.is_empty() or str(target.get("building_id", selected_building_id)) != selected_building_id or (not tools_open and not hovered_detail_id.is_empty()): return
	var view: Dictionary = building_world.get_building(selected_building_id)
	var point: Vector3 = (view["transform"] as Transform3D) * (target["position"] as Vector3)
	if camera.is_position_behind(point): return
	var at := camera.unproject_position(point)
	if target["kind"] == "roof": _set_roof_scope_highlight(true)
	if target["kind"] == "wall":
		var runs: Array = PartPick.walls(view) if _surface_material_picker_open and _surface_material_picker_kind == "wall" else [target.get("run", {})]
		var lines: Array = []
		var transform_value: Transform3D = view["transform"]
		for run in runs:
			if run.is_empty(): continue
			var axis := 0 if str(run["orientation"]) in ["front", "back"] else 2
			var points: Array[Vector3] = []
			for corner in [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]:
				var p := Vector3.ZERO
				p[axis] = lerpf(float(run["tangent_min"]), float(run["tangent_max"]), corner.x)
				p[2 if axis == 0 else 0] = float(run["normal"])
				p.y = lerpf(float(run["bottom"]), float(run["top"]), corner.y)
				points.append(transform_value * p)
			for i in 4:
				var a: Vector3 = points[i]
				var b: Vector3 = points[(i+1)%4]
				if not camera.is_position_behind(a) and not camera.is_position_behind(b): lines.append([camera.unproject_position(a), camera.unproject_position(b)])
		_part_lines.update_lines(lines, [], "", true)
		_part_lines.show()
	var available := get_viewport().get_visible_rect().grow(-16)
	available.size.y = maxf(0, minf(available.end.y, _prompt_bar.position.y - 18) - available.position.y)
	if _part_menu_open: _part_menu.place_near(Rect2(at - Vector2(20,20), Vector2(40,40)), available)
	elif _roof_design_picker_open: (_roof_design_picker as ColourPopover).place_near(Rect2(at - Vector2(20,20), Vector2(40,40)), available)
	elif not tools_open:
		_set_prompts([["LS", "Point"], ["A", "Edit roof" if target["kind"] == "roof" else "Edit wall"], ["X", "Home options"], ["RS", "Orbit"]])
		if _resize_hint: _resize_hint.hide()
		_part_hint.text = "A  Roof" if target["kind"] == "roof" else "A  Wall · Floor %d" % (int((target.get("run", {}) as Dictionary).get("massing_level", 0)) + 1)
		_part_hint.position = (at + Vector2(18, -30)).clamp(available.position, available.end - Vector2(210, 28))
		_part_hint.show()

func _draw_selected_section() -> void:
	var view: Dictionary = building_world.get_building(_part_building)
	var transform_value: Transform3D = view["transform"]
	var item := _section_candidate
	var size: Vector3 = item["size"]
	var offset: Vector3 = item["offset"]
	var bounds := AABB(Vector3(offset.x - size.x * 0.5, HouseMassing.section_bottom(item), offset.z - size.z * 0.5), size)
	var lines: Array = []
	for i in 8:
		for axis in 3:
			var j := i ^ (1 << axis)
			if j <= i: continue
			var a := transform_value * bounds.get_endpoint(i)
			var b := transform_value * bounds.get_endpoint(j)
			if not camera.is_position_behind(a) and not camera.is_position_behind(b): lines.append([camera.unproject_position(a), camera.unproject_position(b)])
	var points: Array = []
	for edge in SectionMath.EDGES:
		var p := bounds.get_center()
		if edge == "left": p.x = bounds.position.x
		elif edge == "right": p.x = bounds.end.x
		elif edge == "front": p.z = bounds.position.z
		else: p.z = bounds.end.z
		var world := transform_value * p
		if not camera.is_position_behind(world): points.append({"edge": edge, "position": camera.unproject_position(world)})
	_part_lines.update_lines(lines, points, SectionMath.EDGES[_section_edge], _section_reason.is_empty())
	_part_lines.show()
	_part_hint.text = "Floor %d · %s · %.1f × %.1f" % [HouseMassing.section_level(item) + 1, SectionMath.EDGES[_section_edge].capitalize(), size.x, size.z] if _section_reason.is_empty() else _section_reason
	_part_hint.position = Vector2(24, _prompt_bar.position.y - 38)
	_part_hint.show()

func _set_roof_scope_highlight(enabled: bool) -> void:
	if not _roof_scope_highlight:
		_roof_scope_highlight = StandardMaterial3D.new()
		_roof_scope_highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_roof_scope_highlight.albedo_color = Color("#ffcf73")
		_roof_scope_highlight.cull_mode = BaseMaterial3D.CULL_FRONT
		_roof_scope_highlight.grow = true
		_roof_scope_highlight.grow_amount = 0.04
	for node in _roof_pick_nodes:
		if not is_instance_valid(node): continue
		var id := node.get_instance_id()
		if enabled:
			if not _roof_overlay_backup.has(id): _roof_overlay_backup[id] = node.material_overlay
			node.material_overlay = _roof_scope_highlight
		elif _roof_overlay_backup.has(id):
			if node.material_overlay == _roof_scope_highlight: node.material_overlay = _roof_overlay_backup[id]
			_roof_overlay_backup.erase(id)
