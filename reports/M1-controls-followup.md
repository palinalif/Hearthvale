# M1 controls and miniature-scale follow-up

Status: implemented and integrated into the Astra M1 rework; physical controller comfort remains not run. See [visual rework evidence](M1-visual-rework.md).

The player could not see the raise/dig target, found Dig apparently resizing the cottage, and found the cottage much too large. These are failed usability observations, superseding any implication that the first automated controller pass established comfortable use.

Lead diagnosis: one combined menu exposes terrain tools while building mode is active. Choosing Dig updates sculpt_tool but leaves view_context as building; A begins resizing and terrain preview remains hidden. The starting target is also inside the large cottage, and the tiny world-space centre marker has no minimum screen size.

Implementation requirements: explicit mutually exclusive modes/actions, correct transitions and release latches, persistent action prompts, visible contrast centre target plus restrained local highlight/ghost, ground target away from the cottage, coherent half-scale miniature with correctly transformed handles and reversible conversion for loaded designs.

The initial controls and scale fixes were delegated to gpt-5.6-luna/high under the then-current policy. The player subsequently superseded mandatory Luna delegation. The main Astra session directly implemented the visual rework and integration fixes; no Luna substitution was used for that rework.

A further integration defect passed the raw airborne cursor into the terrain backend while displaying a grounded preview. The stroke now starts at the sampled surface and carries a fixed aim offset, preserving the captured plane and actual target correspondence. Controller regressions exercise an occluded Dig stroke and assert unchanged building records.

The first strengthened acceptance run exposed a comparison between integer metadata and JSON-restored floats. The comparison now normalizes both complete documents through their persisted JSON representation, excluding only monotonic revision/ID bookkeeping as before. The design data itself was intact. Final automated, visual, build and device evidence is in the linked rework report.
