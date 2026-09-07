extends "res://scripts/m1_scene.gd"

## Focused M1 placement layer. The existing M1 scene logic remains untouched;
## this subclass adds wall-locked detail placement and transactional cottage
## duplication placement.

const WallPlacement = preload("res://scripts/wall_attachment_placement.gd")
const DetailPlacementGhost = preload("res://scripts/detail_placement_ghost.gd")
const BuildingPlacementGhost = preload("res://scripts/building_placement_ghost.gd")

var placement_kind := ""
var placement_asset_id := ""
var placement_previous_detail_id := ""
var placement_previous_surface_id := ""
var detail_move_original_surface_id := ""
var placement_ghost: Node3D

var building_placement_active := false
var building_placement_source_id := ""
var building_placement_origin := Vector3.ZERO
var building_placement_target := Vector3.ZERO
var building_placement_ghost: Node3D

func _ready() -> void:
	super._ready()
	placement_ghost = DetailPlacementGhost.new()
	placement_ghost.name = "AttachmentPlacementGhost"
	placement_ghost.visible = false
	add_child(placement_ghost)
	building_placement_ghost = BuildingPlacementGhost.new()
	building_placement_ghost.name = "BuildingPlacementGhost"
	building_placement_ghost.visible = false
	add_child(building_placement_ghost)

func _input(event: InputEvent) -> void:
	if building_placement_active:
		if event.is_action_pressed("m1_accept"):
			_commit_building_placement()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_cancel"):
			_cancel_building_placement()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_precision"):
			precision_mode = not precision_mode
			_set_status("Cottage placement precision %s" % ("ON" if precision_mode else "OFF"))
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_pause"):
			_cancel_building_placement()
			super._input(event)
			return
		if event.is_action_pressed("m1_tools") or event.is_action_pressed("m1_view") or event.is_action_pressed("m1_cycle_left") or event.is_action_pressed("m1_cycle_right") or event.is_action_pressed("m1_undo") or event.is_action_pressed("m1_redo"):
			get_viewport().set_input_as_handled()
			return
	if view_context == "building" and detail_move_active and not menu_open and not tools_open and not detail_open:
		if event.is_action_pressed("m1_cycle_left"):
			_cycle_attachment_surface(-1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("m1_cycle_right"):
			_cycle_attachment_surface(1)
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _tool_choice(choice: String) -> void:
	if view_context == "building" and choice == "Duplicate cottage":
		_begin_building_placement()
		return
	if view_context == "building" and choice in ["Add flower box", "Add shutter"]:
		_begin_new_attachment("flower_box" if choice == "Add flower box" else "shutter")
		return
	super._tool_choice(choice)

func _read_camera_and_cursor(delta: float) -> void:
	if not building_placement_active:
		super._read_camera_and_cursor(delta)
		return
	var move := Vector2(Input.get_axis("m1_move_left", "m1_move_right"), Input.get_axis("m1_move_up", "m1_move_down"))
	if move.length() > 0.05:
		var magnitude := minf(move.length(), 1.0)
		move = move.normalized() * pow(magnitude, 1.45)
		var speed := lerpf(2.5, 10.0, pow(magnitude, 0.85))
		if precision_mode: speed *= 0.35
		var forward := Vector3(sin(camera_yaw), 0, cos(camera_yaw))
		var right := Vector3(forward.z, 0, -forward.x)
		building_placement_target += (right * move.x + forward * move.y) * delta * speed
		_clamp_building_placement()
		_snap_building_placement_to_ground()
	var orbit_x := Input.get_axis("m1_orbit_left", "m1_orbit_right")
	var orbit_y := Input.get_axis("m1_orbit_up", "m1_orbit_down")
	camera_yaw += orbit_x * delta * 2.2
	camera_pitch = clampf(camera_pitch + orbit_y * delta * 1.5, 0.15, 1.25)
	var zoom := Input.get_axis("m1_zoom_out", "m1_zoom_in")
	camera_distance = clampf(camera_distance - zoom * delta * 18.0, 8, 52)
	cursor = building_placement_target
	cottage_cursor = cursor
	if building_placement_ghost: building_placement_ghost.set_preview_origin(building_placement_target)

func _begin_building_placement() -> void:
	if building_placement_active or detail_move_active or resize_active: return
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty(): return
	var transform_value = view.get("transform", Transform3D.IDENTITY)
	if not transform_value is Transform3D: return
	building_placement_active = true
	building_placement_source_id = selected_building_id
	building_placement_origin = (transform_value as Transform3D).origin
	building_placement_target = building_placement_origin + Vector3(4.0, 0.0, 4.0)
	_clamp_building_placement()
	_snap_building_placement_to_ground()
	tools_open = false
	detail_open = false
	if tools_panel: tools_panel.visible = false
	if building_placement_ghost:
		building_placement_ghost.show_source(view, building_world.get_revision())
		building_placement_ghost.set_preview_origin(building_placement_target)
	cursor = building_placement_target
	cottage_cursor = cursor
	_set_status("Place cottage copy • left stick free place • A place / B cancel • L3 precision")

func _clamp_building_placement() -> void:
	var view: Dictionary = building_world.get_building(building_placement_source_id)
	if view.is_empty(): return
	var dims: Vector3 = view.get("dimensions", Vector3(18, 7, 14))
	var transform_value = view.get("transform", Transform3D.IDENTITY)
	var scale := Vector3.ONE
	if transform_value is Transform3D: scale = (transform_value as Transform3D).basis.get_scale().abs()
	var half_x := dims.x * scale.x * 0.5
	var half_z := dims.z * scale.z * 0.5
	building_placement_target.x = clampf(building_placement_target.x, half_x + 0.25, 48.0 - half_x - 0.25)
	building_placement_target.z = clampf(building_placement_target.z, half_z + 0.25, 48.0 - half_z - 0.25)

func _snap_building_placement_to_ground() -> void:
	if not backend or not backend.has_method("sample_surface_plane"): return
	var sample: Dictionary = backend.sample_surface_plane(building_placement_target + Vector3.UP * 2.0, Vector3.UP, 8.0)
	if bool(sample.get("valid", false)) and sample.get("point", null) is Vector3:
		building_placement_target.y = (sample["point"] as Vector3).y

func _commit_building_placement() -> bool:
	if not building_placement_active: return false
	var offset := building_placement_target - building_placement_origin
	var duplicate_id: String = building_world.duplicate_building(building_placement_source_id, offset)
	var ok := not duplicate_id.is_empty()
	if ok:
		selected_building_id = duplicate_id
		selected_detail_id = ""
		selected_surface_id = ""
		_record_history("building")
	_clear_building_placement()
	_set_status("Cottage copy placed" if ok else "Duplicate rejected")
	super._update_presentation()
	return ok

func _cancel_building_placement() -> void:
	if not building_placement_active: return
	var source_id := building_placement_source_id
	var source_origin := building_placement_origin
	_clear_building_placement()
	selected_building_id = source_id
	cursor = source_origin
	cottage_cursor = cursor
	_set_status("Cottage duplication cancelled")
	super._update_presentation()

func _clear_building_placement() -> void:
	building_placement_active = false
	building_placement_source_id = ""
	building_placement_origin = Vector3.ZERO
	building_placement_target = Vector3.ZERO
	if building_placement_ghost: building_placement_ghost.hide_preview()

func _begin_detail_move() -> void:
	super._begin_detail_move()
	if detail_move_active: detail_move_original_surface_id = detail_move_surface_id

func _begin_new_attachment(kind: String) -> void:
	if detail_move_active or resize_active or kind not in ["flower_box", "shutter"]: return
	var view: Dictionary = building_world.get_building(selected_building_id)
	if view.is_empty(): return
	var walls := WallPlacement.wall_ids(view)
	if walls.is_empty():
		_set_status("No usable cottage wall for attachment")
		return
	placement_previous_detail_id = selected_detail_id
	placement_previous_surface_id = selected_surface_id
	var surface_id := selected_surface_id if walls.has(selected_surface_id) else ""
	var selected_position = null
	if not placement_previous_detail_id.is_empty():
		for detail_value in view.get("details", []):
			var detail: Dictionary = detail_value
			if str(detail.get("id", "")) != placement_previous_detail_id: continue
			if surface_id.is_empty():
				var candidate_surface := str(detail.get("anchor", {}).get("surface_id", ""))
				if walls.has(candidate_surface): surface_id = candidate_surface
			if str(detail.get("anchor", {}).get("surface_id", "")) == surface_id and detail.get("resolved_position", null) is Vector3:
				selected_position = detail["resolved_position"]
			break
	if surface_id.is_empty(): surface_id = walls[0]
	var dims: Vector3 = view.get("dimensions", Vector3(18, 7, 14))
	var start := Vector3(0, clampf(dims.y * 0.45, 1.5, dims.y - 1.0), 0)
	if selected_position is Vector3: start = selected_position
	if kind == "flower_box" and selected_position is Vector3: start.y -= 1.8
	elif kind == "shutter" and selected_position is Vector3:
		var support := WallPlacement.surface(view, surface_id)
		if str(support.get("orientation", "front")) in ["front", "back"]: start.x += 2.2
		else: start.z += 2.2
	var snapped := WallPlacement.clamp_to_wall(view, surface_id, start, WallPlacement.footprint(kind, kind + "_wood"))
	if snapped.is_empty():
		_set_status("Attachment does not fit this wall")
		return
	placement_kind = kind
	placement_asset_id = kind + "_wood"
	selected_detail_id = ""
	selected_surface_id = surface_id
	detail_move_surface_id = surface_id
	detail_move_original_surface_id = surface_id
	detail_move_position = snapped["position"]
	detail_move_active = true
	resize_locked = false
	detail_open = false
	tools_open = false
	if tools_panel: tools_panel.visible = false
	_set_status("Place %s • left stick free on wall • D-pad ←/→ wall • A place / B cancel" % kind.replace("_", " "))
	_update_presentation()

func _read_detail_move(delta: float) -> void:
	if placement_kind.is_empty():
		super._read_detail_move(delta)
		if detail_move_active: _clamp_existing_detail_move()
		return
	if not detail_move_active or resize_locked: return
	var stick := Vector2(Input.get_axis("m1_move_left", "m1_move_right"), Input.get_axis("m1_move_up", "m1_move_down"))
	if stick.length() <= 0.05: return
	var magnitude := minf(stick.length(), 1.0)
	var speed := (0.9 if precision_mode else 3.0) * pow(magnitude, 1.45)
	var view: Dictionary = building_world.get_building(selected_building_id)
	var support := WallPlacement.surface(view, detail_move_surface_id)
	var orientation := str(support.get("orientation", "front"))
	if orientation in ["front", "back"]: detail_move_position.x += stick.x * delta * speed
	else: detail_move_position.z += stick.x * delta * speed
	detail_move_position.y -= stick.y * delta * speed
	var snapped := WallPlacement.clamp_to_wall(view, detail_move_surface_id, detail_move_position, WallPlacement.footprint(placement_kind, placement_asset_id))
	if not snapped.is_empty(): detail_move_position = snapped["position"]
	_update_presentation()

func _clamp_existing_detail_move() -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	var kind := "window"
	var asset := "window_wood"
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("id", "")) == selected_detail_id:
			kind = str(detail.get("kind", "window"))
			asset = str(detail.get("asset_id", "window_wood"))
			break
	var snapped := WallPlacement.clamp_to_wall(view, detail_move_surface_id, detail_move_position, WallPlacement.footprint(kind, asset))
	if not snapped.is_empty() and snapped["position"] != detail_move_position:
		detail_move_position = snapped["position"]
		super._update_presentation()

func _cycle_attachment_surface(direction: int) -> void:
	var view: Dictionary = building_world.get_building(selected_building_id)
	var walls := WallPlacement.wall_ids(view)
	if walls.is_empty(): return
	var index := walls.find(detail_move_surface_id)
	if index < 0: index = 0
	var next_surface := walls[posmod(index + direction, walls.size())]
	if next_surface == detail_move_surface_id: return
	var kind := placement_kind
	var asset := placement_asset_id
	if kind.is_empty():
		kind = "window"
		asset = "window_wood"
		for detail_value in view.get("details", []):
			var detail: Dictionary = detail_value
			if str(detail.get("id", "")) == selected_detail_id:
				kind = str(detail.get("kind", "window"))
				asset = str(detail.get("asset_id", "window_wood"))
				break
	var remapped := WallPlacement.remap_between_walls(view, detail_move_surface_id, next_surface, detail_move_position, WallPlacement.footprint(kind, asset))
	if remapped.is_empty():
		_set_status("Attachment does not fit that wall")
		return
	detail_move_surface_id = next_surface
	selected_surface_id = next_surface
	detail_move_position = remapped["position"]
	_set_status("Support %s • left stick free on wall • D-pad ←/→ wall • A commit / B cancel" % next_surface)
	_update_presentation()

func _commit_detail_move() -> bool:
	if placement_kind.is_empty():
		var existing_ok := super._commit_detail_move()
		if existing_ok: selected_surface_id = detail_move_surface_id
		detail_move_original_surface_id = ""
		return existing_ok
	if not detail_move_active: return false
	var kind := placement_kind
	var new_id: String = building_world.add_detail(selected_building_id, kind, detail_move_surface_id, detail_move_position, placement_asset_id)
	var ok := not new_id.is_empty()
	detail_move_active = false
	if ok:
		selected_detail_id = new_id
		selected_surface_id = detail_move_surface_id
		_record_history("building")
	else:
		selected_detail_id = placement_previous_detail_id
		selected_surface_id = placement_previous_surface_id
	_clear_placement_state()
	_set_status(("%s placed" % kind.replace("_", " ").capitalize()) if ok else "Placement rejected")
	super._update_presentation()
	return ok

func _cancel_detail_move() -> void:
	if placement_kind.is_empty():
		super._cancel_detail_move()
		if not detail_move_original_surface_id.is_empty(): selected_surface_id = detail_move_original_surface_id
		detail_move_original_surface_id = ""
		return
	if not detail_move_active: return
	detail_move_active = false
	selected_detail_id = placement_previous_detail_id
	selected_surface_id = placement_previous_surface_id
	_clear_placement_state()
	_set_status("Placement cancelled")
	super._update_presentation()

func _clear_placement_state() -> void:
	placement_kind = ""
	placement_asset_id = ""
	placement_previous_detail_id = ""
	placement_previous_surface_id = ""
	detail_move_original_surface_id = ""
	if placement_ghost: placement_ghost.hide_attachment()

func _cancel_current_edit(reason: String) -> void:
	if building_placement_active: _cancel_building_placement()
	super._cancel_current_edit(reason)

func _update_presentation() -> void:
	if building_placement_active:
		if building_placement_ghost:
			building_placement_ghost.visible = true
			building_placement_ghost.set_preview_origin(building_placement_target)
		if target_label:
			target_label.text = "Place cottage copy (%.1f, %.1f, %.1f) • A place  B cancel  L3 precision" % [building_placement_target.x, building_placement_target.y, building_placement_target.z]
		_update_resize_handles()
		return
	if building_placement_ghost: building_placement_ghost.hide_preview()
	if not placement_kind.is_empty() and detail_move_active:
		_update_placement_ghost()
		if target_label:
			var support := WallPlacement.surface(building_world.get_building(selected_building_id), detail_move_surface_id)
			var orientation := str(support.get("orientation", detail_move_surface_id)).capitalize()
			target_label.text = "Place %s • %s wall • A place  B cancel  D-pad ←/→ wall  L3 precision" % [placement_kind.replace("_", " "), orientation]
		_update_resize_handles()
		return
	if placement_ghost: placement_ghost.hide_attachment()
	super._update_presentation()

func _update_placement_ghost() -> void:
	if not placement_ghost or placement_kind.is_empty() or not detail_move_active: return
	var view: Dictionary = building_world.get_building(selected_building_id)
	var transform_value = view.get("transform", Transform3D.IDENTITY)
	if not transform_value is Transform3D: return
	var support := WallPlacement.surface(view, detail_move_surface_id)
	if support.is_empty(): return
	placement_ghost.show_attachment(transform_value, str(support.get("orientation", "front")), detail_move_position, placement_kind)
