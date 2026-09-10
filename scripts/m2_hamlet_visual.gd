extends "res://scripts/m2_composition_visual.gd"
class_name M2HamletVisual

## Street-furniture presentation layered over the shared bridge/garden/fence
## renderer. No lights or simulation live here: these are deliberately cheap,
## fine voxel miniatures rebuilt from saved composition records.

const FURNITURE_COLOURS := {
	"bench": [Color("#7d5b43"), Color("#594337"), Color("#9a795c"), Color("#6b6f64")],
	"lantern": [Color("#454a47"), Color("#655344"), Color("#d7a85e"), Color("#8c765c")],
	"signpost": [Color("#72543f"), Color("#4e3d32"), Color("#967556"), Color("#d1c29b")],
	"barrel_planter": [Color("#79563f"), Color("#4b514d"), Color("#527050"), Color("#c89591")],
}

var _furniture_nodes: Array[MeshInstance3D] = []
var _furniture_preview_node: MeshInstance3D
var _furniture_count := 0
var _furniture_geometry_cells := 0

func rebuild_furniture(composition_values: Array, terrain_backend: Node = null) -> void:
	if terrain_backend != null: backend = terrain_backend
	for node in _furniture_nodes:
		if is_instance_valid(node): node.queue_free()
	_furniture_nodes.clear()
	var builders := {}
	for style_id in FURNITURE_COLOURS: builders[style_id] = _new_builder(4)
	_furniture_count = 0
	_furniture_geometry_cells = 0
	for value in composition_values:
		if not value is Dictionary: continue
		var record: Dictionary = value
		if str(record.get("kind", "")) != "furniture": continue
		var style_id := str(record.get("style_id", ""))
		if not builders.has(style_id): continue
		_append_furniture(builders[style_id], record)
		_furniture_count += 1
	for style_id in FURNITURE_COLOURS:
		var builder: Dictionary = builders[style_id]
		_furniture_geometry_cells += _builder_cell_count(builder)
		var mesh := _mesh_from_builder(builder, FURNITURE_COLOURS[style_id])
		if mesh == null: continue
		var node := MeshInstance3D.new()
		node.name = "FurnitureBatch_" + style_id
		node.mesh = mesh
		add_child(node)
		_furniture_nodes.append(node)

func show_furniture_preview(style_id: String, point: Vector2, size: Vector2, yaw_quarters: int, valid: bool) -> void:
	hide_furniture_preview()
	if not FURNITURE_COLOURS.has(style_id) or not point.is_finite(): return
	var record := {"kind": "furniture", "style_id": style_id, "position": [point.x, point.y], "size": [size.x, size.y], "yaw_quarters": posmod(yaw_quarters, 4)}
	var builder := _new_builder(4)
	_append_furniture(builder, record)
	var mesh := _mesh_from_builder(builder, _preview_colours(FURNITURE_COLOURS[style_id], valid), true)
	if mesh == null: return
	_furniture_preview_node = MeshInstance3D.new()
	_furniture_preview_node.name = "FurniturePreview"
	_furniture_preview_node.mesh = mesh
	_furniture_preview_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_furniture_preview_node)

func hide_furniture_preview() -> void:
	if is_instance_valid(_furniture_preview_node): _furniture_preview_node.queue_free()
	_furniture_preview_node = null

func stats() -> Dictionary:
	var result: Dictionary = super.stats()
	result["furniture_count"] = _furniture_count
	result["furniture_geometry_cells"] = _furniture_geometry_cells
	result["geometry_cells"] = int(result.get("geometry_cells", 0)) + _furniture_geometry_cells
	return result

func _append_furniture(builder: Dictionary, record: Dictionary) -> void:
	var style_id := str(record.get("style_id", ""))
	var point := _point(record.get("position", []))
	if not point.is_finite(): return
	var basis := Basis(Vector3.UP, float(posmod(int(record.get("yaw_quarters", 0)), 4)) * PI * 0.5)
	var center := Vector3(point.x, _surface_height(point), point.y)
	match style_id:
		"bench": _append_bench(builder, center, basis)
		"lantern": _append_lantern(builder, center, basis)
		"signpost": _append_signpost(builder, center, basis)
		"barrel_planter": _append_barrel_planter(builder, center, basis)

func _append_bench(builder: Dictionary, center: Vector3, basis: Basis) -> void:
	# Narrow slats and separate supports make the silhouette read at normal
	# miniature distance without turning the bench into one oversized brown cube.
	for x in [-0.56, 0.56]:
		for z in [-0.18, 0.18]:
			_append_box(builder, center + basis * Vector3(x, 0.19, z), Vector3(0.09, 0.38, 0.09), basis, 1)
	for z in [-0.16, 0.0, 0.16]:
		_append_box(builder, center + basis * Vector3(0, 0.40, z), Vector3(1.38, 0.075, 0.12), basis, 0 if z != 0.0 else 2)
	for x in [-0.56, 0.56]:
		_append_box(builder, center + basis * Vector3(x, 0.68, 0.23), Vector3(0.08, 0.58, 0.08), basis, 1)
	for y in [0.60, 0.78]:
		_append_box(builder, center + basis * Vector3(0, y, 0.24), Vector3(1.38, 0.075, 0.09), basis, 2)

func _append_lantern(builder: Dictionary, center: Vector3, basis: Basis) -> void:
	_append_box(builder, center + Vector3.UP * 0.05, Vector3(0.30, 0.10, 0.30), basis, 1)
	_append_box(builder, center + Vector3.UP * 0.66, Vector3(0.10, 1.22, 0.10), basis, 0)
	_append_box(builder, center + basis * Vector3(0.10, 1.24, 0), Vector3(0.26, 0.075, 0.075), basis, 0)
	_append_box(builder, center + basis * Vector3(0.20, 1.10, 0), Vector3(0.24, 0.32, 0.24), basis, 1)
	_append_box(builder, center + basis * Vector3(0.20, 1.10, 0), Vector3(0.14, 0.20, 0.14), basis, 2)
	_append_box(builder, center + basis * Vector3(0.20, 1.29, 0), Vector3(0.30, 0.07, 0.30), basis, 3)

func _append_signpost(builder: Dictionary, center: Vector3, basis: Basis) -> void:
	_append_box(builder, center + Vector3.UP * 0.58, Vector3(0.11, 1.16, 0.11), basis, 1)
	_append_box(builder, center + Vector3.UP * 1.17, Vector3(0.20, 0.08, 0.20), basis, 3)
	var board_a := basis * Basis(Vector3.UP, deg_to_rad(6.0))
	var board_b := basis * Basis(Vector3.UP, deg_to_rad(-18.0))
	_append_box(builder, center + basis * Vector3(0.27, 0.93, 0), Vector3(0.72, 0.18, 0.09), board_a, 0)
	_append_box(builder, center + basis * Vector3(-0.22, 0.72, 0), Vector3(0.62, 0.17, 0.09), board_b, 2)
	# Tiny pale end caps hint at painted lettering without adding illegible text.
	_append_box(builder, center + basis * Vector3(0.52, 0.93, -0.052), Vector3(0.12, 0.055, 0.025), board_a, 3)
	_append_box(builder, center + basis * Vector3(-0.43, 0.72, -0.052), Vector3(0.10, 0.05, 0.025), board_b, 3)

func _append_barrel_planter(builder: Dictionary, center: Vector3, basis: Basis) -> void:
	# A stepped square barrel keeps the voxel language while giving it enough
	# profile variation to avoid reading as a generic crate.
	_append_box(builder, center + Vector3.UP * 0.20, Vector3(0.56, 0.40, 0.56), basis, 0)
	_append_box(builder, center + Vector3.UP * 0.11, Vector3(0.60, 0.065, 0.60), basis, 1)
	_append_box(builder, center + Vector3.UP * 0.31, Vector3(0.60, 0.065, 0.60), basis, 1)
	_append_box(builder, center + Vector3.UP * 0.41, Vector3(0.52, 0.055, 0.52), basis, 1)
	for index in 7:
		var angle := float(index) * TAU / 7.0
		var radius := 0.12 + 0.07 * float(index % 2)
		var local := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		var h := 0.20 + 0.07 * float(index % 3)
		_append_box(builder, center + basis * local + Vector3.UP * (0.43 + h * 0.5), Vector3(0.09, h, 0.09), basis, 2)
		if index % 2 == 0:
			_append_box(builder, center + basis * local + Vector3.UP * (0.46 + h), Vector3(0.10, 0.07, 0.10), basis, 3)
