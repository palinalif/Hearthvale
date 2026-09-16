extends "res://tests/cottage_detail_render_test.gd"
## Measures the real repeat-capture drift (03 vs 04) without changing the gate.
var _capture_a: Image

func _capture(name: String) -> Image:
	var image: Image = await super._capture(name)
	if name == "03-detail-families":
		_capture_a = image
	if name == "04-repeat-stability" and _capture_a != null:
		var a: Image = _capture_a.duplicate()
		var b: Image = image.duplicate()
		var da: PackedByteArray = a.get_data()
		var db: PackedByteArray = b.get_data()
		print("DRIFT_MEASURE sizes a=%dx%d b=%dx%d bytes_a=%d bytes_b=%d" % [a.get_width(), a.get_height(), b.get_width(), b.get_height(), da.size(), db.size()])
		var changed_px := _changed_pixel_count(a, b)
		var max_delta := 0
		var small := 0
		var mid := 0
		var big := 0
		for off in range(0, mini(da.size(), db.size()) - 3, 4):
			var dmax := 0
			for k in 4:
				dmax = maxi(dmax, absi(da[off + k] - db[off + k]))
			if dmax > 0:
				if dmax <= 3: small += 1
				elif dmax <= 12: mid += 1
				else: big += 1
				max_delta = maxi(max_delta, dmax)
		print("DRIFT_MEASURE changed_px=%d max_channel_delta=%d deltas_le3=%d le12=%d gt12=%d" % [changed_px, max_delta, small, mid, big])
	return image