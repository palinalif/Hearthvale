extends "res://scripts/m1_scene_terrain_ux.gd"
## Thor playtest follow-up: gentler Raise/Dig defaults, overhang-aware aiming,
## and a stable camera target while a sculpt stroke changes surface height.

const RAISE_DIG_DEFAULT_LEVEL := 3
const SMOOTH_DEFAULT_LEVEL := 5
var _tool_strength_levels := {"raise": RAISE_DIG_DEFAULT_LEVEL, "dig": RAISE_DIG_DEFAULT_LEVEL, "smooth": SMOOTH_DEFAULT_LEVEL, "level": RAISE_DIG_DEFAULT_LEVEL, "slope": RAISE_DIG_DEFAULT_LEVEL}
var _stroke_camera_target := Vector3.ZERO
var _stroke_camera_target_valid := false

func _ready() -> void:
	# The exported scene starts on Raise. Keep Smooth at its playtested strength
	# while making destructive/additive sculpting calmer by default.
	brush_strength_level = int(_tool_strength_levels.get(sculpt_tool, RAISE_DIG_DEFAULT_LEVEL))
	brush_strength = StrengthScale.rate(brush_strength_level)
	super._ready()

func _set_sculpt_tool(tool: String) -> bool:
	_tool_strength_levels[sculpt_tool] = brush_strength_level
	var changed := super._set_sculpt_tool(tool)
	if changed:
		var desired := int(_tool_strength_levels.get(sculpt_tool, SMOOTH_DEFAULT_LEVEL if sculpt_tool == "smooth" else RAISE_DIG_DEFAULT_LEVEL))
		set_brush_strength_level(desired)
	return changed

func set_brush_strength_level(level: int) -> void:
	super.set_brush_strength_level(level)
	_tool_strength_levels[sculpt_tool] = brush_strength_level

func _begin_stroke() -> void:
	super._begin_stroke()
	if stroke_active:
		_stroke_camera_target = cursor + Vector3(0, 2, 0)
		_stroke_camera_target_valid = true

func _end_stroke() -> void:
	super._end_stroke()
	_stroke_camera_target_valid = false

func _cancel_current_edit(reason: String) -> void:
	super._cancel_current_edit(reason)
	_stroke_camera_target_valid = false

func _update_camera() -> void:
	if not camera: return
	if stroke_active and _stroke_camera_target_valid and view_context == "terrain":
		var offset := Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch)) * camera_distance
		camera.position = _stroke_camera_target + offset
		camera.look_at(_stroke_camera_target, Vector3.UP)
		return
	super._update_camera()

func _find_local_surface(center: Vector3, normal: Vector3, scale_value: float) -> Dictionary:
	var direct := super._find_local_surface(center, normal, scale_value)
	if not backend or not backend.has_method("voxel_at") or scale_value <= 0.0:
		return direct
	# The old fallback searched only the requested face direction. Around a
	# one-cell lip that can miss the exposed side/underside entirely. Search a
	# tiny neighborhood of all exposed faces and choose the face closest to the
	# authored aim, with a mild preference for the requested orientation.
	var native_center := center / scale_value
	var base := Vector3i(floori(native_center.x), floori(native_center.y), floori(native_center.z))
	var patch: Vector3i = backend.get("patch_size") if backend.get("patch_size") is Vector3i else Vector3i(96, 64, 96)
	var requested := normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	var best := direct
	var best_score := INF
	if bool(direct.get("valid", false)) and direct.get("point", null) is Vector3:
		best_score = (direct["point"] as Vector3).distance_squared_to(center)
	var reach := 3
	var faces: Array[Vector3i] = [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]
	for x in range(maxi(0, base.x - reach), mini(patch.x - 1, base.x + reach) + 1):
		for y in range(maxi(0, base.y - reach), mini(patch.y - 1, base.y + reach) + 1):
			for z in range(maxi(0, base.z - reach), mini(patch.z - 1, base.z + reach) + 1):
				var cell := Vector3i(x, y, z)
				if backend.voxel_at(cell) == 0: continue
				for face in faces:
					var neighbor := cell + face
					if neighbor.x < 0 or neighbor.y < 0 or neighbor.z < 0 or neighbor.x >= patch.x or neighbor.y >= patch.y or neighbor.z >= patch.z: continue
					if backend.voxel_at(neighbor) != 0: continue
					var point := (Vector3(cell) + Vector3.ONE * 0.5 + Vector3(face) * 0.5) * scale_value
					var face_normal := Vector3(face)
					var alignment_penalty := (1.0 - clampf(face_normal.dot(requested), -1.0, 1.0)) * scale_value * scale_value * 0.18
					var score := point.distance_squared_to(center) + alignment_penalty
					if score < best_score:
						best_score = score
						best = {"valid": true, "point": point, "normal": face_normal}
	return best
