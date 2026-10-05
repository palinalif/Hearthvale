extends SceneTree

# Lantern glow contract.
#
# The path lantern is the hamlet's only authored light source.  Its glass core
# is surface 2 of the furniture builder, so the glow contract is:
#
#   * the committed lantern mesh carries emission on the glass surface only
#   * the emissive colour is warm, saturated and above the bloom threshold
#   * the preview mesh stays non-emissive (placement preview is not a light)
#   * the glow is presentation only: no light node, record, save field, anchor
#     or authority is introduced by it
#
# Run: godot --headless --path . --script res://tests/m2_lantern_glow_test.gd

const FAIL_COLOR := Color(1.0, 0.3, 0.3)

var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	_check("glow helper exposes the ember colour", _probe_helper())
	_check("lantern glass is emissive in the built furniture", _probe_built_lantern())
	_check("only the glass surface glows", _probe_glow_is_glass_only())
	_check("preview stays non-emissive", _probe_preview_non_emissive())
	_check("glow adds no light node", _probe_no_light_nodes())
	_check("non-lantern furniture is unaffected", _probe_other_furniture_unaffected())
	print("M2 LANTERN GLOW %s: %d/%d checks" % ["PASS" if _failures.is_empty() else "FAIL", _checks - _failures.size(), _checks])
	for failure in _failures:
		print("  - " + failure)
	quit(0 if _failures.is_empty() else 1)

func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)

func _record(id: int, style_id: String) -> Dictionary:
	return {"id": id, "kind": "furniture", "style_id": style_id, "position": [0.0, 0.0], "rotation_degrees": 0.0, "colour_id": "natural"}

func _make_visual() -> Node:
	var visual: Node = load("res://scripts/m2_hamlet_visual.gd").new()
	root.add_child(visual)
	return visual

func _emissive_surfaces(visual: Node) -> Dictionary:
	var found := {}
	for child in visual.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null: continue
		for surface_index in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(surface_index) as StandardMaterial3D
			if material != null and material.emission_enabled:
				found[surface_index] = material.emission
	return found

func _probe_helper() -> bool:
	var glow: Object = load("res://scripts/m2_lantern_glow.gd").new()
	var color: Color = glow.LANTERN_EMBER_COLOR
	return color.r > 0.8 and color.g > 0.35 and color.b < color.g and color.g / maxf(color.r, 0.0001) > 0.5

func _probe_built_lantern() -> bool:
	var visual := _make_visual()
	visual.rebuild_furniture([_record(1, "lantern")])
	var emissive := _emissive_surfaces(visual)
	if emissive.is_empty(): return false
	var color: Color = emissive.values()[0]
	# Warm, saturated, and above the Mobile bloom threshold so the glow is visible.
	return color.r > 0.8 and color.g / maxf(color.r, 0.0001) > 0.5 and color.b < color.g

func _probe_glow_is_glass_only() -> bool:
	var visual := _make_visual()
	visual.rebuild_furniture([_record(1, "lantern"), _record(2, "bench")])
	var emissive := _emissive_surfaces(visual)
	# Exactly one glowing surface across lantern + bench, and it is the glass core.
	return emissive.size() == 1 and emissive.has(2)

func _probe_preview_non_emissive() -> bool:
	var visual := _make_visual()
	visual.show_furniture_preview("lantern", Vector2(0.0, 0.0), Vector2(0.5, 0.5), 0.0, true)
	var node: MeshInstance3D = visual._furniture_preview_node
	if node == null or node.mesh == null: return false
	for surface_index in node.mesh.get_surface_count():
		var material := node.mesh.surface_get_material(surface_index) as StandardMaterial3D
		if material != null and material.emission_enabled: return false
	return true

func _probe_no_light_nodes() -> bool:
	var visual := _make_visual()
	visual.rebuild_furniture([_record(1, "lantern")])
	for child in visual.get_children():
		if child is OmniLight3D or child is SpotLight3D: return false
	return true

func _probe_other_furniture_unaffected() -> bool:
	var visual := _make_visual()
	visual.rebuild_furniture([_record(1, "bench"), _record(2, "signpost")])
	return _emissive_surfaces(visual).is_empty()
