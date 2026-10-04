extends SceneTree
## Authored starter-hamlet prop assets: the .vox sources, the baked runtime
## meshes, the receipts that tie them together, and parity with the prop
## catalogue the hamlet places. No player save is opened.

const Props = preload("res://scripts/m2_starter_props.gd")
const UNIT := 0.125
const TRIANGLE_CEILING := 8000
const NAMES := {
	"well": "hearthvale_prop_village_well",
	"chopping_block": "hearthvale_prop_chopping_block",
	"log_stack": "hearthvale_prop_log_stack",
}

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += (indices.size() / 3) if indices.size() > 0 else (vertices.size() / 3)
	return total

func _run() -> void:
	for style: String in NAMES:
		var name: String = NAMES[style]
		var source := "res://assets/source/magicavoxel/%s.vox" % name
		var asset := "res://assets/models/magicavoxel/%s" % name
		var definition: Dictionary = Props.DEFINITIONS.get(style, {})

		_check(not definition.is_empty(), "%s has a prop catalogue entry" % style)
		_check(FileAccess.file_exists(source), "%s source is tracked" % name)
		if not FileAccess.file_exists(source):
			continue

		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source)
		_check(bytes.size() > 8 and bytes.slice(0, 4).get_string_from_ascii() == "VOX ", "%s is a MagicaVoxel file" % name)
		var format: int = bytes.decode_u32(4) if bytes.size() > 8 else 0
		_check(format == 150, "%s uses the format the pipeline reads (got %d)" % [name, format])

		var mesh := load(asset + ".res") as Mesh
		_check(mesh != null, "%s bakes to a runtime mesh" % name)
		if mesh == null:
			continue

		_check(FileAccess.file_exists(asset + ".asset.json"), "%s carries a bake receipt" % name)
		var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(asset + ".asset.json"))
		_check(receipt is Dictionary, "%s receipt parses" % name)
		if not (receipt is Dictionary):
			continue
		var record: Dictionary = receipt

		_check(str(record.get("source", "")) == "%s.vox" % name, "%s receipt names its source" % name)
		_check(str(record.get("source_sha256", "")) == FileAccess.get_sha256(source), "%s provenance matches source bytes" % name)
		_check(is_equal_approx(float(record.get("voxel_unit", 0.0)), UNIT), "%s receipt declares the 0.125 structural grid" % name)

		var declared: Array = record.get("declared_dimensions", [])
		_check(declared.size() == 3, "%s receipt declares dimensions" % name)
		if declared.size() == 3:
			var size: Vector2 = definition.get("size", Vector2.ZERO)
			# declared_dimensions is in Godot axes (x, height, depth): the bake maps the
			# voxel file's vertical axis onto Godot Y. The catalogue footprint is width
			# and depth, so it pairs with declared[0] and declared[2].
			_check(absf(float(declared[0]) * UNIT - size.x) <= UNIT, "%s declared width matches its catalogue footprint" % name)
			_check(absf(float(declared[2]) * UNIT - size.y) <= UNIT, "%s declared depth matches its catalogue footprint" % name)
			for axis in 3:
				var cells := float(declared[axis])
				_check(cells >= 1.0 and absf(cells - roundf(cells)) < 0.001, "%s dimension %d is a whole number of cells" % [name, axis + 1])

		var box := mesh.get_aabb()
		_check(absf(box.position.y) < 0.0001, "%s mesh pivots on the ground" % name)
		_check(box.size.x > 0.0 and box.size.y > 0.0 and box.size.z > 0.0, "%s mesh has volume" % name)
		_check(mesh.get_surface_count() >= 2, "%s keeps its authored palette groups" % name)

		var triangles := _triangles(mesh)
		_check(triangles > 0 and triangles <= TRIANGLE_CEILING, "%s stays within the prop triangle budget (%d)" % [name, triangles])
		_check(triangles == int(record.get("triangles", -1)), "%s triangle count matches its receipt" % name)

	_check(Props.ORDER.size() == NAMES.size(), "the catalogue places exactly the authored starter props")

	print("M2_STARTER_PROP_ASSET checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures:
		print("M2_STARTER_PROP_ASSET_FAIL " + failure)
	quit(0 if failures.is_empty() else 1)
