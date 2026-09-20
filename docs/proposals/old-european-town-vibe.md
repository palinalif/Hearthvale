# The Old European Town — design exploration

**Status:** discussion document (IDEA-009). Not a ticket; nothing here is authorised until the player approves a phase and we write a `tasks/` ticket.

The goal in one sentence: **a small medieval-flavoured market town that looks like it grew over centuries, not a planning document** — crooked lanes, dense little gabled houses, a square with a well, horses, carts, smoke, laundry, and life that makes the places the player builds feel inhabited.

---

## 1. What we're reaching for

The mood is "old-timey European town", not a specific era: think a hillside market town you'd cross on foot —

- **Lanes** that meander and fork, narrowing and widening, rather than a street grid.
- **Buildings that face the road**, packed close, with slightly different heights, roof pitches and orientations, so every street corner is a different view.
- **One or two landmarks** visible from far away (a chapel steeple, a windmill) that make the town readable from a hillside.
- **Wear and life**: ruts in the lane, laundry strung between houses, smoke from chimneys, animals at feed troughs, a cart parked in the inn yard.

Per project rules the visual references stay the same trio — *Town to City* for architecture and garden composition, *Station to Station* for landscape and fine miniatures, *Tiny Glade* for building interaction — plus the approved palette direction we just shipped (olive-sage meadow, terracotta roofs, warm timber, muted greens). The town reads cozy, not grimy: no squalor, no rats, no poverty, and no traffic (IDEA-002 was rejected on purpose).

## 2. What we already have (the base this builds on)

| System | Today |
| --- | --- |
| Homes | 3 designs — riverside cottage, woodland lodge, village gable; varied wall/roof materials (incl. terracotta), 6 accent colours, saved per house |
| Roads | painted structural regions: packed earth (1–2 voxel stepped U-cut), cobblestone, stepping stones; 2 bridge styles (timber, stone); deterministic 0.0625 m wear presentation |
| Streets | 23 furniture styles: benches, village table, lanterns, signposts, 3 barrel planters, well, chopping block, log stack, clothesline, potted trio, market crate, bird feeder, mailbox, topiary pair, beehive, wheelbarrow, flower arch, 3 gnomes |
| Grounds | 3 garden styles, rustic fence + gate |
| Nature | trees/foliage/rocks records, lakes/streams/waterfalls, meadow palette |
| People & animals | none placed yet — `design.md` §6 already defines the behaviour model (state machine, activity points, reservations, bounded habitats) with ducks first, then cats/dogs/sheep |

Everything below is an *addition* to those systems, not a replacement of them.

## 3. Crooked, uneven pathways

The painted-region road system is already the right tool — winding comes free because there is no centreline to keep straight. The work is in the *vocabulary* of the surface:

1. **A lane hierarchy.** Three tiers that read at a glance:
   - *Main lane* — widest, 2-voxel cut, cobblestone. The town's backbone through the square.
   - *Side lanes* — 1-voxel cut, packed earth. Most streets.
   - *Footpaths* — stepping stones. To gardens and doorways.
   The starter world should demonstrate all three so the player learns the language.
2. **Wear in the wheel tracks.** Cobble presentation at 0.0625 m: a gently worn centre — two parallel tracks about a cart-wheel-width (≈1 m) apart — slightly darker and 1 detail-voxel lower than the flanks. Low contrast, deterministic per cell. This one change is what makes a road read "horses have passed here".
3. **Steps where the land changes.** The existing stepped U-cut already reads as ancient stone steps on slopes; add small 0.0625 m step lips and occasional wider treads at direction changes so cut-road changes of level feel intentional rather than accidental.
4. **Soft edges.** Edge rings already break back to grass; add sparse 0.0625 m weeds and tiny stones in the gaps of wide cobble runs (a few percent of cells, seeded). Puddles: small dark-wet patches in low spots near bridges and the square, presentation-only, no water simulation.
5. **Forks and corners.** The brush already rounds corners; encourage T-forks and 3–4-way junctions with a slightly widened intersection. No road in the town should be a straight line longer than a house or two.
6. **Arched bridge.** A third bridge style: single-arch stone, the kind you see over European streams. The bridge system already owns endpoints/width; a new style is a new asset + presentation.

## 4. The town: density, the square, new building types

Homes today are the only buildings, so the town has nothing to orbit around. The old-town feel mostly comes from a handful of *public* buildings:

| Building | Role in the vibe | Notes |
| --- | --- | --- |
| **Inn / tavern** | The social heart — the design doc's "arrival/linger" place | Gabled, a sign board over the door, barrels and a parked cart out front, lanterns by the door, maybe a horse tied up |
| **Chapel** | The distant landmark — the tallest thing in the valley | Small by real-world standards (cozy scale); steeple + one round window; a small walled garden, not a graveyard |
| **Stable** | Home to the horses (below) | Open front, hay, feed trough, cart storage; fence yard variant |
| **Windmill** | The other landmark; the one thing that moves on its own | Body + rotating sails; the cheapest "the town is alive" cue we can get — a few bones, one rotation |
| **Market stalls** | Life in the square | A few small stalls with stretchable awnings (procedural) over voxel crates — see §6 |
| **Bakery / smithy** (optional) | Smoke and story | Could start as home *variants* (awning + chimney emphasis) rather than new designs |

**Massing language** — the difference between "three houses" and "a town" is roof and wall vocabulary:

- **Stepped (crow-stepped) gables**: a roof-course variant for the gable end. We already have a roof-courses pipeline; this is a new course shape, not a new system.
- **Jettying**: the upper storey overhangs the lower one by half a foot — the single most "old town" silhouette, and it's a massing tweak.
- **Steepness variety**: one of the three home designs should push the pitch noticeably steeper; the village gable is the natural candidate.
- **Orientation**: the starter town should place homes at slight angles to the lane (the placement system already supports free yaw), doors facing the road, with a house or two set back behind a garden gate.

**The square**: the one open space. Cobble, the existing well, two benches, the market stalls, a clothesline strung between two houses, and a single horse at a feed trough — the picture the game is named after.

## 5. Horses and animals

This is the ambient-horse half of the long-standing **IDEA-001** (horses, 2026-09-08) — deliberately *not* riding: the horses here graze, idle and tether. Mounted transport stays open in that backlog entry for a day when a real traversal need justifies it.

`design.md` §6 already commits to animals (ducks first, then cats/dogs/sheep) with a state machine, activity points and bounded habitats. Horses are the flagship for this vibe and fit that model cleanly:

- **The horse model** — standalone MagicaVoxel asset, 0.0625 m grid: ~1.35 m at the withers ≈ 21 detail cells tall, ~2.1 m body. Greedy-baked it lands in the 300–600 triangle range; trivially within budget. Three variants (bay, chestnut, grey) via palette swap, same mesh.
- **Animation without a rig** — the whole animal reads alive with *two* pivots: head+neck (raise to graze, slow nod, one ear-flick pose) and tail (lazy swish). 4–6 poses cross-faded by timer. No full rig, no physics — cost on the Thor is noise.
- **Behaviour** — a horse has three states: graze at a trough, stand idling, walk a short tethered circle. A *tether*, not free pathfinding: horses stay near a trough or a post, which sidesteps the hardest part of §6 navigation until we want it. Ducks already have a pond habitat region; a stable yard and a meadow corner give horses the same.
- **Population** — start with 2 horses (one at the stable, one at the square trough) + the planned 2 ducks + maybe a chicken or two in a coop. Design doc targets 12 animals in the benchmark scene; this fits.
- **The cart** — a horse-drawn cart is a separate static prop (wagon body + wheels, voxel), parked at the inn and the stable. A hand cart/barrow variant fills small gaps. Nothing moves unless a horse is near it, and even then the cart itself stays still — motion budget goes to living things, not objects.
- **Small animals** — ducks (already planned), chickens in a small coop (1 mesh, 3–4 instances, feed near a garden), a cat on a wall (static pose + head pivot), a dog asleep under the bench. Cheap, charming, and each one is a tiny MagicaVoxel asset.

## 6. Street-furniture wishlist

Everything below is a *standalone presentation asset* (MagicaVoxel, 0.0625 m) unless tagged — exactly the class we've already shipped 23 of, so this is pure catalogue growth:

**Transport & trade**
- horse cart (wagon + wheels) · hand barrow
- market stall (voxel base + **procedural stretchable awning** in 4 colours)
- produce crates: apples, pumpkins (autumn), hay bales
- signpost variant: a town-sign with the name plate
- blacksmith anvil + smithy cart (optional)

**The square & landmarks**
- fountain (tiered stone bowl, presentation only — no water sim)
- archway / gate over the main lane at the town entrance (timber or stone — the flower arch just proved this asset shape at 0.0625 m)
- well (existing) beside the fountain, or replace per taste
- stone steps / platform edges for the square's raised corners
- bunting: string of small triangles between two buildings (**procedural**, 1 material)

**Homes' exteriors**
- laundry strung from a window ledge (**procedural** — the clothesline pattern, but shorter and between walls)
- chimney stack with a small cap (voxel; pairs with the smoke below)
- window boxes (the barrel planter's smaller sibling — voxel)
- door steps + a small hanging door lamp
- garden gate (existing) with a pair of gate posts (voxel)
- a cat on the wall (see §5)

**Life & atmosphere**
- **Chimney smoke** — a few puffs per stack, rising and fading; the cheapest, biggest "inhabited" cue in this whole list. Presentation-only, no simulation.
- **Windmill sails** — one slow rotation.
- **Laundry and bunting sway** — a subtle vertex wobble, same trick the trees use.
- **Birds** — the existing bird feeder already implies them; a few perching sparrows (static poses) or drifting gulls near the water.
- **Sound** — per `design.md` §3 the sound direction is open: distant bell (rare, soft), hoof ticks on cobble when near a horse, cart-wheel creak, birds. Cozy ambience, never a soundtrack wall.

## 7. How we'd actually build it (system mapping)

| Idea | System it plugs into | New infrastructure? |
| --- | --- | --- |
| Lane hierarchy, ruts, steps, weeds, puddles, arched bridge | painted-path presentation layer (0.0625 m detail grid, deterministic) + one new bridge style | presentation only — no authority changes, no save migration |
| Stepped gable, jettying, steeper pitches | existing roof-courses + massing systems, new course shapes / design options | small: one roof-course variant |
| Inn, chapel, stable, windmill | existing free placement + home design catalogue: new `design_id`s | one landmark (windmill) needs an *animated* part — the only genuinely new rendering seam (a rotating sub-mesh on a building) |
| Market stalls, carts, fountain, archway, crates, etc. | furniture catalogue: new style IDs, one mesh per asset, batched by style like today's 23 | none — proven pipeline (the arch was this pipeline this week) |
| Awnings, bunting, laundry | **procedural stretchable** elements, per the art-production boundary | none: procedural is the sanctioned route for stretchable things |
| Horses, ducks, chickens, cat, dog | `design.md` §6 behaviour model: activity points + bounded habitats + reservations; **tethered** animals first, free pathfinding later | medium: a small "critter" runtime (pose cross-fade + habitat clamp) — no full nav-mesh needed for tethered animals, which defers the hardest §6 work |
| Smoke, sway, rotation | per-object presentation animation, budgeted per-frame work (bounded, a dozen objects max) | small: a shared "ambient motion" budget helper |
| Starter town layout | new starter-world layout using all of the above | none: layout is content |

**Performance envelope (Thor):** every new prop is one batched mesh per style (proven with the current 23), ≤ ~20 prop styles added total, ≤ 12 critters with 2-pivot animation, ~15 ambient-motion objects, one rotating sub-mesh. All comfortably inside what today's benchmark scene already absorbs.

**Saves:** new furniture style IDs are additive to the existing whitelist; new building designs reuse the existing building record schema (a new `design_id` value); tethered critters would be the first *new record kind* in the world document — that's the one schema-versioning decision to make when a ticket is written (version-bump the document, old saves load unchanged).

## 8. Suggested phasing (when you approve)

- **Phase A — the lane and the square.** Lane hierarchy + ruts + steps + arched bridge; the square (fountain, stalls, bunting, archway at the town mouth); a rewritten starter-world layout that shows the town *growing* around the square; 2 horses + the cart (tethered). *This phase alone changes how every screenshot reads.*
- **Phase B — the public buildings.** Inn, stable yard, chapel, windmill as new building designs; stepped gable + jettying into the home catalogue; smoke and sail rotation.
- **Phase C — small life.** Ducks, chickens, cat, dog, birds, laundry sway, and the ambient sound pass.

## 9. Boundaries (things we deliberately don't do)

- No photorealism, no noisy textures, no smooth low-poly — the voxel language and reference trio stay the rule.
- No riding, no traffic, no vehicles driven by systems (IDEA-001's mounted transport and rejected IDEA-002 stay out of this scope); carts are props.
- No poverty or decay beyond gentle wear; the town is cozy, not grim.
- No new global systems: everything above lives in the existing path, furniture, building, and presentation layers.

---

*This is a discussion document (IDEA-009, backlog). Approve a phase (or a slice of one) and it becomes a ticket in `tasks/` with acceptance criteria; until then it stays a conversation.*
