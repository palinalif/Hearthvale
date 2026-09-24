# Render screenshots (actual Mobile render, on this host)

How to render the real Mobile-renderer scene and capture a screenshot for visual
design iteration and review, from this Linux host (no display, no PowerShell). This is
the "look at it and iterate" loop; it complements the numeric `godot --headless` tests,
which can't see the image.

## Why not `--headless`

`godot --headless` disables the renderer, so `get_texture().get_image()` comes back
blank. A real rendered frame needs a display server. The practical answer is a virtual
X display (**Xvfb**) plus the **Mobile renderer** (the game's actual renderer).

## Method A — Xvfb + a SceneTree capture script (this host)

1. Write a `SceneTree` script that boots the real scene, aims the camera, and saves the
   frame. Model: `tools/det_bisect.gd` (full) and `tests/tmp_capture_probe.gd` (minimal,
   no scene). Template:

```gdscript
extends SceneTree
var scene: Node

func _initialize() -> void:
    call_deferred("_run")

func _capture() -> Image:
    for i in 4:                      # let the renderer settle
        await RenderingServer.frame_post_draw
    return root.get_texture().get_image()

func _run() -> void:
    if DisplayServer.get_name() == "headless":
        print("CAPTURE_UNAVAILABLE headless")
        quit(2)
        return
    root.size = Vector2i(1280, 720)
    scene = (preload("res://scenes/m1.tscn") as PackedScene).instantiate()
    scene.test_mode = true
    root.add_child(scene)
    var deadline := Time.get_ticks_msec() + 120000
    while not (scene._player_restored and scene.backend and scene.backend.is_ready()) \
            and Time.get_ticks_msec() < deadline:
        await process_frame
    if scene.hud:
        scene.hud.visible = false
    # Aim at what you want to see — tune by trial:
    scene.camera_yaw = PI * 0.6
    scene.camera_pitch = 0.35
    scene.camera_distance = 14.0
    scene._update_camera()
    var img := await _capture()
    img.save_png("res://reports/screenshots/my-area/shot.png")
    quit(0)
```

   `scenes/m1.tscn` is the live gameplay scene that renders the current default world
   (the M2 starter valley). For a specific region, set the camera controls (`camera_yaw`
   / `camera_pitch` / `camera_distance` + `_update_camera()`) until the target fills the
   frame; the scene is a full 1280³ world, so pick the region coordinates from the
   generator (e.g. the waterfall is near x=64, z=33).

2. Run it on a virtual display with the Mobile renderer and software GL:

```sh
timeout 400 xvfb-run -a godot --max-fps 60 --renderer mobile --path . --script tools/my_shot.gd
```

   `xvfb-run -a` starts a fresh Xvfb and tears it down (equivalently: start
   `Xvfb :99` and use `DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot ...`).
   `LIBGL_ALWAYS_SOFTWARE=1` keeps it working without a GPU. Always wrap in a bounded
   `timeout` so a stuck scene can't hang the turn.

3. View the result: use the `read` tool on the PNG (it renders the image), open it in a
   browser, or `show_image`. Iterate: change the scene/camera/shader, re-run, re-view,
   until the design reads the way you want.

- Save captures under `reports/screenshots/<area>/` — this tree is committed (the
  `circular-mountain-valley/` captures, including `waterfall.png`, live here).
  `reports/logs/` is gitignored; keep logs there.

## Method B — canonical `--write-movie` (Windows / PowerShell only)

`tools/capture-m1.ps1 -View cottage -Clean -Name my-normal` uses Godot's built-in movie
writer with camera presets:

```
godot --disable-vsync --write-movie .tools/capture-<name>/frame.png --fixed-fps 30 \
      --quit-after 60 -- --review-<view>
```

Views: `cottage` / `close` / `dig` / `near` / `far` / `occluded`; flags `-Clean`,
`-Edited`, `-Front`. Output lands in `reports/screenshots/<name>.png`. This is the
canonical Windows path; it is **not** usable on this host (no PowerShell), so Method A
is the practical equivalent here.

## Caveats

- This is a desktop / software-GL render — a design proxy, **not** Thor evidence
  (AGENTS.md: "Desktop evidence is not Thor evidence").
- Render with `--renderer mobile`; `gl_compatibility` is only for the explicit desktop
  benchmark path.
