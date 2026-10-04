extends SceneTree

## Source check: every authored MagicaVoxel OBJ must reference a material library
## that actually exists, and must only use materials that library declares.
##
## Why: Godot's OBJ importer emits `ERROR: Couldn't open MTL file ...` when an OBJ's
## `mtllib` line names a file that is not present. The CI import step treats any
## `ERROR:` line as a failed import, so a dangling reference breaks every pipeline
## that imports the project — while the model itself still loads, which is why the
## defect is invisible in playtesting.

const MODEL_DIR := "res://assets/models/magicavoxel"

var failures: Array[String] = []

func _init() -> void:
	_check_all()
	if failures.is_empty():
		print("M2 OBJ material reference check PASS")
		quit(0)
		return
	for failure in failures:
		print("M2 OBJ material reference failure: %s" % failure)
	print("M2 OBJ material reference check FAIL: %d" % failures.size())
	quit(1)

func _check_all() -> void:
	var dir := DirAccess.open(MODEL_DIR)
	if dir == null:
		failures.append("cannot open %s" % MODEL_DIR)
		return
	for file_name in dir.get_files():
		# `.import` sidecars are generated; only the authored OBJ is authoritative.
		if not file_name.ends_with(".obj"):
			continue
		_check_obj(MODEL_DIR.path_join(file_name))

func _check_obj(obj_path: String) -> void:
	var file := FileAccess.open(obj_path, FileAccess.READ)
	if file == null:
		failures.append("%s cannot be read" % obj_path)
		return
	var mtllib := ""
	var used: Array[String] = []
	for line in file.get_as_text().split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("mtllib "):
			mtllib = trimmed.trim_prefix("mtllib ").strip_edges()
		elif trimmed.begins_with("usemtl "):
			used.append(trimmed.trim_prefix("usemtl ").strip_edges())
	if mtllib.is_empty():
		# An OBJ with no materials at all is legal; Godot then imports no surfaces.
		if used.is_empty():
			return
		failures.append("%s uses materials without an mtllib line" % obj_path)
		return
	var mtl_path := obj_path.get_base_dir().path_join(mtllib)
	if not FileAccess.file_exists(mtl_path):
		failures.append("%s references missing material library %s" % [obj_path, mtllib])
		return
	var declared := _declared_materials(mtl_path)
	for material_name in used:
		if not declared.has(material_name):
			failures.append("%s uses material %s not declared in %s" % [obj_path, material_name, mtllib])

func _declared_materials(mtl_path: String) -> Dictionary:
	var declared: Dictionary = {}
	var file := FileAccess.open(mtl_path, FileAccess.READ)
	if file == null:
		return declared
	for line in file.get_as_text().split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("newmtl "):
			declared[trimmed.trim_prefix("newmtl ").strip_edges()] = true
	return declared
