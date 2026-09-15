extends SceneTree

## Reads the *-void.png frames produced by tools/bob_rim_capture.gd (flat magenta
## background = hole in the world, since the pitch clamp keeps the sky out of
## frame) and reports where the holes are: total share, a 24-band row profile,
## and left/middle/right thirds. Read-only.
##
##   godot --headless --path . --script tools/bob_void_scan.gd -- \
##       --dir=reports/screenshots/step4-rim --suffix=-before-void

var dir := "reports/screenshots/step4-rim"
var suffix := "-void"
var names := PackedStringArray(["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"])

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dir="): dir = argument.trim_prefix("--dir=")
		elif argument.begins_with("--suffix="): suffix = argument.trim_prefix("--suffix=")
		elif argument.begins_with("--names="):
			names = PackedStringArray(argument.trim_prefix("--names=").split(","))
	call_deferred("_run")

func _run() -> void:
	for name in names:
		var path := "%s/%s%s.png" % [dir, name, suffix]
		var image := Image.load_from_file(path)
		if image == null or image.is_empty():
			print("VOID_SCAN_MISSING " + path)
			continue
		_scan(name, image)
	quit(0)

func _is_void(pixel: Color) -> bool:
	# Magenta background after fog blending: high red+blue, depressed green.
	return pixel.r > 0.70 and pixel.b > 0.70 and pixel.g < 0.60

func _scan(name: String, image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var total := width * height
	var voids := 0
	var third := [0, 0, 0]
	var third_total := [0, 0, 0]
	var bands := 24
	var band_voids := PackedInt32Array()
	var band_total := PackedInt32Array()
	band_voids.resize(bands); band_voids.fill(0)
	band_total.resize(bands); band_total.fill(0)
	var top_row := -1
	var bottom_row := -1
	for y in height:
		var band := mini(bands - 1, y * bands / height)
		for x in width:
			var column := mini(2, x * 3 / width)
			var is_void: bool = _is_void(image.get_pixel(x, y))
			band_total[band] += 1
			third_total[column] += 1
			if is_void:
				voids += 1
				band_voids[band] += 1
				third[column] += 1
				if top_row < 0: top_row = y
				bottom_row = y
	print("VOID %-10s %5d/%6d = %5.2f%%  first_void_row=%d last_void_row=%d  L/M/R=%.1f%%/%.1f%%/%.1f%%" % [
		name, voids, total, 100.0 * float(voids) / float(total), top_row, bottom_row,
		100.0 * float(third[0]) / float(maxi(1, third_total[0])),
		100.0 * float(third[1]) / float(maxi(1, third_total[1])),
		100.0 * float(third[2]) / float(maxi(1, third_total[2]))])
	var profile := "  rows(24 bands, 0=top):"
	for band in bands:
		var share := 100.0 * float(band_voids[band]) / float(maxi(1, band_total[band]))
		profile += " %d:%.0f%%" % [band, share]
	print(profile)
	print(_map(image))

func _map(image: Image) -> String:
	var columns := 64
	var rows := 24
	var cell_w := maxi(1, image.get_width() / columns)
	var cell_h := maxi(1, image.get_height() / rows)
	var output := "  void map (# = hole in world, . = terrain/scenery):"
	for row in rows:
		var line := "\n  %02d " % row
		for column in columns:
			var x0 := column * cell_w
			var y0 := row * cell_h
			var voids := 0
			var samples := 0
			var y := y0
			while y < mini(y0 + cell_h, image.get_height()):
				var x := x0
				while x < mini(x0 + cell_w, image.get_width()):
					if _is_void(image.get_pixel(x, y)): voids += 1
					samples += 1
					x += 2
				y += 2
			line += "#" if samples > 0 and float(voids) / float(samples) > 0.5 else "."
		output += line
	return output
