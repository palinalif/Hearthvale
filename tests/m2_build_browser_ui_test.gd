extends SceneTree

const BuildBrowser = preload("res://scripts/ui/m2_build_browser.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	var browser = BuildBrowser.new()
	root.add_child(browser)
	browser.set_entries([
		{"id": "home_a", "name": "Cottage", "category": "homes", "kind": "home", "summary": "Small home"},
		{"id": "path_a", "name": "Packed path", "category": "paths", "kind": "path", "summary": "Warm earth"},
		{"id": "tree", "name": "Tree brush", "category": "outdoor", "kind": "terrain_tool", "summary": "Varied trees"},
		{"id": "window_a", "name": "Round window", "category": "windows", "kind": "window", "summary": "House detail"},
	])
	browser.set_categories([["homes", "Homes"], ["paths", "Paths & bridges"], ["outdoor", "Outdoor"]])
	browser.show()
	browser.fit(Vector2(1280, 720), 654.0)
	await process_frame
	await process_frame
	_check(browser.tabs.size() == 3, "world browser exposes three compact categories")
	_check(browser.position.y == 360.0 and is_equal_approx(browser.get_rect().end.y, 646.0), "browser is anchored to the lower half immediately above prompts")
	_check(browser.cards.size() == 1 and str(browser.cards[0].get_meta("item")["id"]) == "home_a", "world homes category shows home cards")
	browser.select_category("paths")
	await process_frame
	_check(browser.cards.size() == 1 and str(browser.cards[0].get_meta("item")["id"]) == "path_a", "paths category shows path cards")
	_check(browser.status.text.contains("Warm earth"), "focused card description includes its preview summary")
	browser.next_category(1)
	await process_frame
	_check(browser.category == "outdoor" and browser.cards.size() == 1, "shoulder-style category cycling reaches outdoor cards")
	browser.set_categories([["windows", "Windows"], ["doors", "Doors"], ["wall", "Wall decor"], ["roof", "Roof decor"]])
	await process_frame
	_check(browser.tabs.size() == 4, "house-edit browser has detail categories only")
	var has_homes := false
	for tab in browser.tabs:
		if str(tab.get_meta("category", "")) == "homes": has_homes = true
	_check(not has_homes, "house-edit browser no longer exposes new homes")
	browser.fit(Vector2(960, 600), 534.0)
	_check(browser.position.y == 300.0 and browser.get_rect().end.y <= 526.0, "bottom catalogue remains responsive on a smaller viewport")
	browser.queue_free()
	await process_frame
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures}))
	quit(1 if failures else 0)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
