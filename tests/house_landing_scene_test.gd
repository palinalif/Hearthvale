extends SceneTree

## Scene-level reconciliation checks for the house landing decoration, run
## against the real m1 scene: a home committed through the building record gains
## a planted edge and a dirt shoulder; moving, resizing, undoing and deleting the
## record takes the decoration with it; and the whole pass writes nothing that is
## ever saved.
var checks := 0
var failures := 0
var scene: Node

func _initialize() -> void:
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.checkpoint_root = "user://house-landing-scene-test-%s" % Time.get_ticks_usec()
	scene.test_mode = true
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 30000
	while (scene.backend == null or not scene.backend.is_ready()) and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene.backend != null and scene.backend.is_ready(), "native backend ready")
	if scene.backend == null or not scene.backend.is_ready():
		_print_result()
		return
	await process_frame

	var origin := Vector3(16.0, 8.0, 30.0)
	var target := Transform3D(Basis(), origin)
	var building_id: String = scene.building_world.create_home_at("riverside_cottage", target, -1)
	_check(not building_id.is_empty(), "a home is committed through the building record")
	var serialized_before: String = scene.building_world.serialize_document()

	# --- placement commit: the decoration appears and derives from the record --
	scene._update_presentation()
	await process_frame
	await process_frame
	var placed: Dictionary = scene.house_landing_stats.get(building_id, {})
	_check(not placed.is_empty(), "the committed home is decorated")
	_check(int(placed.get("tufts", 0)) > 0, "the committed home grows edge tufts (tufts=%d)" % int(placed.get("tufts", 0)))
	_check(int(placed.get("rim_cells", 0)) > 0, "the committed home gets a dirt shoulder (cells=%d)" % int(placed.get("rim_cells", 0)))
	_check(int(placed.get("tuft_draw_calls", 0)) == 1 and int(placed.get("rim_draw_calls", 0)) == 1, "the decoration costs one draw call per part")
	var tuft_root := scene.get_node_or_null("HouseEdgeFoliage_%s" % building_id)
	var rim_root := scene.get_node_or_null("HouseDirtRim_%s" % building_id)
	_check(tuft_root != null and rim_root != null, "both decoration roots exist in the scene tree")
	var tuft_view: MeshInstance3D = tuft_root.get_node_or_null("TuftRing") if tuft_root else null
	var rim_view: MeshInstance3D = rim_root.get_node_or_null("FoundationShoulder") if rim_root else null
	_check(tuft_view != null and tuft_view.mesh != null and tuft_view.mesh.get_surface_count() == 1, "the tuft ring is one batched mesh instance")
	_check(rim_view != null and rim_view.mesh != null and rim_view.mesh.get_surface_count() == 1, "the dirt shoulder is one batched mesh instance")
	_check(tuft_root.transform == target and rim_root.transform == target, "decoration roots follow the committed building transform")
	_check(tuft_root.get_child_count() == 1 and rim_root.get_child_count() == 1, "each decoration root carries exactly one batched mesh node")

	# --- presentation writes nothing that is saved ---------------------------
	_check(scene.building_world.serialize_document() == serialized_before, "the landing pass adds no building record, no planting and no save data")
	var children_after_present := scene.get_child_count()
	scene._update_presentation()
	await process_frame
	_check(scene.get_child_count() == children_after_present, "a repeat presentation pass does not rebuild the decoration")
	var placement_digest := str(placed.get("tuft_digest", "")) + str(placed.get("rim_digest", ""))

	# --- move: the decoration follows the record -----------------------------
	var moved_target := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(24.0, 8.0, 20.0))
	_check(scene.building_world.move_building_transform(building_id, moved_target, scene.building_world.get_revision()), "the home record moves")
	scene._update_presentation()
	await process_frame
	await process_frame
	var moved: Dictionary = scene.house_landing_stats.get(building_id, {})
	var moved_digest := str(moved.get("tuft_digest", "")) + str(moved.get("rim_digest", ""))
	_check(not moved.is_empty() and moved_digest != placement_digest, "the moved home re-derives its decoration")
	var moved_tuft_root := scene.get_node_or_null("HouseEdgeFoliage_%s" % building_id)
	var moved_rim_root := scene.get_node_or_null("HouseDirtRim_%s" % building_id)
	_check(moved_tuft_root != null and moved_tuft_root.transform == moved_target, "the tuft ring root moved with the home")
	_check(moved_rim_root != null and moved_rim_root.transform == moved_target, "the dirt shoulder root moved with the home")

	# --- undo: both the home and its planting go back ------------------------
	_check(scene.building_world.undo(), "the move is undone")
	scene._update_presentation()
	await process_frame
	await process_frame
	var restored: Dictionary = scene.house_landing_stats.get(building_id, {})
	_check(str(restored.get("tuft_digest", "")) + str(restored.get("rim_digest", "")) == placement_digest, "undo restores the original decoration exactly")
	var restored_root := scene.get_node_or_null("HouseEdgeFoliage_%s" % building_id)
	_check(restored_root != null and restored_root.transform == target, "the tuft ring root returned with the home")
	_check(scene.building_world.redo(), "the move is redone")
	scene._update_presentation()
	await process_frame
	await process_frame
	var redone: Dictionary = scene.house_landing_stats.get(building_id, {})
	_check(str(redone.get("tuft_digest", "")) + str(redone.get("rim_digest", "")) == moved_digest, "redo re-applies the moved decoration")
	var redone_root := scene.get_node_or_null("HouseEdgeFoliage_%s" % building_id)
	_check(redone_root != null and redone_root.transform == moved_target, "the redone tuft ring root sits on the redone transform")

	# --- resize: the shoulder reconciles to the new footprint ---------------
	var before_resize := int(redone.get("rim_cells", 0))
	_check(scene.building_world.resize(building_id, Vector3(26.0, 7.0, 14.0)), "the home record resizes")
	scene._update_presentation()
	await process_frame
	await process_frame
	var resized: Dictionary = scene.house_landing_stats.get(building_id, {})
	_check(int(resized.get("rim_cells", 0)) > before_resize, "the resized home re-derives a longer dirt shoulder")

	# --- delete: nothing is left behind -------------------------------------
	var document: Dictionary = scene.building_world.get_document()
	document.buildings = []
	_check(scene.building_world.load_document(document), "the home record is deleted")
	scene._update_presentation()
	await process_frame
	await process_frame
	_check(scene.get_node_or_null("HouseEdgeFoliage_%s" % building_id) == null, "the deleted home leaves no tuft ring")
	_check(scene.get_node_or_null("HouseDirtRim_%s" % building_id) == null, "the deleted home leaves no dirt shoulder")
	_check(scene.house_landing_stats.is_empty(), "the deleted home leaves no landing state")

	_print_result()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _print_result() -> void:
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures}))
	quit(1 if failures else 0)
