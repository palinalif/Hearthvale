# Roof finish 01 — courses and eave definition

Player approved the roof/material pass following the lighting comparisons. This candidate starts from verified master 461a5da4, not the unresolved catalogue branch. Lighting and the meadow palette are deliberately unchanged to isolate roof appearance. No new art has been merged.

## Kept after the first actual render review
A final generated-presentation layer adds staggered, tile-sized courses to ordinary gable roofs without changing roof authority, saved dimensions, anchors, placement footprints or UI. Gables retain their original envelope and continuous lower skin, with one-detail-cell recessed end seams and a seated eave lip. The three existing roof colour batches remain; the fascia adds one batch. Details remain cubic 0.0625-world-unit cells.

Joined/upper-floor roofs retain their exact established geometry, pitch and eaves, but regroup colours using coordinate-based course rhythm. Physical lap relief and improvement of joined-roof silhouettes are still later work; this recolouring is not presented as that geometry repair.

The treatment applies to terracotta, moss tile, slate and wood shake. Thatch, standing seam and green roof keep their existing rendering rather than gaining inappropriate tile joints. Roof colour selection, private materials, highlights, picking cache invalidation and placement ghosts retain their existing routes. Generated-node tags avoid rebuilding the finish on unchanged presentation calls.

## Rejected custom-roof approach
Initial commit df7da13c subdivided every custom slab to give it per-tile tint. Actual Mobile comparison made the cost/benefit poor: a hip roof rose from 15 to 3325 rendered box instances with little improvement at the captured distances. Saltbox rose from 32 to 1093. Remove that production path and its unused tessellator rather than ship extra geometry for a barely visible difference. Custom hip/shed/saltbox/gambrel shapes remain unchanged for this slice. Their paired captures remain in the test and now must be pixel- and count-identical. A future custom-roof pass needs genuinely useful lap geometry or a cheaper surface treatment.

The same first-run manifest measured the ordinary cottage roof at 2360 baseline instances versus 952 with courses (5 versus 6 batches); resized gable 2573 versus 987 (5 versus 6 batches). The joined upper-floor roof remained 1340 instances/4 batches. These are renderer-geometry counts, not measured Thor frame-time improvements.

## Evidence and current verification
Initial focused run 34569440898 on df7da13c succeeded. Downloaded artifact 10187289161, verified SHA-256 26af59d7b7465b26a3c41010cb8663d3b0917b1b765150b120318e2fe6213c7f, read all logs and visually reviewed all 12 frames. Godot 4.7.2.stable.official.ed1daf0bf, D3D12 Forward Mobile on Microsoft Basic Render Driver: layout 2865/2865, roof design 27/27, roof accessories 32/32, direct house UX 20/20, actual Mobile roof comparison 66/66 and 12 captures. Render error log empty. This is evidence for that predecessor, not for the trimmed follow-up.

New layout tests retain half-bond seams, stable negative coordinates, solid backing and exact gable/cubic-grid bounds. Actual Mobile review captures paired normal/close gables, unchanged hip and saltbox, a resized steep gable and a genuinely added upper floor. It verifies records remain identical, refresh stability and no extra roof instances / at most one extra fascia batch for changed roofs. All existing project regressions and the full gated delivery remain required. Baseline/candidate use identical lighting, cameras and frozen wind. The original renderer switch is review-only and never stored in a save.

At trimmed-source preparation: source/diff review only; native tests, all twelve final captures and package verification must run again. There is no local Godot executable and a git network probe failed DNS. Runtime evidence comes from pinned CI, not a local engine. No new verified APK, Drive upload, physical Thor performance result or player aesthetic approval is claimed. Lead exposed here is GPT-6 Astra Pro rather than repo-preferred Sol; no model switch/subagents used. Keep PR draft pending evidence and review.

Primary API reference: official Godot MultiMesh class documentation (use_colors before instance_count and vertex_color_use_as_albedo), https://docs.godotengine.org/en/stable/classes/class_multimesh.html. No third-party art or reference-game assets. The user's Town to City screenshots guide style.

Facade/window/foundation depth, broader contact shading, custom roof relief, tree crowns and ground/path transitions remain subsequent slices, not completed here.
