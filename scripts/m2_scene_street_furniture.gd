extends "res://scripts/m2_scene_hamlet_details.gd"

const HamletVisual = preload("res://scripts/m2_hamlet_visual.gd")

const FURNITURE_STYLES := {
	"bench": {"name": "Village bench", "size": Vector2(1.5, 0.625), "summary": "Slatted timber seat with a proper back"},
	"lantern": {"name": "Path lantern", "size": Vector2(0.5, 0.5), "summary": "Small warm lantern on a dark village post"},
	"signpost": {"name": "Wooden signpost", "size": Vector2(0.625, 0.625), "summary": "Two crooked direction boards on one post"},
	"barrel_planter": {"name": "Barrel planter", "size": Vector2(0.75, 0.75), "summary": "Weathered barrel packed with greenery and flowers"},
}
const FURNITURE_STYLE_ORDER: Array[String] = ["bench", "lantern", "signpost", "barrel_planter"]

var furniture_placement_active := false
var furniture_style_id := "bench"
var furniture_size := Vector2(1.5, 0.625)
var furniture_yaw_quarters := 0
var furniture_placement_valid := false
var furniture_placement_reason := ""
var _furniture_render_signature := ""

func _ready() -> void:
	super._ready()
	# Swap the shared renderer for its furniture-capable subclass after the base
	# scene has finished constructing its composition layers.
	var old_visual: Node = composition_visual
	if is_instance_valid(old_visual):
		remove_child(old_visual)
		old_visual.queue_free()
	composition_visual = HamletVisual.new()
	composition_visual.name = "M2CompositionVisual"
	add_child(composition_visual)
	if backend: composition_visual.attach_backend(backend)
	_refresh_bridge_visual(true)
	_refresh_detail_visual(true)

func _install_hamlet_catalogue() -> void:
	super._install_hamlet_catalogue()
	var box := _catalogue_box(_hamlet_catalogue_panel)
	_add_catalogue_heading(box, "STREET FURNITURE", "Small props use the same A/place and left-right/rotate grammar")
	for style_id in FURNITURE_STYLE_ORDER:
		var style: Dictionary = FURNITURE_STYLES[style_id]
		_add_catalogue_button(box, _hamlet_catalogue_buttons, "%s\n%s" % [style["name"], style["summary"]], _choose_furniture_style.bind(style_id))

	# This catalogue is deliberately bounded to nine choices, so keep it all on
	# one 720p handheld page rather than adding scrolling. The selected item's
	# placement HUD still carries the descriptive context once it enters world
	# placement; this menu only needs fast, readable names.
	_hamlet_catalogue_panel.position.y = 36
	_hamlet_catalogue_panel.custom_minimum_size = Vector2(540, 580)
	box.add_theme_constant_override("separation", 3)
	for button in _hamlet_catalogue_buttons:
		button.text = button.text.get_slice("\n", 0)
		button.custom_minimum_size.y = 34
	for child in box.get_children():
		if not child is Label: continue
		var label := child as Label
		if label.text in [
			"Place small details directly into the village",
			"A place • left/right rotate • B back",
			"Fence segments and matching gates use the same placement controls",
			"Small props use the same A/place and left-right/rotate grammar",
		]:
			label.visible = false
		elif label.get_theme_font_size("font_size") >= 22:
			label.add_theme_font_size_override("font_size", 17)

func _choose_furniture_style(style_id: String) -> void:
	if not FURNITURE_STYLES.has(style_id): return
	furniture_style_id = style_id
	furniture_size = FURNITURE_STYLES[style_id]["size"]
	furniture_yaw_quarters = 0
	_begin_detail_placement("furniture", furniture_style_id, furniture_size, furniture_yaw_quarters)

func _begin_furniture_placement() -> void:
	_begin_detail_placement("furniture", furniture_style_id, furniture_size, furniture_yaw_quarters)

func _rotate_furniture(direction: int) -> void:
	if detail_placement_active and detail_kind == "furniture": _rotate_detail(direction)

func _commit_furniture() -> bool:
	if not detail_placement_active or detail_kind != "furniture": return false
	var count_before := landscape_state.composition.size()
	# The shared transaction performs the actual commit. Its original return
	# contract predates furniture, so confirm success from the authoritative count.
	super._commit_detail()
	return landscape_state.composition.size() == count_before + 1

func _cancel_furniture_placement(reason: String = "Furniture cancelled") -> void:
	if detail_placement_active and detail_kind == "furniture": _cancel_detail_placement(reason)

func _update_furniture_validity() -> void:
	if detail_placement_active and detail_kind == "furniture":
		_update_detail_validity()
		_sync_detail_aliases()

func _update_furniture_preview() -> void:
	if detail_placement_active and detail_kind == "furniture": _update_detail_preview()

func _detail_definition(kind: String, style_id: String) -> Dictionary:
	if kind == "furniture" and FURNITURE_STYLES.has(style_id): return FURNITURE_STYLES[style_id]
	return super._detail_definition(kind, style_id)

func _sync_detail_aliases() -> void:
	super._sync_detail_aliases()
	furniture_placement_active = detail_placement_active and detail_kind == "furniture"
	if detail_kind == "furniture":
		furniture_style_id = detail_style_id
		furniture_size = detail_size
		furniture_yaw_quarters = detail_yaw_quarters
		furniture_placement_valid = detail_placement_valid
		furniture_placement_reason = detail_placement_reason

func _update_detail_preview() -> void:
	if not detail_placement_active or detail_kind != "furniture":
		super._update_detail_preview()
		return
	if not composition_visual: return
	var point := _path_cursor_point()
	if not point.is_finite():
		composition_visual.hide_furniture_preview()
		return
	var signature := "%s|%s|%s|%d|%s|%d" % [detail_kind, detail_style_id, point, detail_yaw_quarters, detail_placement_valid, _terrain_revision()]
	if signature == _detail_preview_signature: return
	_detail_preview_signature = signature
	composition_visual.show_furniture_preview(detail_style_id, point, detail_size, detail_yaw_quarters, detail_placement_valid)

func _hide_detail_preview() -> void:
	super._hide_detail_preview()
	if composition_visual and composition_visual.has_method("hide_furniture_preview"): composition_visual.hide_furniture_preview()

func _refresh_detail_visual(force: bool = false) -> void:
	super._refresh_detail_visual(force)
	if not composition_visual or not composition_visual.has_method("rebuild_furniture"): return
	var signature := JSON.stringify(landscape_state.composition) + "|" + str(_terrain_revision())
	if not force and signature == _furniture_render_signature: return
	_furniture_render_signature = signature
	composition_visual.rebuild_furniture(landscape_state.composition, backend)

func _refresh_controller_hud() -> void:
	super._refresh_controller_hud()
	if _hamlet_catalogue_open and _tool_meta:
		_tool_meta.text = "Gardens, rustic fences, gates, and street furniture"
