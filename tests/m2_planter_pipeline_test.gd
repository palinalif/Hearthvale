extends SceneTree
## Explicit development-only promotion/export/import/bake gate. No player saves.
const LOG_ROOT := "res://reports/logs/m2-planter-pipeline"
const NAMES := ["hearthvale_planter_flowers", "hearthvale_planter_herbs", "hearthvale_planter_light"]

func _initialize() -> void:
	_run.call_deferred()

func _step(executable: String, arguments: PackedStringArray, label: String) -> bool:
	var output: Array = []
	var result := OS.execute(executable, arguments, output, true)
	var text := "\n".join(output)
	var file := FileAccess.open(LOG_ROOT + "/" + label + ".log", FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()
	var clean := result == 0 and not text.contains("SCRIPT ERROR") and not text.contains("ERROR:") and not text.contains("Traceback (most recent call last)")
	print(JSON.stringify({"stage": label, "exit_code": result, "ok": clean, "log": LOG_ROOT + "/" + label + ".log"}))
	if not clean: print(text.right(4000))
	return clean

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_ROOT))
	var project := ProjectSettings.globalize_path("res://")
	var promote := FileAccess.file_exists("res://.tools/magicavoxel/vox/hearthvale_planter_flowers.vox")
	var args: PackedStringArray = [ProjectSettings.globalize_path("res://tools/magicavoxel/planter_assets.py")]
	if promote: args.append("--promote")
	if not _step("python", args, "export"):
		quit(1)
		return
	if not _step(OS.get_executable_path(), ["--headless", "--path", project, "--editor", "--import", "--quit"], "import"):
		quit(1)
		return
	for name: String in NAMES:
		var base := "res://assets/models/magicavoxel/" + name
		if not _step(OS.get_executable_path(), ["--headless", "--path", project, "--script", "res://tools/magicavoxel/bake_mesh.gd", "--", base + ".obj", base + ".res", "0.0625"], "bake-" + name):
			quit(1)
			return
	print("PLANTER_PIPELINE_OK: 3 actual MCP sources exported, imported and baked on 0.0625 grid")
	quit(0)
