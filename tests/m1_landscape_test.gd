extends SceneTree

const SceneScript = preload("res://scripts/m1_scene.gd")
const State = preload("res://scripts/landscape_state.gd")
const Flora = preload("res://scripts/vegetation_mesh.gd")
const GardenVisual = preload("res://scripts/m1_garden_visual.gd")
var checks := 0
var failures := 0
var scene: Node
var save_root := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	save_root = "user://m1-landscape-%d" % Time.get_ticks_usec()
	for arg in args:
		if arg.begins_with("--fixture-root="): save_root = arg.trim_prefix("--fixture-root=")
	scene = SceneScript.new(); scene.checkpoint_root = save_root; scene.test_mode = true
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 30000
	while (scene.backend == null or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline: await process_frame
	await process_frame
	_check(scene.backend != null and scene.backend.is_ready(), "native landscape scene ready")
	if scene.backend == null or not scene.backend.is_ready(): _finish(); return
	if "--read-fixture" in args:
		var expectation: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_root.path_join("expectation.json")))
		_check(expectation is Dictionary, "cold process expectation exists")
		if expectation is Dictionary:
			_check(_canonical(scene.landscape_state.document()) == expectation.landscape, "cold restart restores every planting record and next id")
			_check(_terrain_hash() == expectation.terrain_hash, "cold restart restores exact terrain bytes")
			_check(_canonical(scene.backend.loaded_building_document) == expectation.building, "cold restart restores complete persisted cottage and landscape document")
			_check(_canonical(scene.building_world.get_document().buildings) == expectation.building.buildings, "cold restart resolves exact cottage records")
		_finish(); return
	await _run_controller_checks()
	await _press(JOY_BUTTON_START)
	await _press(JOY_BUTTON_A)
	var save_stats: Dictionary = scene.backend.stats()
	_check(save_stats.save_status == "saved", "controller pause Save writes complete checkpoint (%s)" % str(save_stats.get("error", "")))
	var saved_document: Dictionary = scene.building_world.get_document()
	saved_document["landscape"] = scene.landscape_state.document()
	var expected := {"landscape": _canonical(scene.landscape_state.document()), "terrain_hash": _terrain_hash(), "building": _canonical(saved_document)}
	var file := FileAccess.open(save_root.path_join("expectation.json"), FileAccess.WRITE)
	_check(file != null, "write independent restart expectation")
	if file:
		file.store_string(JSON.stringify(expected)); file.close()
	print("LANDSCAPE_FIXTURE_ROOT=" + save_root)
	_finish()

func _run_controller_checks() -> void:
	var invalid := State.new()
	_check(not invalid.add("unknown", Vector3(12, 8, 12), 1) and not invalid.add("tree", Vector3(-1, 8, 12), 1), "invalid kinds and out-of-bounds planting rejected")
	var initial: Dictionary = scene.landscape_state.document()
	_check(State.validate(initial) and initial.records.size() > 20, "deterministic native-ground scatter starts populated")
	var starting_foliage_variants := {}
	var starting_tree_turns := {}
	var starting_foliage_turns := {}
	for record: Dictionary in initial.records:
		if record.kind == "tree": starting_tree_turns[GardenVisual.planting_turn(record)] = true
		if record.kind == "foliage":
			starting_foliage_variants[posmod(int(record.seed), Flora.variant_count("foliage"))] = true
			starting_foliage_turns[GardenVisual.planting_turn(record)] = true
	_check(starting_foliage_variants.size() == Flora.variant_count("foliage"), "starting scene includes every authored foliage variant")
	_check(starting_tree_turns.size() >= 3 and starting_foliage_turns.size() == 4, "starting trees and foliage use varied deterministic quarter turns")
	var tree_turns := {}
	for index in GardenVisual.TREE_TURN_COUNT:
		var tree_record := {"id": index + 1, "kind": "tree", "position": [12.0, 8.0, 12.0], "seed": 0}
		var turn := GardenVisual.planting_turn(tree_record)
		tree_turns[turn] = true
		var expected := Basis(Vector3.UP, float(turn) * PI * 0.5)
		_check(GardenVisual.planting_rotation(tree_record).is_equal_approx(expected), "automatic tree rotation stays on dense authored quarter-turn views")
	_check(tree_turns.size() == GardenVisual.TREE_TURN_COUNT, "deterministic tree rotation can select all four quarter-turn facings")
	var starter_wind_ok := true
	for record: Dictionary in initial.records:
		if GardenVisual.wind_strength(str(record.kind), posmod(int(record.seed), Flora.variant_count(str(record.kind)))) > 0.0:
			starter_wind_ok = starter_wind_ok and _record_has_gameplay_wind(record)
	_check(starter_wind_ok, "starter trees and foliage use independent gameplay wind batches")
	var tint_slots := {}
	for index in 20:
		var tint_record := {"id": index + 1, "kind": "foliage", "position": [24.0, 8.0, 24.0], "seed": index % Flora.variant_count("foliage")}
		tint_slots[GardenVisual.prop_tint_slot(tint_record)] = true
		var basis := GardenVisual.planting_rotation(tint_record)
		_check(is_equal_approx(basis.determinant(), 1.0) and basis.get_scale().is_equal_approx(Vector3.ONE), "planting rotation preserves scale and handedness")
	_check(tint_slots.size() == GardenVisual.PROP_TINTS.size(), "foliage records span restrained deterministic tint slots")
	var distinct_tints := {}
	for slot in GardenVisual.PROP_TINTS.size():
		var tinted: Color = GardenVisual.PROP_TINTS[slot]
		distinct_tints[tinted.to_html()] = true
		_check(tinted.r >= 0.87 and tinted.g >= 0.87 and tinted.b >= 0.87 and tinted.r <= 1.0 and tinted.g <= 1.0 and tinted.b <= 1.0, "foliage tint stays within the approved subtle hue/value range")
	_check(distinct_tints.size() == GardenVisual.PROP_TINTS.size(), "foliage tint slots are visibly distinct")
	var rock_tint_record := {"id": 701, "kind": "rock", "position": [12.0, 8.0, 12.0], "seed": 2}
	_check(GardenVisual.prop_instance_color(rock_tint_record) != Color.WHITE, "rocks receive stable presentation tint variation")
	var tinted_instances := {"foliage": false, "rock": false}
	for key: String in scene.garden_visual._groups:
		var node: MultiMeshInstance3D = scene.garden_visual._groups[key]
		if key.begins_with("foliage_") or key.begins_with("rock_"):
			var kind := "foliage" if key.begins_with("foliage_") else "rock"
			_check(node.multimesh.use_colors and node.material_override is ShaderMaterial and (node.material_override as ShaderMaterial).get_shader_parameter("base_color") is Color, kind + " batch enables palette-preserving per-instance modulation")
			for instance in node.multimesh.instance_count:
				if node.multimesh.get_instance_color(instance) != Color.WHITE: tinted_instances[kind] = true
	_check(tinted_instances.foliage and tinted_instances.rock, "starting foliage and rocks include visible deterministic tint variation")
	scene._restore_landscape({})
	_check(scene.landscape_state.document() == initial, "seeded scatter repeats every position kind id and seed")
	var terrain_before := _terrain_hash()
	var building_before: Dictionary = scene.building_world.get_document()
	scene.cursor = Vector3(32, 8, 26); scene.brush_radius = 1.5
	await process_frame
	_check(scene._terrain_target_valid, "open pad cursor targets actual terrain")
	await _choose("Tree brush")
	var history_before: int = scene._history_tags.size()
	await _hold(JOY_BUTTON_A, 20)
	var tree_doc: Dictionary = scene.landscape_state.document()
	_check(tree_doc.records.size() == initial.records.size() + 1, "stationary held tree brush plants one tree")
	_check(int(tree_doc.records.back().seed) >= 3, "tree brush draws from the expanded compact-variant set")
	_check(_record_has_gameplay_wind(tree_doc.records.back()), "tree brush placement receives gameplay wind")
	_check(scene._history_tags.size() == history_before + 1 and not scene.landscape_active, "tree press-release is one completed transaction")
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(scene.landscape_state.document() == initial, "tree undo restores exact document")
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	_check(scene.landscape_state.document() == tree_doc, "tree redo restores exact document")
	scene.cursor = Vector3(29.5, 8, 26); await process_frame
	await _choose("Foliage brush")
	history_before = scene._history_tags.size()
	await _press(JOY_BUTTON_A)
	var foliage_doc: Dictionary = scene.landscape_state.document()
	_check(foliage_doc.records.size() > tree_doc.records.size(), "foliage brush paints native ground")
	var brush_added_new_variant := false
	var brush_added_wind := false
	for record_index in range(tree_doc.records.size(), foliage_doc.records.size()):
		if int(foliage_doc.records[record_index].seed) >= 3: brush_added_new_variant = true
		if GardenVisual.wind_strength("foliage", posmod(int(foliage_doc.records[record_index].seed), Flora.variant_count("foliage"))) > 0.0:
			brush_added_wind = brush_added_wind or _record_has_gameplay_wind(foliage_doc.records[record_index])
	_check(brush_added_new_variant, "foliage brush draws from the expanded authored variant set")
	_check(brush_added_wind, "foliage brush placement receives gameplay wind")
	_check(scene._history_tags.size() == history_before + 1, "foliage press-release is one transaction")
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(scene.landscape_state.document() == tree_doc, "foliage undo exact")
	await _press(JOY_BUTTON_A)
	_check(scene.landscape_state.document() == foliage_doc, "same input from same state paints deterministic positions and seeds")
	scene.cursor = Vector3(30, 8, 28); await process_frame
	history_before = scene._history_tags.size()
	await _button(JOY_BUTTON_A, true)
	for _i in 20: await process_frame
	_check(scene.landscape_active and scene.landscape_state.document() != foliage_doc, "held foliage stroke changes preview")
	await _press(JOY_BUTTON_B)
	_check(not scene.landscape_active and scene.landscape_state.document() == foliage_doc and scene._history_tags.size() == history_before, "B cancels whole foliage stroke without history")
	for _i in 12: await process_frame
	_check(not scene.landscape_active and scene.landscape_state.document() == foliage_doc, "held A cannot restart after cancel")
	await _button(JOY_BUTTON_A, false)
	await _button(JOY_BUTTON_A, true)
	await _press(JOY_BUTTON_START)
	_check(scene.menu_open and not scene.landscape_active and scene.landscape_state.document() == foliage_doc, "pause cancels planting preview exactly")
	await _press(JOY_BUTTON_START)
	for _i in 12: await process_frame
	_check(not scene.landscape_active and scene.landscape_state.document() == foliage_doc, "resume requires fresh A press")
	await _button(JOY_BUTTON_A, false)
	_check(_terrain_hash() == terrain_before and scene.building_world.get_document() == building_before, "planting leaves terrain bytes and editable cottage untouched")
	scene.cursor = Vector3(29.5, 8, 26); await process_frame
	await _choose("Clear planting")
	await _press(JOY_BUTTON_A)
	_check(scene.landscape_state.records.size() < foliage_doc.records.size(), "controller clear brush removes local planting")
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(scene.landscape_state.document() == foliage_doc, "clear brush undo restores exact planting")
	scene.cursor = Vector3(32, 8, 26); scene.brush_radius = 1.0
	await process_frame
	await _choose("Dig")
	var pre_dig: Dictionary = scene.landscape_state.document()
	var pre_dig_terrain := _terrain_hash()
	await _hold(JOY_BUTTON_A, 30)
	var after_dig: Dictionary = scene.landscape_state.document()
	_check(_terrain_hash() != pre_dig_terrain, "controller dig changes authoritative terrain")
	_check(after_dig.records.size() < pre_dig.records.size(), "dig removes planted roots intersecting changed terrain")
	var unchanged_roots := true
	var changed_cells: Array = scene.backend.get_last_edit_cells()
	for record: Dictionary in pre_dig.records:
		var root_cell := Vector3i((State.position_of(record) / float(scene.backend.voxel_scale)).floor())
		var reach := 2 if record.kind == "tree" else 1
		var affected := false
		for point: Vector3 in changed_cells:
			var offset := Vector3i((point / float(scene.backend.voxel_scale)).floor()) - root_cell
			if absi(offset.x) <= reach and absi(offset.z) <= reach and absi(offset.y) <= 1: affected = true
		if not affected: unchanged_roots = unchanged_roots and after_dig.records.has(record)
	_check(unchanged_roots, "terrain preserves every root outside actual changed cells")
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(scene.landscape_state.document() == pre_dig and _terrain_hash() == pre_dig_terrain, "terrain undo restores planting and exact voxel bytes together")
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	_check(scene.landscape_state.document() == after_dig, "terrain redo repeats exact planting removal")

func _button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new(); event.button_index = button; event.pressed = pressed
	Input.parse_input_event(event); Input.flush_buffered_events(); await process_frame

func _press(button: JoyButton) -> void:
	await _button(button, true); await _button(button, false)

func _hold(button: JoyButton, frames: int) -> void:
	await _button(button, true)
	for _i in frames: await process_frame
	await _button(button, false)

func _choose(label: String) -> void:
	await _press(JOY_BUTTON_X)
	var labels: Array = scene._visible_action_labels()
	var index := labels.find(label)
	_check(index >= 0, "controller menu exposes " + label)
	if index < 0: return
	var buttons: Array = scene._visible_action_buttons()
	var current := buttons.find(scene.get_viewport().gui_get_focus_owner())
	for _i in posmod(index - maxi(0, current), labels.size()): await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_A)

func _terrain_hash() -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256)
	context.update(scene.backend.voxels.get_channel_as_byte_array(0))
	return context.finish().hex_encode()

func _record_has_gameplay_wind(record: Dictionary) -> bool:
	var kind := str(record.kind)
	var variant := posmod(int(record.seed), Flora.variant_count(kind))
	var expected_phase := GardenVisual.wind_phase(record)
	var expected_count := 0
	for current: Dictionary in scene.landscape_state.records:
		if str(current.kind) == kind and posmod(int(current.seed), Flora.variant_count(kind)) == variant: expected_count += 1
	for surface in Flora.meshes(kind, variant).size():
		var key := "%s_%d_%d" % [kind, variant, surface]
		if not scene.garden_visual._groups.has(key): return false
		var node: MultiMeshInstance3D = scene.garden_visual._groups[key]
		if node.multimesh.instance_count != expected_count or not node.multimesh.use_custom_data or not (node.material_override is ShaderMaterial): return false
		# The headless dummy renderer intentionally does not retain MultiMesh
		# buffer values. The actual Mobile render gate verifies their phases.
		if DisplayServer.get_name() == "headless": continue
		var found_phase := false
		for instance in node.multimesh.instance_count:
			found_phase = found_phase or absf(node.multimesh.get_instance_custom_data(instance).r - expected_phase) < 0.005
		if not found_phase: return false
	return true

func _canonical(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: " + label)

func _finish() -> void:
	scene.queue_free(); await process_frame; await process_frame
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "fixture_root": save_root}))
	quit(1 if failures else 0)
