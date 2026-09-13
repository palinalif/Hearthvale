extends SceneTree
## Pure boundary sweep plus the actual shipped scene's camera method, without
## starting native terrain or opening any player checkpoint directory.
const Boundary = preload("res://scripts/m2_camera_boundary.gd")
var failures := 0
var checks := 0

class ExtentBackend extends Node:
	var extent := Vector3(64.0, 32.0, 64.0)
	func world_size() -> Vector3:
		return extent

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for extent: Vector3 in [Vector3(64, 32, 64), Vector3(48, 32, 48), Vector3(24, 32, 40), Vector3(0.2, 1, 0.3)]:
		for fx: float in [0.0, 0.01, 0.5, 0.99, 1.0]:
			for fz: float in [0.0, 0.01, 0.5, 0.99, 1.0]:
				var target := Vector3(extent.x * fx, 10.0, extent.z * fz)
				for turn in 24:
					var yaw := float(turn) * TAU / 24.0
					for pitch: float in [0.08, 0.66, 1.4]:
						for distance: float in [3.5, 28.0, 36.0, 64.0]:
							var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
							var bounded := Boundary.frame(target, offset, extent)
							var position: Vector3 = bounded["position"]
							_check(position.is_finite() and position.x >= 0.0 and position.x <= extent.x and position.z >= 0.0 and position.z <= extent.z, "camera stays in native extent")
							_check((bounded["target"] as Vector3).is_equal_approx(target), "in-bounds focus is not translated")
							var repeated := Boundary.frame(target, position - target, extent)
							_check((repeated["position"] as Vector3).is_equal_approx(position), "constraint is idempotent")
	var interior := Boundary.frame(Vector3(32, 10, 32), Vector3(3, 4, 5), Vector3(64, 32, 64))
	_check((interior["position"] as Vector3).is_equal_approx(Vector3(35, 14, 37)), "ordinary interior orbit unchanged")
	for target: Vector3 in [Vector3(NAN, NAN, NAN), Vector3.INF, Vector3(-1000, 10, 1000)]:
		var bounded := Boundary.frame(target, Vector3.INF, Vector3.ZERO)
		_check((bounded["position"] as Vector3).is_finite() and (bounded["target"] as Vector3).is_finite(), "invalid input recovers to finite camera")
	var scene: Node = load("res://scenes/m1.tscn").instantiate()
	var backend := ExtentBackend.new()
	var camera := Camera3D.new()
	root.add_child(camera)
	scene.camera = camera
	scene.backend = backend
	for extent: Vector3 in [Vector3(48, 32, 48), Vector3(64, 32, 64)]:
		backend.extent = extent
		for context: String in ["terrain", "building", "placement"]:
			scene.view_context = "building" if context == "placement" else context
			scene.building_placement_active = context == "placement"
			scene._free_camera_valid = false
			for corner: Vector3 in [Vector3(1, 8, 1), Vector3(extent.x - 1, 8, 1), Vector3(1, 8, extent.z - 1), Vector3(extent.x - 1, 8, extent.z - 1)]:
				scene.cursor = corner
				scene.cottage_cursor = corner + Vector3.UP * 2.0
				var target := corner + Vector3.UP * 2.0
				for turn in 24:
					scene.camera_yaw = float(turn) * TAU / 24.0
					scene.camera_pitch = 0.66
					scene.camera_distance = 36.0
					scene._update_camera()
					var position := camera.position
					_check(position.x >= 0.0 and position.x <= extent.x and position.z >= 0.0 and position.z <= extent.z, "shipped scene enforces actual backend bounds")
					_check((-camera.global_basis.z).normalized().dot((target - camera.global_position).normalized()) > 0.999, "shipped scene retains subject focus at boundary")
					_check((scene.cursor as Vector3).is_equal_approx(corner), "boundary does not move edit cursor")
					_check(is_equal_approx(float(scene.camera_distance), 36.0), "desired zoom is retained")
	if failures:
		var layer: Script = scene.get_script()
		while layer != null:
			if layer.get_source_code().contains("func _update_camera()"):
				print("CAMERA_OVERRIDE: " + layer.resource_path)
			layer = layer.get_base_script()
	scene.camera = null
	scene.backend = null
	scene.free()
	backend.free()
	camera.queue_free()
	await process_frame
	print(JSON.stringify({"ok": failures == 0, "failures": failures, "checks": checks, "camera_boundary": true}))
	quit(1 if failures else 0)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	if failures <= 20: print("FAIL: " + label)
