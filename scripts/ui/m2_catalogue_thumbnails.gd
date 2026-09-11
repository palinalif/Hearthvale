extends Node

## One isolated renderer, one queued model at a time. Cached images do not
## render every frame and no preview model ever enters the gameplay world.
signal thumbnail_ready(id: String, texture: Texture2D)
const IMAGE_SIZE := Vector2i(160, 128)
const CACHE_LIMIT := 64
var cache: Dictionary = {}
var factory: Callable
var active := false
var rendered_count := 0
var _queue: Array[Dictionary] = []
var _viewport: SubViewport
var _camera: Camera3D
var _stage: Node3D
var _model: Node3D
var _current: Dictionary = {}
var _frames := 0

func _ready() -> void:
	set_process(false)
	if DisplayServer.get_name() == "headless": return
	_viewport = SubViewport.new()
	_viewport.size = IMAGE_SIZE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#3b4e44")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#d7e1f0")
	environment.environment.ambient_light_energy = 0.7
	_stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -30, 0)
	sun.light_color = Color("#fff1d8")
	sun.light_energy = 1.1
	_stage.add_child(sun)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.01
	_camera.far = 100
	_stage.add_child(_camera)
	_camera.make_current()

func request(items: Array[Dictionary]) -> void:
	active = true
	_queue.clear()
	for item in items:
		var id := str(item["id"])
		if cache.has(id): thumbnail_ready.emit(id, cache[id])
		elif str(_current.get("id", "")) != id: _queue.append(item)
	set_process(_viewport != null)

func stop() -> void:
	active = false
	_queue.clear()
	_current.clear()
	if _model:
		_model.queue_free()
		_model = null
	if _viewport: _viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)

func _process(_delta: float) -> void:
	if not active or not factory.is_valid(): return
	if _model:
		_frames += 1
		if _frames < 3: return
		var image := _viewport.get_texture().get_image()
		if not image.is_empty():
			var id := str(_current["id"])
			if cache.size() >= CACHE_LIMIT: cache.erase(cache.keys()[0])
			cache[id] = ImageTexture.create_from_image(image)
			rendered_count += 1
			thumbnail_ready.emit(id, cache[id])
		_stage.remove_child(_model)
		_model.queue_free()
		_model = null
		_current.clear()
	if _queue.is_empty():
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		set_process(false)
		return
	_current = _queue.pop_front()
	_model = factory.call(_current) as Node3D
	if not _model: return
	_stage.add_child(_model)
	var bounds := _bounds(_model, Transform3D.IDENTITY)
	var centre := bounds.get_center()
	# Frame every visible corner in camera coordinates, including deep bays.
	_camera.look_at_from_position(centre + Vector3(0.45, 0.25, 1).normalized() * 20, centre)
	var inverse := _camera.global_transform.affine_inverse()
	var extent := Vector2.ZERO
	for i in 8:
		var point := inverse * bounds.get_endpoint(i)
		extent.x = maxf(extent.x, absf(point.x))
		extent.y = maxf(extent.y, absf(point.y))
	_camera.size = maxf(0.2, maxf(extent.y * 2, extent.x * 2 * IMAGE_SIZE.y / IMAGE_SIZE.x) * 1.15)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_frames = 0

func _bounds(node: Node3D, parent_transform: Transform3D) -> AABB:
	var transform_value := parent_transform * node.transform
	var result := AABB()
	var first := true
	if node is VisualInstance3D:
		result = transform_value * (node as VisualInstance3D).get_aabb()
		first = false
	for child in node.get_children():
		if not child is Node3D or not (child as Node3D).visible: continue
		var box := _bounds(child, transform_value)
		if box.size == Vector3.ZERO: continue
		result = box if first else result.merge(box)
		first = false
	return result
