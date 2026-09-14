extends "res://scripts/m2_scene_path_terrain_ownership.gd"

## Controller-facing path eraser. X toggles paint/erase while the path tool is
## idle; erase strokes reuse the same painted-cell brush and terrain ownership
## reconciliation as direct erases, so packed-earth cuts restore safely.
const SubtlePathVisual = preload("res://scripts/m2_path_visual_subtle.gd")
const LIVE_PREVIEW_CELL_BUDGET := 384

var path_erase_mode := false
var _path_live_lookup: Dictionary = {}
var _path_existing_lookup: Dictionary = {}
var _path_existing_count := 0

func _ready() -> void:
	super._ready()
	if path_visual and is_instance_valid(path_visual):
		path_visual.queue_free()
	path_visual = SubtlePathVisual.new()
	path_visual.name = "M2PathVisual"
	add_child(path_visual)
	if backend: path_visual.attach_backend(backend)
	_path_render_signature = ""
	_refresh_path_visual(true)

func _choose_path_style(style_id: String) -> void:
	path_erase_mode = false
	super._choose_path_style(style_id)

func _input(event: InputEvent) -> void:
	if path_placement_active and not path_painting and not menu_open and event.is_action_pressed("m1_tools"):
		path_erase_mode = not path_erase_mode
		_path_preview_signature = ""
		_set_status("Path eraser • hold A erase" if path_erase_mode else "%s • hold A paint" % _path_style_name())
		_update_path_preview()
		_refresh_controller_hud()
		get_viewport().set_input_as_handled()
		return
	super._input(event)

func _reset_path_baseline() -> void:
	super._reset_path_baseline()
	_path_existing_lookup.clear()
	_path_existing_count = 0
	for style_id in PATH_STYLE_ORDER:
		for cell: Vector2i in landscape_state.path_cells(style_id):
			if _path_existing_lookup.has(cell): continue
			_path_existing_lookup[cell] = true
			_path_existing_count += 1

func _update_path_validity() -> void:
	path_placement_valid = false
	path_placement_reason = "No terrain surface under cursor"
	if not path_placement_active: return
	if _terrain_revision() != _path_terrain_revision:
		path_placement_reason = "Terrain changed; restart path painting"
		return
	if building_world.get_revision() != _path_building_revision:
		path_placement_reason = "Home layout changed; restart path painting"
		return
	var point := _path_cursor_point()
	if not point.is_finite(): return
	if point.x < 0.0 or point.x >= PathState.EDITABLE_WORLD_SIZE or point.y < 0.0 or point.y >= PathState.EDITABLE_WORLD_SIZE:
		path_placement_reason = "Outside editable world"
		return
	var stamp := PathRegion.brush_cells(point, path_width * 0.5, PathState.EDITABLE_WORLD_SIZE)
	if stamp.is_empty():
		path_placement_reason = "Outside editable world"
		return
	if _cells_hit_home_interior(stamp):
		path_placement_reason = "Brush overlaps the interior of a home"
		return
	if not path_erase_mode and not _live_cells_fit_limit(stamp):
		path_placement_reason = "Path render limit reached"
		return
	path_placement_valid = true
	path_placement_reason = "Erasing" if path_erase_mode and path_painting else ("Ready to erase" if path_erase_mode else ("Painting" if path_painting else "Ready to paint"))

func _start_path_stroke() -> bool:
	var started := super._start_path_stroke()
	if started:
		_path_live_lookup.clear()
		for cell: Vector2i in path_cells: _path_live_lookup[cell] = true
	return started

func _sample_path_stroke() -> bool:
	if not path_painting: return false
	_update_path_validity()
	if not path_placement_valid: return false
	var point := _path_cursor_point()
	if not point.is_finite(): return false
	var sweep := PathRegion.stroke_cells(_path_last_sample, point, path_width * 0.5, PathState.EDITABLE_WORLD_SIZE)
	if _cells_hit_home_interior(sweep):
		path_placement_reason = "Brush overlaps the interior of a home"
		path_placement_valid = false
		return false
	if not path_erase_mode and not _live_cells_fit_limit(sweep):
		path_placement_reason = "Path render limit reached"
		path_placement_valid = false
		return false
	var added := 0
	for cell: Vector2i in sweep:
		if _path_live_lookup.has(cell): continue
		_path_live_lookup[cell] = true
		path_cells.append(cell)
		added += 1
	_path_last_sample = point
	if added > 0: _path_preview_signature = ""
	return true

func _live_cells_fit_limit(extra_cells: Array) -> bool:
	var extra_new := 0
	var seen := {}
	for cell: Vector2i in extra_cells:
		if _path_live_lookup.has(cell) or seen.has(cell): continue
		seen[cell] = true
		if not _path_existing_lookup.has(cell): extra_new += 1
	var live_new := 0
	for cell in _path_live_lookup:
		if not _path_existing_lookup.has(cell): live_new += 1
	return _path_existing_count + live_new + extra_new <= PathAuthority.MAX_CELLS

func _commit_path_stroke() -> bool:
	if not path_erase_mode:
		var committed := super._commit_path_stroke()
		if committed: _path_live_lookup.clear()
		return committed
	if not path_painting:
		return false
	if path_cells.is_empty():
		_cancel_path_stroke("Empty erase stroke cancelled")
		return false
	if JSON.stringify(landscape_state.document()) != _path_before_serialized or _terrain_revision() != _path_terrain_revision or building_world.get_revision() != _path_building_revision:
		_cancel_path_stroke("World changed; erase stroke cancelled")
		return false
	return _commit_path_erase_stroke()

func _commit_path_erase_stroke() -> bool:
	var brush_cells := path_cells.size()
	path_painting = false
	var erased := erase_painted_path_cells(path_cells)
	path_cells.clear()
	_path_live_lookup.clear()
	_path_last_sample = Vector2(NAN, NAN)
	if path_visual:
		path_visual.hide_preview()
	_path_preview_signature = ""
	if not erased:
		_set_status("Path eraser • nothing under brush")
		_reset_path_baseline()
		_update_path_validity()
		_update_path_preview()
		_refresh_controller_hud()
		return false
	_set_status("Path eraser • %d brush cells cleared • LB undo" % brush_cells)
	_update_path_validity()
	_update_path_preview()
	_refresh_controller_hud()
	return true

func _cancel_path_stroke(reason: String = "Stroke cancelled") -> void:
	_path_live_lookup.clear()
	super._cancel_path_stroke(reason)

func _cancel_path_placement(reason: String = "Path painting closed") -> void:
	_path_live_lookup.clear()
	super._cancel_path_placement(reason)

func _update_path_preview() -> void:
	if not path_visual or not path_placement_active: return
	var preview_cells := _bounded_preview_cells()
	var signature := "%s|%s|%d|%d" % ["erase" if path_erase_mode else path_style_id, path_placement_valid, _terrain_revision(), _preview_hash(preview_cells)]
	if signature == _path_preview_signature: return
	_path_preview_signature = signature
	if preview_cells.is_empty():
		path_visual.hide_preview()
		return
	path_visual.show_cell_preview(path_style_id, preview_cells, path_placement_valid, path_placement_reason)
	if not path_erase_mode: return
	var erase_colours := [Color("#f29a73"), Color("#ffd08a")] if path_placement_valid else [Color("#d95858"), Color("#ef7676")]
	if is_instance_valid(path_visual._preview_node) and path_visual._preview_node.mesh:
		path_visual._preview_node.name = "PathErasePreview"
		for surface in path_visual._preview_node.mesh.get_surface_count():
			path_visual._preview_node.mesh.surface_set_material(surface, path_visual._preview_material(erase_colours[mini(surface, 1)], 0.58))
	if is_instance_valid(path_visual._preview_marker):
		path_visual._preview_marker.name = "PathErasePreviewMarker"
		path_visual._preview_marker.material_override = path_visual._preview_material(Color("#ff755f") if path_placement_valid else Color("#d95858"), 0.96)

func _bounded_preview_cells() -> Array:
	var cells: Array = []
	var start := maxi(0, path_cells.size() - LIVE_PREVIEW_CELL_BUDGET)
	for index in range(start, path_cells.size()): cells.append(path_cells[index])
	var point := _path_cursor_point()
	if point.is_finite():
		cells = PathRegion.union_cells(cells, PathRegion.brush_cells(point, path_width * 0.5, PathState.EDITABLE_WORLD_SIZE), PathState.EDITABLE_WORLD_SIZE)
	if cells.size() <= LIVE_PREVIEW_CELL_BUDGET: return cells
	var sampled: Array = []
	var stride := float(cells.size()) / float(LIVE_PREVIEW_CELL_BUDGET)
	for index in LIVE_PREVIEW_CELL_BUDGET:
		sampled.append(cells[mini(cells.size() - 1, floori(float(index) * stride))])
	return sampled

func _preview_hash(cells: Array) -> int:
	var value := cells.size() * 31 + (1 if path_placement_valid else 0)
	for cell: Vector2i in cells:
		value = int((value * 33) ^ (cell.x * 73856093) ^ (cell.y * 19349663))
	return value

func _update_presentation() -> void:
	super._update_presentation()
	if path_placement_active and target_label:
		var mode_name := "ERASE" if path_erase_mode else _path_style_name()
		var action_name := "erase" if path_erase_mode else "paint"
		target_label.text = "%s • %.3f m brush • %s\nD-pad L/R size  X paint/erase  Hold A %s  release commit  LB undo  RB redo  B cancel/close" % [mode_name, path_width, path_placement_reason, action_name]

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if path_placement_active and not menu_open and _prompt_row:
		_set_prompts([["A", "Hold to erase" if path_erase_mode else "Hold to paint"], ["D-PAD L/R", "Brush size"], ["X", "Paint/erase"], ["LB", "Undo"], ["RB", "Redo"], ["B", "Cancel/close"]])
