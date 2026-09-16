extends SceneTree

## Locks the per-cell grass tone field: determinism, family, spread, coherence
## and the wiring that publishes the model to the native grass shader.
## Read-only: it generates a fresh patch to compare digests but writes nothing.

const Tone = preload("res://scripts/grass_tone.gd")
const Generator = preload("res://scripts/m1_patch_generator.gd")
const Bounds = preload("res://scripts/m2_world_bounds.gd")
const SHADER_PATH := "res://scripts/terrain_grass.gdshader"
const LATTICE_STEP := 0.25
const LATTICE_COUNT := 128

var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _initialize() -> void:
	_verify_palette()
	_verify_determinism()
	_verify_patch_regeneration()
	_verify_spread()
	_verify_coherence()
	_verify_shader_wiring()
	print("grass_tone_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _verify_palette() -> void:
	check(Tone.TONES.size() >= 4 and Tone.TONES.size() <= 7, "a handful of greens, not a palette flood")
	check(Tone.in_green_family(Tone.SIDE_SHADE), "near-vertical grass shade stays inside the meadow family")
	var family_ok := true
	var hues := {}
	for colour: Color in Tone.TONES:
		family_ok = family_ok and Tone.in_green_family(colour)
		hues[snappedf(colour.h, 0.0005)] = true
	check(family_ok, "every palette tone is inside the approved green family")
	check(Tone.TONES[Tone.TONES.size() / 2] == Tone.palette_color(Tone.base_index()), "field base index is the dominant meadow green")
	check(Tone.TONES.size() == 5 and Tone.span() == 4.0, "five ordered tones with the shader span published from one source")
	print("GRASS_TONE_PALETTE " + JSON.stringify({"tones": Tone.TONES.size(), "hues": hues.keys(), "coherent_scales": Tone.SCALES, "fine_cell": Tone.FINE_CELL, "fine_amplitude": Tone.FINE_AMPLITUDE}))

func _verify_determinism() -> void:
	var first := Tone.digest(Vector2(0.0, 0.0), LATTICE_STEP, LATTICE_COUNT)
	var second := Tone.digest(Vector2(0.0, 0.0), LATTICE_STEP, LATTICE_COUNT)
	check(first == second, "grass albedo digest is identical across two evaluations")
	var repeated := true
	for index in 512:
		var x := float(index) * 0.37
		var z := float(index) * 0.11
		repeated = repeated and Tone.sample(x, z).is_equal_approx(Tone.sample(x, z))
	check(repeated, "per-cell tone is a pure function of world position")
	check(Tone.digest(Vector2(0.0, 0.0), LATTICE_STEP, LATTICE_COUNT) == first, "digest survives unrelated sampling between runs")
	print("GRASS_TONE_DETERMINISM " + JSON.stringify({"digest": first.substr(0, 16), "samples": LATTICE_COUNT * LATTICE_COUNT}))

func _verify_patch_regeneration() -> void:
	if not ClassDB.class_exists("VoxelBuffer"):
		check(false, "native VoxelBuffer unavailable")
		return
	var first: Object = Generator.generate()
	check(first != null and first.get_size() == Bounds.NATIVE_SIZE, "regenerated native patch has the approved dimensions")
	if first == null:
		return
	var first_digest: String = first.get_channel_as_byte_array(Generator.CHANNEL_TYPE).hex_encode().sha256_text()
	first = null
	var second: Object = Generator.generate()
	var second_digest: String = second.get_channel_as_byte_array(Generator.CHANNEL_TYPE).hex_encode().sha256_text()
	check(first_digest == second_digest, "regenerating the patch twice reproduces the identical voxel field")
	# The tone is derived from world position only, so the regenerated ground
	# must still carry the same albedo field over the same cells.
	var first_field := Tone.digest(Vector2(0.0, 0.0), LATTICE_STEP, LATTICE_COUNT)
	var second_field := Tone.digest(Vector2(0.0, 0.0), LATTICE_STEP, LATTICE_COUNT)
	check(first_field == second_field, "grass albedo digest matches after regeneration")
	print("GRASS_TONE_PATCH " + JSON.stringify({"patch_digest": second_digest.substr(0, 16), "albedo_digest": first_field.substr(0, 16)}))

func _verify_spread() -> void:
	var reached := {}
	var outside := 0
	var indices := PackedFloat32Array()
	for row in LATTICE_COUNT:
		for column in LATTICE_COUNT:
			var x := float(column) * LATTICE_STEP
			var z := float(row) * LATTICE_STEP
			var colour := Tone.sample(x, z)
			if not Tone.in_green_family(colour):
				outside += 1
			reached[clampi(roundi(Tone.full_index(x, z)), 0, Tone.TONES.size() - 1)] = true
			indices.append(Tone.full_index(x, z))
	check(outside == 0, "no sampled cell leaves the green family")
	check(reached.size() >= 4, "the field actually reaches at least four of the ordered greens")
	check(reached.size() == Tone.TONES.size(), "every published tone is reachable over the world")
	indices.sort()
	var low := indices[0]
	var high := indices[indices.size() - 1]
	check(low <= 1.0 and high >= 3.0, "tone spread covers deep shade through lifted green")
	check(high - low <= Tone.span(), "spread never exceeds the published palette span")
	print("GRASS_TONE_SPREAD " + JSON.stringify({"tones_reached": reached.size(), "min_index": low, "max_index": high, "outside_family": outside}))

func _verify_coherence() -> void:
	# Adjacent decorative cells must differ only within the bounded fine shift,
	# while cells far apart must be free to differ fully: patches, not noise.
	var neighbour_delta := 0.0
	var neighbour_max := 0.0
	var wide_delta := 0.0
	var samples := 0
	for row in 64:
		for column in 64:
			var x := 2.0 + float(column) * 0.125
			var z := 2.0 + float(row) * 0.125
			var here := Tone.full_index(x, z)
			var detailed := absf(here - Tone.full_index(x + Tone.FINE_CELL, z))
			neighbour_delta += detailed
			neighbour_max = maxf(neighbour_max, detailed)
			wide_delta += absf(here - Tone.full_index(x + 6.0, z))
			samples += 1
	neighbour_delta /= float(samples)
	wide_delta /= float(samples)
	check(neighbour_max <= Tone.FINE_AMPLITUDE * 2.0 + 0.15, "per-voxel tone shift is bounded (not salt-and-pepper)")
	check(neighbour_max <= Tone.span() * 0.2, "adjacent voxels stay well inside the palette span")
	check(neighbour_delta < Tone.FINE_AMPLITUDE, "neighbouring voxels stay close in tone")
	check(wide_delta > neighbour_delta * 2.0, "distant cells vary more than neighbours (coherent patches)")
	var broad_a := 0.0
	var broad_b := 0.0
	for index in 256:
		var x := float(index) * 0.25
		broad_a += Tone.tone_index(x, 4.0)
		broad_b += Tone.tone_index(x, 4.0 + 2.0)
	broad_a /= 256.0
	broad_b /= 256.0
	check(absf(broad_a - broad_b) < Tone.span(), "broad structure stays within the palette over a two-metre offset")
	print("GRASS_TONE_COHERENCE " + JSON.stringify({"neighbour_delta": neighbour_delta, "neighbour_max": neighbour_max, "wide_delta": wide_delta, "fine_bound": Tone.FINE_AMPLITUDE * 2.0}))

func _verify_shader_wiring() -> void:
	var source := FileAccess.get_file_as_string(SHADER_PATH)
	check(not source.is_empty(), "grass shader source is readable")
	var declared_names := {}
	var pattern := RegEx.new()
	pattern.compile("uniform\\s+\\w+\\s+(\\w+)")
	for found: RegExMatch in pattern.search_all(source):
		declared_names[found.get_string(1)] = true
	var declared := true
	for name: String in Tone.shader_uniform_names():
		if not declared_names.has(name):
			declared = false
			print("FAILED_UNIFORM " + name)
	check(declared, "every published parameter is declared by the native grass shader")
	check(source.contains("tone_fine_cell") and source.contains("tone_scales"), "shader keeps the shared patch scales and decorative cell")
	check(source.contains("COLOR.rgb"), "shader still respects the mesher's vertex colour")
	var material := Generator.grass_material()
	check(material != null and material.shader != null and str(material.shader.resource_path) == SHADER_PATH, "native grass model uses the meadow shader")
	var mismatched := PackedStringArray()
	var expected: Dictionary = Tone.shader_uniforms()
	for name: String in expected:
		var actual: Variant = material.get_shader_parameter(name)
		var wanted: Variant = expected[name]
		var matches := false
		if wanted is Color:
			matches = actual is Color and (actual as Color).is_equal_approx(wanted)
		elif wanted is Vector3:
			matches = actual is Vector3 and (actual as Vector3).is_equal_approx(wanted)
		else:
			matches = actual != null and is_equal_approx(float(actual), float(wanted))
		if not matches:
			mismatched.append(name)
	check(mismatched.is_empty(), "grass material receives the exact published palette and scales: " + str(mismatched))
	check(str(material.shader.resource_path) == SHADER_PATH and Generator.GRASS_SHADER == material.shader, "library and test resolve the same shader resource")
	print("GRASS_TONE_WIRING " + JSON.stringify({"uniforms": Tone.shader_uniform_names().size(), "mismatched": mismatched, "shader": SHADER_PATH}))
