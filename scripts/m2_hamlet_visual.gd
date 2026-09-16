extends "res://scripts/m2_composition_visual.gd"
class_name M2HamletVisual

## Street-furniture presentation layered over the shared bridge/garden/fence
## renderer. Authority remains in compact composition records. Planters use real
## baked MagicaVoxel assets; other furniture retains its existing presentation.

const StarterProps = preload("res://scripts/m2_starter_props.gd")
const Planters = preload("res://scripts/m2_planter_assets.gd")
const FURNITURE_COLOURS := {
	"well": StarterProps.COLOURS["well"],
	"chopping_block": StarterProps.COLOURS["chopping_block"],
	"log_stack": StarterProps.COLOURS["log_stack"],
	"bench": [Color("#7d5b43"), Color("#594337"), Color("#9a795c"), Color("#6b6f64")],
	"village_table": [Color("#7d5b43"), Color("#594337"), Color("#9a795c"), Color("#6b6f64")],
	"lantern": [Color("#454a47"), Color("#655344"), Color("#d7a85e"), Color("#8c765c")],
	"signpost": [Color("#72543f"), Color("#4e3d32"), Color("#967556"), Color("#d1c29b")],
	"barrel_planter": Planters.SWATCHES,
	"barrel_planter_herbs": Planters.SWATCHES,
	"barrel_planter_light": Planters.SWATCHES,
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
	_furniture_count = 0
	_furniture_geometry_cells = 0
	for value in composition_values:
		if not value is Dictionary: continue
		var record: Dictionary = value
		if str(record.get("kind", "")) != "furniture": continue
		var style_id := str(record.get("style_id", ""))
		if not FURNITURE_COLOURS.has(style_id): continue
		if not _point(record.get("position", [])).is_finite(): continue
		var authored := Planters.has_style(style_id)
		var mesh: ArrayMesh
		if authored:
			mesh = Planters.mesh_for(style_id, str(record.get("colour_id", "")))
			_furniture_geometry_cells += int(Planters.VOXEL_COUNTS[style_id])
		else:
			var builder := _new_builder(4)
			_append_furniture(builder, record)
			_furniture_geometry_cells += _builder_cell_count(builder)
			mesh = _mesh_from_builder(builder, _record_colours(FURNITURE_COLOURS[style_id], record))
		if mesh == null: continue
		var node := MeshInstance3D.new()
		node.name = "Furniture_%s" % int(record.get("id", 0))
		node.set_meta("composition_id", int(record.get("id", 0)))
		node.mesh = mesh
		if authored:
			node.transform = _planter_transform(record)
			node.set_meta("authored_asset", Planters.PATHS[style_id])
		add_child(node)
		_furniture_nodes.append(node)
		_furniture_count += 1

func show_furniture_preview(style_id: String, point: Vector2, size: Vector2, yaw_degrees: float, valid: bool, colour_id: String = "") -> void:
	hide_furniture_preview()
	if not FURNITURE_COLOURS.has(style_id) or not point.is_finite(): return
	var record := {"kind": "furniture", "style_id": style_id, "position": [point.x, point.y], "size": [size.x, size.y], "yaw_quarters": posmod(roundi(yaw_degrees / 90.0), 4), "yaw_degrees": fposmod(yaw_degrees, 360.0)}
	var authored := Planters.has_style(style_id)
	var mesh: ArrayMesh
	if authored:
		mesh = Planters.mesh_for(style_id, colour_id, true, valid)
	else:
		var builder := _new_builder(4)
		_append_furniture(builder, record)
		mesh = _mesh_from_builder(builder, _preview_colours(FURNITURE_COLOURS[style_id], valid), true)
	if mesh == null: return
	_furniture_preview_node = MeshInstance3D.new()
	_furniture_preview_node.name = "FurniturePreview"
	_furniture_preview_node.mesh = mesh
	_furniture_preview_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if authored:
		_furniture_preview_node.transform = _planter_transform(record)
		_furniture_preview_node.set_meta("authored_asset", Planters.PATHS[style_id])
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

func _planter_transform(record: Dictionary) -> Transform3D:
	var point := _point(record.get("position", []))
	var fallback_yaw := float(posmod(int(record.get("yaw_quarters", 0)), 4)) * 90.0
	var yaw := fposmod(float(record.get("yaw_degrees", fallback_yaw)), 360.0)
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), Vector3(point.x, _surface_height(point), point.y))

func _append_furniture(builder: Dictionary, record: Dictionary) -> void:
	var style_id := str(record.get("style_id", ""))
	var point := _point(record.get("position", []))
	if not point.is_finite(): return
	var yaw_degrees := float(posmod(int(record.get("yaw_quarters", 0)), 4)) * 90.0
	if record.has("yaw_degrees"): yaw_degrees = fposmod(float(record.get("yaw_degrees", 0.0)), 360.0)
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_degrees))
	var center := Vector3(point.x, _surface_height(point), point.y)
	match style_id:
		"bench": _append_bench(builder, center, basis)
		"village_table": _append_village_table(builder, center, basis)
		"lantern": _append_lantern(builder, center, basis)
		"signpost": _append_signpost(builder, center, basis)
		"well", "chopping_block", "log_stack": StarterProps.append(self, builder, center, basis, style_id)

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

func _append_village_table(builder: Dictionary, center: Vector3, basis: Basis) -> void:
	# A square gathering table with backless benches on either side, reusing the
	# bench's slatted timber palette and seat height so the set reads as one family.
	for x in [-0.5, 0.5]:
		for z in [-0.5, 0.5]:
			_append_box(builder, center + basis * Vector3(x, 0.235, z), Vector3(0.1, 0.47, 0.1), basis, 1)
	_append_box(builder, center + basis * Vector3(0, 0.52, 0), Vector3(1.25, 0.1, 1.25), basis, 2)
	for z in [-0.95, 0.95]:
		for x in [-0.48, 0.48]:
			_append_box(builder, center + basis * Vector3(x, 0.2, z), Vector3(0.08, 0.4, 0.08), basis, 1)
		for dz in [-0.09, 0.09]:
			_append_box(builder, center + basis * Vector3(0, 0.42, z + dz), Vector3(1.15, 0.075, 0.14), basis, 0)

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
