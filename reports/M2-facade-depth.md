# Facade finish 01 — opening relief and house-to-ground depth

2026-09-11. Starts from the exact verified joined-roof source `0800a6f134c8e32ea7e5c08a43a139a3e83d2a50`. This is presentation-only visual work after the player's roof-delivery gate passed. It does not merge or retarget PRs #11/#12, and it does not include the separately delegated build-catalogue repair.

## Candidate scope

Add restrained physical depth where the current houses read flattest: projecting window sills, shallow lintels, door thresholds, a stepped stone/plinth facing along exposed ground-floor wall runs, and a one-cell shadow/reveal directly beneath each exposed wall top. The existing window joinery, shutters, bay-window sill/canopy, door surround, roof fascia/eave geometry and raised-foundation system remain authoritative presentation layers; the new pass supplements rather than replaces them.

Facade geometry derives only from current wall-support and detail records. Joined L/T/U courtyard faces and upper storeys use their real exposed runs; deleted/hidden surfaces and Needs-placement details are skipped. Plinth runs are cut around real door openings. Bay windows retain their bespoke sill/canopy instead of receiving a duplicate. Round windows get a projecting sill but no rectangular top lintel. All new pieces use the existing cubic 0.0625 decorative grid and are batched by treatment rather than creating one scene node per stone.

No saved field, surface ID, attachment anchor, collision, placement footprint, wall/roof material authority, personal decor colour, resize increment or undo transaction changes. The wall material/style only selects a quiet derived trim/plinth palette. Generated facade nodes remain whole-house highlightable but are not named as individual details and do not enter detail selection.

## Verification plan

Focused headless coverage derives simple, joined-courtyard and real upper-floor runs, checks door-cut plinth segmentation, confirms read-only generation and toggles the finish without changing the serialized building. Inherited roof, window and direct-house tests remain. Actual Mobile produces matched before/after 1280x720 views for front close, reverse, U courtyard and a genuinely added upper floor; fixed camera and landscape/building records must remain identical while rendered pixels change.

After focused visual review, add these tests to the unchanged full placement/delivery gate and require a verified ARM64/Windows build plus private Drive upload before handoff. Physical Thor quality/performance remains player evidence.

## Integration hygiene

The current draft stack is intentionally not merged during this visual experiment. After this facade slice and the independent catalogue repair are both green/player-reviewed, create a single explicit integration branch from `master`, bring in the verified visual stack in dependency order (roof 01 -> joined roof 02 -> facade), bring in the catalogue only from its independently green head, choose/enable the approved lighting profile, then run one cumulative full delivery and Thor smoke test. Merge that integration PR to `master` only with player approval. This prevents the present stack of draft PRs from becoming the long-term branch structure.
