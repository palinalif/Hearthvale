# Visual lighting study — opt-in, not a gameplay default

The player approved continuing visual work while the gameplay APK builds. This isolated branch adds a reusable lighting profile Resource and a three-profile, three-camera Mobile comparison on the actual exported gameplay scene. It does not change either live `_build_world()` override, the main scene, palettes, meshes, terrain, saved data, or controls. It is not part of gameplay PR #3.

Profiles: `baseline` reproduces the current sun/constant ambient settings; `sky_fill` changes the ambient/reflection source to a procedural sky; `warm_daylight` additionally lowers the sun and reduces ambient energy. Exposure, tonemapping, framing, scenery and wind state are held fixed within each camera comparison. Fog/glow are off. These are proposed starting points, not Town to City settings or an approved final look.

The separate `visual-lighting-study.yml` workflow uses pinned dependency hashes and actual Mobile/D3D12 rendering. It saves nine images and checks environment-resource isolation, fixed exposure/framing and unchanged building/planting/path/composition records. The existing delivery workflow remains intact; this branch does not cancel a run on the gameplay or opaque-material branches. Run success confirms execution, not aesthetic approval or physical Thor performance.

At commit creation: source/API review only. Godot runtime checks, comparison images and APK for this commit are pending CI; physical Thor checks are not run. Do not present the new profiles as active in an exported test build: only the explicit comparison script applies them.

Primary API references checked 2026-09-10:
- https://docs.godotengine.org/en/stable/classes/class_environment.html (sky ambient independent of background, reflection-source enums)
- https://docs.godotengine.org/en/stable/classes/class_proceduralskymaterial.html (sky and ground colour controls)

After review, the preferred profile can replace the duplicated gameplay setup through one shared rig in a separately verified change. Until then retain the current playable baseline.
