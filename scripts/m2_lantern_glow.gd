class_name M2LanternGlow
"""One owner for the lantern glass glow.

Lantern glass is presentation, not authority: the lamp's lit state already lives in the
hamlet's lighting records. This helper only translates that state into emissive material
state on the glass mesh so a lamp reads as a light source at night.

Kept out of the deep gameplay inheritance chain so it can be tested on its own.
"""

const LANTERN_EMBER_COLOR := Color(1.0, 0.62, 0.24)
const LANTERN_EMBER_INTENSITY := 2.4
const LANTERN_EMBER_GLOW_SPECULAR := 0.6
const LANTERN_UNLIT_EMBER_INTENSITY := 0.0


static func apply(glass: MeshInstance3D, lit: bool) -> bool:
	if glass == null:
		return false
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.82, 0.55, 0.88)
	material.emission_enabled = true
	material.emission = LANTERN_EMBER_COLOR
	material.emission_energy_multiplier = LANTERN_EMBER_INTENSITY if lit else LANTERN_EMBER_UNLIT_EMBER_INTENSITY
	material.emission_specular = LANTERN_EMBER_GLOW_SPECULAR
	glass.material_override = material
	return true
