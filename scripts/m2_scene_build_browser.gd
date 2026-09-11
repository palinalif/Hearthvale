extends "res://scripts/m2_scene_facade_depth.gd"

## The X construction route is a catalogue; existing detail-edit and terrain
## tool routes remain contextual. All placement/history is still owned below.
const BuildBrowser = preload("res://scripts/ui/m2_build_browser.gd")
const CatalogueThumbnails = preload("res://scripts/ui/m2_catalogue_thumbnails.gd")
var _build_browser: BuildBrowser
var _catalogue_thumbnails: CatalogueThumbnails
var _browser_open := false
var _browser_entries: Array[Dictionary] = []
var _browser_hit: Dictionary = {}
var _browser_asset := ""
var _browser_placement := ""
var _browser_suppress_return := false
var _browser_camera_offset := 0.0
var _browser_building_id := ""
var _browser_home_palette_key := ""

func _ready() -> void:
	super._ready()
	_build_browser = BuildBrowser.new()
	hud.add_child(_build_browser)
	_browser_entries = _build_browser_entries()
	_build_browser.item_chosen.connect(_choose_browser_item)
	_build_browser.category_changed.connect(_request_browser_thumbnails)
	_build_browser.house_requested.connect(_browser_house_options)
	_build_browser.landscape_requested.connect(_browser_landscape_options)
	_catalogue_thumbnails = CatalogueThumbnails.new()
	_catalogue_thumbnails.factory = _make_catalogue_model
	_catalogue_thumbnails.thumbnail_ready.connect(_build_browser.apply_thumbnail)
	add_child(_catalogue_thumbnails)
	_build_browser.set_entries(_browser_entries)
	get_viewport().size_changed.connect(_fit_build_browser)
	_prompt_bar.item_rect_changed.connect(_fit_build_browser)

func _build_browser_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	# Source the same installed variants used by detail editing, including
	# later cottage/awning/slider/bay additions. No duplicate asset-ID list.
	for key in _style_button_specs:
		var spec: Dictionary = _style_button_specs[key]
		if str(spec.get("mode", "")) != "variation": continue
		var kind := str(spec.get("kind", ""))
		if kind not in ["window", "door", "flower_box", "shutter"]: continue
		var category := "windows" if kind == "window" else "doors" if kind == "door" else "wall"
		entries.append({"id": str(spec["value"]), "name": (_style_buttons[key] as Button).text, "category": category, "kind": kind})
	for spec in ROOF_ACCESSORY_SPECS:
		entries.append({"id": str(spec["id"]), "name": str(spec["label"]), "category": "roof", "kind": "roof_accessory"})
	for id in _catalogue_designs:
		entries.append({"id": str(id), "name": str(_catalogue_designs[id]["name"]), "category": "homes", "kind": "home"})
	return entries

func _input(event: InputEvent) -> void:
	if _browser_open and not _shutting_down:
		# A cancelled operation can require an accept release. Consume it here
		# without letting a held press activate a catalogue card or stay stuck.
		if event.is_action_released("m1_accept"):
			_blocked_until_accept_release = false
			get_viewport().set_input_as_handled()
			return
		if _blocked_until_accept_release and event.is_action_pressed("m1_accept"):
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey or event is InputEventMouseButton: InputGlyph.set_keyboard_mouse_mode(true)
		elif event is InputEventJoypadButton: InputGlyph.set_keyboard_mouse_mode(false)
		if event.is_action_pressed("m1_pause"):
			_close_build_browser()
			_set_menu(true)
		elif event.is_action_pressed("m1_cancel") or event.is_action_pressed("m1_tools"):
			_close_build_browser()
		elif event.is_action_pressed("m1_undo"):
			_build_browser.next_category(-1)
		elif event.is_action_pressed("m1_redo"):
			_build_browser.next_category(1)
		elif (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y) or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_E):
			_browser_house_options()
		elif event.is_action_pressed("m1_accept"):
			var focus := get_viewport().gui_get_focus_owner()
			if focus is Button and _build_browser.is_ancestor_of(focus): (focus as Button).pressed.emit()
		elif event.is_action_pressed("m1_cycle_left") or event.is_action_pressed("ui_left"):
			_build_browser.navigate(-1, 0)
		elif event.is_action_pressed("m1_cycle_right") or event.is_action_pressed("ui_right"):
			_build_browser.navigate(1, 0)
		elif event.is_action_pressed("m1_height_up") or event.is_action_pressed("ui_up"):
			_build_browser.navigate(0, -1)
		elif event.is_action_pressed("m1_height_down") or event.is_action_pressed("ui_down"):
			_build_browser.navigate(0, 1)
		else:
			# Let mouse/touch reach the actual cards and scrolling container.
			if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag: return
		get_viewport().set_input_as_handled()
		return
	if _build_browser and _part_idle() and event.is_action_pressed("m1_tools"):
		_update_detail_hover()
		# X on a detail retains Colour/Variation/etc. X on the shell or empty
		# space opens construction; A on surfaces retains direct editing.
		if hovered_detail_id.is_empty():
			_open_build_browser()
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _unhandled_input(event: InputEvent) -> void:
	if _browser_open:
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

func _open_build_browser(category: String = "") -> void:
	if not _build_browser or _restoring or menu_open or _blocked_until_accept_release: return
	var hit := _pick_house_part(edit_pointer) if view_context == "building" else {}
	_cancel_current_edit("Build catalogue opened")
	_close_all_catalogues(false)
	_browser_hit = hit
	_browser_building_id = selected_building_id
	_browser_camera_offset = camera.v_offset
	_browser_open = true
	tools_open = true
	detail_open = false
	_building_actions_open = false
	_context_actions_open = false
	_build_browser.show()
	if not category.is_empty(): _build_browser.select_category(category)
	else: _build_browser.restore_focus.call_deferred()
	_request_browser_thumbnails(_build_browser.category)
	_fit_build_browser()
	_update_camera()
	_refresh_controller_hud()

func _close_build_browser() -> void:
	if not _browser_open: return
	_browser_open = false
	_build_browser.hide()
	_catalogue_thumbnails.stop()
	camera.v_offset = _browser_camera_offset
	tools_open = false
	get_viewport().gui_release_focus()
	_refresh_controller_hud()

func _fit_build_browser() -> void:
	if _browser_open: _build_browser.fit(get_viewport().get_visible_rect().size, _prompt_bar.position.y)

func _request_browser_thumbnails(category: String) -> void:
	if not _browser_open or not _catalogue_thumbnails: return
	if category == "homes":
		# The old home catalogue prepared these lazily. This route must work
		# without visiting it, and the thumbnail must match the next placement.
		var next_id := int(building_world.get_document().get("next_id", 1))
		if _catalogue_palette_key != next_id: _prepare_catalogue_palettes()
		var palette_key := str([_next_home_seed(), _catalogue_wall_choices, _catalogue_roof_choices, _catalogue_accent_choices])
		if palette_key != _browser_home_palette_key:
			_catalogue_thumbnails.stop()
			for id in _catalogue_designs: _catalogue_thumbnails.cache.erase(id)
			_browser_home_palette_key = palette_key
	var entries: Array[Dictionary] = []
	for item in _browser_entries:
		if str(item["category"]) == category: entries.append(item)
	_catalogue_thumbnails.request(entries)

func _browser_house_options() -> void:
	_close_build_browser()
	_open_building_panel()

func _browser_landscape_options() -> void:
	_close_build_browser()
	_open_build_catalogue()

func _choose_browser_item(item: Dictionary) -> void:
	if not _browser_open or item not in _browser_entries: return
	var kind := str(item["kind"])
	if kind != "home" and (selected_building_id != _browser_building_id or building_world.get_building(selected_building_id).is_empty()):
		_build_browser.status.text = "Select a house first"
		return
	var hit := _browser_hit.duplicate(true)
	_close_build_browser()
	if kind == "home":
		_choose_home_design(str(item["id"]))
		if building_placement_active: _browser_placement = "home"
	elif kind == "roof_accessory":
		_begin_roof_accessory_placement(str(item["id"]))
		if roof_accessory_placement_active: _browser_placement = "roof"
	else:
		_browser_asset = str(item["id"])
		if str(hit.get("kind", "")) == "wall": _direct_attachment_surface = str(hit.get("surface_id", ""))
		_begin_new_attachment(kind)
		_direct_attachment_surface = ""
		_browser_asset = ""
		if detail_move_active:
			_browser_placement = "attachment"
			if str(hit.get("surface_id", "")) == detail_move_surface_id:
				var view: Dictionary = building_world.get_building(selected_building_id)
				var placed := WallPlacement.nearest_available(view, "", detail_move_surface_id, hit["position"], _attachment_preview_half(_attachment_preview_detail()))
				if not placed.is_empty():
					detail_move_position = placed["position"]
					_detail_free_position = detail_move_position
					_update_presentation()
	if _browser_placement.is_empty():
		_open_build_browser()
		_build_browser.status.text = "No room on this surface; choose another wall"

func _default_attachment_asset(kind: String, view: Dictionary) -> String:
	if not _browser_asset.is_empty(): return _browser_asset
	return super._default_attachment_asset(kind, view)

func _return_to_browser(kind: String) -> void:
	if _browser_placement != kind: return
	_browser_placement = ""
	if not _browser_suppress_return and not menu_open and not _shutting_down: _open_build_browser()

func _cancel_detail_move() -> void:
	super._cancel_detail_move()
	_return_to_browser("attachment")

func _cancel_roof_accessory_placement() -> void:
	super._cancel_roof_accessory_placement()
	_return_to_browser("roof")

func _cancel_building_placement() -> void:
	super._cancel_building_placement()
	_return_to_browser("home")

func _commit_detail_move() -> bool:
	var ok := super._commit_detail_move()
	if ok: _browser_placement = ""
	return ok

func _commit_roof_accessory_placement() -> bool:
	var ok := super._commit_roof_accessory_placement()
	if ok: _browser_placement = ""
	return ok

func _commit_building_placement() -> bool:
	var ok := super._commit_building_placement()
	if ok: _browser_placement = ""
	return ok

func _cancel_current_edit(reason: String) -> void:
	_browser_suppress_return = true
	_close_build_browser()
	super._cancel_current_edit(reason)
	_browser_placement = ""
	_browser_suppress_return = false

func _set_menu(open: bool) -> void:
	if open:
		_browser_suppress_return = true
		_close_build_browser()
	super._set_menu(open)
	_browser_suppress_return = false

func _update_camera() -> void:
	super._update_camera()
	if not _browser_open: return
	# Shift the viewed scene into the unobscured half without changing saved
	# orbit/zoom. project_position handles perspective and aspect ratio.
	camera.v_offset = _browser_camera_offset
	var screen := get_viewport().get_visible_rect().size
	var depth := maxf(1, camera_distance)
	var middle := camera.project_position(screen * 0.5, depth)
	var upper := camera.project_position(Vector2(screen.x * 0.5, screen.y * 0.25), depth)
	camera.v_offset -= middle.distance_to(upper)

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if not _browser_open: return
	for control in [tools_panel, _building_panel, _terrain_panel, _tool_card, _world_prompt, _hover_prompt, _resize_hint, _part_hint, _part_lines]:
		if control: control.hide()
	_set_prompts([["LB", "Category"], ["RB", "Category"], ["D-PAD", "Choose"], ["A", "Place"], ["B", "Close"], ["Y", "House options"]])
	_fit_build_browser()

func _refresh_part_feedback() -> void:
	super._refresh_part_feedback()
	if _browser_open:
		_part_hint.hide()
		_part_lines.hide()
		_set_roof_scope_highlight(false)
	elif _part_idle() and not hovered_detail_id.is_empty(): return
	elif _part_idle():
		_set_prompts([["LS", "Point"], ["A", "Edit"], ["X", "Build catalogue"], ["RS", "Orbit"]])

func _make_catalogue_model(item: Dictionary) -> Node3D:
	var kind := str(item["kind"])
	var id := str(item["id"])
	var visual := CottageVisual.new()
	var target := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.25), Vector3.ZERO)
	var view: Dictionary
	if kind == "home":
		var seed := _next_home_seed()
		var palette := _palette_for_seed(seed, id)
		view = _preview_styled_home(id, target, str(_catalogue_wall_choices.get(id, palette["wall"])), str(_catalogue_roof_choices.get(id, palette["roof"])), str(_catalogue_accent_choices.get(id, palette["accent"])), seed)
		visual.apply_building(view, 0)
		visual.rotate_y(PI)
	elif kind == "roof_accessory":
		visual.transform = target
		view = {"id": "catalogue-roof", "dimensions": Vector3(15, 6, 12), "accent_material_id": "sage"}
		_build_roof_accessory(visual, view, {"id": "preview", "asset_id": id, "u": 0.5, "v": 0.75})
		(visual.get_child(0) as Node3D).position = Vector3.ZERO
	else:
		var detail := {"id": "catalogue-detail", "kind": kind, "asset_id": id, "anchor": {"surface_id": "preview-wall"}, "resolved_position": Vector3.ZERO, "visible": true, "show_shutters": false}
		view = {"id": "catalogue-detail-house", "dimensions": Vector3(18, 7, 14), "transform": target, "surfaces": [{"id": "preview-wall", "orientation": "back"}], "details": [detail], "accent_material_id": "sage"}
		visual.transform = target
		visual._unit = Vector3.ONE * 0.5
		visual._detail_unit = Vector3.ONE * 0.25
		visual._applied_view = view
		visual._build_details(view, view["dimensions"])
		_refresh_custom_window_overlays_for_visual(visual)
		_refresh_window_customization_for_visual(visual)
	_apply_accent_to_visual(visual, view, str(view.get("accent_material_id", "sage")))
	# Preview-only signatures must not accumulate when a thumbnail is freed.
	var key := visual.get_instance_id()
	_window_overlay_signatures.erase(key)
	_window_adventure_signatures.erase(key)
	_decor_colour_signatures.erase(key)
	return visual