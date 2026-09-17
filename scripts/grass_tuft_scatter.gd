extends RefCounted
class_name GrassTuftScatter

## Render-only deterministic meadow tuft scatter (living-grass, part 2).
##
## Ground foliage that grows out of the meadow tone field: a sparse, clumped,
## fully deterministic set of decorative fine cells (0.0625 m) sitting on the
## native grass surface. Presentation only - no planting records, no terrain
## writes, no save data, no per-frame work. The field is re-derived from world
## position + the tone field on every presentation pass, so a regenerated patch,
## a reloaded save and an undone sculpt reproduce the identical tufts.
##
## This planner is pure logic (no native query): integer identity only - no RNG,
## no frame time, no terrain revision, no enumeration order. Native validation
## (surface height, grass type, flatness) lives in the scene integration, not
## here, so this module stays testable headless and the deterministic contract
## is locked without a native voxel module.

const Tone = preload("res://scripts/grass_tone.gd")
const FINE := Tone.FINE_CELL

## Coarse candidate lattice in metres. The fine grid (~1M cells over the 64 m
## meadow) is never scanned: a coarse lattice is hash-filtered first, and only
## the survivors are native-checked by the integration, bounding the raycasts.
const COARSE_STEP := 0.25
## Base acceptance per coarse candidate, tuned for a sparse hand-placed read
## (a few hundred tufts over the meadow, one batched draw call).
const DENSITY := 0.0045
## Placement salts, kept out of the tone field's own salts.
const PLACE_SALT := 61
## Ground cover: a short column, occasionally two high, with an optional
## companion cell one fine step along a hashed direction.
const SHORT_COLUMN := 1
const TALL_COLUMN := 2
const TALL_CHANCE := 5
const COMPANION_CHANCE := 2
## Hard cap so the batched mesh and the native re-validation stay bounded on the
## Thor Max no matter how the density is tuned.
const MAX_TUFTS := 800

## Clump bias: lifted/lighter meadow patches carry more tufts. Kept subtle so
## the scatter reads as hand-placed clumps, not a density map.
static func tone_factor(x: float, z: float) -> float:
	return 0.40 + 0.14 * Tone.tone_index(x, z)

## Pure acceptance test for one coarse candidate, given its world centre.
static func accepted(x: float, z: float, density: float = DENSITY) -> bool:
	var cell := Vector2i(floori(x / COARSE_STEP), floori(z / COARSE_STEP))
	return Tone.hash_cell(cell, PLACE_SALT) < density * tone_factor(x, z)

## Deterministic tuft plan over a world rectangle. `exclusions` is an array of
## Rect2 (world metres) to skip - paths, water, stone, foundation bands.
## Returns an array in stable enumeration order.
static func plan(origin: Vector2, size: Vector2, density: float = DENSITY, exclusions: Array = []) -> Array:
	var result: Array = []
	var occupied := {}
	var min_x := int(floori(origin.x / COARSE_STEP))
	var max_x := int(ceili((origin.x + size.x) / COARSE_STEP))
	var min_z := int(floori(origin.y / COARSE_STEP))
	var max_z := int(ceili((origin.y + size.y) / COARSE_STEP))
	for cz in range(min_z, max_z):
		for cx in range(min_x, max_x):
			if result.size() >= MAX_TUFTS:
				return result
			var point := Vector2(float(cx) * COARSE_STEP, float(cz) * COARSE_STEP)
			if not _clears(point, exclusions):
				continue
			if not accepted(point.x, point.y, density):
				continue
			var seed := _seed(cx, cz)
			var cell := Vector2i(floori(point.x / FINE), floori(point.y / FINE))
			if occupied.has(cell):
				continue
			var step := _step(seed)
			var main_height := TALL_COLUMN if seed % TALL_CHANCE == 0 else SHORT_COLUMN
			var companion_height := 0
			if seed % COMPANION_CHANCE == 0 and not occupied.has(cell + step):
				occupied[cell + step] = true
				companion_height = SHORT_COLUMN
			occupied[cell] = true
			result.append({
				"cell": cell,
				"point": point,
				"columns": [main_height, companion_height],
				"step": step,
				"tone": Tone.sample(point.x, point.y),
				"seed": seed,
			})
	return result

## Determinism digest over the plan only (no GPU state).
static func digest(plan_value: Array) -> String:
	var payload: Array = []
	for tuft: Dictionary in plan_value:
		payload.append([tuft["cell"], tuft["columns"], tuft["step"], int(tuft["seed"])])
	return var_to_bytes(payload).hex_encode().sha256_text()

static func _seed(cx: int, cz: int) -> int:
	var value := posmod(cx, 1000003) * 92821 + posmod(cz, 1000003) * 68917 + PLACE_SALT * 2833
	value = posmod(value, 104729)
	return posmod(value * value * 31 + value * 17, 104729)

static func _step(seed: int) -> Vector2i:
	match seed % 4:
		0:
			return Vector2i(1, 0)
		1:
			return Vector2i(-1, 0)
		2:
			return Vector2i(0, 1)
		_:
			return Vector2i(0, -1)

static func _clears(point: Vector2, exclusions: Array) -> bool:
	for area: Variant in exclusions:
		if area is Rect2 and (area as Rect2).has_point(point):
			return false
	return true
