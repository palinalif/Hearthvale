extends "res://scripts/m1_scene_placement.gd"
## M1 terrain UI layer; retain the playtested sculpting and placement paths.
const StrengthScale = preload("res://scripts/sculpt_strength.gd")
const LayerQuery = preload("res://scripts/sculpt_next_layer.gd")
const LayerVisual = preload("res://scripts/terrain_edit_preview.gd")
var brush_strength_level := StrengthScale.DEFAULT_LEVEL
var terrain_edit_preview: Node3D
var _layer_query: Node
var _layer_key: Array = []
var _layer_plan: Dictionary = {}
var _preview_reference: Dictionary = {}

func _init() -> void:
	brush_strength = StrengthScale.rate(brush_strength_level)

func _ready() -> void:
	super._ready()
	_layer_query = LayerQuery.new()
	terrain_edit_preview = LayerVisual.new()
	terrain_edit_preview.name = "TerrainEditPreview"
	terrain_edit_preview.visible = false
	add_child(terrain_edit_preview)
	if target_label:
		target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _exit_tree() -> void:
	if is_instance_valid(_layer_query): _layer_query.free()

func set_brush_strength_level(level: int) -> void:
	brush_strength_level = clampi(level, StrengthScale.MIN_LEVEL, StrengthScale.MAX_LEVEL)
	brush_strength = StrengthScale.rate(brush_strength_level)
	_preview_key = ""
	_layer_key.clear()

func _tool_choice(choice: String) -> void:
	if view_context == "terrain" and choice in ["Strength +", "Strength -"]:
		set_brush_strength_level(brush_strength_level + (1 if choice == "Strength +" else -1))
		tools_open = false
		detail_open = false
		if tools_panel: tools_panel.visible = false
		_set_status("Strength %d/10%s • L3 precision is one-quarter speed" % [brush_strength_level, " (default)" if brush_strength_level == 5 else ""])
		_update_presentation()
		return
	super._tool_choice(choice)

func _update_action_buttons() -> void:
	super._update_action_buttons()
	for label in ["Strength +", "Strength -"]:
		if not _tool_buttons.has(label): continue
		var button: Button = _tool_buttons[label]
		button.text = "%s (%d/10)" % [label, brush_strength_level]
		button.disabled = not button.visible or sculpt_tool in ["foliage", "tree", "clear_planting"] or (brush_strength_level == 10 if label == "Strength +" else brush_strength_level == 1)

func _sculpt_preview_visible() -> bool:
	return view_context == "terrain" and sculpt_tool in ["raise", "dig", "smooth", "level", "slope"] and not menu_open and not tools_open and not detail_open and not _restoring and not _shutting_down and backend != null and backend.is_ready()

func _update_brush_preview() -> void:
	if not terrain_edit_preview or not _layer_query: return
	if sculpt_tool in ["foliage", "tree", "clear_planting"]:
		terrain_edit_preview.visible = false
		super._update_brush_preview()
		return
	# Replace the generic sphere and sparse nine-cell highlight for sculpting.
	if brush_preview: brush_preview.visible = false
	if not _sculpt_preview_visible():
		terrain_edit_preview.visible = false
		if reference_plane: reference_plane.visible = false
		if terrain_hit_marker: terrain_hit_marker.visible = false
		_terrain_target_valid = false
		return
	var sample: Dictionary = {}
	var input_center := cursor + stroke_aim_offset if stroke_active else cursor
	var facing := _active_reference_normal()
	if stroke_active:
		# Follow the existing front. Never cast through a newly exposed cave
		# onto its disconnected floor just to update a visual marker.
		sample = {"valid": true, "point": backend.get_stroke_preview_center(input_center), "normal": facing}
	else:
		sample = backend.sample_surface_plane(input_center, facing, brush_radius + 1.0)
		if not bool(sample.get("valid", false)):
			sample = _find_local_surface(input_center, facing, float(backend.voxel_scale))
	_terrain_target_valid = bool(sample.get("valid", false))
	if not _terrain_target_valid:
		terrain_edit_preview.visible = false
		preview_cells.clear()
		_layer_plan.clear()
		_layer_key.clear()
		if reference_plane: reference_plane.visible = false
		if terrain_hit_marker: terrain_hit_marker.visible = false
		return
	_terrain_target_point = sample["point"]
	_terrain_target_normal = sample.get("normal", Vector3.UP)
	preview_center = _terrain_target_point
	_preview_reference = {}
	if sculpt_tool in ["level", "slope"]:
		if (stroke_active or keep_reference) and not stroke_reference.is_empty():
			_preview_reference = stroke_reference.duplicate(true)
		else:
			_preview_reference = backend.sample_surface_plane(preview_center, _reference_normal(), brush_radius + 1.0)
		_preview_reference = _snap_reference(_preview_reference)
		if sculpt_tool == "level" and not _preview_reference.is_empty(): _preview_reference["normal"] = Vector3.UP
	var query_center := input_center if stroke_active else preview_center
	var settings := {"radius": brush_radius, "strength": brush_strength * (0.25 if precision_mode else 1.0), "falloff": brush_falloff, "surface_normal": facing}
	var key: Array = [backend.get_instance_id(), backend.voxels.get_instance_id(), backend.get("_revision"), backend.get("_stroke_mutations"), stroke_active, query_center, sculpt_tool, settings, _preview_reference]
	last_frame_costs["preview_query_ms"] = 0.0
	last_frame_costs["preview_build_ms"] = 0.0
	if key != _layer_key:
		_layer_plan = _layer_query.plan(backend, sculpt_tool, query_center, settings, _preview_reference)
		_layer_key = key.duplicate(true)
		preview_cells.clear()
		for change in _layer_plan.get("changes", []): preview_cells.append(change["cell"])
		terrain_edit_preview.show_plan(_layer_plan)
		last_frame_costs["preview_query_ms"] = float(_layer_query.last_query_ms)
		last_frame_costs["preview_build_ms"] = float(terrain_edit_preview.last_build_ms)
	terrain_edit_preview.visible = bool(_layer_plan.get("valid", false))
	if stroke_active and _layer_plan.get("center", null) is Vector3:
		_terrain_target_point = _layer_plan["center"]
		preview_center = _terrain_target_point
	_update_reference_guides(preview_center, sample)

func _update_reference_guides(center: Vector3, sample_override: Dictionary = {}) -> void:
	if sculpt_tool in ["foliage", "tree", "clear_planting"]:
		super._update_reference_guides(center, sample_override)
		return
	if terrain_hit_marker: terrain_hit_marker.visible = false
	if not reference_plane: return
	reference_plane.visible = _sculpt_preview_visible() and sculpt_tool in ["level", "slope"] and bool(_preview_reference.get("valid", false))
	if reference_plane.visible:
		var normal: Vector3 = _preview_reference.get("normal", Vector3.UP)
		reference_plane.position = _preview_reference["point"]
		reference_plane.rotation = Quaternion(Vector3.UP, normal.normalized()).get_euler()
		var mesh := reference_plane.mesh as PlaneMesh
		if mesh: mesh.size = Vector2.ONE * brush_radius * 2.0

func _update_cursor_reticle() -> void:
	if view_context != "terrain" or sculpt_tool in ["foliage", "tree", "clear_planting"]:
		super._update_cursor_reticle()
		return
	if not cursor_reticle: return
	if _sculpt_preview_visible() and _terrain_target_valid:
		# A small centre marker is not another large, flat brush footprint.
		cursor_reticle.update_target(_terrain_target_point, _terrain_target_normal, 0.25, sculpt_tool, camera, true)
	else:
		cursor_reticle.set_target_visible(false)

func _update_presentation() -> void:
	if not building_world: return
	super._update_presentation()
	if not target_label or view_context != "terrain": return
	if sculpt_tool in ["foliage", "tree", "clear_planting"]:
		target_label.text = target_label.text.replace("str %.1f falloff %.1f" % [brush_strength, brush_falloff], "planting")
		return
	var summary := "No terrain target"
	if _terrain_target_valid and bool(_layer_plan.get("valid", false)):
		var added := int(_layer_plan.get("add_count", 0))
		var removed := int(_layer_plan.get("remove_count", 0))
		if added + removed > 0:
			summary = "Next layer at current aim: +%d add / // %d remove • edges change slower" % [added, removed]
		elif sculpt_tool == "smooth": summary = "Already smooth • no cells need changing"
		elif sculpt_tool in ["level", "slope"]: summary = "On target plane, or no connected surface to change"
		else: summary = "No connected cells to change • void or terrain boundary"
	target_label.text = "%s • Radius %.2f • Strength %d/10 • %s\n%s" % [sculpt_tool.capitalize(), brush_radius, brush_strength_level, "PRECISION (quarter speed)" if precision_mode else "L3 precision", summary]

func _update_debug_overlay() -> void:
	super._update_debug_overlay()
	if debug_label and debug_label.visible:
		debug_label.text += "\nPreview query %.2f ms / mesh update %.2f ms (0 = cached)" % [float(last_frame_costs.get("preview_query_ms", 0.0)), float(last_frame_costs.get("preview_build_ms", 0.0))]
