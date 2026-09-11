extends PanelContainer

## UI only. Selection never mutates the world; the caller starts placement.
signal item_chosen(item: Dictionary)
signal category_changed(category: String)
signal house_requested
signal landscape_requested
const CATEGORIES := [
	["windows", "Windows"], ["doors", "Doors"], ["wall", "Wall decor"],
	["roof", "Roof decor"], ["homes", "Homes"],
]
var category := "windows"
var remembered: Dictionary = {}
var entries: Array[Dictionary] = []
var cards: Array[Button] = []
var tabs: Array[Button] = []
var grid: GridContainer
var scroll: ScrollContainer
var status: Label
var _stack: VBoxContainer

func _init() -> void:
	name = "BuildBrowser"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 15
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#293a34")
	background.set_content_margin_all(12)
	background.corner_radius_top_left = 12
	background.corner_radius_top_right = 12
	add_theme_stylebox_override("panel", background)
	_stack = VBoxContainer.new()
	_stack.add_theme_constant_override("separation", 8)
	add_child(_stack)
	var heading := HBoxContainer.new()
	_stack.add_child(heading)
	for spec in CATEGORIES:
		var tab := Button.new()
		tab.text = spec[1]
		tab.toggle_mode = true
		tab.custom_minimum_size = Vector2(92, 36)
		tab.pressed.connect(select_category.bind(str(spec[0])))
		tab.set_meta("category", spec[0])
		heading.add_child(tab)
		tabs.append(tab)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(spacer)
	for label in ["House options", "Landscape"]:
		var button := Button.new()
		button.text = label
		button.custom_minimum_size.y = 36
		if label == "House options": button.pressed.connect(func(): house_requested.emit())
		else: button.pressed.connect(func(): landscape_requested.emit())
		heading.add_child(button)
	scroll = ScrollContainer.new()
	scroll.name = "CatalogueScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 8
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	status = Label.new()
	status.custom_minimum_size.y = 24
	status.add_theme_font_size_override("font_size", 16)
	_stack.add_child(status)

func set_entries(values: Array[Dictionary]) -> void:
	entries = values.duplicate(true)
	select_category(category)

func select_category(value: String) -> void:
	var valid := false
	for spec in CATEGORIES:
		if spec[0] == value: valid = true
	if not valid: return
	category = value
	for tab in tabs: tab.set_pressed_no_signal(str(tab.get_meta("category")) == category)
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	cards.clear()
	for item in entries:
		if str(item["category"]) != category: continue
		var card := Button.new()
		card.name = "Item_" + str(item["id"])
		card.custom_minimum_size = Vector2(126, 88)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.accessibility_name = str(item["name"])
		card.set_meta("item", item)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#3b4e44")
		style.set_corner_radius_all(7)
		card.add_theme_stylebox_override("normal", style)
		var selected := style.duplicate() as StyleBoxFlat
		selected.border_color = Color("#ffda8c")
		selected.set_border_width_all(3)
		card.add_theme_stylebox_override("focus", selected)
		card.add_theme_stylebox_override("hover", selected)
		var layout := VBoxContainer.new()
		layout.name = "CardContent"
		layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(layout)
		layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layout.offset_left = 6
		layout.offset_right = -6
		layout.offset_top = 4
		layout.offset_bottom = -4
		var picture := TextureRect.new()
		picture.name = "Preview"
		picture.custom_minimum_size = Vector2(0, 56)
		picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layout.add_child(picture)
		var label := Label.new()
		label.text = str(item["name"])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_font_size_override("font_size", 14)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layout.add_child(label)
		card.focus_entered.connect(_remember.bind(card))
		card.mouse_entered.connect(_describe.bind(item))
		card.pressed.connect(func(): _remember(card); item_chosen.emit(item))
		grid.add_child(card)
		cards.append(card)
	restore_focus.call_deferred()
	category_changed.emit(category)

func _remember(card: Button) -> void:
	var item: Dictionary = card.get_meta("item")
	remembered[category] = str(item["id"])
	_describe(item)
	scroll.ensure_control_visible.call_deferred(card)

func _describe(item: Dictionary) -> void:
	status.text = str(item["name"])

func restore_focus() -> void:
	if not is_visible_in_tree() or cards.is_empty(): return
	var target := cards[0]
	for card in cards:
		if str(card.get_meta("item")["id"]) == str(remembered.get(category, "")): target = card
	target.grab_focus()
	scroll.ensure_control_visible.call_deferred(target)

func navigate(horizontal: int, vertical: int) -> void:
	if cards.is_empty(): return
	var index := cards.find(get_viewport().gui_get_focus_owner())
	index = maxi(index, 0)
	var step := horizontal + vertical * grid.columns
	cards[posmod(index + step, cards.size())].grab_focus()

func next_category(direction: int) -> void:
	var index := 0
	for i in CATEGORIES.size():
		if CATEGORIES[i][0] == category: index = i
	select_category(str(CATEGORIES[posmod(index + direction, CATEGORIES.size())][0]))

func apply_thumbnail(id: String, texture: Texture2D) -> void:
	for card in cards:
		if str(card.get_meta("item")["id"]) != id: continue
		var picture := card.get_node("CardContent/Preview") as TextureRect
		picture.texture = texture

func fit(viewport_size: Vector2, prompt_top: float) -> void:
	position = Vector2(16, viewport_size.y * 0.5)
	size = Vector2(viewport_size.x - 32, maxf(0, minf(viewport_size.y - 12, prompt_top - 8) - position.y))
	grid.columns = maxi(1, floori((size.x - 32) / 134.0))
