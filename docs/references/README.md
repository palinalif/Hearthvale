# Hearthvale reference notes

## Primary visual references

Player clarification, 6 September 2026. These roles guide Hearthvale's art direction; they do not describe or prescribe the source games' internal rendering or simulation techniques.

| Reference and official source | What to study |
| --- | --- |
| [Town to City](https://store.steampowered.com/app/3115220/Town_to_City/) — Galaxy Grove / Kwalee | Architecture, street decoration, planting, and intimate village composition. |
| [Station to Station](https://store.steampowered.com/app/2272400/Station_to_Station/) — Galaxy Grove / Prismatika | Landscape palettes, vegetation, and the detailed voxel-miniature aesthetic. |
| [Tiny Glade](https://store.steampowered.com/app/2198150/Tiny_Glade/) — Pounce Light | Building interaction: drawing, stretching, and responsive architectural details. |

Target readable silhouettes, fine stepped details, coherent colours, inviting lighting, and restrained surface variation. Detailed does not mean oversized cubes, noisy textures, or photorealism. M0's terrain is much too coarse according to the player's Thor playtest; its block size is not the visual target.

Keep decorative detail resolution independent of the terrain editing grid. A visible voxel need not be an independently simulated block; fine geometry can supply decorative detail while the native terrain remains volumetrically editable. Judge scale at the normal gameplay camera and in close inspection. Structural terrain, cottage shells and roof profiles, general vegetation and props use the `0.125` world-space unit. The player-approved exception is a cottage-only `0.0625` presentation tier for visible roof tiles/edges, window and door joinery, entrance canopy, shutters, trims, flower boxes and flowers; structural edits, roof authority and anchors remain at `0.125`.

During M1, present a small cottage-and-riverbank scene for player visual review before expanding the building catalogue. Review architecture and nearby decoration/planting against Town to City, landscape colour and vegetation against Station to Station, and building interaction against Tiny Glade. The original images below continue to guide terrain and geography. The player has separately authorized M1's editable cottage and continuous terrain sculpting; these visual references add no railways or economic management and change no M0 evidence.

Planet Coaster / Planet Zoo additionally guide continuous terrain-sculpting interaction: gentle held strokes, brush influence, fixed flattening references and local smoothing. This is an interaction reference, not a replacement for the visual direction above. See `../../tasks/M1-terrain-sculpting.md` for the authoritative requirements.

The linked game imagery remains the property of its respective rights holders. Links are reference sources, not an asset licence; no game assets or screenshots have been copied into production content.

## Original supplied terrain and geography references

These three images were supplied by the player as inspiration. They are not screenshots of this project, production assets, or a licensed asset pack.

`01-terraced-canyon.jpg` shows warm voxel terraces and a canyon. It visibly includes AURELION / Kingsfall Basin labels and Reddit attribution to u/LostRequirement4828 in r/codex.

`02-stone-crossing.jpg` shows a stone arch crossing and turquoise water, with AURELION / The Old Crossing labels.

`03-valley-overview.jpg` shows a broad mountain valley and river, with AURELION / Kingsfall Basin labels.

Use them for private design discussion about terrain and geography: landforms, terraces, arches, river placement, valley scale, and atmospheric depth. The primary games above guide the overall visual treatment. Do not strip attribution, claim the imagery as project work, or extract and redistribute the depicted scenery as assets. Seek permission before reusing these images in a public project presentation.

## Lead visual review — first M1 correction

The player explicitly rejected the first M1 scene's weak adherence to these references. Naming the games in a worker prompt did not establish a visual match. The lead re-opened the official Steam pages and inspected their in-page gameplay imagery during the controls follow-up.

Observed Town to City cues: compact buildings within a larger composed scene; layered terracotta roof edges and small repeated tile steps; relatively small windows with contrasting frames/shutters; warm plaster, restrained cornices and planting that links buildings to paths. Observed Station to Station cues: fine stepped roof surfaces, clear tree silhouettes made from many small foliage clusters, layered greens/ochres, and warm light against cooler shaded land.

For this same M1 cottage, require finer derived roof/trim geometry, a smaller proportioned door, coherent half-scale details, clustered foliage and limited bank planting. Keep broad surfaces calm. Use shared materials and batched geometry; visible detail must not become individually simulated blocks. Do not copy reference assets, add reference-game systems, or call the art approved solely because geometry counts increased.

The lead must inspect actual normal/close gameplay captures against these cues before handoff and explicitly report remaining differences. Player visual approval is still required.


## Astra rework comparison

The actual pre-rework Mobile captures are retained as `reports/screenshots/m1-controls-*.png`; the three render iterations and resized/moved-window views are recorded in `reports/M1-visual-rework.md`. The changes address the observed roof layering, facade depth, compact proportions and vegetation scale. Remaining gaps include the straight channel, raised pad edge, simple gable facade and still-stylized foliage. Reference imagery was inspected on the official pages; no reference-game assets were downloaded into production. Visual approval belongs to the player.


The player additionally requires a single visible voxel size across all asset families and terrain detail. Reference matching must not introduce a different voxel density per asset. Compare assets side by side after their final transforms; larger forms use more cells. See `../design.md` for the requirement and current noncompliance audit.


## Collected rulebook images

[Open the illustrated reference board](rulebook/index.html) or [read the annotated image index](rulebook/README.md). Sixteen official screenshots are stored locally with source URLs, attribution and hashes, alongside links to the three supplied geography references and three Hearthvale comparison captures. This is reference material only; game runtime/build files are unchanged.
