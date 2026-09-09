# M2-03 home details and editing UI

Implemented a unified residential-detail pass for the three M2 homes.

## Player-facing result

- Riverside, woodland, and village recipes now default to cottage, lodge, and Tudor window/door families respectively.
- The variation browser is categorized as **WINDOW STYLES** or **DOOR STYLES** and offers four window families and three door families on any compatible house.
- **Add window** and **Add door** are available beside the existing decorative attachment actions. Their previews stay wall-locked, choose the nearest clear position, cut the shell only on commit, and retain independent IDs.
- The woodland lodge uses opening-aware stacked-log courses and projecting log ends. The tall village home uses dark Tudor posts, rails, and stepped diagonal braces.
- Colour and variation pickers dock to the opposite screen edge from the selected detail, show colour swatches, and preserve live A-apply/B-restore behavior.
- Amber highlighting is a material overlay on the actual selected detail or cottage geometry. The earlier approximate screen-space rectangles are not used.

## Verification

- `tools/check.ps1`: pass (`check ok`), including checkpoint compatibility, building authority, detail visuals, the 0.0625 decorative grid, terrain/controller acceptance, save/reload, and undo/redo.
- Focused scene tests: M2 catalogue 29/29; attachment placement 31/31; cottage edit UX pass; terrain/detail highlighting 61/61 after the mesh-outline assertions.
- Actual Forward Mobile / D3D12 captures: cottage repair/detail UI 39/39 and residential comparison 6/6 at 1280×720.
- ARM64 APK export, verification, gated Drive upload, and physical Thor judgment are recorded separately after the exact commit is pushed.

## Review images

- `reports/screenshots/m2-home-catalogue/three-home-recipes.png`
- `reports/screenshots/m2-home-details/window-colour-picker.png`
- `reports/screenshots/m2-home-details/door-variations.png`
- `reports/screenshots/m2-home-details/house-mesh-hover.png`
