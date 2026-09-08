# Hearthvale — current M1 handoff

Updated 2026-09-08 after a successful repair APK export and private Drive upload. Read AGENTS.md and the user's latest request first. **A new repair APK is ready for physical Thor testing. M1 and its UI overhaul are NOT complete or device-approved.**

## Current candidate and evidence

Branch: `fix/m1-cottage-playtest-2`. Candidate commit: `ca5185dc90a5f8bc6dbda4d646b2046b1f35cf5d`. Any subsequent documentation-only commit does not change this APK. `master` remains untouched. The exported scene uses `scripts/m1_scene_playtest_repair.gd`, NOT the historical terrain-only layer.

Successful complete CI: https://github.com/palinalif/Hearthvale/actions/runs/34223484717

Both jobs completed successfully: gameplay/render `102051889124` and APK `102052636203`. Existing 11 M1 integration suites pass, plus targeting/repair/settings/stability checks (54/60/14/35, total 163). The actual Mobile/D3D12 software-render fixture passes 41 checks, writes eight 1280x720 captures, and requires exact image equality after cancelling colour preview. Physical Thor testing of this candidate has NOT been performed. Desktop headless and software-render evidence is not handheld performance or user visual approval.

APK artifact `10054832687`; source/log/capture artifact `10054770603`. APK: `hearthvale-m1-repair-ca5185dc.apk`, 37,756,626 bytes. SHA256: `b618d29f4229918333a036b476b4d487056e3cf68ed9c75490bf7fa771104421`. Archive hash and extracted APK hash/size were verified locally against the CI receipt. APK package/version, signature, Mobile metadata, ARM64-only architecture, compiled repair script and byte-identical pinned native voxel library passed verification. Development resources are excluded.

Private Drive APK: https://drive.google.com/file/d/1HklTqWnJ4RGN9mBxbMY1K0xphjlQhbZQ/view

Private Drive checklist: https://drive.google.com/file/d/1ukkFbVmsk89AKkduFQXOfEp6dt159eYU/view

Both uploads were read back as metadata: exact names/MIME/sizes, shared=false. Drive's normalized metadata response did not return checksums; do not claim a Drive hash readback. The actual extracted APK, not its ZIP, was uploaded.

## Critical installation distinction

This is a SEPARATE TEST APP, labelled `Hearthvale Test ca5185dc`, package `org.hearthvale.game.repair.cca5185dc`, version code 6 / `0.1.3-repair-ca5185dc`. It starts with a fresh valley. Existing saves are not migrated or deleted, and the original app is not overwritten. Never suggest uninstalling the original to bypass signing.

The two previously shared APKs used different ephemeral debug certificates. Their private keys were not recovered; update-compatible signing is still open. The reusable repair workflow uses an isolated commit-derived package identity and ephemeral key; it does NOT establish permanent signing continuity. No private key was uploaded. Production export presets/package and save schema are unchanged; candidate identity is changed only in the CI export working copy.

There were TWO earlier shared builds (`m1-terrain-ux` and `m1-ui-ux`); the earlier three-section checklist did not mean three APKs. This new, explicitly named repair candidate is another actual APK, not a relabelled older artifact.

## Repairs included for player retest

The current complete scene contains specific-cottage Terrain hover/X entry, corrected facing/ownership checks, geometric pointer, visible window outline and A Move/X Options prompts, idle B exit with operation-first cancellation, view-preserving exit, free-camera duplication, renderer/style ownership isolation, camera-facing attachment start, unsnapped movement accumulation, controller-reachable Needs Placement, reload/preview reacquisition, per-tool Raise/Dig 3 and Smooth 5 defaults, and faster left/right terrain-settings adjustment with repeat/focus memory. These are implemented and covered by targeted tests, not accepted by the user until tested on the Thor.

This session additionally addressed native startup diagnostics, CI capture staging, colour-cancel image instability and overlapping architectural geometry. Details and unsuccessful iterations are in `reports/M1-repair-ca5185dc-delivery.md`. Original physical feedback remains in `reports/M1-apk2-playtest-followup.md` and `reports/M1-apk2-ui-playtest-followup.md`.

The separate terrain follow-up branch was NOT blindly merged. Its experimental all-face overhang picker and frozen-stroke camera layer are not used by this candidate; current repair-scene defaults and camera adjustments were integrated deliberately.

## Remaining work, in order

1. Get the user's focused retest: X enters a particular cottage, highlight identifies a window, A actually moves it, B restores/exits correctly; colour preview/cancel and two-cottage ownership; attachment recovery; reload then immediate sculpting. Preserve successful terrain responsiveness and controller grammar.
2. Direct selectable side/corner/height resize handles and complete manual-window resize/layout stability remain OPEN. Current resizing has not become the approved handle-driven design.
3. One-block overhang targeting follow-up, Slope performance and plane-guide clarity remain OPEN. Do not claim those solved by the capture-harness startup change.
4. Separate graphic HUD/panel/controller-glyph polish; higher-detail cottage prototype, river and tree refinement later. No M2.
5. Establish stable, securely retained Android signing identity and deliberate save migration before routine in-place updates; the isolated test app is only the safe present delivery path.

## Reproduction and constraints

Pinned Godot 4.7.2.stable.official.ed1daf0bf, existing locked templates/Voxel Tools. World dimensions, .125 visible grid, miniature scale and schemas remain unchanged. Preserve native caves/overhangs, IDs/manual overrides, one transaction per commit, undo/redo, cancellation, controller-only single-screen use, player/legacy saves and existing artifacts.

`.github/workflows/cottage-playtest.yml` runs the full regression and actual Mobile capture gates, then invokes `.github/workflows/thor-repair-apk.yml` ONLY after success. `tools/verify-repair-apk.py` uses the established aapt2 badging/aapt xmltree path, strict return codes and metadata checks. It produces an APK verification JSON receipt. Do not weaken readiness, visual equality, native-library or failure checks to manufacture a green build.

No native Godot runtime in the editing container; tests ran on Windows CI. The staged render test defers 3D drawing ONLY during CI bootstrap, keeps native generation/meshing and the runtime 45-second readiness deadline unchanged, and re-enables real rendering for every capture. This is not evidence that actual Thor startup performance changed.
