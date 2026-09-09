extends SceneTree

const Preview = preload("res://scripts/tree_wind_preview.gd")
const SizeVariationPreview = preload("res://scripts/size_variations_preview.gd")
const WoodlandPreview = preload("res://scripts/woodland_preview.gd")
const ExpansionPreview = preload("res://scripts/meadow_expansion_preview.gd")
const FoliagePreview = preload("res://scripts/foliage_wind_preview.gd")
const Wind = preload("res://scripts/tree_wind.gd")
var checks := 0
var failures := 0
var metrics: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var preview = SizeVariationPreview.new() if "--size-variations" in args else WoodlandPreview.new() if "--woodland" in args else ExpansionPreview.new() if "--expansion" in args else (FoliagePreview.new() if "--foliage" in args else Preview.new())
	preview.automatic = false; root.add_child(preview)
	await process_frame
	if "--expansion" in args or "--woodland" in args or "--size-variations" in args:
		for rock: MeshInstance3D in preview.rocks:
			var transform_before := rock.transform
			preview.set_time(3.0); preview.advance(2.0)
			_check(rock.transform == transform_before and rock.material_override == null, "static asset stays fixed")
			for surface in rock.mesh.get_surface_count():
				_check(rock.get_surface_override_material(surface) == null and rock.mesh.surface_get_material(surface) is StandardMaterial3D, "static asset has no wind shader")
	var sources: Array[Mesh] = []
	for i in preview.trees.size():
		var tree: MeshInstance3D = preview.trees[i]
		var wind: TreeWind = preview.winds[i]
		sources.append(tree.mesh)
		var grounded := true; var bounded := true; var affine := true; var rest_grid := true
		for step in 48:
			wind.strength = Wind.MAX_STRENGTH
			var basis := Wind.deformation(wind.shear_at(step * Wind.PERIOD / 48.0))
			for surface in tree.mesh.get_surface_count():
				var arrays := tree.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for point in vertices:
					if point.y == 0.0: grounded = grounded and (basis * point).is_equal_approx(point)
					bounded = bounded and tree.custom_aabb.has_point(basis * point)
					for axis in 3: rest_grid = rest_grid and absf(point[axis] / 0.0625 - roundf(point[axis] / 0.0625)) < 0.0002
				for index in range(0, indices.size(), 3):
					var a := vertices[indices[index]]; var b := vertices[indices[index + 1]]
					# Every point along a shared edge follows its endpoints exactly,
					# including T junctions on the original greedy rectangles.
					affine = affine and (basis * a.lerp(b, 0.37)).is_equal_approx((basis * a).lerp(basis * b, 0.37))
		wind.strength = Wind.DEFAULT_STRENGTH
		_check(grounded, "tree %d ground-contact roots remain fixed" % i)
		_check(bounded, "tree %d culling bounds enclose maximum wind" % i)
		_check(affine, "tree %d shared edges stay coincident" % i)
		_check(rest_grid, "tree %d authored grid unchanged" % i)
		_check(wind.shear_at(0).is_equal_approx(wind.shear_at(Wind.PERIOD)), "tree %d seamless cycle" % i)
	_check(not preview.winds[0].shear_at(2).is_equal_approx(preview.winds[1].shear_at(2)), "trees have independent phases")
	preview.set_time(2.0); preview.paused = true; preview.advance(1.0)
	_check(is_equal_approx(preview.elapsed, 2.0), "preview pause freezes animation clock")
	preview.paused = false; preview.wind_enabled = false; preview.set_time(2.0)
	for wind in preview.winds: _check(wind.shear_at(2.0) == Vector2.ZERO, "wind off restores undeformed mesh")
	preview.wind_enabled = true
	var rendered := DisplayServer.get_name() != "headless"
	if "--require-rendering" in OS.get_cmdline_user_args():
		_check(rendered and RenderingServer.get_current_rendering_method() == "mobile", "actual Mobile renderer")
	if rendered:
		var previous: Image
		for seconds in [0.0, 3.0, 7.0]:
			preview.set_time(seconds)
			var shader_image := await _capture()
			if previous != null: _check(_difference(previous, shader_image) > 0.00005, "visible wind movement")
			previous = shader_image
			for i in preview.trees.size():
				preview.trees[i].mesh = _reference(sources[i], Wind.deformation(preview.winds[i].shear_at(seconds)))
				for s in sources[i].get_surface_count(): preview.trees[i].set_surface_override_material(s, null)
			var reference_image := await _capture()
			var difference := _difference(shader_image, reference_image)
			metrics["reference_difference_" + str(seconds)] = difference
			_check(difference < 0.002, "GPU deformation/normals match CPU reference at %.1fs" % seconds)
			for i in preview.trees.size():
				preview.trees[i].mesh = sources[i]
				for s in sources[i].get_surface_count(): preview.trees[i].set_surface_override_material(s, preview.winds[i].materials[s])
		preview.wind_enabled = false; preview.set_time(0.0)
		var off_image := await _capture()
		for i in preview.trees.size():
			for s in sources[i].get_surface_count(): preview.trees[i].set_surface_override_material(s, null)
		var rest_image := await _capture()
		_check(_difference(off_image, rest_image) < 0.002, "wind off matches original baked appearance")
		for i in preview.trees.size():
			for s in sources[i].get_surface_count(): preview.trees[i].set_surface_override_material(s, preview.winds[i].materials[s])
		preview.wind_enabled = true; preview.set_time(2.0); preview.paused = true
		var frozen := await _capture(); preview.advance(3.0)
		_check(frozen.get_data() == (await _capture()).get_data(), "paused render is pixel-identical")
		preview.paused = false
		for argument in OS.get_cmdline_user_args():
			if str(argument).begins_with("--frames="):
				var directory := str(argument).trim_prefix("--frames=")
				DirAccess.make_dir_recursive_absolute(directory)
				for frame in 288:
					preview.set_time(frame / 24.0)
					var capture := await _capture()
					if capture.save_png(directory.path_join("%04d.png" % frame)) != OK:
						_check(false, "frame save"); break
				_check(FileAccess.file_exists(directory.path_join("0287.png")), "12-second Mobile capture saved")
	_check(preview.trees[0].mesh == sources[0], "baked source mesh remains unmodified")
	print(JSON.stringify({"ok": failures == 0, "checks": checks, "failures": failures, "renderer": RenderingServer.get_current_rendering_method(), "metrics": metrics}))
	preview.queue_free(); await process_frame
	quit(1 if failures else 0)

func _reference(source: Mesh, basis: Basis) -> ArrayMesh:
	var result := ArrayMesh.new()
	var normal_basis := basis.inverse().transposed()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size():
			vertices[i] = basis * vertices[i]; normals[i] = (normal_basis * normals[i]).normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, source.surface_get_material(surface))
	return result

func _capture() -> Image:
	for unused in 3: await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _difference(a: Image, b: Image) -> float:
	var bytes_a := a.get_data(); var bytes_b := b.get_data()
	if bytes_a == bytes_b: return 0.0
	var total := 0.0
	for i in bytes_a.size(): total += abs(int(bytes_a[i]) - int(bytes_b[i]))
	return total / (bytes_a.size() * 255.0)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: " + label)
