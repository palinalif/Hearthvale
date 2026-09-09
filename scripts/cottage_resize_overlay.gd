extends Control
## Presentation adapter: accepted screen-space candidates still own hit testing.
## The same candidate centres are displayed as small world-space spheres.
var handles: Array = []
var edges: Array = []
var hovered := ""
var grabbed := ""
var _world_root: Node3D
var _spheres: Dictionary = {}
var _sphere_mesh: SphereMesh
var _materials: Array[StandardMaterial3D] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visibility_changed.connect(_sync_visibility)

func attach_world(parent: Node3D) -> void:
	_world_root = Node3D.new()
	_world_root.name = "CottageResizeSpheres"
	parent.add_child(_world_root)
	_sphere_mesh = SphereMesh.new()
	_sphere_mesh.radius = 0.14
	_sphere_mesh.height = 0.28
	_sphere_mesh.radial_segments = 12
	_sphere_mesh.rings = 5
	for colour in [Color("#c1b18c"), Color("#f3edda"), Color("#edc27c")]:
		var material := StandardMaterial3D.new()
		material.albedo_color = colour
		material.roughness = 0.85
		# Preserve the prior overlay's visibility over terrain relief: accepted
		# facing/other-cottage filtering owns occlusion, including sunken targets.
		material.no_depth_test = true
		material.disable_receive_shadows = true
		material.render_priority = 10
		_materials.append(material)
	_sync_visibility()

func set_layout(next_handles: Array, next_edges: Array, next_hovered: String, next_grabbed: String) -> void:
	handles = next_handles
	edges = next_edges
	hovered = next_hovered
	grabbed = next_grabbed
	if not is_instance_valid(_world_root): return
	for sphere in _spheres.values(): sphere.visible = false
	for handle in handles:
		var id := str(handle["id"])
		if not _spheres.has(id):
			var sphere := MeshInstance3D.new()
			sphere.name = "Handle_" + id
			sphere.mesh = _sphere_mesh
			sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_world_root.add_child(sphere)
			_spheres[id] = sphere
		var sphere: MeshInstance3D = _spheres[id]
		var state := 2 if id == grabbed else (1 if id == hovered else 0)
		sphere.material_override = _materials[state]
		sphere.scale = Vector3.ONE * [1.0, 1.18, 1.3][state]
		sphere.global_position = handle["world"]
		sphere.visible = true
	_sync_visibility()

func _sync_visibility() -> void:
	if is_instance_valid(_world_root): _world_root.visible = is_visible_in_tree()

func _exit_tree() -> void:
	if is_instance_valid(_world_root): _world_root.queue_free()
