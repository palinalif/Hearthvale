#!/usr/bin/env python3
"""Declare which authored sources the bake pipeline owns, and on which grid.

Each author script is the single place that says which assets it owns; this
module only aggregates those declarations so that `bake_all.sh` has one place
to enumerate.  Output is space-separated "name=grid" pairs on stdout.

Grids follow the project contract: 0.125 structural, 0.0625 decorative
presentation.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import author_furniture
import author_props
import author_tier_b
import planter_assets

# Every asset the starter hamlet places is decorative presentation, so all of
# them bake on the fine 0.0625 grid; native terrain keeps the 0.125 grid.
DECORATIVE = "0.0625"

# Palette roles that emit light, and how hot.  The bake writes these into the
# asset receipt and gives those surfaces emissive materials, so the runtime
# glow targets exactly what was authored rather than guessing.
EMISSIVE = {
    "hearthvale_prop_path_lantern": ((5, 6), 2.2),
    "hearthvale_furniture_lantern": ((20, 22), 2.0),
}


# Authored sources that no runtime script consumes yet.  They stay in
# assets/source/magicavoxel as reviewable voxel art, but they are deliberately
# NOT baked: every baked .res ships in the APK, so baking art the game never
# loads buys 2 MB of device storage for pixels nobody sees.  Wiring one up
# means moving its name out of this set and giving the runtime a path to it.
UNWIRED = {
    # Tier A furniture.  The hamlet still builds these procedurally; only the
    # lantern has a runtime consumer (and a mesh contract test).
    "hearthvale_furniture_bench",
    "hearthvale_furniture_signpost",
    "hearthvale_furniture_lamp_post",
    "hearthvale_furniture_maypole",
    "hearthvale_furniture_notice_board",
    "hearthvale_furniture_pumpkin_post",
    "hearthvale_furniture_hay_cart",
    "hearthvale_furniture_well",
    "hearthvale_furniture_market_cross",
    "hearthvale_furniture_stone_bench",
    "hearthvale_furniture_water_pump",
    "hearthvale_furniture_chopping_block",
    "hearthvale_furniture_log_stack",
    # Tier C aliases of the same Tier A shapes.  The composition layer places
    # the village well, chopping block and log stack under their prop_ names,
    # so these bare duplicates have no consumer.
    "hearthvale_bench",
    "hearthvale_stone_bench",
    "hearthvale_signpost",
    "hearthvale_lamp_post",
    "hearthvale_maypole",
    "hearthvale_notice_board",
    "hearthvale_water_pump",
    "hearthvale_hay_cart",
    "hearthvale_market_cross",
}


def targets() -> list[tuple[str, str, tuple[int, ...], float]]:
    out: list[tuple[str, str, tuple[int, ...], float]] = []
    for mesh in author_furniture.FURNITURE:
        out.append(("hearthvale_furniture_%s" % mesh, DECORATIVE))
    for name in author_tier_b.MODELS:
        out.append(("hearthvale_prop_%s" % name, DECORATIVE))
    for name in author_props.MESH_NAMES:
        out.append(("hearthvale_%s" % name, DECORATIVE))
    for name in planter_assets.NAMES:
        out.append((name, DECORATIVE))
    # The path lantern is authored by the Tier A lighting work; it presents on
    # the fine grid and is the only asset with an emissive part.
    out.append(("hearthvale_prop_path_lantern", DECORATIVE))
    return out


if __name__ == "__main__":
    # "name=grid[:emissive:energy]" -- emissive roles ride along with the grid
    # so the bake has one place to enumerate every authored asset.
    for name, grid in targets():
        if name in UNWIRED:
            continue
        indices, energy = EMISSIVE.get(name, ((), 0.0))
        if indices:
            print("%s=%s:%s:%s" % (name, grid, ",".join(str(i) for i in indices), energy), end=" ")
        else:
            print("%s=%s" % (name, grid), end=" ")
    print()
