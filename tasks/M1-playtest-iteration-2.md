# M1 physical-feedback iteration 2

Authorized by the player after the tree trial. This supplements the editable cottage and sculpting tickets; all existing acceptance requirements remain. No M2, villagers, additional house catalogue or engine/backend replacement.

- Make default held sculpting substantially faster; retain a usable precision rate and controller strength adjustment.
- Repair fixed-height flattening across both higher and lower surfaces. Preserve slopes, native caves, one-stroke history and save compatibility.
- Fresh cottages use quarter scale, half the preceding build's linear size. Existing saved transforms remain until the explicit undoable Miniature scale action. Trees should rise above the cottage. Test dimensions and attachments after conversion.
- Generate/remove/reflow automatic windows by available wall space. Suppress optional shutters when crowded. Preserve manual/modified/suppressed choices and recover invalid attachments. Allow manual flower boxes and shutters.
- Use a 0.125 world-unit visible cell for derived cottage, vegetation and rock geometry. Merged surfaces represent integer cell spans. Native terrain uses the same 0.125 cell edge (four times finer per axis than the previous 0.5 grid). Preserve old saves through exact volumetric upsampling; keep legacy checkpoints. Measure the larger data/memory cost. Earlier plans to count visibly coarse terrain steps as merged fine cells were rejected by the player.
- Provide separate controller foliage and tree brushes, plus local planting removal. Seed a restrained scatter of trees, foliage and rocks; save placement records in the same atomic checkpoint. A terrain edit clears roots intersecting changed cells, not its whole bounding rectangle. Undo/redo/cancel restores both layers; reload must not resurrect removed planting.

Evidence: rerun full existing regression suite, new placement/history/checkpoint and visual-grid tests; actual Mobile normal/close/edited captures; short desktop cost measurements; versioned signed ARM64 debug APK. Upload to the player's Drive only when the writable connection is actually available. Physical Thor checks and palette/visual approval remain separate and pending player review.
