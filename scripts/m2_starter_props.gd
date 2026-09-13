extends RefCounted
## Original, deterministic miniature props. Every dimension and step is an
## integer multiple of the decorative 1/16-unit cell. Coplanar runs are merged.
const CELL := 0.0625
const COLOURS := {
	"well": [Color("#a89d85"), Color("#665f51"), Color("#79583e"), Color("#64715b")],
	"chopping_block": [Color("#654937"), Color("#bda073"), Color("#8c6747"), Color("#9caaa6")],
	"log_stack": [Color("#674b36"), Color("#b39468"), Color("#493d30"), Color("#867050")],
}
const DEFINITIONS := {
	"well": {"name": "Village well", "size": Vector2(2.5, 2.25), "summary": "Stone well, timber roof, winding beam and hanging bucket"},
	"chopping_block": {"name": "Axe and chopping block", "size": Vector2(1.0, 1.0), "summary": "Barked stump with a pale cut face and embedded axe"},
	"log_stack": {"name": "Stacked firewood", "size": Vector2(1.5, 1.0), "summary": "Split logs stacked beside a cottage or woodcutting corner"},
}
const ORDER: Array[String] = ["well", "chopping_block", "log_stack"]

static func append(visual: Node, builder: Dictionary, center: Vector3, basis: Basis, style: String) -> void:
	match style:
		"well": _well(visual, builder, center, basis)
		"chopping_block": _chopping_block(visual, builder, center, basis)
		"log_stack": _logs(visual, builder, center, basis)

static func _box(visual: Node, builder: Dictionary, center: Vector3, basis: Basis, p: Vector3, dimensions: Vector3, material: int) -> void:
	# p and dimensions are specified in cells, not independently scaled assets.
	var corner := (p - dimensions * 0.5).floor()
	var snapped_center := corner + dimensions * 0.5
	visual.call("_append_box", builder, center + basis * (snapped_center * CELL), dimensions * CELL, basis, material)

static func _well(visual: Node, builder: Dictionary, center: Vector3, basis: Basis) -> void:
	# An open stepped circular stone ring, not a solid cylinder.
	for z in range(-10, 10):
		var outer := floori(sqrt(maxf(0.0, 100.0 - pow(float(z) + 0.5, 2.0))))
		var inner := floori(sqrt(maxf(0.0, 49.0 - pow(float(z) + 0.5, 2.0))))
		if outer < 1: continue
		for side in [-1, 1]:
			var width := outer - inner
			if width < 1: continue
			for course in 4:
				var colour := 1 if course == 0 else 0
				_box(visual, builder, center, basis, Vector3(float(side) * (float(inner) + float(width) * 0.5), float(course * 3) + 1.5, float(z) + 0.5), Vector3(width, 3, 1), colour)
	# Dark recessed water is part of the prop, not simulated scene water.
	_box(visual, builder, center, basis, Vector3(0, 3, 0), Vector3(12, 1, 12), 1)
	for x in [-12, 12]:
		_box(visual, builder, center, basis, Vector3(x, 20, 0), Vector3(3, 40, 3), 2)
	_box(visual, builder, center, basis, Vector3(0, 33, 0), Vector3(29, 2, 2), 2)
	_box(visual, builder, center, basis, Vector3(0, 23, 0), Vector3(1, 20, 1), 1)
	_box(visual, builder, center, basis, Vector3(0, 14, 0), Vector3(5, 5, 5), 2)
	_box(visual, builder, center, basis, Vector3(0, 16.5, 0), Vector3(6, 1, 6), 1)
	# Fine stepped pitched canopy with a separate ridge and timber fascia.
	for z in range(-16, 16):
		var y := 43.0 - floorf(absf(float(z) + 0.5) * 0.5)
		_box(visual, builder, center, basis, Vector3(0, y, float(z) + 0.5), Vector3(34, 2, 1), 3)
	_box(visual, builder, center, basis, Vector3(0, 44, 0), Vector3(36, 2, 2), 2)
	for z in [-16, 16]:
		_box(visual, builder, center, basis, Vector3(0, 35, z), Vector3(36, 2, 2), 2)
	# Small crank attached to the right end of the winding beam.
	_box(visual, builder, center, basis, Vector3(16, 31, 0), Vector3(2, 6, 2), 1)
	_box(visual, builder, center, basis, Vector3(18, 28, 0), Vector3(4, 2, 2), 2)

static func _chopping_block(visual: Node, builder: Dictionary, center: Vector3, basis: Basis) -> void:
	for z in range(-5, 5):
		var half_width := floori(sqrt(maxf(0.0, 25.0 - pow(float(z) + 0.5, 2.0))))
		if half_width < 1: continue
		_box(visual, builder, center, basis, Vector3(0, 4, float(z) + 0.5), Vector3(half_width * 2, 8, 1), 0)
		_box(visual, builder, center, basis, Vector3(0, 8.5, float(z) + 0.5), Vector3(maxi(1, half_width * 2 - 2), 1, 1), 1)
	# A stepped diagonal handle; voxels stay cubic rather than being sheared.
	for y in range(8, 21):
		_box(visual, builder, center, basis, Vector3(floorf(float(y - 8) / 3.0), float(y) + 0.5, 0), Vector3(1, 1, 1), 2)
	for y in range(9, 13):
		var width := 6 - (y - 9)
		_box(visual, builder, center, basis, Vector3(-float(width) * 0.5, float(y) + 0.5, 0), Vector3(width, 1, 2), 3)

static func _logs(visual: Node, builder: Dictionary, center: Vector3, basis: Basis) -> void:
	for layer in 3:
		for index in range(3 - layer):
			var x := float(index * 7 + layer * 3 - 7)
			var y := float(layer * 5 + 3)
			_box(visual, builder, center, basis, Vector3(x, y, 0), Vector3(6, 4, 12), 0)
			_box(visual, builder, center, basis, Vector3(x, y, 0), Vector3(4, 6, 12), 0)
			for z in [-6, 6]:
				_box(visual, builder, center, basis, Vector3(x, y, z), Vector3(4, 4, 1), 1)
