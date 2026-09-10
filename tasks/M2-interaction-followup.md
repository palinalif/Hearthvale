# M2 interaction follow-up — Thor feedback, 2026-09-10

The player tested the 9f7d0eb1 APK and reports that the opaque shader looks good and play is good. No numerical device performance claim is inferred. The player then requested interaction work before further visual polish:

1. Personal house-detail colour must not be overwritten by the house accent. Preview, apply, cancel, undo/redo, regenerated custom windows, duplication and reload must display the actual personal choice. Natural wood must be an explicit choice, not confused with missing/inherited colour. This first patch addresses that contract without adding a save schema or changing the accepted shader.
2. Existing upper-floor portions need a discoverable controller selection and resize route after placement, with in-world feedback. The current add-portion workflow is not a substitute for editing an existing portion. Preserve portion IDs, floor support, authoritative windows/recovery, preview/cancel and one undo transaction. This remains **not implemented by the colour patch**.
3. Reduce duplicate instructional prose in submenus, particularly recolouring: concise contextual title, swatches/short names and the existing controller prompt strip. Preserve necessary warnings, readability and controller focus. This remains **not implemented by the colour patch**.

The lighting study remains separate and inactive. Do not merge new visual work or imply that these UX requests are complete from a passing colour test.

Verification of the colour patch: new regression checks actual gameplay material colours, not just IDs in saved records, and is added to the unchanged placement/delivery gate. No local Godot executable is available in this session; runtime, Mobile capture, APK and physical-device checks are pending at commit creation. Source model exposed in this session: GPT-6 Astra Pro, not the repository's preferred Sol; no subagents or model switch are used. Keep the follow-up PR draft pending CI and the player's next test. The player permits proceeding without waiting for APK export; an unverified package is not delivered.
