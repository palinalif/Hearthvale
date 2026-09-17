extends SceneTree

## Locks the deterministic meadow tuft scatter (living-grass, part 2 planner):
## determinism, sparseness, clumping by the tone field, exclusions, occupancy
## and the decorative-cell budget. Pure logic: runs headless with no native
## voxel module. Native validation (surface/grass/flatness) is CI-gated in the
## scene integration.

const Scatter = preload("res://scripts/grass_tuft_scatter.gd")
const Tone = preload("res://scripts/grass_tone.gd")
const MEADOW := Vector2(64.0, 64.0)

var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _initialize() -> void:
	_verify_determinism()
	_verify_sparseness()
	_verify_clumping()
	_verify_exclusions()
	_verify_occupancy_and_cells()
	print("grass_tuft_scatter_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _verify_determinism() -> void:
	var first := Scatter.plan(Vector2.ZERO, MEADOW)
	var second := Scatter.plan(Vector2.ZERO, MEADOW)
	check(not first.is_empty(), "the meadow scatters tufts")
	check(Scatter.digest(first) == Scatter.digest(second), "tuft plan digest is identical across two evaluations")
	var stable := true
	for index in 512:
		var x := 1.0 + float(index) * 0.37
		var z := 1.0 + float(index) * 0.13
		stable = stable and Scatter.accepted(x, z) == Scatter.accepted(x, z)
	check(stable, "acceptance is a pure function of world position")
	check(Scatter.digest(first) == Scatter.digest(Scatter.plan(Vector2.ZERO, MEADOW)), "digest survives unrelated sampling between runs")
	print("TUFT_DETERMINISM " + JSON.stringify({"tufts": first.size(), "digest": Scatter.digest(first).substr(0, 16)}))

func _verify_sparseness() -> void:
	var plan := Scatter.plan(Vector2.ZERO, MEADOW)
	var area := MEADOW.x * MEADOW.y
	var per_m2 := float(plan.size()) / area
	check(plan.size() <= Scatter.MAX_TUFTS, "hard cap holds")
	check(plan.size() >= 80 and plan.size() <= 900, "a few hundred tufts, not a carpet (got %d)" % plan.size())
	check(per_m2 < 0.10, "sparse: under one tuft per 10 m^2 (got %.3f)" % per_m2)
	var cells := 0
	for tuft: Dictionary in plan:
		var columns: Array = tuft["columns"]
		cells += int(columns[0]) + int(columns[1])
	check(cells / float(maxi(plan.size(), 1)) <= 2.5, "ground cover, not shrubs (avg %.2f cells/tuft)" % (float(cells) / maxi(plan.size(), 1)))
	print("TUFT_SPARSE " + JSON.stringify({"tufts": plan.size(), "per_m2": per_m2, "cells": cells}))

func _verify_clumping() -> void:
	# Tufts must follow the meadow tone patches: per unit area, lifted (lighter)
	# regions carry more tufts than shaded (darker) ones. Bin the sampled field
	# and the tufts by tone_index and compare density per bin.
	var plan := Scatter.plan(Vector2.ZERO, MEADOW)
	var area := MEADOW.x * MEADOW.y
	var lifted_samples := 0
	var shaded_samples := 0
	var total_samples := 0
	for row in 256:
		for column in 256:
			var x := float(column) * 0.25
			var z := float(row) * 0.25
			var index := Tone.tone_index(x, z)
			if index > 2.3:
				lifted_samples += 1
			elif index < 1.7:
				shaded_samples += 1
			total_samples += 1
	var lifted_tufts := 0
	var shaded_tufts := 0
	for tuft: Dictionary in plan:
		var point: Vector2 = tuft["point"]
		var index := Tone.tone_index(point.x, point.y)
		if index > 2.3:
			lifted_tufts += 1
		elif index < 1.7:
			shaded_tufts += 1
	var lifted_area := area * float(lifted_samples) / float(total_samples)
	var shaded_area := area * float(shaded_samples) / float(total_samples)
	check(lifted_samples > 0 and shaded_samples > 0, "the field has both lifted and shaded regions")
	var lifted_density := float(lifted_tufts) / maxf(lifted_area, 1.0)
	var shaded_density := float(shaded_tufts) / maxf(shaded_area, 1.0)
	check(lifted_density > shaded_density * 1.10, "tufts cluster where the meadow is lifted (lifted %.4f vs shaded %.4f per m^2)" % [lifted_density, shaded_density])
	print("TUFT_CLUMP " + JSON.stringify({"lifted_tufts": lifted_tufts, "shaded_tufts": shaded_tufts, "lifted_density": lifted_density, "shaded_density": shaded_density}))

func _verify_exclusions() -> void:
	var rect := Rect2(20.0, 20.0, 8.0, 8.0)
	var open_plan := Scatter.plan(Vector2.ZERO, MEADOW)
	var excluded := Scatter.plan(Vector2.ZERO, MEADOW, Scatter.DENSITY, [rect])
	var open_inside := 0
	for tuft: Dictionary in open_plan:
		if rect.has_point(tuft["point"] as Vector2):
			open_inside += 1
	var inside := 0
	for tuft: Dictionary in excluded:
		if rect.has_point(tuft["point"] as Vector2):
			inside += 1
	check(inside == 0, "no tuft lands inside an exclusion rect (got %d)" % inside)
	check(open_inside > 0, "the unexcluded plan actually fills the rect (control, got %d)" % open_inside)
	check(excluded.size() < open_plan.size(), "excluding an area removes tufts")
	print("TUFT_EXCLUDE " + JSON.stringify({"open": open_plan.size(), "excluded": excluded.size(), "open_inside": open_inside, "inside": inside}))

func _verify_occupancy_and_cells() -> void:
	var plan := Scatter.plan(Vector2.ZERO, MEADOW)
	var cells := {}
	var unique := true
	var family_ok := true
	var bounded := true
	for tuft: Dictionary in plan:
		var cell: Vector2i = tuft["cell"]
		var step: Vector2i = tuft["step"]
		var columns: Array = tuft["columns"]
		if cells.has(cell) or cells.has(cell + step):
			unique = false
		cells[cell] = true
		if int(columns[1]) > 0:
			cells[cell + step] = true
		var main_height := int(columns[0])
		var companion_height := int(columns[1])
		if main_height < Scatter.SHORT_COLUMN or main_height > Scatter.TALL_COLUMN:
			bounded = false
		if companion_height != 0 and companion_height > Scatter.SHORT_COLUMN:
			bounded = false
		if not Tone.in_green_family(tuft["tone"] as Color):
			family_ok = false
	check(unique, "no two tufts share a fine cell")
	check(bounded, "column heights stay ground cover (1-2 cells)")
	check(family_ok, "every tuft tone is inside the meadow green family")
	print("TUFT_CELLS " + JSON.stringify({"tufts": plan.size(), "cells": cells.size(), "unique": unique, "bounded": bounded, "family": family_ok}))
