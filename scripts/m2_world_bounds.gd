extends RefCounted
## Shared physical bounds. Native editing stays on the eighth-unit grid;
## decorative geometry stays on the sixteenth-unit grid. M0 is unchanged.
const SIZE := 64.0
const HEIGHT := 32.0
const EXTENT := Vector3(SIZE, HEIGHT, SIZE)
const NATIVE_SIZE := Vector3i(512, 256, 512)
const PREVIOUS_NATIVE_SIZE := Vector3i(384, 256, 384)
const PREVIOUS_GENERATOR_ID := "m1_cottage_pad_v2"
