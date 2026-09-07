extends "res://scripts/m1_scene.gd"

## Focused M1 attachment-placement layer. The existing M1 scene logic remains
## untouched; this subclass adds wall-locked ghost placement and support
## switching for furniture/details.

const WallPlacement = preload("res://scripts/wall_attachment_placement.gd")
const DetailPlacementGhost = preload("res://scripts/detail_placement_ghost.gd")

var placement_kind := ""
var placement_asset_id := ""
var placement_previous_detail_id := ""
var placement_previous_surface_id := ""
var detail_move_original_surface_id := ""
var placement_ghost: Node3D

func _ready() -> void:
	super._ready()
	placement_ghost = DetailPlacementGhost.new()
	placement_ghost.name = "AttachmentPlacementGhost"
	placement_ghost.visible = false
	add_child(placement_ghost)

func _input(event: InputEvent) -> void:
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
	if view_context == "building" and choice in ["Add flower box", "Add shutter"]:
		_begin_new_attachment("flower_box" if choice == "Add flower box" else "shutter")
		return
	super._tool_choice(choice)

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

func _update_presentation() -> void:
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
