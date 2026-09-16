extends SceneTree

const Backend := preload("res://scripts/terrain_backend.gd")
const Generator := preload("res://scripts/m1_patch_generator.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	var backend := Backend.new()
	backend.patch_size = Generator.PATCH_SIZE
	backend.voxel_scale = Generator.VOXEL_SCALE
	backend.startup_mesh_focus_world = Vector3(24.0, 8.0, 22.0)
	backend.startup_mesh_radius_world = 20.0
	# Startup readiness only needs the generated/interactive terrain band, not
	# the unused upper half of the authoritative 32-metre world volume.
	backend.set("startup_mesh_height_world", 16.0)

	var area: AABB = backend.initial_mesh_area()
	_check(area.position.y == 0.0, "startup mesh begins at valley floor")
	_check(area.size.y == 128.0, "startup mesh only waits for first sixteen world metres")
	_check(area.end.y >= 96.0, "startup mesh includes highest generated starter terrain")
	_check(area.size.y < Generator.PATCH_SIZE.y, "startup mesh excludes unused upper vertical volume")

	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "area": {"position": str(area.position), "size": str(area.size)}}))
	quit(1 if failures > 0 else 0)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: %s" % label)
