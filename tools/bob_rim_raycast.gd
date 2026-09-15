extends SceneTree

## Analytic ray-march of the hamlet review camera against the exact world geometry
## model (editable terrain height field + the outer valley floor function from the
## live scene script + the hill mounds as boxes). No scene boot, no rendering, so
## it answers "what SHOULD the frame show" in seconds and isolates whether a void
## in a render is a geometry gap or a rendering problem.
##
##   godot --headless --path . --script tools/bob_rim_raycast.gd

const Generator = preload("res://scripts/m1_patch_generator.gd")
const WorldScript = preload("res://scripts/m2_scene_upper_wall_details.gd")

const TARGET := Vector3(25.0, 10.0, 25.0)
const PITCH := 0.72
const DISTANCE := 42.0
const FOV_DEG := 52.0
const ASPECT := 1280.0 / 720.0
const COLUMNS := 64
const ROWS := 24
const DIRECTIONS := [
	["north", 0.0], ["northeast", -PI / 4.0], ["east", -PI / 2.0], ["southeast", -3.0 * PI / 4.0],
	["south", PI], ["southwest", 3.0 * PI / 4.0], ["west", PI / 2.0], ["northwest", PI / 4.0],
]

var world_script: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	world_script = WorldScript.new()
	for entry in DIRECTIONS:
		var name: String = entry[0]
		var yaw: float = entry[1]
		_scan(name, yaw)
	world_script.free()
	quit(0)

func _camera(yaw: float) -> Dictionary:
	var offset := Vector3(sin(yaw) * cos(PITCH), sin(PITCH), cos(yaw) * cos(PITCH)) * DISTANCE
	return {"position": TARGET + offset, "forward": (TARGET - (TARGET + offset)).normalized()}

func _scan(name: String, yaw: float) -> void:
	var camera := _camera(yaw)
	var position: Vector3 = camera["position"]
	var forward: Vector3 = camera["forward"]
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	var tan_v := tan(deg_to_rad(FOV_DEG * 0.5))
	var tan_h := tan_v * ASPECT
	var misses := 0
	var grid := ""
	for row in ROWS:
		var line := "\n  %02d " % row
		var v := 1.0 - 2.0 * (float(row) + 0.5) / float(ROWS)
		for column in COLUMNS:
			var u := -1.0 + 2.0 * (float(column) + 0.5) / float(COLUMNS)
			var direction := (forward + right * (u * tan_h) + up * (v * tan_v)).normalized()
			var hit := _march(position, direction)
			if not hit:
				misses += 1
				line += "#"
			else:
				line += "."
		grid += line
	print("RAYCAST %-10s yaw=%.3f cam=(%.1f,%.1f,%.1f) miss=%d/%d = %.2f%%" % [
		name, yaw, position.x, position.y, position.z, misses, COLUMNS * ROWS,
		100.0 * float(misses) / float(COLUMNS * ROWS)])
	print(grid)

## True if the ray reaches any world geometry before leaving the sampled volume.
func _march(origin: Vector3, direction: Vector3) -> bool:
	var t := 0.5
	var limit := 600.0
	while t < limit:
		var point := origin + direction * t
		if point.y < 0.0: return false
		if point.x > -140.0 and point.x < 188.0 and point.z > -140.0 and point.z < 188.0:
			var surface := _surface_height(point.x, point.z)
			if point.y <= surface: return true
		t += 0.6
	return false

func _surface_height(x: float, z: float) -> float:
	var inside := x > 0.0 and x < Generator.EXTENT.x and z > 0.0 and z < Generator.EXTENT.y
	if inside: return Generator.terrain_height(x, z)
	return world_script._outer_floor_height(x, z)
