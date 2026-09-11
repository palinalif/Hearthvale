# Direct house editing UX candidate

User-authorized interaction work, not a lighting/art pass. Based on window/shutter head c67f51e; run 34541287534 passed its complete native/Mobile, APK/Windows verification and Drive upload. The new candidate is not covered by that predecessor result.

## Implemented candidate

- Point at exposed roof/wall geometry and press A for a compact contextual action row. Existing detail picking retains priority. Roof shape choices are icon-only; roof/wall material controls reuse the approved compact palettes. Selecting any wall recolours all walls of that house; personal decor colours remain independent.
- Window/Door begins on the pointed-at facade. Ground-floor exposed runs now include L/T/U wings and courtyard walls; concealed legacy wall portions reject attachment placement while retaining anchor identities. Coplanar aliases do not bypass manual overlap checks.
- Resize targets the existing stable section ID. Select an edge with left/right, expand/contract with up/down or vertical left stick, confirm/cancel. The opposite edge stays fixed. All upper-floor supports are validated; invalid attempts have an outline/reason and cannot commit. Preview ID allocation and generated windows live in an isolated document; commit creates one undo transaction.
- Main-section resizing rebases its coordinate origin without translating other sections. Added sections and upper floors keep their level and identities; no-op/stale commits are rejected.
- Add section and Add floor are distinct actions seeded from the selected section rather than an unrelated last/highest portion. Accumulate left-stick motion before snapping so gentle input can move a placement.
- Whole-house Move/Resize is retained under the explicit House action. The legacy controller regression now enters that chooser through real contextual navigation; its existing move/cancel/history/preservation assertions remain.

## Verification required

New pure/native tests cover courtyard support, manual placement, identities/reload, one-sided section math, read-only previews and support validation. The full-scene test exercises contextual courtyard placement, joined material preview and upper-floor editing. Actual Mobile mode must also find a rendered roof and save four UI views. All new tests and that Mobile requirement are added before the existing export gates, with an additional targeted workflow for faster diagnosis.

At candidate source preparation: whitespace/source review only. No local Godot executable is installed; no native, render, APK or physical Thor success is claimed until exact-head CI results are read. Lead is GPT-6 Astra Pro rather than repository preference Sol; no subagents or model switch were used. Keep this larger pass draft and unmerged for the user's next Thor review. PR #7's earlier conditional merge permission does not automatically approve this new broad UX candidate.

## Deliberate limits / review points

This exposes the existing roof-profile vocabulary; it does not redesign joined roof generation or claim every profile matches its single-house silhouette. Shape presets and less-common catalogue actions remain available through Home options; primary editing no longer requires that menu. Screen-space pointer feel, icon clarity, roof-hit caching cost, dense-scene performance and corner cases of overlapping sections need actual device review. Windows whose support genuinely disappears remain recoverable rather than being silently deleted or reassigned to arbitrary walls. Lighting experiments remain separate and inactive.
