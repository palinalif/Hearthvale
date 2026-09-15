extends SceneTree

## Read-only PNG inspector for Bob runs that have no vision tool available.
## Renders an image as a coarse ASCII grid plus a quantised palette histogram,
## or diffs two images. Nothing is written to the repo.
##
##   godot --headless --path . --script tools/bob_ascii_view.gd -- \
##       --img=reports/screenshots/m2-hamlet/full-hamlet.png --grid=96x32
##   ... --mode=palette --colors=24
##   ... --mode=diff --other=path/a.png --img=path/b.png
##
## Colours are clustered by a fixed 4x4x4 RGB bucket so results are stable
## between runs and machines (no k-means, no new dependencies).

var images: Array[String] = []
var other := ""
var mode := "ascii"
var grid_w := 96
var grid_h := 32
var colors := 20

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--img="): images.append(argument.trim_prefix("--img="))
		elif argument.begins_with("--other="): other = argument.trim_prefix("--other=")
		elif argument.begins_with("--mode="): mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--grid="):
			var parts := argument.trim_prefix("--grid=").split("x")
			if parts.size() == 2: grid_w = int(parts[0]); grid_h = int(parts[1])
		elif argument.begins_with("--colors="): colors = int(argument.trim_prefix("--colors="))
	call_deferred("_run")

func _load(path: String) -> Image:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		print("CANNOT_LOAD " + path)
		return null
	# Authoritative byte layout for get_data(): force RGBA8 so the stride is 4.
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _run() -> void:
	if images.is_empty():
		print("NO_IMAGES")
		quit(1)
		return
	if mode == "diff":
		_diff()
		quit(0)
		return
	for path in images:
		var image := _load(path)
		if image == null: continue
		print("\n=== %s  %dx%d ===" % [path, image.get_width(), image.get_height()])
		if mode == "palette": _palette(image)
		else: _ascii(image)
	quit(0)

func _buckets(image: Image) -> Dictionary:
	var counts := {}
	var total := 0
	var data := image.get_data()
	var limit := image.get_data().size() / 4
	# Stride keeps big images cheap while staying deterministic.
	var stride := maxi(1, int(limit / 400000.0))
	var index := 0
	while index < limit:
		var base := index * 4
		var r := data[base]; var g := data[base + 1]; var b := data[base + 2]
		var key := "%02x%02x%02x" % [(r / 16) * 16, (g / 16) * 16, (b / 16) * 16]
		counts[key] = int(counts.get(key, 0)) + 1
		total += 1
		index += stride
	counts["_total"] = total
	return counts

func _palette(image: Image) -> void:
	var counts := _buckets(image)
	var total := int(counts.get("_total", 1))
	var keys: Array = []
	for key: String in counts:
		if key != "_total": keys.append(key)
	keys.sort_custom(func(a: String, b: String) -> bool: return int(counts[a]) > int(counts[b]))
	for index in mini(keys.size(), colors):
		var key: String = keys[index]
		var share := 100.0 * float(counts[key]) / float(total)
		print("  #%s  %5.1f%%  lum=%3d" % [key, share, _lum(key)])

func _lum(hex: String) -> int:
	var r := ("0x" + hex.substr(0, 2)).hex_to_int()
	var g := ("0x" + hex.substr(2, 2)).hex_to_int()
	var b := ("0x" + hex.substr(4, 2)).hex_to_int()
	return int((r * 3 + g * 6 + b) / 10)

func _ascii(image: Image) -> void:
	var counts := _buckets(image)
	var total := int(counts.get("_total", 1))
	var keys: Array = []
	for key: String in counts:
		if key != "_total": keys.append(key)
	keys.sort_custom(func(a: String, b: String) -> bool: return int(counts[a]) > int(counts[b]))
	var legend: Array = keys.slice(0, mini(keys.size(), colors))
	var glyphs := "abcdefghijklmnopqrstuvwxyz"
	print("  legend (top-%d buckets, %d sample px):" % [legend.size(), total])
	for index in legend.size():
		print("    %s #%s %5.1f%%" % [glyphs[index], legend[index], 100.0 * float(counts[legend[index]]) / float(total)])
	var cell_w := maxi(1, int(image.get_width() / grid_w))
	var cell_h := maxi(1, int(image.get_height() / grid_h))
	for row in grid_h:
		var line := ""
		for column in grid_w:
			var bucket := _cell_bucket(image, column * cell_w, row * cell_h, cell_w, cell_h)
			var best := -1
			var best_distance := 1 << 30
			for index in legend.size():
				var distance := _bucket_distance(bucket, legend[index])
				if distance < best_distance: best_distance = distance; best = index
			line += glyphs[best] if best >= 0 else "?"
		print("  %02d %s" % [row, line])

func _cell_bucket(image: Image, x0: int, y0: int, w: int, h: int) -> String:
	var r := 0; var g := 0; var b := 0; var samples := 0
	var y := y0
	while y < mini(y0 + h, image.get_height()):
		var x := x0
		while x < mini(x0 + w, image.get_width()):
			var pixel := image.get_pixel(x, y)
			r += int(pixel.r * 255.0); g += int(pixel.g * 255.0); b += int(pixel.b * 255.0)
			samples += 1
			x += 2
		y += 2
	if samples == 0: return "000000"
	return "%02x%02x%02x" % [((r / samples) / 16) * 16, ((g / samples) / 16) * 16, ((b / samples) / 16) * 16]

func _bucket_distance(a: String, b: String) -> int:
	var total := 0
	for index in 3:
		var left := ("0x" + a.substr(index * 2, 2)).hex_to_int()
		var right := ("0x" + b.substr(index * 2, 2)).hex_to_int()
		total += absi(left - right)
	return total

func _diff() -> void:
	if images.size() != 1 or other.is_empty():
		print("DIFF_NEEDS --img=<new> --other=<old>")
		return
	var old := _load(other); var fresh := _load(images[0])
	if old == null or fresh == null: return
	if old.get_width() != fresh.get_width() or old.get_height() != fresh.get_height():
		print("DIFF_SIZE_MISMATCH"); return
	var width := old.get_width(); var height := old.get_height()
	var changed := 0
	var strong := 0
	var bands := {"top": 0, "middle": 0, "bottom": 0}
	var band_total := {"top": 0, "middle": 0, "bottom": 0}
	var columns: Array[int] = []
	columns.resize(8); columns.fill(0)
	var column_total: Array[int] = []; column_total.resize(8); column_total.fill(0)
	for y in height:
		for x in width:
			var first := old.get_pixel(x, y); var second := fresh.get_pixel(x, y)
			var delta := absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b)
			var band := "top" if y < height / 3 else ("middle" if y < height * 2 / 3 else "bottom")
			var column := mini(7, x * 8 / width)
			band_total[band] += 1; column_total[column] += 1
			if delta > 0.012:
				changed += 1; bands[band] += 1; columns[column] += 1
				if delta > 0.20: strong += 1
	print("DIFF %s -> %s  %dx%d" % [other, images[0], width, height])
	print("  changed>3levels %d / %d (%.2f%%)  strong>51levels %d" % [changed, width * height, 100.0 * float(changed) / float(width * height), strong])
	for band in ["top", "middle", "bottom"]:
		print("  band %-6s changed %6d / %6d = %5.1f%%" % [band, bands[band], band_total[band], 100.0 * float(bands[band]) / float(band_total[band])])
	var line := "  columns(eighths) "
	for column in 8:
		line += "%5.1f%% " % (100.0 * float(columns[column]) / float(maxi(1, column_total[column])))
	print(line)
