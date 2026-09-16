extends "res://tests/m1_playtest_repair_render_test.gd"
## Measures the drift behind the failing
## "cancel restores the two-cottage image within raster tolerance" check.
var _baseline: Image

func _capture(name: String) -> Image:
	var image: Image = await super._capture(name)
	if name == "02-two-cottages-clean":
		_baseline = image
	if name == "06-colour-cancel-clean" and _baseline != null:
		var a: Image = image.duplicate()
		var b: Image = _baseline.duplicate()
		var changed := _changed_pixel_count(a, b)
		var da: PackedByteArray = a.get_data()
		var db: PackedByteArray = b.get_data()
		var max_delta := 0
		var gt12 := 0
		for off in range(0, mini(da.size(), db.size()) - 3, 4):
			var dmax := 0
			for k in 4:
				dmax = maxi(dmax, absi(da[off + k] - db[off + k]))
			if dmax > 12: gt12 += 1
			max_delta = maxi(max_delta, dmax)
		print("CANCEL_DRIFT changed_px=%d max_channel_delta=%d gt12px=%d" % [changed, max_delta, gt12])
	return image