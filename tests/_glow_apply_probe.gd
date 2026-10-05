extends SceneTree
func _init() -> void:
	var p := VisualLightingProfile.new()
	p.glow_enabled = true
	var sun := DirectionalLight3D.new()
	var we := WorldEnvironment.new()
	var ok := p.apply_to(sun, we)
	var e := we.environment
	print("applied=", ok)
	print("glow_enabled=", e.glow_enabled, " intensity=", e.glow_intensity, " strength=", e.glow_strength)
	print("blend=", e.glow_blend_mode, " hdr_threshold=", e.glow_hdr_threshold, " mix=", e.glow_mix)
	print("level2=", e.get("glow_levels/2"), " level3=", e.get("glow_levels/3"))
	# Baseline profile must stay dark: glow off.
	var base := VisualLightingProfile.new()
	var we2 := WorldEnvironment.new()
	base.apply_to(DirectionalLight3D.new(), we2)
	print("baseline glow_enabled=", we2.environment.glow_enabled)
	quit()
