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


def targets() -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
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
    print(" ".join("%s=%s" % pair for pair in targets()))
