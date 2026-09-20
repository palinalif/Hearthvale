extends "res://scripts/m2_scene_hamlet_details.gd"

const HamletVisual = preload("res://scripts/m2_hamlet_visual.gd")

const PlanterFurniture = preload("res://scripts/m2_planter_assets.gd")
const StarterFurniture = preload("res://scripts/m2_starter_props.gd")
const FURNITURE_STYLES := {
	"well": StarterFurniture.DEFINITIONS["well"],
	"topiary_pair": {"name": "Topiary pair", "size": Vector2(0.875, 0.5), "summary": "A clipped ball and a rounded column, close together"},
	"beehive": {"name": "Beehive", "size": Vector2(0.4375, 0.5625), "summary": "Banded skep on a post with a quiet entrance"},
	"wheelbarrow": {"name": "Wheelbarrow", "size": Vector2(1.0, 0.375), "summary": "Timber barrow spilling pink and cream flowers"},
	"flower_arch": {"name": "Flower arch", "size": Vector2(2.375, 0.5625), "summary": "Timber archway under a heavy canopy of leaves and blossom"},
	"garden_gnome": {"name": "Garden gnome", "size": Vector2(0.375, 0.375), "summary": "Bearded gnome with a pointed hat"},
	"garden_gnome_small": {"name": "Small gnome", "size": Vector2(0.375, 0.375), "summary": "Armless gnome with a stubby hat"},
	"garden_gnome_tall": {"name": "Tall gnome", "size": Vector2(0.375, 0.375), "summary": "Slim gnome with a very long hat"},
	"chopping_block": StarterFurniture.DEFINITIONS["chopping_block"],
	"log_stack": StarterFurniture.DEFINITIONS["log_stack"],
	"bench": {"name": "Village bench", "size": Vector2(1.5, 0.625), "summary": "Slatted timber seat with a proper back"},
	"village_table": {"name": "Gathering table and benches", "size": Vector2(1.25, 1.875), "summary": "Authored timber table with a backless bench on each side"},
	"clothesline": {"name": "Clothesline", "size": Vector2(2.5, 0.5), "summary": "Two timber posts with a sagging line of drying laundry"},
	"potted_trio": {"name": "Potted trio", "size": Vector2(1.0, 0.75), "summary": "Rose, herb and leafy pots in a casual V"},
	"market_crate": {"name": "Market crate", "size": Vector2(0.625, 0.625), "summary": "Apple crate with a straw hat slung on top"},
	"bird_feeder": {"name": "Bird feeder", "size": Vector2(0.875, 0.875), "summary": "Shelved feeder with a little bird and seed pile"},
	"mailbox": {"name": "Mailbox", "size": Vector2(0.75, 0.5), "summary": "Village post box with a raised flag"},
	"lantern": {"name": "Path lantern", "size": Vector2(0.5, 0.5), "summary": "Small warm lantern on a dark village post"},
	"signpost": {"name": "Wooden signpost", "size": Vector2(0.625, 0.625), "summary": "Two crooked direction boards on one post"},
	"barrel_planter": PlanterFurniture.DEFINITIONS["barrel_planter"],
	"barrel_planter_herbs": PlanterFurniture.DEFINITIONS["barrel_planter_herbs"],
	"barrel_planter_light": PlanterFurniture.DEFINITIONS["barrel_planter_light"],
}
const FURNITURE_STYLE_ORDER: Array[String] = ["bench", "village_table", "lantern", "signpost", "barrel_planter", "well", "chopping_block", "log_stack", "barrel_planter_herbs", "barrel_planter_light", "clothesline", "potted_trio", "market_crate", "bird_feeder", "mailbox", "topiary_pair", "beehive", "wheelbarrow", "flower_arch", "garden_gnome", "garden_gnome_small", "garden_gnome_tall"]
const FURNITURE_RANDOM_TURN_COUNT := 24
const FURNITURE_RANDOM_STEP_DEGREES := 15.0

var furniture_placement_active := false
var furniture_style_id := "bench"
var furniture_size := Vector2(1.5, 0.625)
var furniture_yaw_quarters := 0
var furniture_yaw_degrees := 0.0
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
	# Two columns of eleven keep every style on one 720p handheld page; the
	# selected item's placement HUD still carries the descriptive context.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 8)
	box.add_child(columns)
	var column_boxes: Array[VBoxContainer] = []
	for i in 2:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 3)
		columns.add_child(column)
		column_boxes.append(column)
	for i in FURNITURE_STYLE_ORDER.size():
		var style_id: String = FURNITURE_STYLE_ORDER[i]
		var style: Dictionary = FURNITURE_STYLES[style_id]
		_add_catalogue_button(column_boxes[i % 2], _hamlet_catalogue_buttons, "%s\n%s" % [style["name"], style["summary"]], _choose_furniture_style.bind(style_id))

	_hamlet_catalogue_panel.position.y = 36
	_hamlet_catalogue_panel.custom_minimum_size = Vector2(560, 580)
	for button in _hamlet_catalogue_buttons:
		button.text = button.text.get_slice("\n", 0)
		button.custom_minimum_size = Vector2(266, 34)
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
	furniture_yaw_degrees = 0.0
	_begin_detail_placement("furniture", furniture_style_id, furniture_size, furniture_yaw_quarters)
	_apply_random_furniture_yaw()

func _begin_furniture_placement() -> void:
	_begin_detail_placement("furniture", furniture_style_id, furniture_size, furniture_yaw_quarters)
	_apply_random_furniture_yaw()

func _apply_random_furniture_yaw() -> void:
	if not detail_placement_active or detail_kind != "furniture": return
	var turn := posmod(int(landscape_state.next_id) * 17 + int(detail_style_id.hash()), FURNITURE_RANDOM_TURN_COUNT)
	detail_yaw_degrees = float(turn) * FURNITURE_RANDOM_STEP_DEGREES
	detail_yaw_quarters = posmod(roundi(detail_yaw_degrees / 90.0), 4)
	_detail_preview_signature = ""
	_update_detail_validity()
	_update_detail_preview()
	_sync_detail_aliases()

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
		furniture_yaw_degrees = detail_yaw_degrees
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
	var signature := "%s|%s|%s|%.1f|%s|%d" % [detail_kind, detail_style_id, point, detail_yaw_degrees, detail_placement_valid, _terrain_revision()]
	if signature == _detail_preview_signature: return
	_detail_preview_signature = signature
	composition_visual.show_furniture_preview(detail_style_id, point, detail_size, detail_yaw_degrees, detail_placement_valid, _detail_selected_colour if _detail_edit_id > 0 else "")

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
