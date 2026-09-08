# Repair APK delivery — ca5185dc, 2026-09-08

## Result

Actual extracted APK privately uploaded to Drive. Complete CI run `34223484717` passed gameplay, Mobile rendering and Android verification before publication. Runtime commit `ca5185dc90a5f8bc6dbda4d646b2046b1f35cf5d`; branch `fix/m1-cottage-playtest-2`. No master merge or physical-device approval.

APK `hearthvale-m1-repair-ca5185dc.apk`, 37,756,626 bytes, SHA256 `b618d29f4229918333a036b476b4d487056e3cf68ed9c75490bf7fa771104421`. CI APK artifact `10054832687`; diagnostics/source/captures `10054770603`. Local archive and APK hashes verified; private Drive metadata readback confirms name, MIME and byte size.

APK: https://drive.google.com/file/d/1HklTqWnJ4RGN9mBxbMY1K0xphjlQhbZQ/view

Checklist: https://drive.google.com/file/d/1ukkFbVmsk89AKkduFQXOfEp6dt159eYU/view

Install as **Hearthvale Test ca5185dc**, a separate fresh-save test app. Original app/saves remain untouched. Package `org.hearthvale.game.repair.cca5185dc`; code 6, name `0.1.3-repair-ca5185dc`. The key is ephemeral; permanent update signing remains unresolved.

## Startup failure, measured rather than guessed

At `488fa081`, additional diagnostics reproduced editable native data but meshing not ready: the Microsoft Basic Render Driver completed only 62 process frames in 45.457 seconds, max gap 1476 ms. The unchanged native 45-second initialization deadline expired. Window focus and pause state did not explain the failure.

`m1_playtest_staged_render_test.gd` now defers only 3D drawing during CI bootstrap. Native generation, paste, meshing and readiness continue; the fixture asserts real meshing and enabled 3D before each capture. Bootstrap finished in approximately 3.7–4.2 seconds in the first staged runs. Full-size Mobile/D3D12 screenshots and pixel assertions then ran. This changes the CI capture harness, not runtime startup or Thor performance. The original unstaged failure is retained, not relabelled as a pass.

## Image stability repairs

The first staged run `68c01893` produced eight captures but failed exact colour-cancel restoration by ten pixels on the unselected cottage. Commit `64ed3f83` keeps a private deep snapshot of the applied recipe and skips identical same-revision geometry rebuilds, after normal stale-revision guards. This removed changes to the unaffected cottage.

Six remaining mismatched pixels appeared on the edited cottage. Corner-stone faces rounded onto the wall plane. Commit `4ee3d81e` changes the stone footprint to straddle both wall planes by whole cells, avoiding those coplanar faces. The original exact image equality assertion then passed. Pixel tolerances were NOT relaxed. Other earlier trim/window separation repairs remain part of the candidate.

## Test and export corrections

`cottage_render_stability_test` initially attempted MultiMesh transform readback in the headless dummy renderer. That did not provide useful uploaded transforms. The corrected test intercepts the actual generated box inputs while still calling the original upload path, checks their quantized bounds, caching/private ownership and stale revision handling; the separate real Mobile test checks actual pixels.

The first gated APK exported but verification failed because old aapt badging could not read the modern resource payload. `ca5185dc` uses the project's established aapt2 badging path, keeping aapt xmltree, signature verification and strict checks. The rerun passed; no failed or unverified APK was uploaded to the user.

## Evidence and boundaries

Existing 11 M1 integration suites pass. Additional targeting/repair/settings/stability tests pass (54, 60, 14, 35 checks respectively). Actual Mobile capture test passes 41 checks across eight captures, including byte-identical baseline/cancelled two-cottage images. Identical runtime captures at `46dbfe02` were inspected locally for window targeting and Needs Placement focus; the last candidate commit changes only the packaging verifier, and all render gates also reran successfully for it.

Android package/version, signature, Mobile metadata, ARM64-only architecture, pinned voxel-library bytes, compiled repair scene and excluded development resources all verified. This does not establish physical Thor usability, frame rate or installation testing. Direct resize handles, complete manual-window resize refinement, one-block-overhang targeting, Slope performance/guide redesign and graphic HUD polish remain open. Use the focused checklist rather than declaring M1 complete.
