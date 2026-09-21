extends RefCounted
## Shared physical bounds. Native editing stays on the eighth-unit grid;
## decorative geometry stays on the sixteenth-unit grid. M0 is unchanged.
const SIZE := 80.0
const HEIGHT := 32.0
const EXTENT := Vector3(SIZE, HEIGHT, SIZE)
const NATIVE_SIZE := Vector3i(640, 256, 640)
const PREVIOUS_NATIVE_SIZE := Vector3i(512, 256, 512)
const PREVIOUS_GENERATOR_ID := "m2_starter_valley_v3"
