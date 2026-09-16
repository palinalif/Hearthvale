extends SceneTree

## Actual-Mobile render smoke test for the build browser. The exhaustive browser
## registry, controller navigation, authority, cancel/commit and cache semantics
## live in m2_build_browser_test.gd. Hosted Windows uses Microsoft's software
## D3D12 renderer, so this capture shard renders one real representative model
## per category instead of serially rasterizing the entire catalogue.

const OUTPUT := ".tools/cottage-repair/build-browser"
const HOUSE_CATEGORIES: Array[String] = ["windows", "doors", "wall", "roof"]
const WORLD_CATEGORIES: Array[String] = ["homes", "paths", "outdoor"]
const REPRESENTATIVES := {
	"windows": "window_round",
	"doors": "door_tudor_arch",
	"wall": "flower_box_woven",
	"roof": "chimney_brick",
	"homes": "woodland_lodge",
	"paths": "packed_earth",
	"outdoor": "bench",
}

var scene: Node
var checks := 0
var failures := 0
var captures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	check(DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "mobile", "actual Mobile renderer required")
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1280, 720)
	scene = preload("res://scenes/m1.tscn").instantiate()
	scene.test_mode = true
	scene.checkpoint_root = "user://m2-build-browser-capture-%s" % Time.get_ticks_usec()
	root.add_child(scene)

	var ready_deadline := Time.get_ticks_msec() + 30000
	while (scene._build_browser == null or scene._catalogue_thumbnails == null) and Time.get_ticks_msec() < ready_deadline:
		await process_frame
	check(scene._build_browser != null and scene._catalogue_thumbnails != null, "browser render subsystem ready")
	if scene._build_browser == null or scene._catalogue_thumbnails == null:
		await _finish()
		return

	# Capture tests the browser renderer, not terrain/checkpoint restoration. Keep
	# the parent scene from doing unrelated per-frame work while the thumbnail
	# child processes its one-item render queue.
	scene.set_process(false)
	var browser = scene._build_browser
	browser.set_entries(scene._browser_entries)
	browser.show()
	scene._browser_open = true
	scene.tools_open = true

	await _capture_group(HOUSE_CATEGORIES, scene.HOUSE_BROWSER_CATEGORIES, "")
	await _capture_group(WORLD_CATEGORIES, scene.WORLD_BROWSER_CATEGORIES, "world-")

	check(scene._catalogue_thumbnails.get_child_count() == 1 and scene._catalogue_thumbnails._viewport.own_world_3d, "one private render viewport serves catalogue thumbnails")
	check(scene._catalogue_thumbnails.cache.size() <= scene._catalogue_thumbnails.CACHE_LIMIT, "thumbnail cache remains bounded")
	await _finish()

func _capture_group(category_ids: Array[String], category_specs: Array, prefix: String) -> void:
	var browser = scene._build_browser
	browser.set_categories(category_specs)
	for category in category_ids:
		browser.select_category(category)
		for _i in 3: await process_frame
		var representative_id := str(REPRESENTATIVES[category])
		var item := _entry(representative_id)
		check(not item.is_empty() and str(item.get("category", "")) == category, "representative exists in category: " + category)
		if item.is_empty():
			continue

		# Selecting a category normally queues every visible card. Replace that
		# queue with one real model so software D3D12 verifies the production
		# SubViewport/factory/cache path without becoming an exhaustive GPU test.
		scene._catalogue_thumbnails.stop()
		var render_items: Array[Dictionary] = [item]
		scene._catalogue_thumbnails.request(render_items)
		var render_deadline := Time.get_ticks_msec() + 45000
		while not scene._catalogue_thumbnails.cache.has(representative_id) and Time.get_ticks_msec() < render_deadline:
			await process_frame
		check(scene._catalogue_thumbnails.cache.has(representative_id), "representative thumbnail rendered: " + category)
		var card := _card(representative_id)
		check(card != null, "representative card visible: " + category)
		if card != null:
			var picture := card.get_node_or_null("CardContent/Preview") as TextureRect
			check(picture != null and picture.texture != null, "representative card displays rendered thumbnail: " + category)
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var file_name := prefix + category + ".png"
		check(not image.is_empty() and image.get_width() == 1280 and image.get_height() == 720, "capture has expected dimensions: " + category)
		check(not image.is_empty() and image.save_png(OUTPUT + "/" + file_name) == OK, "save actual catalogue screenshot: " + file_name)
		captures += 1

func _entry(id: String) -> Dictionary:
	for item in scene._browser_entries:
		if str(item.get("id", "")) == id:
			return (item as Dictionary).duplicate(true)
	return {}

func _card(id: String) -> Button:
	for card in scene._build_browser.cards:
		var item: Dictionary = card.get_meta("item", {})
		if str(item.get("id", "")) == id:
			return card
	return null

func _finish() -> void:
	if is_instance_valid(scene):
		scene._shutting_down = true
		if scene._catalogue_thumbnails:
			scene._catalogue_thumbnails.stop()
		scene.queue_free()
		await process_frame
		await process_frame
	check(captures == 7, "all seven current browser categories captured")
	print("BUILD_BROWSER_RESULT " + JSON.stringify({"checks": checks, "failures": failures, "ok": failures == 0, "captures": captures, "phase": "capture"}))
	quit(1 if failures else 0)
