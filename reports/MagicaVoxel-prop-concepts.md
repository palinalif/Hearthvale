# MagicaVoxel prop concepts — hamlet vocabulary gaps

Status: **proposal only**. Nothing here is authored, staged, promoted or wired.
Awaiting player selection before any MCP work.

## What the game already has (in-game, runtime)

| Family | Styles | Source |
| --- | --- | --- |
| Street furniture | `bench`, `village_table`, `lantern`, `signpost`, `well`, `chopping_block`, `log_stack` | procedural builders (`m2_starter_props.gd`, hamlet visual) |
| Street furniture | `barrel_planter` + `_herbs` + `_light` | authored vox (barrel family) |
| Street furniture | `topiary_pair`, `beehive`, `wheelbarrow`, `flower_arch`, `garden_gnome`, `garden_gnome_small`, `garden_gnome_tall` | authored vox |
| Street furniture | `clothesline`, `potted_trio`, `market_crate`, `bird_feeder`, `mailbox` | authored vox (prop set) |
| Gardens | `cottage_flowers`, `kitchen_rows`, `herb_garden` × 2 sizes each | authored vox (6 plots) |
| Boundaries | `rustic_fence`, `rustic_gate` | procedural |
| Bridges | `timber`, `stone` | procedural |
| Vegetation | 6 trees, 11 foliage variants, 3 rocks | authored vox |
| Cottage details | 3 windows, 3 doors, chimney, lantern, signpost, planter, steps, rock, fence, hedge, trellis, flower box, root flare, grass patch, ivy, shutter, trim | procedural |

Palette in use (authoring JSON, indices 1–11):
`#79563f` warm brown · `#638348` green · `#486d46` deep green · `#87a657` sage ·
`#df9a8b` rose · `#c7b897` cream · `#9a795c` tan · `#594337` dark timber ·
`#4b514d` slate · `#6b6f64` grey stone · `#473629` deep brown.
Prop sets additionally use warm cap groups 12/13/14 and dark 15.

## Reading of the current set

The prop vocabulary is **domestic and decorative** — laundry, crates, feeders,
planters, gnomes. It reads as *a cottage with nice stuff around it*. What it
does not yet read as is **a hamlet**: there is no shared focus, no working
side, and no edge vocabulary. Concretely:

- **No centre.** Nothing gives a cluster of homes a reason to be a group.
  No meeting point, no landmark, nothing taller than a lantern.
- **No water.** One well. No trough, pump, basin, rain barrel, crossing.
- **No work.** One chopping block and one log stack. No harvest, storage,
  garden-work, cartage.
- **One fence voice.** Rustic fence + gate only; no stone, wattle, rail, hedge
  run to give fields and gardens edges.
- **One light.** A single path lantern; a hamlet needs a taller, spaced light.
- **Seating is one shape.** Only the slatted timber bench.

## Authoring constraints (all concepts below obey these)

- `0.0625` presentation cell; **declared volume even on every axis** (an odd
  axis half-cells every face and degenerates greedy quads — this bit the
  `potted_trio` first pass).
- Pivot at the horizontal centre of the declared volume, model base at `Y=0`.
- Restrained village palette only; matte, non-metallic bake.
- Prop triangle budget ~100–450 (existing props: 104–364; table 280).
- Footprint registered in `FURNITURE_STYLES` must match the authored volume.
- Pipeline: MCP staging → `vox_to_obj.py --greedy` → pinned editor import →
  `bake_mesh.gd -- 0.0625` → receipt + test + Mobile render + Thor approval.

## Tier A — hamlet anchors (recommended first slice)

Five props that make several homes read as one settlement.

| Style id | Item | Volume X·Y·Z (cells) | Footprint | Est. tris | Design note |
| --- | --- | --- | --- | --- | --- |
| `market_cross` | Village market cross | 20·44·20 | 1.25 × 1.25 m | ~420 | Stone plinth, four timber posts, shingled canopy, small hanging bell. Tallest thing in the catalogue today is a 0.5 m lantern — this is the landmark. |
| `lamp_post` | Tall iron lamp post | 12·56·12 | 0.75 × 0.75 m | ~240 | Dark metal post, four-pane glass head, warm glow. Spaces along paths; pairs with existing `lantern` for near/far rhythm. |
| `notice_board` | Notice board | 24·30·8 | 1.5 × 0.5 m | ~260 | Two posts, board with pinned cream papers, small candle box, mud-splashed base. |
| `stone_bench` | Mossy stone bench | 28·8·10 | 1.75 × 0.625 m | ~190 | Slab seat on two block legs, chipped edge, moss on the sunny side. Gives seating a second voice and ages the green. |
| `maypole` | Maypole | 12·64·12 | 0.75 × 0.75 m | ~300 | Painted pole, woven rose/cream ribbon crown, ring of stones at the base. Cheap vertical drama, strong silhouette from a distance. |

## Tier B — water and garden work

| Style id | Item | Volume | Footprint | Est. tris | Design note |
| --- | --- | --- | --- | --- | --- |
| `water_trough` | Stone water trough | 32·12·14 | 2.0 × 0.875 m | ~250 | Hollowed stone basin on stub legs, dark water plane, bucket on the rim. |
| `village_pump` | Village pump | 16·34·16 | 1.0 × 1.0 m | ~330 | Stone collar, iron column, angled spout, bucket beneath. Reads as the well's working cousin. |
| `rain_barrel` | Rain barrel | 14·18·14 | 0.875 × 0.875 m | ~200 | Lidded barrel, tap, overflowing rim, splash of cream. Sits against a cottage wall. |
| `garden_workset` | Watering can, seed tray, spade | 20·14·14 | 1.25 × 0.875 m | ~280 | Casual cluster for garden edges; ties gardens to the prop vocabulary. |
| `bird_bath` | Stone bird bath | 14·18·14 | 0.875 × 0.875 m | ~180 | Pedestal basin, shallow water, one perched bird. Pairs with `bird_feeder`. |

## Tier C — harvest and storage

| Style id | Item | Volume | Footprint | Est. tris | Design note |
| --- | --- | --- | --- | --- | --- |
| `hay_cart` | Hay cart | 44·26·26 | 2.75 × 1.625 m | ~420 | Two spoked wheels, slatted body, loaded hay cresting over the shafts. Biggest single hamlet-read win in this tier. |
| `hay_bale_pair` | Hay bale pair | 32·18·20 | 2.0 × 1.25 m | ~300 | Two banded bales, one loose flake. Field-edge filler. |
| `pumpkin_patch` | Pumpkins and vine | 24·10·24 | 1.5 × 1.5 m | ~260 | Three pumpkins, trailing vine, one split crate. |
| `grain_sheaf_trio` | Tied grain sheaves | 16·22·16 | 1.0 × 1.0 m | ~230 | Three sheaves leaning on a standing rake. |
| `apple_baskets` | Apple baskets | 18·14·18 | 1.125 × 1.125 m | ~290 | Two stacked baskets of rose apples, one tipped with spill. Extends `market_crate`. |

## Tier D — edge vocabulary (composition elements, fence-shaped)

These are **not** point props; they belong with `rustic_fence` as placed runs.

| Style id | Item | Est. tris | Design note |
| --- | --- | --- | --- |
| `stone_wall` | Low mossy stone wall | ~340 | Dry-stone course, moss caps, one gap. Separates garden from field. |
| `wattle_fence` | Woven hurdle | ~300 | Woven wands between stakes; softer, older than rustic fence. |
| `rail_fence` | Split-rail corner | ~280 | Two rails and a corner post; reads open and pastoral. |
| `hedge_run` | Low clipped hedge | ~260 | Continuous green mass, matches `topiary_pair` language. |
| `stepping_stones` | Stepping stones | ~150 | Five flat mossy stones; path crossing without a bridge. |
| `footbridge_rail` | Railed plank footbridge | ~380 | Third bridge style: narrow, railed, for garden/stream crossings. |

## Tier E — charm (matches the existing gnome voice)

| Style id | Item | Est. tris | Design note |
| --- | --- | --- | --- |
| `scarecrow` | Scarecrow | ~260 | Cross frame, straw head, patched shirt; garden sentinel. |
| `stone_urn` | Stone urn planter | ~200 | Tapered urn with spilling cream/rose; doorway flanking pair. |
| `hanging_basket` | Eave hanging basket | ~180 | Hook, cord, blossom spill; needs an eave anchor decision. |
| `cart_wheel` | Lean-to cart wheel | ~170 | Old wheel against a wall; pure age-maker, cheapest item here. |

## Voxel-upgrade candidates (already in game, currently procedural)

`bench`, `lantern`, `signpost`, `well`, `chopping_block`, `log_stack`,
`rustic_fence`, `rustic_gate`, `timber`/`stone` bridges. These are the items
players see most, and they are the only ones not authored in MagicaVoxel.
Upgrading them buys visual consistency without new catalogue scope — the
`village_table` precedent shows the pattern (style id and footprint unchanged,
procedural builder kept as fallback, so old saves keep working).

## Suggested order

1. **Tier A** (5 props) — one bounded slice, one CI shard, one Thor review.
   This is the slice that changes how a hamlet *reads*.
2. **Tier D fence runs** (`stone_wall`, `wattle_fence`) — composition tools
   need more than one boundary voice.
3. **Tier B water set** — trough + pump + rain barrel.
4. Voxel-upgrade of `bench`, `lantern`, `signpost` (highest-seen procedural).
5. Tiers C/E as content polish.

## Wiring each new style requires

`FURNITURE_STYLES` entry (name, footprint, summary) · `FURNITURE_STYLE_ORDER` ·
`PROP_MESHES` + colour group in `m2_hamlet_visual.gd` · canonical `.vox` +
OBJ/MTL/receipt/baked `.res` · authoring provenance JSON · asset test
(follow `tests/m2_table_asset_test.gd`) registered in the `hamlet` CI shard ·
actual Mobile render · Thor visual approval.
