extends Node3D
class_name CottageVisual

## Small procedural renderer for one authoritative building recipe. Geometry is
## disposable; IDs, states, anchors and revisions remain in BuildingWorld.

const WALL_COLOR := Color("#c99570")
const TRIM_COLOR := Color("#704c3e")
const ROOF_COLOR := Color("#a95843")
const STONE_COLOR := Color("#766c63")
const WINDOW_COLOR := Color("#ffd58b")
const FLOWER_COLOR := Color("#d56d65")

var applied_revision := -1
var requested_revision := -1
var building_id := ""

func request_revision(revision: int) -> void:
	requested_revision = maxi(requested_revision, revision)

func apply_building(view: Dictionary, source_revision: int) -> bool:
	if requested_revision < 0: requested_revision = source_revision
	if source_revision != requested_revision or source_revision < applied_revision: return false
	if view.is_empty(): return false
	for child in get_children(): child.free()
	building_id = str(view.get("id", ""))
	applied_revision = source_revision
	var dimensions: Vector3 = view.get("dimensions", Vector3(18, 10, 14))
	var transform_value = view.get("transform", Transform3D.IDENTITY)
	var building_transform: Transform3D = transform_value if transform_value is Transform3D else Transform3D.IDENTITY
	# Preserve the authored transform as a whole.  Rotation and scale are part
	# of the document identity and must affect every generated child equally.
	transform = building_transform
	_build_shell(dimensions, view)
	_build_details(view, dimensions)
	return true

func _build_shell(dimensions: Vector3, view: Dictionary) -> void:
	var material_id := str(view.get("material_id", "stone_plaster"))
	var wall_color := WALL_COLOR
	if material_id == "warm_plaster": wall_color = Color("#d5a982")
	elif material_id == "timber": wall_color = Color("#9c684d")
	elif material_id == "pale_stone": wall_color = Color("#b9aa96")
	_add_box("Foundation", Vector3(dimensions.x + 0.5, 0.6, dimensions.z + 0.5), Vector3(0, 0.3, 0), STONE_COLOR)
	var deleted := {}
	for surface_value in view.get("surfaces", []):
		var surface: Dictionary = surface_value
		if str(surface.get("kind", "wall")) == "wall": deleted[str(surface.get("orientation", ""))] = bool(surface.get("deleted", false))
	var wall_height := dimensions.y - 0.6
	if not bool(deleted.get("front", false)): _add_box("WallFront", Vector3(dimensions.x, wall_height, 0.28), Vector3(0, dimensions.y * 0.5 + 0.3, -dimensions.z * 0.5 + 0.14), wall_color)
	if not bool(deleted.get("back", false)): _add_box("WallBack", Vector3(dimensions.x, wall_height, 0.28), Vector3(0, dimensions.y * 0.5 + 0.3, dimensions.z * 0.5 - 0.14), wall_color)
	if not bool(deleted.get("left", false)): _add_box("WallLeft", Vector3(0.28, wall_height, dimensions.z), Vector3(-dimensions.x * 0.5 + 0.14, dimensions.y * 0.5 + 0.3, 0), wall_color)
	if not bool(deleted.get("right", false)): _add_box("WallRight", Vector3(0.28, wall_height, dimensions.z), Vector3(dimensions.x * 0.5 - 0.14, dimensions.y * 0.5 + 0.3, 0), wall_color)
	_add_box("FrontTrim", Vector3(dimensions.x + 0.2, 0.18, 0.22), Vector3(0, dimensions.y - 0.75, -dimensions.z * 0.5 - 0.08), TRIM_COLOR)
	_add_box("BackTrim", Vector3(dimensions.x + 0.2, 0.18, 0.22), Vector3(0, dimensions.y - 0.75, dimensions.z * 0.5 + 0.08), TRIM_COLOR)
	var roof_run := dimensions.z * 0.5 + 0.45
	var roof_angle := atan2(dimensions.y * 0.42, dimensions.z * 0.5)
	var roof_length := sqrt(roof_run * roof_run + (dimensions.y * 0.42) * (dimensions.y * 0.42))
	var left := _add_box("RoofLeft", Vector3(dimensions.x + 0.7, 0.35, roof_length), Vector3(0, dimensions.y + dimensions.y * 0.21, -roof_run * 0.5), ROOF_COLOR)
	left.rotation.x = -roof_angle
	var right := _add_box("RoofRight", Vector3(dimensions.x + 0.7, 0.35, roof_length), Vector3(0, dimensions.y + dimensions.y * 0.21, roof_run * 0.5), ROOF_COLOR)
	right.rotation.x = roof_angle
	_add_box("RidgeTrim", Vector3(dimensions.x + 0.8, 0.22, 0.24), Vector3(0, dimensions.y + dimensions.y * 0.42, 0), TRIM_COLOR)
	# The broad side door leaves the three front windows readable at cottage scale.
	_add_box("Door", Vector3(0.16, 6.5, 3.0), Vector3(-dimensions.x * 0.5 - 0.1, 3.55, 0), TRIM_COLOR)
	# The ridge follows X, so the stepped gable infill belongs on the two
	# narrow X ends. Derive each quarter-unit row from the actual roof triangle
	# so there are no teeth outside the slope or an open gap below the ridge.
	var eave_y := dimensions.y
	var rise := dimensions.y * 0.42
	var gable_run := dimensions.z * 0.5 + 0.45
	var row_height := 0.25
	var row_count := maxi(1, ceili(rise / row_height))
	for step in row_count:
		var level := eave_y + row_height * (float(step) + 0.5)
		var row_top := level + row_height * 0.5
		var ratio := clampf((row_top - eave_y) / rise, 0.0, 1.0)
		var span := maxf(0.12, gable_run * 2.0 * (1.0 - ratio) - 0.12)
		_add_box("GableLeft_%d" % step, Vector3(0.22, row_height + 0.015, span), Vector3(-dimensions.x * 0.5, level, 0), wall_color)
		_add_box("GableRight_%d" % step, Vector3(0.22, row_height + 0.015, span), Vector3(dimensions.x * 0.5, level, 0), wall_color)

func _build_details(view: Dictionary, dimensions: Vector3) -> void:
	var window_material := StandardMaterial3D.new()
	window_material.albedo_color = WINDOW_COLOR
	window_material.emission_enabled = true
	window_material.emission = Color(0.55, 0.28, 0.08)
	var surface_orientations := {}
	for surface_value in view.get("surfaces", []):
		var surface: Dictionary = surface_value
		surface_orientations[str(surface.get("id", ""))] = str(surface.get("orientation", "front"))
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("kind", "")) != "window" or not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)): continue
		var local = detail.get("resolved_position", null)
		if not local is Vector3: continue
		var anchor: Dictionary = detail.get("anchor", {})
		var surface_id := str(anchor.get("surface_id", ""))
		var orientation := str(surface_orientations.get(surface_id, "front"))
		var basis := Basis.IDENTITY
		if orientation == "front": basis = Basis(Vector3.UP, PI)
		elif orientation == "left": basis = Basis(Vector3.UP, -PI * 0.5)
		elif orientation == "right": basis = Basis(Vector3.UP, PI * 0.5)
		_build_window(detail, local, basis, window_material)
	for detail_value in view.get("details", []):
		var detail: Dictionary = detail_value
		if str(detail.get("kind", "")) != "flower_box" or not bool(detail.get("visible", true)) or bool(detail.get("needs_placement", false)): continue
		var local = detail.get("resolved_position", null)
		if local is Vector3:
			var anchor: Dictionary = detail.get("anchor", {})
			var orientation := str(surface_orientations.get(str(anchor.get("surface_id", "")), "front"))
			var basis := _surface_basis(orientation)
			var flower_box := _add_box("FlowerBox_%s" % str(detail.get("id", "")), Vector3(1.5, 0.22, 0.42), local + basis * Vector3(0, -0.8, -0.12), FLOWER_COLOR)
			flower_box.transform = Transform3D(basis, flower_box.position)

func _surface_basis(orientation: String) -> Basis:
	if orientation == "front": return Basis(Vector3.UP, PI)
	if orientation == "left": return Basis(Vector3.UP, -PI * 0.5)
	if orientation == "right": return Basis(Vector3.UP, PI * 0.5)
	return Basis.IDENTITY

func _add_box(node_name: String, size: Vector3, local_position: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.material_override = material
	node.position = local_position
	add_child(node)
	return node

func _build_window(detail: Dictionary, local: Vector3, basis: Basis, window_material: StandardMaterial3D) -> void:
	var node := MeshInstance3D.new()
	node.name = "Detail_%s" % str(detail.get("id", "window"))
	var asset := str(detail.get("asset_id", "window_wood"))
	if asset.contains("round"):
		var round_mesh := CylinderMesh.new(); round_mesh.top_radius = 0.54; round_mesh.bottom_radius = 0.54; round_mesh.height = 0.14; round_mesh.radial_segments = 16; node.mesh = round_mesh
	else:
		var window_mesh := BoxMesh.new(); window_mesh.size = Vector3(2.2, 3.0, 0.14); node.mesh = window_mesh
	var material := window_material.duplicate() as StandardMaterial3D
	if asset.contains("round"): material.albedo_color = Color("#e6ba70")
	node.material_override = material
	node.transform = Transform3D(basis, local)
	if asset.contains("round"): node.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	add_child(node)
	if not asset.contains("round"):
		var frame_color := TRIM_COLOR
		for side in [-1.0, 1.0]:
			var vertical := _add_box("Frame_%s_%s" % [str(detail.get("id", "")), str(side)], Vector3(0.14, 3.25, 0.18), local + basis * Vector3(side * 1.14, 0, -0.09), frame_color)
			vertical.transform = Transform3D(basis, vertical.position)
		for side in [-1.0, 1.0]:
			var horizontal := _add_box("Frame_%s_H%s" % [str(detail.get("id", "")), str(side)], Vector3(2.3, 0.14, 0.18), local + basis * Vector3(0, side * 1.59, -0.09), frame_color)
			horizontal.transform = Transform3D(basis, horizontal.position)
	if asset.contains("shutter"):
		_add_box("Shutter_%s_L" % str(detail.get("id", "")), Vector3(0.16, 3.1, 0.12), local + basis * Vector3(-1.22, 0, 0), TRIM_COLOR)
		_add_box("Shutter_%s_R" % str(detail.get("id", "")), Vector3(0.16, 3.1, 0.12), local + basis * Vector3(1.22, 0, 0), TRIM_COLOR)
