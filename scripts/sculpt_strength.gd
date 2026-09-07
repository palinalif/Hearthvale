extends RefCounted
## Player-facing levels are separate from world units per second.
const DEFAULT_LEVEL := 5
const MIN_LEVEL := 1
const MAX_LEVEL := 10

static func rate(level: int) -> float:
	var value := clampi(level, MIN_LEVEL, MAX_LEVEL)
	if value <= DEFAULT_LEVEL:
		return pow(2.0, float(value - MIN_LEVEL) / 4.0)
	return 2.0 * pow(2.0, float(value - DEFAULT_LEVEL) / 5.0)
